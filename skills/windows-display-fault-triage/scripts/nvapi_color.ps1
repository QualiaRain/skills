# NVIDIA driver-side output colour state for the primary display, via nvapi_QueryInterface.
# Reads: colour format (RGB / YUV444 / YUV422 / YUV420), colorimetry, selection policy,
# dynamic range (Full VESA vs Limited CEA 16-235), bpc, and digital vibrance level.
# -FixRange writes dynamic range back to Full if it is currently Limited (the one write this makes).
#
# REQUIRES PowerShell 7 (pwsh): uses the ::Get[T]() generic-method call syntax, which 5.1 cannot parse.
#
# FOOTGUNS, all of which cost real time:
#  * MAKE_NVAPI_VERSION is  size | (version << 16)  -- NOT (size << 16) | version. Get it backwards
#    and every call returns INCOMPATIBLE_STRUCT_VERSION with no other clue.
#  * A hex literal above 0x7FFFFFFF is a NEGATIVE int32 in PowerShell, so the function id must be
#    written [uint32]'0x92F9D80D', not 0x92F9D80D.
#  * Driver 616.56 REJECTS NV_COLOR_DATA v3 (rc -9) and accepts v2 at size 12. Do not hard-code a
#    version: probe 12/2, 12/3, 16/4, 16/5 and use whichever the installed driver accepts. That is
#    why this script writes a raw buffer instead of marshalling a typed struct.
param([switch]$FixRange)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class NvApiX {
  [DllImport("nvapi64.dll", EntryPoint="nvapi_QueryInterface", CallingConvention=CallingConvention.Cdecl)]
  public static extern IntPtr QueryInterface(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int InitializeD();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int GetGDIPrimaryDisplayIdD(out uint displayId);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int DispColorControlRawD(uint displayId, IntPtr data);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int GetErrorMessageD(int status, StringBuilder msg);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int EnumNvidiaDisplayHandleD(int thisEnum, out IntPtr handle);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int GetDVCInfoD(IntPtr hDisplay, uint outputId, ref NV_DISPLAY_DVC_INFO info);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int GetAssociatedNvidiaDisplayNameD(IntPtr hDisplay, StringBuilder name);
  [StructLayout(LayoutKind.Sequential)] public struct NV_DISPLAY_DVC_INFO { public uint version; public int currentLevel; public int minLevel; public int maxLevel; }
  public static T Get<T>(uint id) where T : class { IntPtr p = QueryInterface(id); if (p == IntPtr.Zero) throw new Exception("nvapi fn not found 0x" + id.ToString("X")); return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T)); }
}
"@
$init = [NvApiX]::Get[NvApiX+InitializeD](0x0150E828); [void]$init.Invoke()
$errf = [NvApiX]::Get[NvApiX+GetErrorMessageD](0x6C2D048C)
function ErrText([int]$s) { $sb = New-Object System.Text.StringBuilder 128; [void]$errf.Invoke($s, $sb); return $sb.ToString() }
$getPrim = [NvApiX]::Get[NvApiX+GetGDIPrimaryDisplayIdD](0x1E9D8A31)
[uint32]$did = 0; [void]$getPrim.Invoke([ref]$did); "displayId=0x$('{0:X}' -f $did)"
$cc = [NvApiX]::Get[NvApiX+DispColorControlRawD]([uint32]'0x92F9D80D')
$fmt = @{ 0 = 'RGB'; 1 = 'YUV422'; 2 = 'YUV444'; 3 = 'YUV420'; 254 = 'DEFAULT'; 255 = 'AUTO' }
$rng = @{ 0 = 'FULL (VESA 0-255)'; 1 = 'LIMITED (CEA 16-235)'; 255 = 'AUTO' }
$bpcm = @{ 0 = 'default'; 1 = '6bpc'; 2 = '8bpc'; 3 = '10bpc'; 4 = '12bpc'; 5 = '16bpc' }
$pol = @{ 0 = 'USER'; 1 = 'BEST_QUALITY(driver default)'; 255 = 'UNKNOWN' }
$buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(128)
function Call([int]$size, [int]$ver, [byte]$cmd, [byte[]]$payload) {
    for ($i = 0; $i -lt 128; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($buf, $i, 0) }
    [Runtime.InteropServices.Marshal]::WriteInt32($buf, 0, [int]($size -bor ($ver -shl 16)))
    [Runtime.InteropServices.Marshal]::WriteInt16($buf, 4, [int16]$size)
    [Runtime.InteropServices.Marshal]::WriteByte($buf, 6, $cmd)
    if ($payload) { for ($i = 0; $i -lt $payload.Length; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($buf, 7 + $i, $payload[$i]) } }
    $rc = $cc.Invoke($did, $buf)
    $out = New-Object 'byte[]' 16; [Runtime.InteropServices.Marshal]::Copy($buf, $out, 0, 16)
    return @{ rc = $rc; bytes = $out }
}
function Decode([byte[]]$b) { "format={0} colorimetry={1} policy={2} dynamicRange={3} bpc={4}  raw7..15={5}" -f $fmt[[int]$b[7]], $b[8], $pol[[int]$b[9]], $rng[[int]$b[10]], $bpcm[[int]$b[11]], (($b[7..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') }
$found = $null
foreach ($try in @(@(12, 2), @(12, 3), @(16, 4), @(16, 5), @(12, 1), @(20, 5), @(24, 5), @(16, 3), @(20, 4))) {
    $r = Call $try[0] $try[1] 1 $null
    "GET size=$($try[0]) ver=$($try[1]) -> rc=$($r.rc) ($(ErrText $r.rc))"
    if ($r.rc -eq 0) { $found = $try; "  CURRENT: " + (Decode $r.bytes); break }
}
if ($found) {
    $d = Call $found[0] $found[1] 4 $null
    "GET_DEFAULT rc=$($d.rc): " + $(if ($d.rc -eq 0) { Decode $d.bytes } else { ErrText $d.rc })
}
"Digital vibrance (NVCP 'Digital Vibrance'; 0 = the 50% neutral default, max = 100% oversaturated):"
$enum = [NvApiX]::Get[NvApiX+EnumNvidiaDisplayHandleD]([uint32]'0x9ABDD40D')
$dvc = [NvApiX]::Get[NvApiX+GetDVCInfoD](0x4085DE45)
$nameF = [NvApiX]::Get[NvApiX+GetAssociatedNvidiaDisplayNameD](0x22A78B05)
for ($i = 0; $i -lt 8; $i++) {
    [IntPtr]$h = [IntPtr]::Zero
    $r = $enum.Invoke($i, [ref]$h); if ($r -ne 0) { break }
    $sb = New-Object System.Text.StringBuilder 64; [void]$nameF.Invoke($h, $sb)
    $info = New-Object 'NvApiX+NV_DISPLAY_DVC_INFO'; $info.version = [uint32](16 -bor (1 -shl 16))
    $r2 = $dvc.Invoke($h, 0, [ref]$info)
    "  handle $i ($($sb.ToString())): rc=$r2 currentLevel=$($info.currentLevel) min=$($info.minLevel) max=$($info.maxLevel)"
}
if ($FixRange -and $found) {
    $cur = (Call $found[0] $found[1] 1 $null).bytes
    if ($cur[10] -eq 1) {
        "Dynamic range is LIMITED -> setting FULL, RGB, policy USER, bpc unchanged."
        $payload = [byte[]]@(0, 0, 0, 0, $cur[11])
        $s = Call $found[0] $found[1] 2 $payload
        "SET rc=$($s.rc) ($(ErrText $s.rc))"
        Start-Sleep -Seconds 3
        $a = Call $found[0] $found[1] 1 $null
        "AFTER rc=$($a.rc): " + (Decode $a.bytes)
    } else { "Dynamic range is not Limited; nothing changed." }
}
[Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
