<#
.SYNOPSIS
    Read-only sanity check on the Windows pointer pipeline. Prints one verdict
    line and exits non-zero if the pointer is not 1:1.

.DESCRIPTION
    Two Windows settings silently rescale every application that reads the mouse
    CURSOR instead of raw input, which makes any cm/360 arithmetic wrong for
    those applications and produces the classic "the desktop is fine but games
    feel wrong" complaint:

      MouseSensitivity   a registry value 1-20 on the ladder
                         1,2,4,6,8,10,12,14,16,18,20, which are the 11 slider
                         notches. Value 10 is notch 6/11 and is the 1:1 setting.
                         Any other value multiplies pointer movement by a fixed
                         factor, printed below.

      MouseSpeed 0 plus MouseThreshold1/2 0 means Enhance Pointer Precision is
                         OFF. With EPP on, the multiplier depends on how fast
                         the mouse moved, so the same physical swipe gives a
                         different turn every time and no stable cm/360 exists.

    Raw-input applications - virtually every 3D game - bypass both. You cannot
    tell from outside which kind a given game is, so check regardless: it is one
    call. Reads only; changes nothing.

    Multiplier provenance: value 4 = 0.25 and value 10 = 1.0 were measured on
    the machine this skill was built on, by injected-move test in August 2026.
    The other nine rows are the public Windows pointer-ballistics table and have
    not been measured here.
    Detail and the fold-the-multiplier-into-DPI method: reference/windows-pointer.md

    ASCII only on purpose: PowerShell 5.1 reads a BOM-less .ps1 as ANSI and
    mangles smart quotes and dashes.

.EXAMPLE
    pwsh -NoProfile -File scripts/windows_pointer_check.ps1

    Smoke test. Exit code 0 means clean, 1 means something is rescaling the
    pointer, 2 means the registry values could not be read at all.
#>

$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Control Panel\Mouse'

function Get-MouseValue([string]$name) {
    try {
        $v = (Get-ItemProperty -Path $key -Name $name -ErrorAction Stop).$name
        if ($null -eq $v) { return $null }
        return [int]"$v"
    } catch {
        return $null
    }
}

$sens = Get-MouseValue 'MouseSensitivity'
$speed = Get-MouseValue 'MouseSpeed'
$t1 = Get-MouseValue 'MouseThreshold1'
$t2 = Get-MouseValue 'MouseThreshold2'

if ($null -eq $sens) {
    Write-Output "VERDICT: FAIL - could not read MouseSensitivity from $key"
    exit 2
}

# Registry value -> slider notch (1..11) -> fixed multiplier on every delta.
$notchTable = @(1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20)
$multTable = @(0.03125, 0.0625, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5)

$idx = $notchTable.IndexOf([int]$sens)
if ($idx -ge 0) {
    $notchText = "notch $($idx + 1)/11"
    $mult = $multTable[$idx]
    $multText = "x$mult"
} else {
    $notchText = 'non-standard value, not on the slider ladder'
    $mult = $null
    $multText = 'x? (unknown - off-ladder values are not in the published table)'
}

Write-Output ("MouseSensitivity={0} ({1}, {2})  MouseSpeed={3}  MouseThreshold1={4}  MouseThreshold2={5}" -f `
    $sens, $notchText, $multText, $speed, $t1, $t2)

$problems = @()
if ($sens -ne 10) {
    $problems += "pointer speed is not 1:1 (MouseSensitivity=$sens, $multText; want 10 = notch 6/11 = x1.0)"
}
if ($speed -ne 0 -or $t1 -ne 0 -or $t2 -ne 0) {
    $problems += 'Enhance Pointer Precision is ON (want MouseSpeed/MouseThreshold1/MouseThreshold2 all 0)'
}

if ($problems.Count -eq 0) {
    Write-Output 'VERDICT: clean - 1 count in, 1 pixel out, no acceleration. cm/360 math is valid.'
    exit 0
}

if ($null -ne $mult -and $mult -ne 1.0) {
    Write-Output ("  Cursor-reading apps are running at an effective {0} x DPI while raw-input games are not." -f $mult)
    Write-Output ("  The fix is usually to fold that {0} into the mouse DPI rather than to leave the slider off-centre;" -f $mult)
    Write-Output ("  that also means every raw-input game tuned before the change needs its sensitivity re-solved.")
}
Write-Output '  Read reference/windows-pointer.md before changing either number.'
Write-Output '  UI path, Windows 11: Settings > Bluetooth and devices > Mouse > Additional mouse settings > Pointer Options.'
Write-Output '  UI path, Windows 10: Settings > Devices > Mouse > Additional mouse options > Pointer Options.'
Write-Output ("VERDICT: " + ($problems -join ' + '))
exit 1
