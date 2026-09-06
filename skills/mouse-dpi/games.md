# Per-game sensitivity ledger

One row per game, so the next session does not re-derive anything. The column
that matters is **deg/count as f(s)** - once that is known, `sens_calc.py`
answers every question about that game forever.

Add a row the same session you work one out, even if the number is provisional.
A row marked provisional and dated beats a missing row. How to derive one that is
not here: `reference/finding-a-formula.md`.

Every row states where its formula came from and when, because the trust order is
load-bearing: decompiled code > a measured 360 > a community calculator > a forum
post. Nothing in this file is a personal setting - those live in `baseline.md`.

A range cell marked **RANGE UNVERIFIED** means no checkable source was found for
what that game's own slider accepts. `sens_calc.py` still solves for those games,
but it WARNS and exits 0 rather than erroring with exit 3 when the answer falls
outside the range recorded here - an uncited range is not grounds for refusing an
answer, only for flagging it.

| Game | Engine | Config location | Setting key | Range / default | deg/count = f(s) | Live reload | Provenance |
|---|---|---|---|---|---|---|---|
| Minecraft Java (and RLCraft, and any Forge pack on vanilla mouse code) | Minecraft Java / LWJGL | `%APPDATA%\.minecraft\options.txt`; a pack under a launcher profile has its own instance dir | `mouseSensitivity` | 0.0-1.0, default 0.5. The slider displays `s*200` percent, so 0.5 reads as "100%" and 1.0 is "HYPERSPEED" | `(s*0.6+0.2)^3 * 8 * 0.15` - **NONLINEAR**, so a DPI change must be re-solved, never scaled | Slider applies instantly; the file is rewritten on quit, so edits made while the game runs get clobbered | Public knowledge of the engine, recorded 2026-09-01; not measured here |
| Source / GoldSrc / idTech descendants (CS, TF2, L4D, Apex, Quake lineage) | Source | `<game>\cfg\config.cfg`, or `autoexec.cfg` to persist | `sensitivity` cvar (and `m_yaw`, default 0.022) | >0, default 3 (CS:GO/CS2: 2.5) | `0.022 * s` - linear | `sensitivity 1.5` in console applies instantly; `config.cfg` is rewritten on exit | Public knowledge of the engine, recorded 2026-09-01; not measured here |
| How to Fish (Dazed Games) | Unity Mono, Steam, new Input System (`Unity.InputSystem.dll` reports 1.19 - read off the assembly in the 2026-09-01 decompile below, not from a store page) | PlayerPrefs at `HKCU:\Software\Dazed Games\How to Fish`, value `Sensitivity_h<hash>` (REG_BINARY float); the value only appears once the setting has been changed once. Saves at `%USERPROFILE%\AppData\LocalLow\Dazed Games\How to Fish\Saves\local.txt` hold InvertX/InvertY only | PlayerPrefs `Sensitivity` (float) | Slider 0.01-10 continuous, default 0.5 | `0.025 * s` - linear, both axes, hipfire. ADS multiplies by `curFov / origFov` (FOV pref `FOV`, default 74). So cm/360 = `36576 / (s * dpi)` | Typing a number in the settings text box, or moving the slider, applies instantly and is the exact-entry route (the display rounds to 2 dp, the applied float does not). A registry edit applies only at next launch and is clamped to 0.01-10 on load | Decompiled `PlayerCamera.cs:268` + `ButtonManager.cs` via ilspycmd, 2026-09-01; not yet measured in-game |
| ARC Raiders (Embark) | Unreal Engine 5, project name `PioneerGame` | `%LOCALAPPDATA%\PioneerGame\Saved\SaveGames\EmbarkOptionSaveGame.sav`. NOT the ini, which carries no sensitivity key. The `.sav` is a UE save with readable `GameplayOption.<Group>.<Name> <value>` pairs - strip non-printables and regex them out | `GameplayOption.Accessibility.SensitivityXAxis` / `SensitivityYAxis`; multipliers `Accessibility.ZoomSensitivity`, `Accessibility.ScopedZoomSensitivity`; `Controls.Mouse.Smoothing`. Gamepad has its own `Accessibility.Gamepad.*` set | 1-100, default 50 (mouse-sensitivity.com's ARC Raiders game-update page, revision r1627, 2025-11-18); allthings.how's mouse-smoothing article gives the range as 5-100 instead, unresolved | **PROVISIONAL, one datapoint:** `0.000682 * s` - linear in `s` as far as anyone can tell, but the game's smoothing makes the real turn speed-dependent, so treat it as nominal. Default 50 at 800 DPI would be about 33.5 cm/360. Read the section below before using it | Slider applies in the menu; the `.sav` is rewritten on exit | Back-solved 2026-09-01 from a single forum datapoint - mouse-sensitivity.com forum topic 10704, "ARC Raiders wrong sensitivity" (2025-11-09): sens 44 = 38.1 cm/360, DPI assumed 800. No published yaw constant exists; converters keep theirs internal. Web research only, NOT measured |
| Valorant (Riot) | Riot in-house | `%LOCALAPPDATA%\VALORANT\Saved\Config\<PUUID>\Windows\` - the sensitivity is in `RiotUserSettings.ini`, which is opaque (obfuscated key/value blob, not a readable ini). **Do not edit it: use the in-game slider**, Settings > General > Sensitivity | in-game "Sensitivity" only; no readable file key | **RANGE UNVERIFIED.** The 0.1-10 carried here is uncited. MouseTester.io's Valorant page (https://mousetester.io/sensitivity/valorant/, read 2026-09-02) says "Sensitivity Range 0.1 - 1, Default 0.3", which reads as a recommended band rather than the field's limits; guide articles found the same day say 0.01-10. Nothing checkable resolves it and no source found states the decimal precision, so `sens_calc.py` WARNS (exit 0) instead of erroring on an out-of-range answer for this game | `0.07 * s` - linear (0.07 deg of yaw per count per unit of sensitivity) | Slider applies instantly in the menu | Yaw constant: MouseTester.io, "Valorant (VAL) Sensitivity Conversion" (https://mousetester.io/sensitivity/valorant/), read 2026-09-02 - "each unit of sensitivity corresponds to 0.07° of camera rotation per mouse count". A community converter, so trust tier 3; not measured here, and the slider range is unverified (left cell). **Vanguard is a kernel-level anti-cheat driver - never run `spin_test.py` against this game, not even in the range.** Verify with the hand-distance test |
| Overwatch 2 (Blizzard) | Blizzard in-house | `%USERPROFILE%\Documents\Overwatch\Settings\Settings_v0.ini`; the in-game slider is the safe route and applies instantly | in-game Options > Controls > Sensitivity | **RANGE UNVERIFIED.** The 1-100 carried here is uncited. MouseTester.io's Overwatch 2 page (https://mousetester.io/sensitivity/overwatch-2/, read 2026-09-02) says "Sensitivity Range 2 - 15, Default 5", which reads as a recommended band rather than the slider's limits, and aiming.pro's OW2 calculator (read the same day) states neither. So `sens_calc.py` WARNS (exit 0) instead of erroring on an out-of-range answer for this game | `0.0066 * s` - linear (0.0066 deg of yaw per count per unit of sensitivity) | Slider applies instantly; the ini is rewritten on exit | Yaw constant: MouseTester.io, "Overwatch 2 Sensitivity Conversion" (https://mousetester.io/sensitivity/overwatch-2/), read 2026-09-02 - "each unit of sensitivity corresponds to 0.0066° of camera rotation per mouse count". A community converter, so trust tier 3; not measured here, and the slider range is unverified (left cell) |

## ARC Raiders: read this before quoting the constant

Everything below is web research, not measurement on this machine. Each claim
names its source so a later session can re-check it rather than inherit it.

- **The mapping is not a clean constant at normal polling rates.** The game
  applies mouse smoothing that produces speed-dependent negative acceleration,
  scaled by polling rate.
  *Source: mouse-sensitivity.com forum topic 10704, "ARC Raiders wrong
  sensitivity", 2025-11-09 - the same thread the provisional constant is
  back-solved from (sens 44 = 38.1 cm/360).*
- **Convert at 250 Hz or lower**, and even then fast flicks are only accurate
  near 125 Hz. Setting `bEnableMouseSmoothing=False` is reported not to fix it.
  *Source: mouse-sensitivity.com "ARC Raiders - Supported Games" topic 10399.*
- **A user converting at 1000 Hz reported 15-20 percent slower than predicted.**
  One report, not a measurement.
  *Source: mouse-sensitivity.com forum topic 10704, 2025-11-09.*
- **The ini keys** `bEnableMouseSmoothing`, `bViewAccelerationEnabled` under
  `[/script/engine.inputsettings]`, and the 5-100 sensitivity range, come from
  allthings.how's ARC Raiders mouse-smoothing article. `RawMouseInputEnabled` is
  **not** a stock Unreal input key - it appears only in that article, so treat it
  as "reported by allthings.how" and do not assume the engine honours it.
- **Zoom Sens and Scoped Sens are separate multipliers** with caps of 100 and
  200, and the base sensitivity defaults to 50.
  *Source: mouse-sensitivity.com's ARC Raiders game-update page, revision r1627,
  2025-11-18.*
- **ADS is per weapon class** (each has its own zoom FOV), so one Zoom Sens value
  gives a different cm/360 per gun. Match hipfire only unless asked otherwise.
- **Ground truth route:** measure a real 360 at a known DPI and polling rate at
  two sensitivity values, solve for `k`, and replace the provisional row
  (`reference/finding-a-formula.md`, method B). mouse-sensitivity.com has the
  game in its database and is the next-best source, but it is a browser tool and
  opening a browser needs explicit permission.

## How to Fish: what the decompile established (2026-09-01)

- Look path `PlayerCamera.cs:268`:
  `LookInput = (-raw.y, raw.x) * _sensitivity * SensMulti * 0.025f`, added
  straight into Euler degrees. Input is `<Mouse>/delta` through the new Input
  System with **no processors** on the binding or the action, so raw pixels =
  mouse counts. Event merging is on (one accumulated delta per update), so a
  sweep sums to exactly the counts moved.
- **No `Time.deltaTime`** on the mouse path - the controller branch has it, gated
  on the Controller scheme. No smoothing, no acceleration, no separate
  horizontal/vertical multiplier for mouse. Inversion keys `InvertX` / `InvertY`
  (PlayerPrefs, default 0).
- Legacy `Input.GetAxis("Mouse X")` is dead code here: `ThirdPersonCamera.cs` is
  referenced by no scene, so the Input Manager 0.1 factor does **not** apply.
- Sanity numbers: default s=0.5 at 800 DPI = 91.4 cm/360; slider max s=10 at
  800 DPI = 4.6 cm/360.
- Unresolved: whether Windows pointer speed or EPP scales `<Mouse>/delta` inside
  `UnityPlayer.dll`. Keep the Windows check clean (notch 6/11, EPP off) and the
  question is moot - which is one more reason step 2 of the runbook is not
  optional.
- The "View Bobbing" toggle is never read by the game code; head bob runs
  regardless. Recoil is additive, not an input scale.
- Decompiled sources were left in a session scratchpad only. Re-run
  `ilspycmd -p -o <dir> <Assembly-CSharp.dll>` if they are needed again.

## Keeping this file and the scripts in step

`scripts/sens_calc.py` carries the same formulas as built-ins so they can be used
without retyping, and `spin_test.py` imports them from `sens_calc.py` rather than
keeping its own copy. **If you change a formula here, change the matching entry
in `sens_calc.py`'s `FORMULAS` dict in the same edit** - two sources of truth for
one constant is how a skill starts giving confidently wrong answers.
`python scripts/sens_calc.py --list` prints what the code currently believes,
including provenance; if that disagrees with a row above, the code and this file
have drifted and one of them is lying.
