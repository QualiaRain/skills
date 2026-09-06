#Requires -Version 5.1
# Read-only system health sweep. Writes one redacted text file per section into $OutDir, plus
# _index.txt listing each section with its line count and runtime.
#
# Read-only and unelevated by design: nothing is changed or deleted, and no elevation is requested.
#
# Redaction: every fenced path / drive from ~/.claude/hooks/private_paths.json is replaced with
# [FENCED] BEFORE anything is written to disk or printed, and the fenced drive letter is excluded
# from volume queries entirely. private_paths.json is the single source of truth for that list -
# do not hard-code a second copy of it anywhere.
#
# Usage:
#   collect.ps1 -OutDir <scratchpad>\diag
#   collect.ps1 -OutDir <dir> -Sections 05_events_hardware_stability,09_gpu
[CmdletBinding()]
param([string]$OutDir, [string[]]$Sections)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('pc-health-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------------- redaction (single source of truth: private_paths.json) ----------------
$cfg = $null
try { $cfg = Get-Content (Join-Path $HOME '.claude\hooks\private_paths.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $cfg = $null }
# FAIL CLOSED: with no config there is no redaction list, and the sweep would write unredacted output silently.
if (-not $cfg -or -not $cfg.fenced_dirs -or @($cfg.fenced_dirs).Count -eq 0) { throw 'private_paths.json unreadable or empty - refusing to run an unredacted sweep.' }
$patterns = New-Object System.Collections.Generic.List[string]
foreach ($d in $cfg.fenced_dirs) {
    $parts = $d -split '/'
    $esc = ($parts | ForEach-Object { [regex]::Escape($_) }) -join '[\\/]+'
    $patterns.Add('(?i)' + $esc + '[^\s"''<>|]*')
}
$excludedLetters = @()
foreach ($drv in $cfg.fenced_drives) {
    $letter = $drv.TrimEnd(':').ToUpper()
    $excludedLetters += $letter
    $patterns.Add('(?i)\b' + [regex]::Escape($drv) + '[\\/][^\s"''<>|]*')
    $patterns.Add('(?i)(?<![A-Za-z0-9])' + [regex]::Escape($drv) + '(?![A-Za-z0-9])')
}
# Bare folder names are DERIVED from the same config, never hard-coded here: a second copy of the
# fenced list living in a script is exactly the drift this redaction exists to prevent.
$leafNames = @()
foreach ($d in $cfg.fenced_dirs) { $leaf = @($d -split '[\\/]+' | Where-Object { $_ }) | Select-Object -Last 1; if ($leaf -and $leaf.Length -ge 4) { $leafNames += $leaf } }
$leafNames = @($leafNames | Sort-Object -Unique)
function Redact([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    foreach ($p in $patterns) { $text = [regex]::Replace($text, $p, '[FENCED]') }
    # Leaf names match only in path context (after a slash; before a slash, whitespace, quote or end).
    # A bare substring match over-redacts ordinary words that equal a fenced folder name (e.g. a Private_MB column).
    foreach ($n in $leafNames) { $text = [regex]::Replace($text, '(?i)[\\/]' + [regex]::Escape($n) + '(?=[\\/\s"''<>|]|$)', '\[FENCED-NAME]') }
    return $text
}
function Trunc([string]$s, [int]$n) {
    if (-not $s) { return '' }
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $n) { return $s.Substring(0, $n) + '...' } else { return $s }
}

$script:index = New-Object System.Collections.Generic.List[string]
function Section([string]$name, [scriptblock]$body) {
    if ($Sections -and ($name -notin $Sections)) { return }
    $file = Join-Path $OutDir ($name + '.txt')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = ''
    try { $out = (& $body 2>&1 | Out-String -Width 220) } catch { $out = "SECTION ERROR: $($_.Exception.Message)`n" + $out }
    if ($null -eq $out) { $out = '' }
    $out = Redact $out
    Set-Content -Path $file -Value $out -Encoding UTF8
    $lines = ($out -split "`n").Count
    $script:index.Add(('{0,-34} {1,6} lines {2,7} ms' -f $name, $lines, $sw.ElapsedMilliseconds))
}

$since7 = (Get-Date).AddDays(-7)
$since14 = (Get-Date).AddDays(-14)
$since30 = (Get-Date).AddDays(-30)

# ---------------- 00 system ----------------
Section '00_system' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $bb = Get-CimInstance Win32_BaseBoard
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    "Now: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')   Collector elevated: $isAdmin   PS version: $($PSVersionTable.PSVersion)"
    "OS: $($os.Caption) $($os.Version) build $($os.BuildNumber).$($cv.UBR)  DisplayVersion: $($cv.DisplayVersion)  InstallDate: $($os.InstallDate)"
    "LastBoot: $($os.LastBootUpTime)  Uptime: $((Get-Date) - $os.LastBootUpTime)"
    "Model: $($cs.Manufacturer) $($cs.Model)  RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB  HypervisorPresent: $($cs.HypervisorPresent)  AutomaticManagedPagefile: $($cs.AutomaticManagedPagefile)"
    "Board: $($bb.Manufacturer) $($bb.Product)  BIOS: $($bios.SMBIOSBIOSVersion) released $($bios.ReleaseDate)"
    "Workgroup/Domain: $($cs.Domain)  PartOfDomain: $($cs.PartOfDomain)"
    "FastStartup(HiberbootEnabled): $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -EA SilentlyContinue).HiberbootEnabled)"
    "Pending reboot flags:"
    "  CBS RebootPending: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')"
    "  WU RebootRequired: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')"
    $pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue).PendingFileRenameOperations
    "  PendingFileRenameOperations: $([bool]$pfr) (entries: $(@($pfr).Count))"
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -EA SilentlyContinue
    "VBS: status=$($dg.VirtualizationBasedSecurityStatus) (0 off,1 enabled-not-running,2 running)  SecurityServicesRunning=$($dg.SecurityServicesRunning -join ',') (1=CredGuard,2=HVCI/MemoryIntegrity)"
    "HAGS (HwSchMode, 2=on): $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -EA SilentlyContinue).HwSchMode)"
    "Activation:"; cscript //nologo C:\Windows\System32\slmgr.vbs /xpr 2>&1
    "Time zone: $(tzutil /g 2>&1)"
    "w32tm status:"; w32tm /query /status 2>&1
    "w32tm source: $(w32tm /query /source 2>&1)"
    "Environment: PROCESSOR_ARCHITECTURE=$env:PROCESSOR_ARCHITECTURE  NUMBER_OF_PROCESSORS=$env:NUMBER_OF_PROCESSORS"
}

# ---------------- 01 reliability ----------------
Section '01_reliability' {
    $m = Get-CimInstance Win32_ReliabilityStabilityMetrics -EA SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 30
    "Stability index (newest first, 10 = best, 1 = worst):"
    $m | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.TimeGenerated, $_.SystemStabilityIndex }
    $r = @(Get-CimInstance Win32_ReliabilityRecords -EA SilentlyContinue | Where-Object { $_.TimeGenerated -gt $since30 })
    "Reliability records, 30d: $($r.Count)"
    "By source/event id (top 40):"
    $r | Group-Object SourceName, EventIdentifier | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object { "  {0,4}  {1}" -f $_.Count, $_.Name }
    "Most recent 50 records:"
    $r | Sort-Object TimeGenerated -Descending | Select-Object -First 50 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1,-42} {2,6}  {3}" -f $_.TimeGenerated, $_.SourceName, $_.EventIdentifier, (Trunc $_.Message 220) }
}

# ---------------- 02 system log errors ----------------
Section '02_events_system_errors' {
    "Log sizes / retention:"
    Get-WinEvent -ListLog System, Application, Security, 'Microsoft-Windows-Windows Defender/Operational' -EA SilentlyContinue | Select-Object LogName, RecordCount, @{n = 'SizeMB'; e = { [math]::Round($_.FileSize / 1MB, 1) } }, @{n = 'MaxMB'; e = { [math]::Round($_.MaximumSizeInBytes / 1MB, 1) } }, LastWriteTime, IsLogFull | Format-Table -AutoSize
    $oldest = Get-WinEvent -LogName System -Oldest -MaxEvents 1 -EA SilentlyContinue; "System log oldest record: $($oldest.TimeCreated)"
    $oldestA = Get-WinEvent -LogName Application -Oldest -MaxEvents 1 -EA SilentlyContinue; "Application log oldest record: $($oldestA.TimeCreated)"
    $ev = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 1, 2; StartTime = $since14 } -EA SilentlyContinue)
    "Critical+Error System events, 14d: $($ev.Count)"
    "Per day:"
    $ev | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { "  {0}  {1}" -f $_.Name, $_.Count }
    "By provider/id (top 40):"
    $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object {
        $s = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        "  {0,5}  {1}  | last {2:yyyy-MM-dd HH:mm} | {3}" -f $_.Count, $_.Name, $s.TimeCreated, (Trunc $s.Message 240)
    }
    "Most recent 60 (newest first):"
    $ev | Sort-Object TimeCreated -Descending | Select-Object -First 60 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss}  L{1} {2,-45} {3,6}  {4}" -f $_.TimeCreated, $_.Level, $_.ProviderName, $_.Id, (Trunc $_.Message 200) }
}

# ---------------- 03 warnings ----------------
Section '03_events_warnings' {
    $ev = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 3; StartTime = $since7 } -EA SilentlyContinue)
    "System warnings, 7d: $($ev.Count)"
    "Per day:"
    $ev | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { "  {0}  {1}" -f $_.Name, $_.Count }
    "By provider/id (top 40):"
    $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object {
        $s = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        "  {0,5}  {1}  | last {2:yyyy-MM-dd HH:mm} | {3}" -f $_.Count, $_.Name, $s.TimeCreated, (Trunc $s.Message 240)
    }
    $ea = @(Get-WinEvent -FilterHashtable @{LogName = 'Application'; Level = 3; StartTime = $since7 } -EA SilentlyContinue)
    "Application warnings, 7d: $($ea.Count)"
    "By provider/id (top 25):"
    $ea | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object {
        $s = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        "  {0,5}  {1}  | last {2:yyyy-MM-dd HH:mm} | {3}" -f $_.Count, $_.Name, $s.TimeCreated, (Trunc $s.Message 200)
    }
}

# ---------------- 04 application errors ----------------
Section '04_events_application_errors' {
    $ev = @(Get-WinEvent -FilterHashtable @{LogName = 'Application'; Level = 1, 2; StartTime = $since14 } -EA SilentlyContinue)
    "Critical+Error Application events, 14d: $($ev.Count)"
    "Per day:"
    $ev | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { "  {0}  {1}" -f $_.Name, $_.Count }
    "By provider/id (top 40):"
    $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 40 | ForEach-Object {
        $s = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        "  {0,5}  {1}  | last {2:yyyy-MM-dd HH:mm} | {3}" -f $_.Count, $_.Name, $s.TimeCreated, (Trunc $s.Message 240)
    }
    "Faulting apps (Application Error 1000 / Application Hang 1002, 30d):"
    Get-WinEvent -FilterHashtable @{LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; StartTime = $since30 } -EA SilentlyContinue | ForEach-Object {
        if ($_.Message -match '(?:Faulting application name: |The program )([^,\s]+)') { $matches[1] } else { 'unknown' }
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object { "  {0,4}  {1}" -f $_.Count, $_.Name }
    "Most recent 50 (newest first):"
    $ev | Sort-Object TimeCreated -Descending | Select-Object -First 50 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss}  L{1} {2,-40} {3,6}  {4}" -f $_.TimeCreated, $_.Level, $_.ProviderName, $_.Id, (Trunc $_.Message 220) }
}

# ---------------- 05 targeted hardware / stability signals ----------------
Section '05_events_hardware_stability' {
    $checks = @(
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Power'; I = @(41); N = 'Kernel-Power 41 = unexpected reboot / power loss / hard hang' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Power'; I = @(42, 107, 109, 137, 142, 172, 187); N = 'Kernel-Power sleep/resume/shutdown related' },
        @{ L = 'System'; P = 'Microsoft-Windows-WER-SystemErrorReporting'; I = @(1001); N = 'BugCheck (BSOD) records' },
        @{ L = 'System'; P = 'EventLog'; I = @(6008); N = 'EventLog 6008 = previous shutdown was unexpected' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Boot'; I = @(27); N = 'Kernel-Boot 27 boot type (0 cold, 1 fast startup, 2 resume from hibernate)' },
        @{ L = 'System'; P = 'Microsoft-Windows-WHEA-Logger'; I = $null; N = 'WHEA hardware errors (any id; 17/19 corrected, 18/20 uncorrected, 47 PCIe)' },
        @{ L = 'System'; P = 'disk'; I = $null; N = 'disk driver (7 bad block, 11 controller, 51 paging, 153 IO retried, 157 surprise removed)' },
        @{ L = 'System'; P = 'Ntfs'; I = $null; N = 'Ntfs' },
        @{ L = 'System'; P = 'Microsoft-Windows-Ntfs'; I = $null; N = 'Microsoft-Windows-Ntfs' },
        @{ L = 'System'; P = 'volmgr'; I = $null; N = 'volmgr' },
        @{ L = 'System'; P = 'stornvme'; I = $null; N = 'stornvme (129 = reset to device)' },
        @{ L = 'System'; P = 'storahci'; I = $null; N = 'storahci' },
        @{ L = 'System'; P = 'Display'; I = @(4101); N = 'Display 4101 = GPU driver TDR (display driver stopped responding and recovered)' },
        @{ L = 'System'; P = 'nvlddmkm'; I = $null; N = 'nvlddmkm NVIDIA kernel driver (Xid)' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Processor-Power'; I = @(35, 37, 55); N = 'Kernel-Processor-Power (37 = firmware limited CPU speed / throttling)' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-PnP'; I = @(219, 411, 442); N = 'Kernel-PnP driver load / device failures' },
        @{ L = 'System'; P = 'Microsoft-Windows-DNS-Client'; I = @(1014); N = 'DNS-Client 1014 name resolution timeouts' },
        @{ L = 'System'; P = 'Microsoft-Windows-MemoryDiagnostics-Results'; I = $null; N = 'Windows Memory Diagnostic results' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-General'; I = @(1, 12, 13); N = 'Kernel-General (1 = system time changed, 12 boot, 13 shutdown)' },
        @{ L = 'System'; P = 'Microsoft-Windows-Time-Service'; I = $null; N = 'Time-Service' },
        @{ L = 'System'; P = 'Service Control Manager'; I = @(7000, 7001, 7009, 7011, 7022, 7023, 7024, 7026, 7031, 7034, 7043, 7045); N = 'Service Control Manager failures (7045 = new service installed)' },
        @{ L = 'System'; P = 'Microsoft-Windows-DistributedCOM'; I = @(10016, 10010, 10005); N = 'DistributedCOM (10016 is usually benign noise)' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-EventTracing'; I = $null; N = 'Kernel-EventTracing (session failures, usually benign)' },
        @{ L = 'System'; P = 'Microsoft-Windows-UserPnp'; I = @(20001, 20003); N = 'UserPnp device driver installs' },
        @{ L = 'System'; P = 'Microsoft-Windows-Hyper-V-VmSwitch'; I = $null; N = 'Hyper-V VmSwitch' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-IoTrace'; I = $null; N = 'Kernel-IoTrace' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Tm'; I = $null; N = 'Kernel-Tm' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Boot'; I = @(29, 30, 32); N = 'Kernel-Boot 29/30/32 (secure boot / boot manager)' },
        @{ L = 'System'; P = 'Microsoft-Windows-Kernel-Power'; I = @(105, 125, 130); N = 'Kernel-Power battery/thermal' },
        @{ L = 'Application'; P = 'Application Error'; I = @(1000); N = 'Application Error 1000 (app crashes)' },
        @{ L = 'Application'; P = 'Application Hang'; I = @(1002); N = 'Application Hang 1002' },
        @{ L = 'Application'; P = 'Windows Error Reporting'; I = @(1001); N = 'WER 1001 reports' },
        @{ L = 'Application'; P = 'Microsoft-Windows-Winlogon'; I = @(6000, 6003, 6005, 6006); N = 'Winlogon (slow logon subscribers)' },
        @{ L = 'Application'; P = 'ESENT'; I = @(455, 488, 489, 490, 508, 509, 510); N = 'ESENT database errors / slow IO' },
        @{ L = 'Application'; P = 'Microsoft-Windows-Search'; I = $null; N = 'Windows Search (indexer)' },
        @{ L = 'Application'; P = 'SecurityCenter'; I = $null; N = 'Security Center' },
        @{ L = 'Application'; P = 'VSS'; I = $null; N = 'VSS' },
        @{ L = 'Application'; P = 'Microsoft-Windows-Perflib'; I = $null; N = 'Perflib (perf counter provider) errors' },
        @{ L = 'Application'; P = 'Microsoft-Windows-RestartManager'; I = $null; N = 'RestartManager' },
        @{ L = 'Application'; P = 'Microsoft-Windows-Kernel-Power'; I = $null; N = 'Kernel-Power (Application log)' }
    )
    $script:qerrs = New-Object System.Collections.Generic.List[string]
    # FOOTGUN: a single bad Get-WinEvent -FilterHashtable query can abort this WHOLE scriptblock with
    # "The parameter is incorrect", even under -EA SilentlyContinue, silently losing every later check.
    # Every event query in this section goes through Q, which catches per-query and records the failure.
    function Q([hashtable]$fh) {
        try { return @(Get-WinEvent -FilterHashtable $fh -EA Stop) }
        catch { if ($_.Exception.Message -notmatch 'No events were found') { $script:qerrs.Add(("{0} | {1}" -f (($fh.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -join ',')" }) -join ' '), $_.Exception.Message)) }; return @() }
    }
    foreach ($c in $checks) {
        $fh = @{ LogName = $c.L; ProviderName = $c.P; StartTime = $since30 }
        if ($c.I) { $fh.Id = $c.I }
        $e = Q $fh
        "== {0} [{1}/{2}]: {3} in 30d" -f $c.N, $c.L, $c.P, $e.Count
        if ($e.Count -gt 0) {
            $e | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "   id {0,6} x{1}" -f $_.Name, $_.Count }
            $e | Sort-Object TimeCreated -Descending | Select-Object -First 8 | ForEach-Object { "   {0:yyyy-MM-dd HH:mm:ss}  L{1} id {2,6}  {3}" -f $_.TimeCreated, $_.Level, $_.Id, (Trunc $_.Message 260) }
        }
    }
    "== Boot/shutdown timeline (30d, newest first, max 100):"
    $tl = @()
    $tl += Q @{LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12, 13; StartTime = $since30 }
    $tl += Q @{LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41, 42, 107, 109; StartTime = $since30 }
    $tl += Q @{LogName = 'System'; ProviderName = 'EventLog'; Id = 6005, 6006, 6008; StartTime = $since30 }
    $tl += Q @{LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Boot'; Id = 27; StartTime = $since30 }
    $tl += Q @{LogName = 'System'; ProviderName = 'User32'; Id = 1074, 1076; StartTime = $since30 }
    $tl | Where-Object { $_ } | Sort-Object TimeCreated -Descending | Select-Object -First 100 | ForEach-Object { "   {0:yyyy-MM-dd HH:mm:ss}  {1,-40} id {2,5}  {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, (Trunc $_.Message 150) }
    "== SetDisplayConfig callers (System 'Display' id 4107 and Kernel-PnP monitor arrivals, 14d):"
    Q @{LogName = 'System'; ProviderName = 'Display'; StartTime = $since14 } | Sort-Object TimeCreated -Descending | Select-Object -First 40 | ForEach-Object { "   {0:yyyy-MM-dd HH:mm:ss}  id {1,5}  {2}" -f $_.TimeCreated, $_.Id, (Trunc $_.Message 200) }
    "== Query errors (if any):"
    $script:qerrs | ForEach-Object { "   $_" }
    "== Boot performance (Diagnostics-Performance id 100; may need admin):"
    try {
        Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100; StartTime = $since30 } -EA Stop | Select-Object -First 15 | ForEach-Object {
            $x = [xml]$_.ToXml()
            $bt = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
            $md = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'MainPathBootTime' }).'#text'
            $pb = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootPostBootTime' }).'#text'
            "   {0:yyyy-MM-dd HH:mm}  BootTime={1} ms  MainPath={2} ms  PostBoot={3} ms" -f $_.TimeCreated, $bt, $md, $pb
        }
    } catch { "   n/a: $($_.Exception.Message)" }
    "== Slow boot/shutdown/standby causes (Diagnostics-Performance non-100 ids, top by count):"
    try {
        Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; StartTime = $since30 } -EA Stop | Where-Object { $_.Id -ne 100 } | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
            $s = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
            "   id {0,4} x{1}  last {2:yyyy-MM-dd}  {3}" -f $_.Name, $_.Count, $s.TimeCreated, (Trunc $s.Message 220)
        }
    } catch { "   n/a: $($_.Exception.Message)" }
}

# ---------------- 06 crash dumps / WER ----------------
Section '06_crash_dumps_wer' {
    foreach ($p in 'C:\Windows\Minidump', 'C:\Windows\MEMORY.DMP', 'C:\Windows\LiveKernelReports') {
        if (Test-Path $p) {
            "$p :"
            Get-ChildItem $p -Recurse -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 20 | ForEach-Object { "   {0:yyyy-MM-dd HH:mm}  {1,12:N0} bytes  {2}" -f $_.LastWriteTime, $_.Length, $_.FullName }
        } else { "$p : absent" }
    }
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -EA SilentlyContinue
    "CrashControl: CrashDumpEnabled=$($cc.CrashDumpEnabled) (0 none,1 complete,2 kernel,3 small,7 automatic) AutoReboot=$($cc.AutoReboot) Overwrite=$($cc.Overwrite) DumpFile=$($cc.DumpFile) MinidumpDir=$($cc.MinidumpDir) AlwaysKeepMemoryDump=$($cc.AlwaysKeepMemoryDump)"
    $lad = [Environment]::GetFolderPath('LocalApplicationData')
    foreach ($p in 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive', 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue', (Join-Path $lad 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $lad 'Microsoft\Windows\WER\ReportQueue')) {
        if (Test-Path $p) {
            $d = @(Get-ChildItem $p -Directory -EA SilentlyContinue)
            "$p : $($d.Count) reports"
            $d | Sort-Object LastWriteTime -Descending | Select-Object -First 25 | ForEach-Object { "   {0:yyyy-MM-dd HH:mm}  {1}" -f $_.LastWriteTime, $_.Name }
            "   by app (top 15): "
            $d | ForEach-Object { ($_.Name -split '_')[0..1] -join '_' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { "     {0,4}  {1}" -f $_.Count, $_.Name }
        } else { "$p : absent" }
    }
}

# ---------------- 07 storage ----------------
Section '07_storage' {
    "Physical disks:"
    Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB) } }, FirmwareVersion, SerialNumber | Format-Table -AutoSize
    "Disks:"
    Get-Disk | Select-Object Number, FriendlyName, HealthStatus, OperationalStatus, PartitionStyle, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB) } }, BootFromDisk, IsSystem, IsBoot | Format-Table -AutoSize
    "Storage reliability counters (SMART-derived; may need admin):"
    Get-PhysicalDisk | ForEach-Object {
        $pd = $_
        try {
            $c = $pd | Get-StorageReliabilityCounter -EA Stop
            "  {0}: Temp={1}C TempMax={2}C Wear={3}% ReadErrTotal={4} ReadErrUncorr={5} WriteErrTotal={6} WriteErrUncorr={7} PowerOnHours={8} StartStop={9} ReadLatMax={10}ms WriteLatMax={11}ms FlushLatMax={12}ms" -f $pd.FriendlyName, $c.Temperature, $c.TemperatureMax, $c.Wear, $c.ReadErrorsTotal, $c.ReadErrorsUncorrected, $c.WriteErrorsTotal, $c.WriteErrorsUncorrected, $c.PowerOnHours, $c.StartStopCycleCount, $c.ReadLatencyMax, $c.WriteLatencyMax, $c.FlushLatencyMax
        } catch { "  {0}: n/a ({1})" -f $pd.FriendlyName, $_.Exception.Message }
    }
    "Volumes (fenced drive letter excluded by policy):"
    Get-Volume | Where-Object { $_.DriveLetter -and ([string]$_.DriveLetter).ToUpper() -notin $excludedLetters } | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, OperationalStatus, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 1) } }, @{n = 'FreeGB'; e = { [math]::Round($_.SizeRemaining / 1GB, 1) } }, @{n = 'FreePct'; e = { if ($_.Size) { [math]::Round($_.SizeRemaining / $_.Size * 100) } } } | Format-Table -AutoSize
    "C: dirty bit:"; fsutil dirty query C: 2>&1
    "TRIM (DisableDeleteNotify 0 = TRIM on):"; fsutil behavior query DisableDeleteNotify 2>&1
    "Mapped network drives:"; Get-SmbMapping -EA SilentlyContinue | Select-Object LocalPath, RemotePath, Status | Format-Table -AutoSize
    "SMB shares served by this PC:"; Get-SmbShare -EA SilentlyContinue | Select-Object Name, Path, Description | Format-Table -AutoSize
    "Pagefile usage:"; Get-CimInstance Win32_PageFileUsage | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage | Format-Table -AutoSize
    "Pagefile settings:"; Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue | Select-Object Name, InitialSize, MaximumSize | Format-Table -AutoSize
    "Shadow storage (may need admin):"; vssadmin list shadowstorage 2>&1 | Select-Object -First 30
    "Storage Sense: $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -EA SilentlyContinue).'01')"
    "BitLocker (may need admin):"; try { Get-BitLockerVolume -EA Stop | Where-Object { ([string]$_.MountPoint).TrimEnd(':').ToUpper() -notin $excludedLetters } | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage | Format-Table -AutoSize } catch { "  n/a: $($_.Exception.Message)" }
}

# ---------------- 08 memory / cpu / power ----------------
Section '08_memory_cpu_power' {
    $os = Get-CimInstance Win32_OperatingSystem
    "RAM: total {0:N1} GB, free {1:N1} GB ({2}% free); commit used {3:N1} GB of limit {4:N1} GB" -f ($os.TotalVisibleMemorySize / 1MB), ($os.FreePhysicalMemory / 1MB), [math]::Round($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB), ($os.TotalVirtualMemorySize / 1MB)
    "DIMMs:"
    Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, DeviceLocator, @{n = 'GB'; e = { $_.Capacity / 1GB } }, Speed, ConfiguredClockSpeed, ConfiguredVoltage, Manufacturer, PartNumber | Format-Table -AutoSize
    "CPU:"
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, CurrentClockSpeed, LoadPercentage, VirtualizationFirmwareEnabled | Format-List
    "Thermal zones (ACPI; often unsupported on desktops):"
    Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -EA SilentlyContinue | ForEach-Object { "  {0}: {1:N1} C" -f $_.InstanceName, (($_.CurrentTemperature / 10) - 273.15) }
    "Perf counters (5 x 1s samples, averaged):"
    $ctr = '\Processor(_Total)\% Processor Time', '\Processor(_Total)\% Interrupt Time', '\Processor(_Total)\% DPC Time', '\Processor(_Total)\% Privileged Time', '\Processor Information(_Total)\% Processor Performance', '\System\Processor Queue Length', '\System\Context Switches/sec', '\Memory\Available MBytes', '\Memory\Pages/sec', '\Memory\Page Faults/sec', '\Memory\Committed Bytes', '\Memory\Pool Nonpaged Bytes', '\Memory\Pool Paged Bytes', '\Memory\Cache Bytes', '\Paging File(_Total)\% Usage', '\LogicalDisk(C:)\Avg. Disk Queue Length', '\LogicalDisk(C:)\% Disk Time', '\LogicalDisk(C:)\Avg. Disk sec/Read', '\LogicalDisk(C:)\Avg. Disk sec/Write', '\LogicalDisk(C:)\Disk Bytes/sec', '\Network Interface(*)\Bytes Total/sec'
    $s = Get-Counter -Counter $ctr -SampleInterval 1 -MaxSamples 5 -EA SilentlyContinue
    $s.CounterSamples | Group-Object Path | ForEach-Object { "  {0,-75} {1,16:N2}" -f ($_.Name -replace '^\\\\[^\\]+', ''), (($_.Group | Measure-Object CookedValue -Average).Average) }
    "Power plan:"; powercfg /getactivescheme 2>&1
    "Last wake:"; powercfg /lastwake 2>&1
    "Power requests (may need admin):"; powercfg /requests 2>&1 | Select-Object -First 40
    "Processor min/max state (AC):"
    powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>&1 | Select-String 'Current AC Power Setting Index'
    powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>&1 | Select-String 'Current AC Power Setting Index'
    "Sleep/hibernate availability:"; powercfg /a 2>&1
    "Driver Verifier:"; verifier /querysettings 2>&1 | Select-Object -First 12
}

# ---------------- 09 gpu ----------------
Section '09_gpu' {
    Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, Status, @{n = 'VRAM_GB_reported'; e = { [math]::Round($_.AdapterRAM / 1GB, 1) } }, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, VideoModeDescription | Format-List
    if (Get-Command nvidia-smi -EA SilentlyContinue) {
        "nvidia-smi core query:"
        nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu,power.draw,power.limit,clocks.sm,clocks.max.sm,clocks.mem,utilization.gpu,utilization.memory,memory.used,memory.total,fan.speed --format=csv 2>&1
        "nvidia-smi pcie/throttle query:"
        nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,clocks_throttle_reasons.active,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.sw_thermal_slowdown,clocks_throttle_reasons.hw_thermal_slowdown,clocks_throttle_reasons.sw_power_cap,clocks_throttle_reasons.hw_power_brake_slowdown --format=csv 2>&1
        "nvidia-smi ecc/retired:"
        nvidia-smi --query-gpu=ecc.mode.current,ecc.errors.uncorrected.aggregate.total,retired_pages.pending --format=csv 2>&1
        "nvidia-smi -q (PERFORMANCE,TEMPERATURE,POWER,CLOCK):"
        nvidia-smi -q -d PERFORMANCE, TEMPERATURE, POWER, CLOCK 2>&1 | Select-Object -First 220
        "GPU compute processes:"
        nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv 2>&1
        "nvidia-smi header (utilization/mem/processes):"
        nvidia-smi 2>&1 | Select-Object -First 40
    } else { 'nvidia-smi not on PATH' }
    "NVIDIA display container services:"
    Get-Service | Where-Object { $_.Name -like 'NV*' -or $_.DisplayName -like 'NVIDIA*' } | Select-Object Name, Status, StartType | Format-Table -AutoSize
}

# ---------------- 10 devices / drivers ----------------
Section '10_devices_drivers' {
    "PnP devices present but not OK:"
    Get-PnpDevice -PresentOnly -EA SilentlyContinue | Where-Object { $_.Status -ne 'OK' } | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 250
    "Devices with ConfigManagerErrorCode != 0:"
    Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object ConfigManagerErrorCode, Name, DeviceID | Format-Table -AutoSize | Out-String -Width 250
    "Key drivers by class:"
    Get-CimInstance Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -in 'DISPLAY', 'NET', 'MEDIA', 'SCSIADAPTER', 'HDC', 'SYSTEM', 'USB', 'BLUETOOTH', 'MONITOR', 'PROCESSOR', 'DISKDRIVE' -and $_.DriverVersion } | Sort-Object DeviceClass, DeviceName | Select-Object DeviceClass, DeviceName, DriverVersion, DriverDate, DriverProviderName, IsSigned | Format-Table -AutoSize | Out-String -Width 250
    "Monitors:"
    Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -EA SilentlyContinue | ForEach-Object { "  " + (($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '') + "  (mfg " + (($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '') + ")" }
    "Audio devices:"
    Get-CimInstance Win32_SoundDevice | Select-Object Name, Status, StatusInfo | Format-Table -AutoSize
    "USB controllers/hubs status:"
    Get-PnpDevice -PresentOnly -Class USB -EA SilentlyContinue | Select-Object Status, FriendlyName | Group-Object Status | ForEach-Object { "  {0}: {1}" -f $_.Name, $_.Count }
    "Recent driver installs (Setup log / UserPnp 20001, 30d):"
    Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-UserPnp'; Id = 20001, 20003; StartTime = $since30 } -EA SilentlyContinue | Select-Object -First 30 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.TimeCreated, (Trunc $_.Message 200) }
}

# ---------------- 11 services / startup / scheduled tasks ----------------
Section '11_services_startup_tasks' {
    "Automatic services not running:"
    Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Select-Object Name, DisplayName, State, ExitCode, DelayedAutoStart | Format-Table -AutoSize
    "Key services:"
    foreach ($n in 'SysMain', 'WSearch', 'wuauserv', 'WinDefend', 'Spooler', 'Themes', 'Audiosrv', 'AudioEndpointBuilder', 'Dnscache', 'Dhcp', 'BITS', 'Schedule', 'W32Time', 'TrustedInstaller', 'DiagTrack', 'WerSvc', 'EventLog', 'wscsvc', 'SecurityHealthService', 'mpssvc', 'LanmanServer', 'LanmanWorkstation', 'ssh-agent', 'sshd', 'TermService', 'WinRM', 'RemoteRegistry', 'vmcompute', 'LxssManager', 'Winmgmt', 'PlugPlay', 'Power', 'UsoSvc', 'DoSvc', 'wisvc') {
        $svc = Get-Service -Name $n -EA SilentlyContinue
        if ($svc) { "  {0,-24} {1,-10} {2}" -f $svc.Name, $svc.Status, $svc.StartType } else { "  {0,-24} (absent)" -f $n }
    }
    "Non-Microsoft services (running; path outside Windows dir):"
    Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' -and $_.PathName -notmatch '(?i)\\Windows\\(System32|SysWOW64|servicing|WinSxS)' } | Select-Object Name, StartMode, StartName, PathName | Format-Table -AutoSize | Out-String -Width 260
    "Non-Microsoft services (stopped, auto):"
    Get-CimInstance Win32_Service | Where-Object { $_.State -ne 'Running' -and $_.StartMode -eq 'Auto' -and $_.PathName -notmatch '(?i)\\Windows\\(System32|SysWOW64|servicing|WinSxS)' } | Select-Object Name, StartMode, State, PathName | Format-Table -AutoSize | Out-String -Width 260
    "Startup commands (Win32_StartupCommand):"
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, Command, User | Format-Table -AutoSize | Out-String -Width 260
    "Run / RunOnce keys:"
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
        "[$k]"
        (Get-ItemProperty $k -EA SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "  {0} = {1}" -f $_.Name, (Trunc ([string]$_.Value) 200) }
    }
    "StartupApproved state (enabled/disabled in Task Manager):"
    foreach ($k in 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder') {
        "[$k]"
        (Get-ItemProperty $k -EA SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $b = $_.Value[0]
            $state = if ($b -eq 2 -or $b -eq 6) { 'enabled' } elseif ($b -eq 3) { 'disabled' } else { "raw=$b" }
            "  {0} = {1}" -f $_.Name, $state
        }
    }
    "Scheduled tasks:"
    $tasks = @(Get-ScheduledTask -EA SilentlyContinue)
    $info = foreach ($t in $tasks) {
        $i = $t | Get-ScheduledTaskInfo -EA SilentlyContinue
        [pscustomobject]@{
            Path = $t.TaskPath; Name = $t.TaskName; State = $t.State; LastRun = $i.LastRunTime; LastResult = ('0x{0:X}' -f $i.LastTaskResult); NextRun = $i.NextRunTime; Missed = $i.NumberOfMissedRuns
            Exec = (Trunc ((($t.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' | ')) 170)
        }
    }
    "  total: $($tasks.Count)"
    "Non-Microsoft tasks (all):"
    $info | Where-Object { $_.Path -notlike '\Microsoft\*' } | Sort-Object Path, Name | Format-Table Path, Name, State, LastRun, LastResult, NextRun, Missed, Exec -AutoSize | Out-String -Width 320
    "Tasks with non-zero LastResult that ran in last 7d (0x41301 running, 0x41303 never ran, 0x41306 terminated), top 40:"
    $info | Where-Object { $_.LastResult -ne '0x0' -and $_.LastRun -gt $since7 } | Sort-Object LastRun -Descending | Select-Object -First 40 | Format-Table Path, Name, State, LastRun, LastResult, Missed -AutoSize | Out-String -Width 250
    "Task Scheduler operational events, failures (Microsoft-Windows-TaskScheduler/Operational ids 101,103,203,311; 7d; may need admin):"
    try { Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-TaskScheduler/Operational'; Id = 101, 103, 203, 311; StartTime = $since7 } -EA Stop | Group-Object Id | ForEach-Object { "  id {0} x{1}" -f $_.Name, $_.Count } } catch { "  n/a: $($_.Exception.Message)" }
}

# ---------------- 12 processes ----------------
Section '12_processes' {
    $cores = [Environment]::ProcessorCount
    $p1 = Get-Process
    $map = @{}
    foreach ($p in $p1) { try { $map[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { } }
    Start-Sleep -Seconds 3
    $p2 = Get-Process
    $rows = foreach ($p in $p2) {
        $prev = $map[$p.Id]
        $cpuNow = $null; try { $cpuNow = $p.TotalProcessorTime.TotalMilliseconds } catch { }
        $st = $null; try { $st = $p.StartTime } catch { }
        $path = $null; try { $path = $p.Path } catch { }
        $pct = if ($null -ne $prev -and $null -ne $cpuNow) { [math]::Round(($cpuNow - $prev) / 3000 / $cores * 100, 1) } else { $null }
        [pscustomobject]@{ Name = $p.Name; Id = $p.Id; CpuPct = $pct; WS_MB = [math]::Round($p.WorkingSet64 / 1MB); Private_MB = [math]::Round($p.PrivateMemorySize64 / 1MB); Handles = $p.HandleCount; Threads = $p.Threads.Count; Start = $st; Path = $path; Company = $p.Company }
    }
    "Process count: $($p2.Count)  Total handles: $(($p2 | Measure-Object HandleCount -Sum).Sum)  Total threads: $(($rows | Measure-Object Threads -Sum).Sum)  Logical CPUs: $cores"
    "Top 25 by CPU% (3s window, of all cores):"; $rows | Sort-Object CpuPct -Descending | Select-Object -First 25 Name, Id, CpuPct, WS_MB, Private_MB, Handles, Threads, Company | Format-Table -AutoSize
    "Top 25 by working set:"; $rows | Sort-Object WS_MB -Descending | Select-Object -First 25 Name, Id, WS_MB, Private_MB, CpuPct, Handles, Threads, Start, Company | Format-Table -AutoSize
    "Handle hogs (>3000 handles):"; $rows | Where-Object { $_.Handles -gt 3000 } | Sort-Object Handles -Descending | Select-Object Name, Id, Handles, Threads, WS_MB | Format-Table -AutoSize
    "Thread hogs (>300 threads):"; $rows | Where-Object { $_.Threads -gt 300 } | Sort-Object Threads -Descending | Select-Object Name, Id, Threads, Handles, WS_MB | Format-Table -AutoSize
    "Instance counts (top 20 names):"; $rows | Group-Object Name | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object { "  {0,4}  {1,-30} sum WS {2,8} MB  sum CPU% {3}" -f $_.Count, $_.Name, (($_.Group | Measure-Object WS_MB -Sum).Sum), (($_.Group | Measure-Object CpuPct -Sum).Sum) }
    "Distinct process names with paths outside Windows / Program Files:"
    $rows | Where-Object { $_.Path -and $_.Path -notmatch '^(?i)C:\\(Windows|Program Files|Program Files \(x86\))\\' } | Sort-Object Name -Unique | Select-Object Name, Company, Path | Format-Table -AutoSize | Out-String -Width 260
    "Processes started in last 24h (newest first, max 40):"
    $rows | Where-Object { $_.Start -and $_.Start -gt (Get-Date).AddHours(-24) } | Sort-Object Start -Descending | Select-Object -First 40 Start, Name, Id, WS_MB, Company | Format-Table -AutoSize
    "Long-lived heavy processes (started before last 24h, WS > 500 MB):"
    $rows | Where-Object { $_.Start -and $_.Start -lt (Get-Date).AddHours(-24) -and $_.WS_MB -gt 500 } | Sort-Object WS_MB -Descending | Select-Object Start, Name, Id, WS_MB, Private_MB, Handles | Format-Table -AutoSize
}

# ---------------- 13 network ----------------
Section '13_network' {
    "Adapters:"
    Get-NetAdapter -EA SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MediaConnectionState, DriverVersionString, DriverDate, MacAddress | Format-Table -AutoSize | Out-String -Width 260
    "IP config (up adapters):"
    Get-NetIPConfiguration -EA SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { "  {0}: IPv4={1} GW={2} DNS={3}" -f $_.InterfaceAlias, ($_.IPv4Address.IPAddress -join ','), ($_.IPv4DefaultGateway.NextHop -join ','), ($_.DNSServer.ServerAddresses -join ',') }
    "Connection profiles:"; Get-NetConnectionProfile -EA SilentlyContinue | Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity | Format-Table -AutoSize
    "Firewall profiles:"; Get-NetFirewallProfile -EA SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize
    $procs = @{}; Get-Process | ForEach-Object { $procs[$_.Id] = $_.Name }
    "Listening TCP ports (with owning process):"
    Get-NetTCPConnection -State Listen -EA SilentlyContinue | Sort-Object LocalPort | Select-Object LocalAddress, LocalPort, OwningProcess, @{n = 'Proc'; e = { $procs[[int]$_.OwningProcess] } } | Format-Table -AutoSize
    "Established connections per process (top 20):"
    Get-NetTCPConnection -State Established -EA SilentlyContinue | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object { "  {0,4}  {1} (pid {2})" -f $_.Count, $procs[[int]$_.Name], $_.Name }
    "Connection state totals:"; Get-NetTCPConnection -EA SilentlyContinue | Group-Object State | Sort-Object Count -Descending | ForEach-Object { "  {0,5}  {1}" -f $_.Count, $_.Name }
    "Gateway reachability (4 pings):"
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) { Test-Connection -TargetName $gw -Count 4 -EA SilentlyContinue | Select-Object Destination, Status, Latency | Format-Table -AutoSize } else { "  no default route" }
    "DNS resolution test:"; Resolve-DnsName microsoft.com -Type A -EA SilentlyContinue | Select-Object Name, IPAddress, TTL | Format-Table -AutoSize
    "Hosts file (non-comment lines):"; Get-Content C:\Windows\System32\drivers\etc\hosts -EA SilentlyContinue | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
    "User proxy settings:"; Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue | Select-Object ProxyEnable, ProxyServer, AutoConfigURL | Format-List
    "winhttp proxy:"; netsh winhttp show proxy 2>&1
    "Interface statistics (netstat -e):"; netstat -e 2>&1
    "Adapter advanced: power saving / offloads (Ethernet only):"
    Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { $a = $_; Get-NetAdapterAdvancedProperty -Name $a.Name -EA SilentlyContinue | Where-Object { $_.DisplayName -match 'Energy|Power|Green|Speed|Duplex|Interrupt|Jumbo|Flow' } | ForEach-Object { "  {0}: {1} = {2}" -f $a.Name, $_.DisplayName, $_.DisplayValue } }
}

# ---------------- 14 security / updates ----------------
Section '14_security_updates' {
    "Defender status:"
    Get-MpComputerStatus -EA SilentlyContinue | Select-Object AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, IsTamperProtected, AMEngineVersion, AntivirusSignatureVersion, AntivirusSignatureLastUpdated, AntivirusSignatureAge, QuickScanEndTime, QuickScanAge, FullScanEndTime, FullScanAge, ComputerState, DeviceControlState | Format-List
    "Defender threat detections (newest 20, all history):"
    Get-MpThreatDetection -EA SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 20 InitialDetectionTime, ThreatID, ProcessName, ActionSuccess, CurrentThreatExecutionStatusID, Resources | Format-List
    "Defender threat catalog:"; Get-MpThreat -EA SilentlyContinue | Select-Object ThreatName, SeverityID, IsActive, DidThreatExecute | Format-Table -AutoSize
    $pref = Get-MpPreference -EA SilentlyContinue
    "Defender preferences:"
    "  ExclusionPath count: $(@($pref.ExclusionPath).Count)"
    $pref.ExclusionPath | ForEach-Object { "    $_" }
    "  ExclusionProcess: $($pref.ExclusionProcess -join '; ')"
    "  ExclusionExtension: $($pref.ExclusionExtension -join '; ')"
    "  DisableRealtimeMonitoring=$($pref.DisableRealtimeMonitoring) DisableBehaviorMonitoring=$($pref.DisableBehaviorMonitoring) MAPSReporting=$($pref.MAPSReporting) SubmitSamplesConsent=$($pref.SubmitSamplesConsent) PUAProtection=$($pref.PUAProtection) EnableControlledFolderAccess=$($pref.EnableControlledFolderAccess) ScanAvgCPULoadFactor=$($pref.ScanAvgCPULoadFactor) ScanScheduleDay=$($pref.ScanScheduleDay) ScanScheduleTime=$($pref.ScanScheduleTime)"
    "Security Center AV products:"; Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -EA SilentlyContinue | Select-Object displayName, productState, timestamp | Format-Table -AutoSize
    "Defender operational events (30d, detection/protection-state ids):"
    Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1006, 1007, 1008, 1015, 1116, 1117, 1118, 1119, 1120, 5001, 5004, 5007, 5008, 5010, 5012, 2001, 2003; StartTime = $since30 } -EA SilentlyContinue | Select-Object -First 40 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1,5}  {2}" -f $_.TimeCreated, $_.Id, (Trunc $_.Message 240) }
    "Local users:"; Get-LocalUser -EA SilentlyContinue | Select-Object Name, Enabled, LastLogon, PasswordLastSet, PasswordRequired, Description | Format-Table -AutoSize
    "Administrators group:"; Get-LocalGroupMember Administrators -EA SilentlyContinue | Select-Object Name, PrincipalSource, ObjectClass | Format-Table -AutoSize
    "Remote Desktop Users group:"; Get-LocalGroupMember 'Remote Desktop Users' -EA SilentlyContinue | Select-Object Name | Format-Table -AutoSize
    "RDP: fDenyTSConnections=$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -EA SilentlyContinue).fDenyTSConnections) (1 = RDP disabled)"
    $pol = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -EA SilentlyContinue
    "UAC: EnableLUA=$($pol.EnableLUA) ConsentPromptBehaviorAdmin=$($pol.ConsentPromptBehaviorAdmin) PromptOnSecureDesktop=$($pol.PromptOnSecureDesktop)"
    "Secure Boot: $(try { Confirm-SecureBootUEFI } catch { 'n/a: ' + $_.Exception.Message })"
    "TPM:"; try { Get-Tpm -EA Stop | Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated | Format-List } catch { "  n/a: $($_.Exception.Message)" }
    "Failed logons (Security 4625, 7d; needs admin):"; try { $f = @(Get-WinEvent -FilterHashtable @{LogName = 'Security'; Id = 4625; StartTime = $since7 } -EA Stop); "  count: $($f.Count)" } catch { "  n/a: $($_.Exception.Message)" }
    "New services installed (System 7045, 30d):"
    Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7045; StartTime = $since30 } -EA SilentlyContinue | Select-Object -First 20 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.TimeCreated, (Trunc $_.Message 200) }
    "Windows Update last success times:"
    $wu = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results'
    foreach ($s in 'Detect', 'Download', 'Install') { "  {0}: {1}" -f $s, (Get-ItemProperty "$wu\$s" -EA SilentlyContinue).LastSuccessTime }
    "Installed hotfixes (newest 15):"; Get-HotFix -EA SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 15 HotFixID, Description, InstalledOn | Format-Table -AutoSize
    "WU client events (30d; 19 installed, 20 failed, 43 install started, 44 download started):"
    Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; StartTime = $since30 } -EA SilentlyContinue | Select-Object -First 40 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1,3}  {2}" -f $_.TimeCreated, $_.Id, (Trunc $_.Message 170) }
    "WU policies:"; Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -EA SilentlyContinue | Select-Object NoAutoUpdate, AUOptions, UseWUServer | Format-List
    "WU pause state:"; Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -EA SilentlyContinue | Select-Object PauseUpdatesExpiryTime, PauseFeatureUpdatesStartTime, PauseQualityUpdatesStartTime, ActiveHoursStart, ActiveHoursEnd | Format-List
    "Windows Security health (wscsvc): $((Get-Service wscsvc -EA SilentlyContinue).Status)   WinDefend: $((Get-Service WinDefend -EA SilentlyContinue).Status)"
}

# ---------------- 15 installed apps (recent changes) ----------------
Section '15_installed_apps_recent' {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = @(Get-ItemProperty $keys -EA SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate)
    "Installed apps (registry): $($apps.Count)"
    $cut = (Get-Date).AddDays(-45).ToString('yyyyMMdd')
    "Installed/updated in last 45 days (InstallDate yyyymmdd, newest first):"
    $apps | Where-Object { $_.InstallDate -and $_.InstallDate -ge $cut } | Sort-Object InstallDate -Descending | Format-Table InstallDate, DisplayName, DisplayVersion, Publisher -AutoSize | Out-String -Width 220
    "Security/system-affecting software present (AV, VPN, overlays, RGB, tuning, virtualization, remote access):"
    $apps | Where-Object { $_.DisplayName -match '(?i)antivirus|norton|mcafee|avast|avg|kaspersky|bitdefender|malwarebytes|vpn|nord|express|proton|wireguard|tailscale|zerotier|hamachi|overlay|rivatuner|afterburner|icue|armoury|aura|razer|synapse|logitech|g hub|corsair|nzxt|cam |lian|signalrgb|openrgb|hwinfo|throttlestop|process lasso|vmware|virtualbox|hyper-v|docker|wsl|teamviewer|anydesk|parsec|rustdesk|chrome remote|discord|steam|epic|battle\.net|gog|ea app|ubisoft|riot|vanguard|faceit|easy anti|battleye|wallpaper engine|voicemeeter|wave link|elgato|obs|nvidia|geforce|amd|intel|realtek|asus|msi|gigabyte|asrock' } | Sort-Object DisplayName | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize | Out-String -Width 220
}

# ---------------- 16 display / input / user session ----------------
Section '16_display_session_misc' {
    "Display config (DXGI-level):"
    Get-CimInstance Win32_DesktopMonitor -EA SilentlyContinue | Select-Object Name, Status, ScreenWidth, ScreenHeight | Format-Table -AutoSize
    "Logged-on sessions:"; query user 2>&1
    "Explorer restarts today (Application Error / Hang naming explorer.exe, 7d):"
    Get-WinEvent -FilterHashtable @{LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; StartTime = $since7 } -EA SilentlyContinue | Where-Object { $_.Message -match '(?i)explorer\.exe|dwm\.exe|ShellExperienceHost|StartMenuExperienceHost|SearchHost|widgets' } | Select-Object -First 15 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.TimeCreated, (Trunc $_.Message 180) }
    "DWM / shell events (Microsoft-Windows-Dwm-Core, 7d):"
    Get-WinEvent -FilterHashtable @{LogName = 'Application'; ProviderName = 'Desktop Window Manager'; StartTime = $since7 } -EA SilentlyContinue | Select-Object -First 10 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.TimeCreated, (Trunc $_.Message 180) }
    "Windows Search indexer status:"
    try { $idx = New-Object -ComObject Microsoft.Search.Interop.CSearchManager -EA Stop; "  n/a (COM not available)" } catch { "  COM unavailable; service state: $((Get-Service WSearch -EA SilentlyContinue).Status)" }
    "Fonts / temp dir sizes (bounded, no listing):"
    $tmp = [IO.Path]::GetTempPath()
    $tsum = (Get-ChildItem $tmp -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    "  user temp: {0:N1} GB  ({1})" -f ($tsum / 1GB), (Split-Path $tmp -Leaf)
    $wtmp = 'C:\Windows\Temp'
    $wsum = (Get-ChildItem $wtmp -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    "  windows temp: {0:N1} GB" -f ($wsum / 1GB)
    $sd = 'C:\Windows\SoftwareDistribution\Download'
    if (Test-Path $sd) { $ssum = (Get-ChildItem $sd -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum; "  SoftwareDistribution\Download: {0:N1} GB" -f ($ssum / 1GB) }
    "Windows.old present: $(Test-Path 'C:\Windows.old')"
    "Hibernation file: $(if (Test-Path 'C:\hiberfil.sys') { '{0:N1} GB' -f ((Get-Item 'C:\hiberfil.sys' -Force -EA SilentlyContinue).Length / 1GB) } else { 'absent' })"
    "Pagefile on C: $(if (Test-Path 'C:\pagefile.sys') { '{0:N1} GB' -f ((Get-Item 'C:\pagefile.sys' -Force -EA SilentlyContinue).Length / 1GB) } else { 'absent' })"
    "Swapfile on C: $(if (Test-Path 'C:\swapfile.sys') { '{0:N1} GB' -f ((Get-Item 'C:\swapfile.sys' -Force -EA SilentlyContinue).Length / 1GB) } else { 'absent' })"
}

# ---------------- index ----------------
$idx = ($script:index -join "`n")
Set-Content -Path (Join-Path $OutDir '_index.txt') -Value $idx -Encoding UTF8
"COLLECTION COMPLETE -> $OutDir"
$idx
