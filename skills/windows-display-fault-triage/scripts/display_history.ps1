# Read-only. "What is attached, what profile is bound to it, and what changed recently."
# Slower than the other probes (dxdiag can take up to 90 s), so run it only when the fast probes have
# not settled the question, or when the fault started after a specific change and you need dates.
#
# Usage: display_history.ps1 -OutDir <dir for dxdiag.txt> [-SkipDxdiag]   (OutDir is required: this script writes dxdiag.txt there)
param([Parameter(Mandatory = $true)][string]$OutDir, [switch]$SkipDxdiag)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$since7 = (Get-Date).AddDays(-7); $since14 = (Get-Date).AddDays(-14)

"== WMI monitor connection params (VideoOutputTechnology per monitor) =="
Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorConnectionParams -EA SilentlyContinue | ForEach-Object { "  $($_.InstanceName): VideoOutputTechnology=$($_.VideoOutputTechnology) Active=$($_.Active)" }
"== WMI monitor basic params (physical size) =="
Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBasicDisplayParams -EA SilentlyContinue | ForEach-Object { "  $($_.InstanceName): Active=$($_.Active) MaxH=$($_.MaxHorizontalImageSize)cm MaxV=$($_.MaxVerticalImageSize)cm SupportedFeatures=$($_.SupportedDisplayFeatures)" }
"== Monitor EDID-derived identity (WmiMonitorID) =="
Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -EA SilentlyContinue | ForEach-Object {
    $name = (($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '')
    $mfg = (($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '')
    $serial = (($_.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '')
    "  $name (mfg $mfg, week $($_.WeekOfManufacture)/$($_.YearOfManufacture), serial len $($serial.Length))  Active=$($_.Active)  $($_.InstanceName)"
}
"== Monitor PnP devices (stale entries here are normal; 'Present' is what matters) =="
Get-PnpDevice -Class Monitor -EA SilentlyContinue | Select-Object Status, Present, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 200
"== Video controller =="
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, Status, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, CurrentBitsPerPixel, VideoModeDescription | Format-List
"== ICC profile associations =="
# FOOTGUN: the per-user values are one level DEEPER than expected --
# HKCU\...\ICM\ProfileAssociations\Display\<device>\000N -- so a non-recursive read finds nothing.
foreach ($root in 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\ProfileAssociations\Display') {
    "[$root]"
    Get-ChildItem $root -Recurse -EA SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        $vals = ($props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value -join ',')" }) -join '; '
        if ($vals) { "  $($_.PSChildName): $vals" }
    }
}
"== Registered ICC profiles in the system colour directory (newest 15) =="
Get-ChildItem (Join-Path $env:SystemRoot 'System32\spool\drivers\color') -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1,9}  {2}" -f $_.LastWriteTime, $_.Length, $_.Name }
"== Colour calibration loader task (this is what applies a vcgt curve at sign-in) =="
Get-ScheduledTask -TaskPath '\Microsoft\Windows\WindowsColorSystem\' -EA SilentlyContinue | ForEach-Object { $i = $_ | Get-ScheduledTaskInfo; "  $($_.TaskName): $($_.State) last=$($i.LastRunTime) result=0x$('{0:X}' -f $i.LastTaskResult)" }
"== HDR / video playback settings (per-user) =="
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\VideoSettings' -EA SilentlyContinue | Select-Object EnableHDRForPlayback, EnableAutoHDR, VideoQualityOnBattery | Format-List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -EA SilentlyContinue | Select-Object HwSchMode, DirectXUserGlobalSettings | Format-List
"UserGlobalSettings (Game Mode / AutoHDR / VRR flags): $((Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -EA SilentlyContinue).DirectXUserGlobalSettings)"
"== Per-monitor DPI overrides =="
Get-ChildItem 'HKCU:\Control Panel\Desktop\PerMonitorSettings' -EA SilentlyContinue | ForEach-Object { "  $($_.PSChildName): DpiValue=$((Get-ItemProperty $_.PSPath).DpiValue)" }
"Global: LogPixels=$((Get-ItemProperty 'HKCU:\Control Panel\Desktop' -EA SilentlyContinue).LogPixels) Win8DpiScaling=$((Get-ItemProperty 'HKCU:\Control Panel\Desktop' -EA SilentlyContinue).Win8DpiScaling)"
"== GPU driver events, 7d (nvlddmkm Xid, Display 4101 TDR) =="
# FOOTGUN: one failing Get-WinEvent -FilterHashtable can abort the surrounding scriptblock even with
# -EA SilentlyContinue ("The parameter is incorrect"). Wrap every query in its own try/catch.
try { Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'nvlddmkm', 'Display'; StartTime = $since7 } -EA Stop | Select-Object -First 20 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss} id {1} {2}" -f $_.TimeCreated, $_.Id, (($_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($_.Message -replace '\s+', ' ').Length))) } } catch { "  none / n/a: $($_.Exception.Message)" }
"== Recent monitor/display driver installs (UserPnp 20001/20003, 14d) =="
try { Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-UserPnp'; Id = 20001, 20003; StartTime = $since14 } -EA Stop | Where-Object { $_.Message -match '(?i)monitor|display|nvidia|DISPLAY\\|MONITOR\\' } | Select-Object -First 20 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss} id {1} {2}" -f $_.TimeCreated, $_.Id, (($_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(220, ($_.Message -replace '\s+', ' ').Length))) } } catch { "  none / n/a: $($_.Exception.Message)" }
if (-not $SkipDxdiag) {
    "== dxdiag Display Devices section =="
    $dx = Join-Path $OutDir 'dxdiag.txt'
    if (Test-Path $dx) { Remove-Item $dx -Force -EA SilentlyContinue }
    $proc = Start-Process -FilePath dxdiag -ArgumentList "/whql:off /t `"$dx`"" -PassThru -WindowStyle Hidden
    $proc.WaitForExit(90000) | Out-Null
    if (Test-Path $dx) {
        $txt = Get-Content $dx -Raw
        $m = [regex]::Match($txt, '(?s)-+\r?\nDisplay Devices\r?\n-+\r?\n(.*?)\r?\n-+\r?\nSound Devices')
        if ($m.Success) { $m.Groups[1].Value } else { "(Display Devices section not found; file length $($txt.Length))" }
    } else { "dxdiag produced no file" }
}
