# Read-only. Per active display path: monitor name, output tech, refresh, WIRE colour encoding
# (RGB / YCbCr 444 / 422 / 420), bits per channel, HDR state, SDR white level, DPI current vs recommended.
# Plus NVIDIA adapter registry hints and monitor EDID presence.
#
# FOOTGUN (cost hours once): in PowerShell a struct field that is itself a struct is a VALUE type, so
#   $s.header.type = 2
# mutates a temporary COPY and the real header stays zeroed. DisplayConfigGetDeviceInfo then returns
# rc=31 (ERROR_GEN_FAILURE) for every call. Build the inner struct in its own variable and assign the
# whole thing back ($s.header = $h). That is what New-Header below exists for. Do not "simplify" it.
$ErrorActionPreference = 'Continue'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DC2 {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator; public uint Denominator; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET_INFO { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE_INFO { public uint infoType; public uint id; public LUID adapterId; [MarshalAs(UnmanagedType.ByValArray, SizeConst=48)] public byte[] raw; }
  [StructLayout(LayoutKind.Sequential)] public struct HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TARGET_DEVICE_NAME { public HEADER header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }
  [StructLayout(LayoutKind.Sequential)] public struct ADVANCED_COLOR_INFO { public HEADER header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; }
  [StructLayout(LayoutKind.Sequential)] public struct SDR_WHITE_LEVEL { public HEADER header; public uint SDRWhiteLevel; }
  [StructLayout(LayoutKind.Sequential)] public struct DPI_SCALE_GET { public HEADER header; public int minScaleRel; public int curScaleRel; public int maxScaleRel; }
  [StructLayout(LayoutKind.Sequential)] public struct ADVANCED_COLOR_INFO_2 { public HEADER header; public uint value; public uint colorEncoding; public uint bitsPerColorChannel; public uint activeColorMode; }
  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PATH_INFO[] paths, ref uint numModes, [Out] MODE_INFO[] modes, IntPtr topology);
  [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetTargetName(ref TARGET_DEVICE_NAME p);
  [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetAdvancedColor(ref ADVANCED_COLOR_INFO p);
  [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetAdvancedColor2(ref ADVANCED_COLOR_INFO_2 p);
  [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetSdrWhite(ref SDR_WHITE_LEVEL p);
  [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetDpiScale(ref DPI_SCALE_GET p);
}
"@
function New-Header([uint32]$type, [int]$size, $adapter, [uint32]$id) {
    $h = New-Object 'DC2+HEADER'; $h.type = $type; $h.size = [uint32]$size; $h.adapterId = $adapter; $h.id = $id; return $h
}
[uint32]$np = 0; [uint32]$nm = 0
$null = [DC2]::GetDisplayConfigBufferSizes(2, [ref]$np, [ref]$nm)
$paths = New-Object 'DC2+PATH_INFO[]' $np
$modes = New-Object 'DC2+MODE_INFO[]' $nm
$rc = [DC2]::QueryDisplayConfig(2, [ref]$np, $paths, [ref]$nm, $modes, [IntPtr]::Zero)
"QueryDisplayConfig rc=$rc paths=$np"
# Correct DISPLAYCONFIG_OUTPUT_TECHNOLOGY values. HDMI is 5, DisplayPort external is 10.
$tech = @{ 0='HD15(VGA)'; 1='SVIDEO'; 2='COMPOSITE'; 3='COMPONENT'; 4='DVI'; 5='HDMI'; 6='LVDS'; 8='D_JPN'; 9='SDI'; 10='DISPLAYPORT_EXTERNAL'; 11='DISPLAYPORT_EMBEDDED'; 12='UDI_EXTERNAL'; 13='UDI_EMBEDDED'; 14='SDTVDONGLE'; 15='MIRACAST'; 16='INDIRECT_WIRED'; 17='INDIRECT_VIRTUAL'; 18='DISPLAYPORT_USB_TUNNEL'; 2147483648='INTERNAL' }
$enc = @{ 0='RGB (full 4:4:4)'; 1='YCbCr 4:4:4'; 2='YCbCr 4:2:2'; 3='YCbCr 4:2:0 (chroma subsampled)'; 4='INTENSITY' }
$acm = @{ 0='SDR'; 1='WCG'; 2='HDR' }
$dpiSteps = @(100,125,150,175,200,225,250,300,350,400,450,500)
for ($i = 0; $i -lt $np; $i++) {
    $p = $paths[$i]
    "---- PATH $i ----"
    $tn = New-Object 'DC2+TARGET_DEVICE_NAME'
    $tn.header = New-Header 2 ([Runtime.InteropServices.Marshal]::SizeOf($tn)) $p.targetInfo.adapterId $p.targetInfo.id
    $rc = [DC2]::GetTargetName([ref]$tn)
    "Monitor: '$($tn.monitorFriendlyDeviceName)'  connector instance=$($tn.connectorInstance)  output=$($tech[[int]$tn.outputTechnology]) ($($tn.outputTechnology))  path=$($tn.monitorDevicePath)  (rc=$rc)"
    $rr = if ($p.targetInfo.refreshRate.Denominator) { [math]::Round($p.targetInfo.refreshRate.Numerator / $p.targetInfo.refreshRate.Denominator, 3) } else { 'n/a' }
    "Path refresh: $rr Hz   scaling=$($p.targetInfo.scaling)   pathStatusFlags=0x$('{0:X}' -f $p.targetInfo.statusFlags)"
    $ac = New-Object 'DC2+ADVANCED_COLOR_INFO'
    $ac.header = New-Header 9 ([Runtime.InteropServices.Marshal]::SizeOf($ac)) $p.targetInfo.adapterId $p.targetInfo.id
    $rc = [DC2]::GetAdvancedColor([ref]$ac)
    $supported = [bool]($ac.value -band 1); $enabled = [bool]($ac.value -band 2); $wide = [bool]($ac.value -band 4); $forceOff = [bool]($ac.value -band 8)
    "ADVANCED COLOR (rc=$rc): HDR supported=$supported  HDR enabled=$enabled  wideColorEnforced=$wide  forceDisabled=$forceOff"
    "WIRE FORMAT (rc=$rc): colorEncoding=$($enc[[int]$ac.colorEncoding]) [$($ac.colorEncoding)]   bitsPerColorChannel=$($ac.bitsPerColorChannel)"
    $ac2 = New-Object 'DC2+ADVANCED_COLOR_INFO_2'
    $ac2.header = New-Header 15 ([Runtime.InteropServices.Marshal]::SizeOf($ac2)) $p.targetInfo.adapterId $p.targetInfo.id
    $rc2 = [DC2]::GetAdvancedColor2([ref]$ac2)
    if ($rc2 -eq 0) { "ADVANCED COLOR 2 (Win11 24H2+): activeColorMode=$($acm[[int]$ac2.activeColorMode]) [$($ac2.activeColorMode)]  encoding=$($enc[[int]$ac2.colorEncoding])  bpc=$($ac2.bitsPerColorChannel)  value=0x$('{0:X}' -f $ac2.value)" } else { "ADVANCED COLOR 2: rc=$rc2 (not supported on this build)" }
    $sw = New-Object 'DC2+SDR_WHITE_LEVEL'
    $sw.header = New-Header 11 ([Runtime.InteropServices.Marshal]::SizeOf($sw)) $p.targetInfo.adapterId $p.targetInfo.id
    $rc = [DC2]::GetSdrWhite([ref]$sw)
    "SDR white level: $($sw.SDRWhiteLevel) (1000 = 80 nits; matters only with HDR on)  (rc=$rc)"
    $dp = New-Object 'DC2+DPI_SCALE_GET'
    $dp.header = New-Header ([uint32]4294967293) ([Runtime.InteropServices.Marshal]::SizeOf($dp)) $p.sourceInfo.adapterId $p.sourceInfo.id
    $rc = [DC2]::GetDpiScale([ref]$dp)
    if ($rc -eq 0) {
        $recIdx = [math]::Abs($dp.minScaleRel); $curIdx = $recIdx + $dp.curScaleRel
        $rec = if ($recIdx -lt $dpiSteps.Count) { $dpiSteps[$recIdx] } else { '?' }
        $cur = if ($curIdx -ge 0 -and $curIdx -lt $dpiSteps.Count) { $dpiSteps[$curIdx] } else { '?' }
        "DPI SCALING: current=$cur%  Windows-recommended=$rec%  (minRel=$($dp.minScaleRel) curRel=$($dp.curScaleRel) maxRel=$($dp.maxScaleRel))"
    } else { "DPI scaling: rc=$rc" }
}
"== NVIDIA per-display color/format hints in registry (read-only) =="
$cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $pp = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    if ($pp.DriverDesc -match 'NVIDIA') {
        "  [$($_.PSChildName)] $($pp.DriverDesc)  DriverVersion=$($pp.DriverVersion)  DriverDate=$($pp.DriverDate)"
        $pp.PSObject.Properties | Where-Object { $_.Name -match '(?i)color|dither|hdr|vibran|edid|dsc|hdmi|dp|scaling|rr|refresh' -and $_.Name -notmatch '^PS' } | ForEach-Object { "     {0} = {1}" -f $_.Name, (([string]($_.Value -join ',')).Substring(0, [Math]::Min(120, ([string]($_.Value -join ',')).Length))) }
    }
}
"== Monitor EDID presence per DISPLAY enum key (all vendors) =="
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY' -EA SilentlyContinue | ForEach-Object {
    $vendor = $_.PSChildName
    Get-ChildItem $_.PSPath -EA SilentlyContinue | ForEach-Object {
        $dev = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        $edid = (Get-ItemProperty (Join-Path $_.PSPath 'Device Parameters') -EA SilentlyContinue).EDID
        $len = if ($edid) { $edid.Length } else { 0 }
        $ext = if ($edid -and $len -ge 127) { $edid[126] } else { 'n/a' }
        "  $vendor\$($_.PSChildName) : EDID bytes=$len extensions=$ext  FriendlyName=$($dev.FriendlyName)"
    }
}
