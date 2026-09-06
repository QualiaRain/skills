# The Windows pointer pipeline, and folding it into DPI

Read this when `scripts/windows_pointer_check.ps1` says anything but `clean`, or
whenever someone says the desktop feels fine but games feel wrong (or the
reverse). That sentence is the signature of this whole problem.

## What Windows actually does to mouse counts

Two independent things sit between the sensor and a cursor-reading application:

1. **Pointer speed** (`HKCU:\Control Panel\Mouse` -> `MouseSensitivity`, a
   REG_SZ number 1-20). A fixed multiplier on every mouse delta.
2. **Enhance Pointer Precision** (`MouseSpeed`, `MouseThreshold1`,
   `MouseThreshold2`). A *speed-dependent* multiplier - Windows pointer
   ballistics. With it on, the same physical swipe produces a different turn
   depending on how fast it was made, so no stable cm/360 exists at all.

**Raw-input applications bypass both.** Anything reading WM_INPUT - virtually
every 3D game, and any game that locks the cursor - sees the sensor's counts
untouched. Cursor-reading surfaces - the desktop, most 2D UI, menus, some older
or 2D games - see the scaled version.

So with pointer speed at anything other than 1:1, the machine is running **two
different effective DPIs at once**, and which one a given piece of software uses
is not visible from outside.

## The notch / multiplier table

The pointer-speed slider has 11 positions but the registry value is not the
position. Reading `MouseSensitivity` as a notch number is an off-by-several
mistake that has already caused one wrong note in this skill's history.

| Notch | `MouseSensitivity` | Multiplier |
|---|---|---|
| 1/11 | 1 | 0.03125 (1/32) |
| 2/11 | 2 | 0.0625 (1/16) |
| 3/11 | 4 | **0.25** |
| 4/11 | 6 | 0.5 |
| 5/11 | 8 | 0.75 |
| 6/11 | 10 | **1.0** - the default, 1 count in = 1 pixel out |
| 7/11 | 12 | 1.5 |
| 8/11 | 14 | 2.0 |
| 9/11 | 16 | 2.5 |
| 10/11 | 18 | 3.0 |
| 11/11 | 20 | 3.5 |

Provenance: the two bolded rows were **measured on the machine this skill was
built on, in mid-August 2026**, by an injected-move test -
`MouseSensitivity=4` moved the cursor exactly
0.25 px per count, and `MouseSensitivity=10` moved it exactly 1 px per count in
24 of 25 samples. The other nine rows are public knowledge (the Windows pointer
ballistics table) and have not been measured here. Say which when quoting them.

`windows_pointer_check.ps1` prints the multiplier for whatever value it finds, so
you do not have to read this table to get the number - only to check it.

## Folding the multiplier into DPI

**When to reach for this:** pointer speed is not 1.0 and the person wants the
desktop and their games to agree. It is the correct fix, not a workaround, and it
is strictly better than leaving the slider off-centre - but it invalidates every
in-game sensitivity that was tuned before it, all at once. That aftercare is the
expensive half; do not do the first part without doing the second.

Given a current pointer multiplier `m` and a current mouse DPI `D`:

```
desktop / cursor apps behave as   D * m
raw-input games behave as         D
they disagree by                  1/m
```

The move:

1. **New DPI `D' = D * m`**, set on the mouse (`logi_dpi.py --set D' --yes`, or
   the vendor software). Round to an available stage if `D * m` is not one.
2. **Pointer speed to notch 6/11 (`MouseSensitivity` 10)**, EPP off.
3. The desktop is now *unchanged*: `D' * 1.0 == D * m`. Hand-to-cursor distance
   is identical to before.
4. Every **raw-input** game is now slower by `m`, so each one's in-game
   sensitivity has to come back up to hold its cm/360. Cursor-reading games and
   apps need no change. **How much it has to come up depends on the game's
   formula:**
   - **Linear** (`deg/count = k * s`, which is most games): multiply by `1/m`.
   - **Nonlinear** (Minecraft's cubic, anything with a curve near zero):
     **re-solve**, do not multiply. Worked case: Minecraft at `s = 0.18` and
     1600 DPI is 16.30 cm/360; the same feel at 400 DPI needs `s ~ 0.48`, while
     the naive `0.18 * 4 = 0.72` lands at 7.5 cm/360 - 2.2x too fast. The needed
     factor is not even constant along the slider, so there is no shortcut:
     `python scripts/sens_calc.py --dpi <new> --game <g> --target-cm360 <old>`.
5. If step 1 had to round to a stage `D''` instead of `D'`, correct for it: every
   game's sensitivity gets an extra factor of `D' / D''`, subject to the same
   linear/nonlinear rule.

**Worked example, and the one the machine this skill was built on actually ran
(August 2026):** `m = 0.25` at `D = 1600`. New DPI `1600 * 0.25 = 400`; slider to notch 6. The
desktop feels identical. Every raw-input game whose sensitivity was tuned at 1600
DPI is now **4x slower in the hand** and needs its setting raised - by exactly
x4 if the game is linear, by a re-solve if it is not.

## Why this is better than just leaving the slider alone

At `m < 1` Windows scales the delta down and rounds, so slow, fine movements get
quantized toward zero and small corrections are simply lost - it feels like a
dead zone or like the pointer is sticky. At `m > 1` it multiplies up, so the
cursor skips pixels and fine positioning is impossible. Only `m = 1` passes every
count through intact. Folding the factor into DPI buys back that resolution while
keeping the hand distance identical.

This also explains a complaint that sounds like acceleration but is not: at
`m < 1`, the desktop is slow and every raw-input game is `1/m` times faster than
the hand expects. That mismatch gets described as "severe acceleration" or "the
mouse is inconsistent" even with EPP already off.

## Aftercare, and the trap in it

The change is one command; remembering which games it broke is the hard part,
and nobody remembers correctly.

- Record the date and the ratio in `baseline.md` the same session.
- Then walk `games.md` row by row. For each game, recompute its cm/360 at the
  **new** DPI and compare it against the cm/360 it had at the old one. Do not ask
  whether they "re-tuned it" - a save file's own timestamp answers that better
  than memory does, and a game not opened since the change definitely was not
  re-tuned.
- A game whose config predates the change and was never reopened is still on the
  old number and is wrong by `1/m`. Say so with the file date as evidence.

## Changing pointer speed

The two-second route is the UI. Slider to the 6th notch, and untick "Enhance
pointer precision".

- **Windows 11:** Settings > Bluetooth & devices > Mouse > Additional mouse
  settings > Pointer Options.
- **Windows 10:** Settings > Devices > Mouse > Additional mouse options >
  Pointer Options.

Both land on the same Control Panel applet, so `main.cpl` typed into Run gets
there directly on either version.

If it has to be scripted: writing `MouseSensitivity` in the registry is **inert
until the next sign-in** unless the write is followed by a
`SystemParametersInfo(SPI_SETMOUSESPEED, ...)` call with `SPIF_SENDCHANGE`.
(Documented Win32 behaviour; not measured here.) A registry write that appears to
succeed and changes nothing is exactly the silent failure this skill is trying to
avoid, so prefer the UI, and if you do script it, verify by measuring cursor
movement, not by reading the value back.
