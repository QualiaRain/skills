# mouse-dpi

A Claude Code skill for answering "why does my mouse feel wrong in this game" with
arithmetic instead of guesswork.

It finds your mouse's **real** DPI, checks that Windows is not silently rescaling
your pointer, works out how a specific game converts mouse counts into camera
degrees, and then solves for the in-game slider value that gives you the
**cm/360** you want - the number of centimetres of desk it takes to turn a full
circle. cm/360 is the only sensitivity measure that compares meaningfully across
games, so once you know yours, matching a new game stops being a taste question.

Claude loads this automatically when you ask something like "what DPI am I on",
"set my sens in X", "make X feel like Y", or "the mouse feels off since I changed
something". You can also just run the scripts yourself.

## The one equation

```
cm/360 = (360 * 2.54) / (dpi * degrees_per_count)   =   914.4 / (dpi * deg_per_count)
```

Everything the game does is in `degrees_per_count`, which is a function of its
sensitivity setting. `games.md` records that function per game; `sens_calc.py`
does the rest.

## Requirements

| Need | For what | Notes |
|---|---|---|
| Windows 10 or 11 | everything | The registry, HID and SendInput paths are Windows-only. |
| Python 3.11+ | all `.py` scripts | Standard library only, except `logi_dpi.py`. Nothing to `pip install`. Verified on 3.11 and 3.12 on 2026-09-02: `--selftest`, the spin dry-run, the raw-input refusal path, `ghub_dpi.py` and the HID++ read all pass on both. |
| PowerShell | `.ps1` scripts | pwsh 7 recommended; Windows PowerShell 5.1 works. |
| [uv](https://docs.astral.sh/uv/) | `logi_dpi.py` only | Supplies `hidapi` in a throwaway environment so nothing is installed into your Python. Install: `winget install astral-sh.uv` |

## Logitech-only vs works-on-anything

**Logitech-only:**

- `scripts/logi_dpi.py` - reads the DPI over HID++ 2.0 straight from the mouse.
  The only way to get ground truth without a ruler. Verified 2026-09-01 against a
  Logitech G PRO-series wireless mouse via a LIGHTSPEED receiver, feature 0x2202,
  and re-run on 2026-09-02; it speaks plain HID++ 2.0 to any Logitech interface on usage page
  0xFF00 or 0xFF43 (the two pages Solaar and libratbag enumerate), so a Unifying
  receiver or a wired Logitech mouse should work too - **untested**, and it stays
  labelled untested until someone runs it on that hardware and says so here.
- `scripts/ghub_dpi.py` - reads Logitech G HUB's `settings.db`. Software intent
  only; it is frequently out of step with the mouse.

Both exit non-zero with an explanation on other hardware rather than guessing.

**Works on any mouse, any brand:**

- `scripts/windows_pointer_check.ps1` - is Windows scaling your pointer?
- `scripts/sens_calc.py` - the cm/360 calculator.
- `scripts/spin_test.py` - proves a game's formula by injecting an exact turn.
- `scripts/rawinput_dpi_test.py` - measures real DPI with a ruler and Raw Input.
- `games.md` and `reference/` - the per-game ledger and the how-to-derive guide.

**On non-Logitech hardware this skill cannot read or set DPI; the ruler test is
the only ground truth.** On a Razer/SteelSeries/Corsair mouse, read the DPI out
of the vendor software, treat it as intent, and confirm it with
`rawinput_dpi_test.py` and a ruler. Everything downstream of that is identical.

## Quick start

**Every path below is relative to the skill folder** (`~/.claude/skills/mouse-dpi`
when installed as a Claude Code skill): `cd` there first, or prefix the path.

```
pwsh -NoProfile -File scripts/smoke.ps1                 # does it work here?
pwsh -NoProfile -File scripts/windows_pointer_check.ps1 # is Windows 1:1?
uv run --with hidapi python scripts/logi_dpi.py read    # real DPI (Logitech)
python scripts/sens_calc.py --dpi 800 --game source --target-cm360 30
```

`smoke.ps1` prints PASS / FAIL / SKIP for every read-only check and ends with
`SUMMARY: 7 pass, 0 fail, 0 skip` on a Logitech rig with G HUB. SKIP lines are
normal on non-Logitech hardware. Every outcome ends with a `VERDICT:` line, so a
caller never has to parse the block above it; argparse usage errors - a bad flag,
a missing required one - print usage instead, on stderr, with exit 2.

## Safety

Three scripts are not read-only. Each refuses to act without an explicit flag,
and each shows you the before and after:

| Script | What it does | Gate |
|---|---|---|
| `logi_dpi.py --set N` | writes a new DPI to the mouse | `--yes`; prints the DPI read back from the device afterwards, never the value sent |
| `rawinput_dpi_test.py` | captures every mouse movement system-wide for the capture window | `--yes`; only mouse deltas, nothing written to disk |
| `spin_test.py` | injects mouse movement into the focused window | `--yes`; `--dry-run` previews the plan and injects nothing |

Do not run any of the three during a live match. **Never run `spin_test.py` at all
against a game with kernel-level anti-cheat** - Vanguard (Valorant), EAC,
BattlEye, Javelin - because injected input can be flagged even in a practice range
or an offline mode; use the hand-distance test on those. Everything else here only
reads.

## What is in the box

| File | What it is |
|---|---|
| `SKILL.md` | The runbook Claude follows, in order, with the landmines. |
| `games.md` | Per-game ledger: config location, setting key, the deg/count formula, and where each formula came from. Add a row whenever you work one out. |
| `reference/finding-a-formula.md` | How to derive a formula for a game that is not in the ledger - Unity, Unreal, Source, Minecraft, or measure it. |
| `reference/windows-pointer.md` | The pointer-speed notch/multiplier table and how to fold a non-1:1 slider into your DPI without breaking every game you already tuned. |
| `baseline.template.md` | The empty shape of `baseline.md`: the per-game table, the fields to fill in, and the append-only recording rules. |
| `scripts/` | The tools. Every one has `--help` (or `Get-Help` for `.ps1`). |

`baseline.md` holds one person's own settled cm/360 and hardware. If this copy
came to you without it, that is on purpose - it is the only file with personal
data in it, and nothing else depends on its contents. Create your own once you
have converged on a feel you like: **copy `baseline.template.md` to `baseline.md`
and fill it in**. `SKILL.md` steps 4A and 8 tell Claude to do exactly that. Keep
it append-only - a correction goes below the line it corrects, never over it.

## Licence / provenance

Every formula in `games.md` carries where it came from and the date - decompiled
game code, a measured turn, a community calculator, or a single forum post - so
you can see how much to trust it before acting on it. Nothing here is copied from
a proprietary converter; the engine constants are public knowledge and the rest
was derived on the machine that built this.
