# Read-only. Answers "is anything actually bending the colours on the desktop right now?"
#   1. the LIVE GPU gamma ramp vs identity  (this is the load-bearing measurement)
#   2. the Windows "use display calibration" toggle
#   3. every candidate ICC profile parsed for its vcgt tag (the only tag that can touch the desktop)
#   4. registry key last-write times, so "when did this change" is answerable
#
# WHY THE ORDER MATTERS: an ICC profile with NO vcgt tag cannot alter the desktop at all. It only
# affects colour-managed apps (Photoshop, some browsers). A confident story about "that ICC profile
# someone installed" dies in one run if the ramp is identity and the profile has no vcgt. Measure the
# LUT before blaming profiles.
#
# Usage: gamma_icc_probe.ps1 [-Profiles a.icm,b.icc]   (default: profiles associated with the display
#        in the registry, plus the newest 8 files in the system colour directory)
param([string[]]$Profiles)
$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GammaReg {
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
  [DllImport("gdi32.dll")] public static extern bool GetDeviceGammaRamp(IntPtr hDC, [Out] ushort[] lpRamp);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode)] public static extern int RegQueryInfoKey(IntPtr hKey, StringBuilder lpClass, ref uint lpcbClass, IntPtr lpReserved, out uint lpcSubKeys, out uint lpcbMaxSubKeyLen, out uint lpcbMaxClassLen, out uint lpcValues, out uint lpcbMaxValueNameLen, out uint lpcbMaxValueLen, out uint lpcbSecurityDescriptor, out long lpftLastWriteTime);
}
"@
"== Live GPU gamma ramp (primary display DC) =="
$hdc = [GammaReg]::GetDC([IntPtr]::Zero)
$ramp = New-Object 'ushort[]' 768
$ok = [GammaReg]::GetDeviceGammaRamp($hdc, $ramp)
[void][GammaReg]::ReleaseDC([IntPtr]::Zero, $hdc)
"  GetDeviceGammaRamp ok=$ok"
if ($ok) {
    $maxDev = 0
    foreach ($ch in 0..2) { foreach ($i in 0..255) { $d = [math]::Abs([int]$ramp[$ch * 256 + $i] - $i * 257); if ($d -gt $maxDev) { $maxDev = $d } } }
    "  max deviation from identity: $maxDev / 65535 ($([math]::Round($maxDev/655.35,2))%)   identity would be 0"
    "  READ THIS AS: 0 = nothing is loading a calibration curve. Non-zero = the Calibration Loader task"
    "  or some colour tool IS bending the desktop, and that is a live suspect."
    foreach ($i in 0, 16, 32, 64, 96, 128, 160, 192, 224, 255) { "  idx {0,3}: R={1,5} G={2,5} B={3,5}  (identity {4,5})" -f $i, $ramp[$i], $ramp[256 + $i], $ramp[512 + $i], ($i * 257) }
}
"== Windows display calibration toggle (colorcpl Advanced: 'Use Windows display calibration') =="
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\Calibration', 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\Calibration') {
    $v = Get-ItemProperty $k -EA SilentlyContinue
    if ($v) { "  [$k] " + (($v.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ') } else { "  [$k] absent" }
}
"== ICC profiles: calibration (vcgt) content =="
function Read-BE32([byte[]]$b, [int]$o) { return ([uint32]$b[$o] -shl 24) -bor ([uint32]$b[$o + 1] -shl 16) -bor ([uint32]$b[$o + 2] -shl 8) -bor [uint32]$b[$o + 3] }
function Read-BE16([byte[]]$b, [int]$o) { return ([uint16]$b[$o] -shl 8) -bor [uint16]$b[$o + 1] }
function S15F16([byte[]]$b, [int]$o) { $v = [int32](Read-BE32 $b $o); return [math]::Round($v / 65536.0, 4) }
$dir = Join-Path $env:SystemRoot 'System32\spool\drivers\color'
if (-not $Profiles) {
    $assoc = @()
    foreach ($root in 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display') {
        Get-ChildItem $root -Recurse -EA SilentlyContinue | ForEach-Object {
            (Get-ItemProperty $_.PSPath -EA SilentlyContinue).PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $assoc += ([string]($_.Value -join ',') -split ',') }
        }
    }
    $mc = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96e-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $mc -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
        $v = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        $assoc += @($v.ICMProfile) + @($v.ICMProfileAC)
    }
    $recent = Get-ChildItem $dir -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8 -ExpandProperty Name
    $Profiles = @($assoc + $recent) | Where-Object { $_ -and $_ -match '\.ic[cm]$' } | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique
}
foreach ($name in $Profiles) {
    $p = if (Test-Path $name) { $name } else { Join-Path $dir $name }
    if (-not (Test-Path $p)) { "  $name : absent"; continue }
    $b = [IO.File]::ReadAllBytes($p)
    $tagCount = Read-BE32 $b 128
    $desc = ''; $vcgt = $null
    for ($i = 0; $i -lt $tagCount; $i++) {
        $o = 132 + 12 * $i
        $sig = [Text.Encoding]::ASCII.GetString($b, $o, 4)
        $off = Read-BE32 $b ($o + 4); $sz = Read-BE32 $b ($o + 8)
        if ($sig -eq 'vcgt') { $vcgt = @{ off = $off; sz = $sz } }
        if ($sig -eq 'desc' -and $off + 12 -lt $b.Length) {
            $t = [Text.Encoding]::ASCII.GetString($b, $off, 4)
            if ($t -eq 'desc') { $len = Read-BE32 $b ($off + 8); $desc = [Text.Encoding]::ASCII.GetString($b, $off + 12, [Math]::Min($len, 60)).Trim([char]0) }
            elseif ($t -eq 'mluc') { $n = Read-BE32 $b ($off + 8); $rl = Read-BE32 $b ($off + 20); $ro = Read-BE32 $b ($off + 24); $desc = [Text.Encoding]::BigEndianUnicode.GetString($b, $off + $ro, [Math]::Min($rl, 120)) }
        }
    }
    $cls = [Text.Encoding]::ASCII.GetString($b, 12, 4); $pcs = [Text.Encoding]::ASCII.GetString($b, 20, 4); $csp = [Text.Encoding]::ASCII.GetString($b, 16, 4)
    $line = "  {0}: size={1} class={2} colorspace={3} pcs={4} tags={5} desc='{6}'" -f $name, $b.Length, $cls, $csp, $pcs, $tagCount, $desc
    if ($vcgt) {
        $o = $vcgt.off
        $type = Read-BE32 $b ($o + 8)
        if ($type -eq 0) {
            $ch = Read-BE16 $b ($o + 12); $en = Read-BE16 $b ($o + 14); $es = Read-BE16 $b ($o + 16)
            $line += "  VCGT=table channels=$ch entries=$en entrySize=$es"
            $base = $o + 18
            $pts = @()
            foreach ($c in 0..($ch - 1)) {
                $first = if ($es -eq 2) { Read-BE16 $b ($base + ($c * $en) * 2) } else { $b[$base + $c * $en] }
                $mid = if ($es -eq 2) { Read-BE16 $b ($base + ($c * $en + [int]($en / 2)) * 2) } else { $b[$base + $c * $en + [int]($en / 2)] }
                $last = if ($es -eq 2) { Read-BE16 $b ($base + ($c * $en + $en - 1) * 2) } else { $b[$base + $c * $en + $en - 1] }
                $scale = if ($es -eq 2) { 65535.0 } else { 255.0 }
                $pts += ("ch{0}: first={1:P1} mid={2:P1} last={3:P1}" -f $c, ($first / $scale), ($mid / $scale), ($last / $scale))
            }
            $line += "  [" + ($pts -join '; ') + "]  (identity: first 0%, mid ~50%, last 100%)"
        } elseif ($type -eq 1) {
            $line += "  VCGT=formula R(gamma={0} min={1} max={2}) G(gamma={3} min={4} max={5}) B(gamma={6} min={7} max={8})" -f (S15F16 $b ($o + 12)), (S15F16 $b ($o + 16)), (S15F16 $b ($o + 20)), (S15F16 $b ($o + 24)), (S15F16 $b ($o + 28)), (S15F16 $b ($o + 32)), (S15F16 $b ($o + 36)), (S15F16 $b ($o + 40)), (S15F16 $b ($o + 44))
        } else { $line += "  VCGT=unknown type $type" }
    } else { $line += "  VCGT=none (no calibration curve: the Windows loader cannot apply it, but NVIDIA 'Enhanced' colour accuracy mode still applies the profile to the desktop - see SKILL.md step 0)" }
    $line
    "     file mtime: $((Get-Item $p).LastWriteTime)"
}
"== Registry key last-write times (what changed when) =="
function KeyTime([string]$hive, [string]$path) {
    try {
        $root = if ($hive -eq 'HKLM') { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
        $k = $root.OpenSubKey($path, $false)
        if (-not $k) { return "$hive\$path : (absent)" }
        $cb = [uint32]0; $a = [uint32]0; $b2 = [uint32]0; $c = [uint32]0; $d = [uint32]0; $e = [uint32]0; $f = [uint32]0; $g = [uint32]0; [long]$ft = 0
        $rc = [GammaReg]::RegQueryInfoKey($k.Handle.DangerousGetHandle(), $null, [ref]$cb, [IntPtr]::Zero, [ref]$a, [ref]$b2, [ref]$c, [ref]$d, [ref]$e, [ref]$f, [ref]$g, [ref]$ft)
        $k.Close()
        if ($rc -ne 0) { return "$hive\$path : rc=$rc" }
        return ("{0:yyyy-MM-dd HH:mm:ss}  {1}\{2}  (subkeys={3} values={4})" -f [DateTime]::FromFileTime($ft), $hive, $path, $a, $d)
    } catch { return "$hive\$path : error $($_.Exception.Message)" }
}
$keys = @(
    @('HKCU', 'Control Panel\Desktop'),
    @('HKCU', 'Control Panel\Desktop\PerMonitorSettings'),
    @('HKCU', 'Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display'),
    @('HKLM', 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display'),
    @('HKLM', 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\Calibration'),
    @('HKLM', 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers'),
    @('HKLM', 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration'),
    @('HKLM', 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity'),
    @('HKLM', 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors'),
    @('HKCU', 'Software\Microsoft\Windows\CurrentVersion\VideoSettings'),
    @('HKCU', 'Software\Microsoft\DirectX\UserGpuPreferences')
)
# FOOTGUN: the per-user ICC association values live one level DEEPER than you expect, under
# HKCU\...\ICM\ProfileAssociations\Display\<device>\000N -- not directly under \Display.
foreach ($n in 0..9) { $keys += , @('HKCU', "Software\Microsoft\Avalon.Graphics\DISPLAY$n") }
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96e-e325-11ce-bfc1-08002be10318}' -EA SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object { $keys += , @('HKLM', "SYSTEM\CurrentControlSet\Control\Class\{4d36e96e-e325-11ce-bfc1-08002be10318}\$($_.PSChildName)") }
foreach ($kk in $keys) { $t = KeyTime $kk[0] $kk[1]; if ($t -notmatch '\(absent\)$') { "  $t" } }
"== Monitor-class registry slots: ICMProfile / ICMProfileAC per slot =="
$mc = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96e-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $mc -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $v = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    "  [{0}] {1}  MatchingDeviceId={2}  ICMProfile={3}  ICMProfileAC={4}" -f $_.PSChildName, $v.DriverDesc, $v.MatchingDeviceId, ($v.ICMProfile -join '|'), ($v.ICMProfileAC -join '|')
}
"== GraphicsDrivers\Configuration entries (Windows saved display configs, newest 8) =="
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration' -EA SilentlyContinue | Sort-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).Timestamp } -Descending | Select-Object -First 8 | ForEach-Object {
    $v = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    "  {0}  ts={1}" -f ($_.PSChildName.Substring(0, [Math]::Min(60, $_.PSChildName.Length)) + '...'), $v.Timestamp
}
