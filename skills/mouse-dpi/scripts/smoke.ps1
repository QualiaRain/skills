<#
.SYNOPSIS
    Run every READ-ONLY check in the mouse-dpi skill and print PASS / FAIL / SKIP
    per line. Nothing here writes to the mouse, injects input, or captures input.

.DESCRIPTION
    This is the "does this skill still work" check, and the first thing to run in
    a fresh session or on a machine that has never used it. It is safe to run
    while a game is open.

    Checks, in order:
      1. --help on every script          - catches an import or docstring break
      2. sens_calc --selftest            - the arithmetic, against hand-computed
                                           values; this is the one that matters
      3. sens_calc worked example        - a real invocation, exact expected value
      4. windows_pointer_check.ps1       - reads HKCU pointer settings
      5. ghub_dpi.py                     - reads G HUB's settings.db if present
      6. logi_dpi.py read                - HID++ read if a Logitech receiver is
                                           present and `uv` is installed
      7. spin_test.py --dry-run          - builds an injection plan, injects
                                           nothing

    SKIP is a correct outcome, not a failure: checks 5 and 6 SKIP on non-Logitech
    hardware, and 6 also SKIPs without `uv`. Checks 1, 2, 3 and 7 must PASS on any
    Windows machine with Python 3.11+ - if they do not, the skill itself is broken.

    Python floor: every script here is verified on 3.11 and 3.12 on 2026-09-02
    (3.11.15 via `uv run --python 3.11`, 3.12 as the machine's own interpreter) -
    sens_calc --selftest, spin_test --dry-run, the rawinput refusal path,
    ghub_dpi, and the logi_dpi HID++ read all pass on both.

    Check 6 can SKIP transiently on a Logitech rig: the HID++ read is a live
    request to the mouse, and a receiver saturated with motion (someone is
    playing, 2000 Hz report rate) can miss the reply window. Measured 2026-09-02
    while the machine was in a game: roughly one run in three answered, and the
    same command run standalone answered in between the SKIPs. So a lone SKIP
    here is not evidence the mouse is non-Logitech - re-run it two or three
    times before believing it, and read logi_dpi.py's own probe list.

    Check 4 FAILs when the machine's pointer is not 1:1. That is a real finding
    about the machine, not a defect in the skill, and it is exactly what the
    skill exists to catch - read reference/windows-pointer.md before changing
    anything.

    rawinput_dpi_test.py is deliberately NOT run here: running it at all opens a
    system-wide mouse capture window, so only its --help is checked.

    Every outcome in this skill ends with a line starting `VERDICT:`, which is
    what the per-check detail column below quotes; argparse usage errors (a bad
    or missing flag) print usage on stderr instead. This script does the same:
    its own last line is `VERDICT: PASS` or `VERDICT: FAIL`, printed after the
    `SUMMARY:` count line, including the no-Python early exit.

.EXAMPLE
    pwsh -NoProfile -File scripts/smoke.ps1

    Exit code 0 if nothing FAILed, 1 otherwise. On a Logitech rig with G HUB
    installed, expect `SUMMARY: 7 pass, 0 fail, 0 skip`.
#>

$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
$results = New-Object System.Collections.Generic.List[object]

function Get-PythonExe {
    foreach ($c in @('python', 'python3')) {
        $p = Get-Command $c -ErrorAction SilentlyContinue
        if ($p) { return $p.Source }
    }
    $py = Get-Command 'py' -ErrorAction SilentlyContinue
    if ($py) { return $py.Source }
    return $null
}

function Add-Result([string]$state, [string]$name, [string]$detail) {
    $results.Add([pscustomobject]@{ State = $state; Name = $name; Detail = $detail })
    Write-Output ("{0,-4}  {1,-28}  {2}" -f $state, $name, $detail)
}

function Invoke-Capture([string]$exe, [string[]]$argv) {
    $out = & $exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

function Get-LastLine([string]$text, [string]$match) {
    $lines = ($text -split "`r?`n") | Where-Object { $_.Trim() -ne '' }
    if ($match) {
        $hit = $lines | Where-Object { $_ -match $match } | Select-Object -Last 1
        if ($hit) { return $hit.Trim() }
    }
    if ($lines.Count -gt 0) { return ($lines[-1]).Trim() }
    return '(no output)'
}

Write-Output "mouse-dpi smoke test - read-only, nothing here moves the mouse"
Write-Output ("scripts: {0}" -f $scriptDir)
Write-Output ''

$python = Get-PythonExe
if (-not $python) {
    Add-Result 'FAIL' 'python' 'no python on PATH - install Python 3.11+ (see README.md)'
    Write-Output ''
    Write-Output 'SUMMARY: 0 pass, 1 fail, 0 skip'
    Write-Output 'VERDICT: FAIL - no Python on PATH, so nothing could be checked. Install Python 3.11+ (README.md).'
    exit 1
}

# ---------------------------------------------------------------- 1. --help
$helpOk = $true
$helpBad = @()
foreach ($s in @('sens_calc.py', 'ghub_dpi.py', 'logi_dpi.py', 'spin_test.py', 'rawinput_dpi_test.py')) {
    $r = Invoke-Capture $python @((Join-Path $scriptDir $s), '--help')
    if ($r.Code -ne 0) { $helpOk = $false; $helpBad += "$s (exit $($r.Code))" }
}
if ($helpOk) {
    Add-Result 'PASS' '--help on all 5 scripts' 'every script explains itself'
} else {
    Add-Result 'FAIL' '--help on all 5 scripts' ("broken: " + ($helpBad -join ', '))
}

# ------------------------------------------------------- 2. sens_calc selftest
$r = Invoke-Capture $python @((Join-Path $scriptDir 'sens_calc.py'), '--selftest')
if ($r.Code -eq 0) {
    Add-Result 'PASS' 'sens_calc --selftest' (Get-LastLine $r.Out 'SELFTEST')
} else {
    Add-Result 'FAIL' 'sens_calc --selftest' (Get-LastLine $r.Out 'FAIL')
}

# -------------------------------------------------- 3. sens_calc worked example
# Hand-checked: deg/count wanted = 914.4 / (800 * 30) = 0.0381; s = 0.0381/0.022.
$r = Invoke-Capture $python @((Join-Path $scriptDir 'sens_calc.py'),
    '--dpi', '800', '--game', 'source', '--target-cm360', '30')
if ($r.Code -eq 0 -and $r.Out -match 'SET s = 1\.7318') {
    Add-Result 'PASS' 'sens_calc worked example' 'source @ 800 dpi, 30 cm/360 -> s = 1.7318'
} else {
    Add-Result 'FAIL' 'sens_calc worked example' ("expected 'SET s = 1.7318', got: " + (Get-LastLine $r.Out 'target'))
}

# ------------------------------------------------------- 4. windows pointer
$pwshExe = (Get-Process -Id $PID).Path
$r = Invoke-Capture $pwshExe @('-NoProfile', '-File', (Join-Path $scriptDir 'windows_pointer_check.ps1'))
$verdict = Get-LastLine $r.Out 'VERDICT'
if ($r.Code -eq 0) {
    Add-Result 'PASS' 'windows_pointer_check' $verdict
} elseif ($r.Code -eq 1) {
    Add-Result 'FAIL' 'windows_pointer_check' ($verdict + '  <- real finding about this PC, not a skill defect')
} else {
    Add-Result 'FAIL' 'windows_pointer_check' ('script error: ' + $verdict)
}

# ------------------------------------------------------------- 5. G HUB db
$r = Invoke-Capture $python @((Join-Path $scriptDir 'ghub_dpi.py'))
$verdict = Get-LastLine $r.Out 'VERDICT'
switch ($r.Code) {
    0 { Add-Result 'PASS' 'ghub_dpi (intent only)' $verdict }
    2 { Add-Result 'SKIP' 'ghub_dpi (intent only)' 'no G HUB on this machine - expected off a Logitech rig' }
    default { Add-Result 'FAIL' 'ghub_dpi (intent only)' $verdict }
}

# ------------------------------------------------------------ 6. HID++ read
$uv = Get-Command 'uv' -ErrorAction SilentlyContinue
if (-not $uv) {
    Add-Result 'SKIP' 'logi_dpi read (HID++)' 'no `uv` on PATH - see README.md for the one-line install'
} else {
    $r = Invoke-Capture $uv.Source @('run', '--with', 'hidapi', 'python',
        (Join-Path $scriptDir 'logi_dpi.py'), 'read')
    $verdict = Get-LastLine $r.Out 'VERDICT'
    if ($r.Code -eq 0) {
        Add-Result 'PASS' 'logi_dpi read (HID++)' $verdict
    } elseif ($r.Code -eq 2) {
        Add-Result 'SKIP' 'logi_dpi read (HID++)' 'no Logitech HID++ device answered - expected on other brands'
    } else {
        Add-Result 'FAIL' 'logi_dpi read (HID++)' $verdict
    }
}

# ---------------------------------------------------------- 7. spin dry run
$r = Invoke-Capture $python @((Join-Path $scriptDir 'spin_test.py'),
    '--game', 'source', '--sens', '1.5', '--dry-run')
if ($r.Code -eq 0 -and $r.Out -match 'nothing injected') {
    Add-Result 'PASS' 'spin_test --dry-run' (Get-LastLine $r.Out 'VERDICT')
} else {
    Add-Result 'FAIL' 'spin_test --dry-run' (Get-LastLine $r.Out 'VERDICT')
}

# ------------------------------------------------------------------ summary
$pass = ($results | Where-Object { $_.State -eq 'PASS' }).Count
$fail = ($results | Where-Object { $_.State -eq 'FAIL' }).Count
$skip = ($results | Where-Object { $_.State -eq 'SKIP' }).Count
Write-Output ''
Write-Output ("SUMMARY: {0} pass, {1} fail, {2} skip" -f $pass, $fail, $skip)
if ($fail -eq 0) {
    Write-Output 'VERDICT: PASS - the skill works on this machine.'
    exit 0
}
Write-Output 'A windows_pointer_check FAIL is a finding about the machine; any other FAIL'
Write-Output 'means the skill itself needs fixing.'
Write-Output ("VERDICT: FAIL - {0} of {1} checks failed; see the FAIL lines above." -f `
    $fail, ($pass + $fail + $skip))
exit 1
