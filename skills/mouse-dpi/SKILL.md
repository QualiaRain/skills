---
name: mouse-dpi
description: >-
  Find a mouse's real DPI and set in-game sensitivity to a target cm/360 on Windows - HID++ read of a Logitech LIGHTSPEED receiver for ground truth, G HUB settings.db as intent only, a Windows pointer-speed sanity check, then work out how a game maps mouse counts to camera degrees and solve for the slider. Use whenever mouse feel or mouse numbers come up - mouse dpi, what dpi am I on, set my sensitivity, sens, eDPI, cm/360, match my sensitivity in a game, make the mouse feel the same in a game, polling rate, new mouse set it up, this game feels too fast or too slow, the mouse feels off since I changed something. Not for display DPI or Windows display scaling, a mouse that is broken, laggy, or dropping connection, or FPS and stutter tuning (game-perf-tuning-windows).
---

# Mouse DPI and in-game sensitivity

Every "this game feels wrong" question reduces to one chain, and each link is
knowable rather than a matter of taste:

```
in-game setting s  ->  degrees of camera yaw per mouse count   (the game's formula)
mouse DPI          ->  counts per cm of desk                   (the hardware)
                   ->  cm of desk per 360 degree turn          = what the hand knows
```

**The master equation, used by every script and every number in this skill:**

```
cm/360 = (360 * 2.54) / (dpi * deg_per_count)     =  914.4 / (dpi * deg_per_count)
```

So the job is: get the real DPI, get the game's formula, pick a target cm/360,
solve, apply, **verify**, converge. Work the steps in order - each invalidates the
next if wrong, and skipping step 2 is the commonest way to produce confident
arithmetic that does not match what the hand feels. **Every path below is relative
to the skill folder** (`~/.claude/skills/mouse-dpi`): `cd` there, or prefix it.

## Fast route

| What was said | Go to |
|---|---|
| "what DPI am I on" / "did my DPI change" | Step 1 |
| "the mouse feels off / too fast / too slow everywhere, not just in a game" | Step 2 first, then Step 1 |
| "make \<game\> feel like \<other game\>" | Step 3, then Step 4 "match another game" |
| "set my sens in \<game\>" / "this game feels wrong" | Steps 1-2 (one command each), then 3 |
| "I changed my DPI, what do I do about my games" | Step 4, the slider-folding section |
| "new mouse, set it up" | Steps 1, 2, then 4D: the target is the old cm/360, so the OLD mouse's DPI must be known (`baseline.md` hardware section, or the old vendor software); 4B only if no old DPI was recorded |
| "is my polling rate right" | It does not affect cm/360. Landmines, last bullet |

Personal reference values - a settled cm/360, the hardware it was measured on,
per-game set-points - live in **`baseline.md`**, and the worked examples below use
those numbers, so read them as illustrations, not as anyone else's answer.
`pwsh -NoProfile -File scripts/smoke.ps1` proves in ~15 s what works on a machine
that has never run this skill.

## Step 1 - DPI ground truth

Three sources, in descending order of authority. **If source 1 answers, stop; 2 is
for when 1 fails; 3 only when 1 and 2 both fail or disagree.**

```
uv run --with hidapi python scripts/logi_dpi.py read                    # 1
python scripts/ghub_dpi.py                # 2  --all for prefabs, --json to pipe
python scripts/rawinput_dpi_test.py --distance-cm 20 --seconds 8 --yes  # 3
```

`logi_dpi.py` needs `uv` (`winget install astral-sh.uv`); everything else is
plain Python.

1. **HID++ read - this is the answer (Logitech only).** Talks HID++ 2.0 straight
   to the mouse through the receiver and reports what the sensor is actually set
   to; no Logitech software need be running. Also reports the DPI stages and the
   report rate. *Not a Logitech mouse?* It says so and exits non-zero -
   Razer/SteelSeries/Corsair keep onboard DPI in vendor software with no open
   protocol here, so read it out of that software, treat it as intent (same
   caveat as 2), and confirm with 3.
2. **G HUB `settings.db` - intent only, and often wrong.** Reads
   `%LOCALAPPDATA%\LGHUB\settings.db` read-only and follows the two-hop card
   chain to the DPI table; it also reports the polling rate and whether the G HUB
   agent is running. **Read the `lghub_agent` line before quoting any number from
   it** - see Landmines for why this source lies.
3. **Raw-input distance test - last resort, needs an explicit yes.** Works on any
   mouse, because it measures the sensor instead of asking software. It registers
   a system-wide raw-input sink that sees **every** mouse movement for the capture
   window, so it refuses to run without `--yes`, and never start it while a game
   or anything else that matters is in the foreground. Its `--help` carries the
   ruler procedure to hand over.

## Step 2 - Windows pointer check

```
pwsh -NoProfile -File scripts/windows_pointer_check.ps1
```

One command, one verdict line, exit 0 when clean. It reads
`HKCU:\Control Panel\Mouse` and checks the two things that silently rescale the
pointer:

- `MouseSensitivity` **10** is the 6/11 notch = 1 count in, 1 count out. Any other
  value multiplies pointer movement by a fixed factor; the script prints it.
- `MouseSpeed` 0 with `MouseThreshold1`/`MouseThreshold2` 0 means Enhance Pointer
  Precision is **off**. With EPP on the multiplier depends on how fast the mouse
  moved, so the same swipe gives a different turn every time and no cm/360 is
  stable.

These only scale games that read the Windows **cursor**; raw-input games bypass them
entirely. You cannot tell which a game does from outside, and a mismatch between the
two is itself a common complaint ("the desktop is fine but games are way too fast"),
so check anyway - it is one call. Table and fix: **`reference/windows-pointer.md`**.

## Step 3 - The game's formula

**Read `games.md` first.** If the game has a row, the formula is there and this step
is done. If not, work it out with **`reference/finding-a-formula.md`** (Unity,
Unreal, Source/idTech, Minecraft, and the measure-two-points fallback) and **write
the row the same session** - even provisional, even a single datapoint; a formula
rediscovered twice is a session wasted. Every row carries where it came from and the
date, because the trust order matters: decompiled game code > a measured in-game
360 > a community calculator > a forum post.

## Step 4 - The target

- **A. The recorded baseline.** Read `baseline.md`; if it is absent, copy
  `baseline.template.md` to `baseline.md` and start it there. A settled cm/360
  recorded in it IS the target, and this step is arithmetic.
- **B. Match another game they already like.** Better than any default. Compute
  that game's cm/360 from its row - `sens_calc.py --ref-*` does it in one call.
- **C. Nothing recorded.** Start at **30 cm/360** and converge. Say out loud that
  30 is a starting point, not their number, so a first attempt that feels wrong
  reads as expected rather than as a failure. Rough community convention, not a
  measurement and not cited anywhere here: 20-40 cm/360 for aim-heavy shooters,
  8-15 for arena games, 40+ for building-heavy. Say it as convention, not fact.
- **D. The DPI changed, or the pointer slider was not 1:1.** The target is
  "whatever it was before": compute each game's old cm/360 from its old setting
  and old DPI, then re-solve at the new DPI. It is one ratio *only* for games
  linear in `s` - see the ratio landmine. This slider-folding case has its own
  section in **`reference/windows-pointer.md`**; read that before touching either
  number, and before telling anyone their old in-game settings are still fine.

## Step 5 - Compute

```
python scripts/sens_calc.py --dpi 800 --game source --setting 1.5
python scripts/sens_calc.py --dpi 800 --game source --target-cm360 30
python scripts/sens_calc.py --dpi 400 --game howtofish \
    --ref-dpi 1600 --ref-game arcraiders --ref-setting 50
```

Pure stdlib, no dependencies. `--game` for the built-ins (`--list` shows them with
provenance and slider range), `--k` for a linear game whose constant you measured,
`--formula` for anything nonlinear. `--setting` reports where they are now,
`--target-cm360` solves for where they want to be, both together print the
faster/slower ratio, and `--ref-*` sets the target from another game's feel. If the
answer falls outside a slider range that has a checkable source it prints
`VERDICT: OUT OF RANGE`, says what DPI *would* reach the target, and exits 3 - a
setting the game will clamp is not an answer. Where `games.md` marks the range
UNVERIFIED (Valorant and Overwatch 2 today) it hands the number over with
`range unverified` in the VERDICT and exits 0 instead. Neither applies to a
hand-supplied `--k` or `--formula`: those describe the curve, not the slider.

## Step 6 - Apply

**Game running:** do not touch files. Hand over the exact slider value and where to
find it - a two-second action they do themselves. Menu edits are also the only safe
route for games that keep settings in a binary save or rewrite their config on exit.
**Game closed:** back up the file, write the key, then **read it back and show the
read-back value**. A write that was not read back is not a change, it is a hope.

## Step 7 - Verify before asking how it feels

Two checks. Do at least one, because a wrong formula and a wrong target feel
identical from the player's side and the converge loop cannot tell them apart.

**Spin test (exact, needs their go).** Injects a known count of horizontal movement
into the focused window; if the formula is right the view lands exactly where it
started after one turn.

```
python scripts/spin_test.py --game source --sens 1.5 --dry-run   # plan only, safe
python scripts/spin_test.py --game source --sens 1.5 --yes       # injects input
```

`--dry-run` prints the plan and injects nothing - always run that first and show it.
The real run needs `--yes`, needs them clicked into the game, and needs their
explicit go in the current chat. **Never against kernel anti-cheat: Vanguard,
EAC, BattlEye, Javelin; hand-distance test there** - the dry run prints that same
line above its VERDICT, so it is on screen before anyone reaches for `--yes`.

**Hand-distance test (no tooling, works anywhere).** Tell them the computed cm/360,
have them turn exactly 360 degrees in-game against a landmark, and compare with a
ruler or a known mousepad width. Off by ~2x means a factor of 2 in the formula; off
by ~10x on a Unity game means the Input Manager 0.1 factor; off by a wandering
amount every attempt means EPP is on (back to step 2).

## Step 8 - Converge

Ask one question: **faster, slower, or good?** Nothing else - not "how does it
feel", not a scale of 1 to 10.

- Faster or slower with no number attached: move 25% and ask again.
- They give a fraction ("half as fast"): apply it directly, it beats a guess.
- **One change per round.** Changing DPI and the in-game setting together makes the
  next answer uninterpretable, and they play a round per question.
- When they say good, record the number in `baseline.md` (start it from
  `baseline.template.md` if it does not exist) and in the game's `games.md` row.
  `baseline.md` is append-only: a correction goes below the line it corrects.

Two or three rounds is normal. Still wrong after four means the formula is probably
wrong rather than the setting - go back to step 3.

## Consent gates

Three scripts here are not read-only. Each refuses to act without a mandatory flag,
and each prints before/after so the change is auditable:

| Script | What it does | Gate |
|---|---|---|
| `logi_dpi.py --set N` | writes DPI to the mouse over HID++ | `--yes`; prints BEFORE and AFTER from re-reads |
| `rawinput_dpi_test.py` | captures ALL mouse movement system-wide | `--yes`; never while anything that matters is in the foreground |
| `spin_test.py` | injects mouse movement into the focused window | `--yes`; `--dry-run` is the safe preview; **never against a kernel anti-cheat game** |

The flag is the mechanism, not the permission. **Never run any of the three while a
game is active without the owner saying go in the current conversation** - a DPI
change lands instantly and mid-fight, and injected input in a live match is
indistinguishable from cheating. Everything else - `logi_dpi.py read`,
`ghub_dpi.py`, `sens_calc.py`, `windows_pointer_check.ps1`, `smoke.ps1` - is
read-only and safe to run unannounced.

## Landmines

- **G HUB's `settings.db` is intent, not state.** If `lghub_agent` is not running
  the mouse is on its onboard / last-pushed DPI and can sit on a different number
  for weeks. `ghub_dpi.py` prints the agent state first; read that line.
- **The DPI chain in that DB is TWO hops, not one.** assignment `cardId` -> a
  MOUSE_SENSITIVITY card holding only `{activeDpiIndex, presetId}` -> the preset
  card with `advancedDpiTable.entries`. Stop at the first card and you get an
  index and no numbers.
- **`dpi` can disagree with `dpiX`/`dpiY` in the same step**, because `dpi` is a
  stale label and the mouse follows X/Y. `ghub_dpi.py` flags mismatches; never
  quote the label past one.
- **HID++ replies arrive on either of two HID collections.** Windows splits the
  receiver's vendor interface into usage 1 (short 0x10 reports) and usage 2 (long
  0x11 reports), on separate device paths; a handle on one silently misses half
  the traffic and looks like an unresponsive mouse.
- **The rest of the HID++ wire format is in `scripts/logi_dpi.py`'s module
  docstring** - feature indices, the 0x2202 function numbering that is not
  0x2201's, the error frames, and the read-back-verify rule for every write. A
  guessed function number decodes into plausible nonsense, so read it there.
- **"Multiply the in-game sensitivity by the ratio" only works on LINEAR games.**
  A linear game (`deg/count = k * s`) really does take `s * old_dpi / new_dpi`; a
  nonlinear slider does not, and the needed factor is not even constant along the
  slider. Worked case: Minecraft at `s = 0.18` and 1600 DPI is 16.30 cm/360, but
  at 400 DPI the same feel needs `s ~ 0.48` - the naive `0.18 * 4 = 0.72` lands
  at 7.5 cm/360, **2.2x too fast**, in the direction that makes the fix feel like
  the problem. Re-solve with `sens_calc.py --target-cm360` unless the row says
  the game is linear in `s`.
- **Unity: `Input.GetAxis("Mouse X")` is pre-multiplied by the axis Sensitivity** -
  0.1 is the default `sensitivity` on the `Mouse X` / `Mouse Y` axes in a fresh
  Unity project's `ProjectSettings/InputManager.asset`. UNVERIFIED against Unity
  docs; a project can change the field, so check the target project's own
  `InputManager.asset`. `Mouse.current.delta` is not scaled. Same look code, 10x
  different constant.
- **Unity: `Time.deltaTime` on the mouse path** makes sensitivity framerate
  dependent, so there is no single cm/360 - only one per framerate. Say that
  instead of quoting a constant, and tune at their normal capped framerate.
- **Unity PlayerPrefs reads throw Int64 cast errors.** Values are suffixed
  `_h<hash>` and `Get-ItemProperty` chokes on some - use `reg query` or a
  byte-tolerant read. A missing key usually means the slider was never moved.
- **Games rewrite their config on exit.** Minecraft's `options.txt`, Source's
  `config.cfg`, Unreal's `GameUserSettings.ini` and `.sav` files are written from
  in-memory state at close, so an edit made while the game runs is silently
  clobbered. Edit closed, or use the in-game menu.
- **ARC Raiders has polling-rate-dependent smoothing**, so its cm/360 is not
  stable: mouse-sensitivity.com's guidance is 250 Hz or lower for a conversion,
  and a 1000 Hz user reported 15-20% slower than predicted. Match hipfire only;
  ADS differs per weapon class. Sources and dates: `games.md`'s ARC section.
- **Never run `spin_test.py` against a game with kernel-level anti-cheat** -
  Vanguard (Valorant), EAC, BattlEye, Javelin. Injected input can be flagged even
  in a practice range or offline, and the account is what is at risk. Use the
  hand-distance test there.
- **Read/Glob/Grep can be blocked by a restrictive permission config on
  `%LOCALAPPDATA%` game folders**, and a broad recursive sweep across a publisher
  root also trips the permission classifier. Tested workaround (2026-09-02): one
  narrow PowerShell pass confined to that one game's `Saved` subfolder. Do not
  widen a sweep to get around a denial - narrow it.
- **cm/360 is comparable across games; eDPI is not.** eDPI (dpi x setting) drops
  the engine constant, so it only compares two players in the *same* game.
- **Polling rate is not sensitivity.** 1000 vs 2000 Hz changes latency and
  smoothness, never cm/360. Do not let it into a sens loop.

## How to verify this skill in a fresh session

Read-only, ~15 seconds, safe to run while a game is up:

```
pwsh -NoProfile -File scripts/smoke.ps1     # expect `SUMMARY: 7 pass, 0 fail`
python scripts/sens_calc.py --selftest      # the arithmetic on its own
```

Seven checks, one `PASS`/`FAIL`/`SKIP` line each; all seven verified 2026-09-02 on
Windows 11, pwsh 7.6.5, Python 3.12, and every script re-verified on 3.11 the same day. Off a Logitech rig the `logi_dpi` and
`ghub_dpi` lines report `SKIP` with the reason and the other five still PASS - that
is correct, not a failure. A `windows_pointer_check` FAIL is a finding about the
machine, not a defect here. `rawinput_dpi_test.py` is excluded because starting it
at all opens a system-wide capture window; only its `--help` is checked.
