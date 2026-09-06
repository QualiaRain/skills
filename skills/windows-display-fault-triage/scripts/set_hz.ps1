# Temporarily change the primary display refresh rate. CDS_TEST first, then a DYNAMIC change that is
# NOT written to the registry, so it reverts at the next sign-in and nothing is left behind.
# Use it as an A/B: if the fault disappears at a lower refresh, the link is the problem (cable, DSC,
# DP/HDMI version negotiated) rather than the panel or the PC's colour stack.
#
# Usage: set_hz.ps1 -Hz 120        then re-run the probes        then set_hz.ps1 -Hz 240
#
# FOOTGUN: PowerShell converts $null to "" when binding a .NET *string* parameter, so passing $null as
# the device name makes EnumDisplaySettingsW return ok=False and ChangeDisplaySettingsExW return -5.
# The API wants a real NULL. Pass [NullString]::Value.
param([int]$Hz = 120)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class DispMode {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public ushort dmSpecVersion; public ushort dmDriverVersion; public ushort dmSize; public ushort dmDriverExtra; public uint dmFields;
    public int dmPositionX; public int dmPositionY; public uint dmDisplayOrientation; public uint dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public ushort dmLogPixels; public uint dmBitsPerPel; public uint dmPelsWidth; public uint dmPelsHeight; public uint dmDisplayFlags; public uint dmDisplayFrequency;
    public uint dmICMMethod; public uint dmICMIntent; public uint dmMediaType; public uint dmDitherType; public uint dmReserved1; public uint dmReserved2; public uint dmPanningWidth; public uint dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettingsW(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsExW(string dev, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr param);
}
"@
$dm = New-Object 'DispMode+DEVMODE'
$dm.dmSize = [uint16][Runtime.InteropServices.Marshal]::SizeOf($dm)
$ok = [DispMode]::EnumDisplaySettingsW([NullString]::Value, -1, [ref]$dm)
"Current: ok=$ok $($dm.dmPelsWidth)x$($dm.dmPelsHeight) @ $($dm.dmDisplayFrequency) Hz, $($dm.dmBitsPerPel) bpp"
$dm.dmDisplayFrequency = [uint32]$Hz
$dm.dmFields = [uint32](0x40000 -bor 0x80000 -bor 0x100000 -bor 0x400000)   # BITSPERPEL | PELSWIDTH | PELSHEIGHT | DISPLAYFREQUENCY
$test = [DispMode]::ChangeDisplaySettingsExW([NullString]::Value, [ref]$dm, [IntPtr]::Zero, 2, [IntPtr]::Zero)   # CDS_TEST
"CDS_TEST for $Hz Hz -> $test (0 = ok)"
if ($test -eq 0) {
    $rc = [DispMode]::ChangeDisplaySettingsExW([NullString]::Value, [ref]$dm, [IntPtr]::Zero, 0, [IntPtr]::Zero)   # dynamic, not saved
    "ChangeDisplaySettingsEx -> $rc (0 = success, 1 = needs restart, -2 = bad mode)"
    Start-Sleep -Seconds 2
    $dm2 = New-Object 'DispMode+DEVMODE'; $dm2.dmSize = $dm.dmSize
    [void][DispMode]::EnumDisplaySettingsW([NullString]::Value, -1, [ref]$dm2)
    "Now: $($dm2.dmPelsWidth)x$($dm2.dmPelsHeight) @ $($dm2.dmDisplayFrequency) Hz"
}
