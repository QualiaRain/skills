# Read-only. Everything on the PC that can change how TEXT and COLOUR look without touching the
# wire format: ClearType / subpixel order, the per-display ClearType tuner, accessibility colour
# filters / magnifier / high contrast, night light, NVIDIA per-display registry values and profile
# database timestamps, ASUS or other monitor tooling, monitor USB devices, display scheduled tasks,
# and any running process known to bend gamma.
$ErrorActionPreference = 'Continue'
"== ClearType / font smoothing (HKCU Control Panel\Desktop) =="
$d = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -EA SilentlyContinue
"  FontSmoothing=$($d.FontSmoothing) (2=on)  FontSmoothingType=$($d.FontSmoothingType) (1=standard/grayscale, 2=ClearType)  FontSmoothingGamma=$($d.FontSmoothingGamma)  FontSmoothingOrientation=$($d.FontSmoothingOrientation) (1=RGB, 2=BGR)"
"  NOTE: FontSmoothingOrientation wrong for the panel is a classic source of colour fringing on text."
"  DragFullWindows=$($d.DragFullWindows)  UserPreferencesMask(hex)=$(($d.UserPreferencesMask | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
"== ClearType tuner per-display (Avalon.Graphics) =="
Get-ChildItem 'HKCU:\Software\Microsoft\Avalon.Graphics' -EA SilentlyContinue | ForEach-Object { $v = Get-ItemProperty $_.PSPath; "  $($_.PSChildName): " + (($v.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ') }
"== Windows accessibility / visual effects that alter rendering =="
$acc = Get-ItemProperty 'HKCU:\Software\Microsoft\Accessibility' -EA SilentlyContinue
"  Accessibility keys: " + (($acc.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')
$cf = Get-ItemProperty 'HKCU:\Software\Microsoft\ColorFiltering' -EA SilentlyContinue
"  ColorFiltering: Active=$($cf.Active) FilterType=$($cf.FilterType) HotkeyEnabled=$($cf.HotkeyEnabled)   (Active=1 recolours the whole desktop)"
$mag = Get-ItemProperty 'HKCU:\Software\Microsoft\ScreenMagnifier' -EA SilentlyContinue
"  Magnifier: Magnification=$($mag.Magnification) Invert=$($mag.Invert) RunningState=$($mag.RunningState)   (a left-running Magnifier looks exactly like 'pixelation')"
$hc = Get-ItemProperty 'HKCU:\Control Panel\Accessibility\HighContrast' -EA SilentlyContinue
"  HighContrast Flags=$($hc.Flags)  Theme=$($hc.'High Contrast Scheme')"
"== Night light state blob (CloudStore) =="
$nl = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate'
$nls = Get-ItemProperty $nl -EA SilentlyContinue
if ($nls) { $b = $nls.Data; "  bytes=$($b.Length) hex[0..30]=" + (($b[0..([Math]::Min(30, $b.Length - 1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '); "  heuristic: byte[18]=0x$('{0:X2}' -f $b[18]) (0x15 typically = night light ON, 0x13 = OFF)" } else { "  no state key (never configured)" }
"== Explorer colour filter toggle =="
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -EA SilentlyContinue | Select-Object EnableColorFilter | Format-List
"== NVIDIA per-display (_User_*) registry values =="
$cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $cls -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $pp = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    if ($pp.DriverDesc -match 'NVIDIA') {
        $pp.PSObject.Properties | Where-Object { $_.Name -match '^_User_|^Display|^Dither|^Vibr|^HDR|^Edid|^Nv' -and $_.Name -notmatch '^PS' } | Sort-Object Name | ForEach-Object { $s = [string]($_.Value -join ','); "  {0} = {1}" -f $_.Name, $s.Substring(0, [Math]::Min(80, $s.Length)) }
    }
}
"== NVIDIA driver profile database timestamps (NVCP global/app profiles; shows when NVCP last wrote) =="
Get-ChildItem (Join-Path $env:ProgramData 'NVIDIA Corporation\Drs') -File -EA SilentlyContinue | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss}  {1,10}  {2}" -f $_.LastWriteTime, $_.Length, $_.Name }
"== NVIDIA processes running =="
Get-Process | Where-Object { $_.Name -match '(?i)nv|nvidia' } | Select-Object Name, Id, StartTime -EA SilentlyContinue | Format-Table -AutoSize
"== Monitor vendor tooling installed (DisplayWidget, Armoury, RGB suites) =="
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $keys -EA SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)asus|armoury|displaywidget|rog|aura|displaycal|calman|colorcontrol|monitorian|twinkle' } | Select-Object DisplayName, DisplayVersion, InstallDate, InstallLocation | Format-Table -AutoSize | Out-String -Width 200
Get-AppxPackage -EA SilentlyContinue | Where-Object { $_.Name -match '(?i)asus|displaywidget|armoury' } | Select-Object Name, Version, InstallLocation | Format-Table -AutoSize | Out-String -Width 200
"== Monitor USB / DDC devices present (firmware-update and OSD-control path) =="
Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.FriendlyName -match '(?i)monitor|display' -or $_.Class -eq 'Monitor' } | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 220
"== Monitor arrival/removal events since boot (Kernel-PnP configuration log) =="
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
try { Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; StartTime = $boot } -EA Stop | Where-Object { $_.Message -match '(?i)DISPLAY\\|monitor|HDMI' } | Select-Object -First 25 | ForEach-Object { "  {0:HH:mm:ss}  id {1}  {2}" -f $_.TimeCreated, $_.Id, (($_.Message -replace '\s+', ' ').Substring(0, [Math]::Min(200, ($_.Message -replace '\s+', ' ').Length))) } } catch { "  n/a: $($_.Exception.Message)" }
"== Display-related scheduled tasks =="
Get-ScheduledTask -EA SilentlyContinue | Where-Object { ($_.TaskName + ' ' + (($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' ')) -match '(?i)display|monitor|color|hdr|nvidia|asus|gamma|icc|cleartype|dpi|resolution' } | ForEach-Object { $i = $_ | Get-ScheduledTaskInfo; "  {0}{1}  state={2} last={3} result=0x{4:X}  exec={5}" -f $_.TaskPath, $_.TaskName, $_.State, $i.LastRunTime, $i.LastTaskResult, ((($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' | ').Substring(0, [Math]::Min(140, (($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' | ').Length))) }
"== Processes that commonly alter desktop colour/gamma =="
Get-Process | Where-Object { $_.Name -match '(?i)flux|iris|displaycal|colorcontrol|twinkle|lightbulb|asus|displaywidget|armoury|rtss|rivatuner|wallpaper|monitorian|clickmonitor|dimmer|redshift|sunset|gamma|nightlight|calibr' } | Select-Object Name, Id, StartTime, Path -EA SilentlyContinue | Format-Table -AutoSize | Out-String -Width 220
