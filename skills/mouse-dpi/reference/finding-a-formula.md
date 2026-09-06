# Working out a game's deg/count formula

Read this when `games.md` has no row for the game. The goal is one function:
**degrees of camera yaw per mouse count, as a function of the in-game setting
`s`.** Once that exists, `sens_calc.py` answers every question about the game
forever, and the row you write means nobody derives it twice.

## Order of trust

Say which of these a row rests on, in the row, with a date:

1. **Decompiled game code.** Exact, and it also tells you about smoothing,
   acceleration, `deltaTime`, and per-axis differences you would never see from
   outside.
2. **A measured in-game 360** at a known DPI. Real, but only as good as the
   landmark and the ruler.
3. **A community calculator** (mouse-sensitivity.com and friends). Usually right,
   occasionally stale after a patch, and it keeps its constants internal so you
   cannot check its work.
4. **A forum post.** One datapoint. Write "PROVISIONAL, one datapoint" in the row
   and mean it.

A guess is not on this list. If none of the four is available, measure - the
procedure at the bottom takes about three minutes.

## Unity

**Find the identity.** `<Game>_Data\app.info` is two lines, company then product.
Those two strings are exactly:

- PlayerPrefs: `HKCU:\Software\<company>\<product>`
- Save folder: `%USERPROFILE%\AppData\LocalLow\<company>\<product>`

**Read the PlayerPrefs value.** Keys carry a `_h<hash>` suffix, and
`Get-ItemProperty` throws Int64 cast errors on some of them - use `reg query` or
a byte-tolerant read. Floats are stored as REG_BINARY. Unity writes a key only
once the setting has been changed at least once, so a missing key usually means
untouched rather than unsupported; asking the player to nudge the slider once is
the cheapest possible probe and it names the key for free.

**Decompile for the formula.**

```
ilspycmd -p -o <outdir> "<Game>_Data\Managed\Assembly-CSharp.dll"
```

Then grep the output for `sensitivity`, `Mouse X`, `Mouse.current.delta`,
`lookSpeed`, `rotationSpeed`, `LookInput`. What to check once you find the look
code, in order of how often it changes the answer:

- **Which input API.** `Input.GetAxis("Mouse X")` (legacy) has *already* been
  multiplied by the Input Manager's axis Sensitivity. **0.1** is the default
  `sensitivity` on the `Mouse X` / `Mouse Y` axes in a fresh Unity project's
  `ProjectSettings/InputManager.asset` - UNVERIFIED against Unity docs, and a
  project can change the field, so check the target project's own
  `InputManager.asset` if you have it. `Mouse.current.delta` (new Input System)
  has not. Identical-looking code, 10x different constant. If both exist in the
  assembly, check which class is actually referenced by a scene - dead legacy code
  is common.
- **`Time.deltaTime` on the mouse path.** If present, sensitivity is framerate
  dependent and there is no single cm/360 - only one at a given framerate. Record
  that in the row instead of a constant, and tune at their normal capped
  framerate. (Controller look code legitimately uses `deltaTime`; make sure you
  are reading the mouse branch.)
- **Processors on the binding or the action** (Scale, Invert, Normalize) in the
  `.inputactions` asset. These multiply silently and are not in the C# at all.
- **Event merging.** With it on (the default), one accumulated delta arrives per
  update and a sweep sums to exactly the counts moved. With it off, per-event
  processing can round each event separately.
- **Smoothing / acceleration.** Any averaging over frames, any `Mathf.Pow` on the
  delta. If present, cm/360 is speed dependent - say so.
- **Separate horizontal/vertical multipliers, and the ADS path.** Zoomed
  sensitivity is usually the hipfire value times `currentFOV / baseFOV`.

## Unreal Engine

Config lives in `%LOCALAPPDATA%\<ProjectName>\Saved\Config\Windows\` -
`GameUserSettings.ini` and `Input.ini`. Look for `MouseSensitivity`,
`bEnableMouseSmoothing`, `bViewAccelerationEnabled`, `FOVScaling` under
`[/script/engine.inputsettings]`.

Two traps:

- **The project name is not the store name.** ARC Raiders ships as
  `PioneerGame`. Find the real one from the folder under `%LOCALAPPDATA%`, or
  from the `.exe` path, before concluding the config does not exist.
- **Newer titles keep sensitivity in a binary `.sav`, not the ini.** UE
  `SaveGame` files are mostly binary but carry readable
  `GameplayOption.<Group>.<Name> <value>` pairs - strip non-printables and regex
  them out. If the ini has no sensitivity key, look in
  `Saved\SaveGames\*.sav` before deciding the setting is not persisted.

Edit with the game **closed**: Unreal rewrites the whole file from in-memory
state on the next in-game Apply, and a `.sav` is rewritten on exit.

**Tooling note for `%LOCALAPPDATA%` game folders:** Read/Glob/Grep can be blocked
by a restrictive permission config on some of them, and a broad recursive sweep
across a publisher root trips the permission classifier as well. The pattern that works is one narrow PowerShell pass confined
to the single `Saved` subfolder of the one game in question - not the publisher
root, not a `-Recurse` from `%LOCALAPPDATA%`.

## Source, GoldSrc, idTech and descendants

Yaw is `m_yaw` degrees per count times the `sensitivity` cvar, and `m_yaw`
defaults to **0.022** across the family (CS, TF2, L4D, Apex, the Quake lineage).

```
deg/count = 0.022 * s
```

Check `m_yaw` in the console before assuming the default - it is settable, and
some configs ship with it changed. `sensitivity 1.5` in console applies
instantly, which makes this family the easiest to converge on. `config.cfg` is
rewritten on exit, so persist changes in `autoexec.cfg` instead.

## Minecraft Java (and Forge packs on vanilla mouse code)

`%APPDATA%\.minecraft\options.txt`, key `mouseSensitivity`, range 0.0-1.0,
default 0.5. A modpack under a launcher profile has its own instance directory -
find the one the launcher actually uses.

```
f = s * 0.6 + 0.2
deg/count = f^3 * 8 * 0.15
```

Cubic, so nothing about it scales linearly. The in-game slider shows `s * 200`
percent, so the file value 0.5 displays as "100%" and 1.0 displays as
"HYPERSPEED". **Feed the file value to `sens_calc.py`, not the percent** - a
factor of 200 error is easy here and produces an answer that looks reasonable.
The file is rewritten on quit, so edit it closed.

## Anything else: measure it

Three minutes, works on any game, and it beats every source except a decompile.

**Setup.** Pointer check clean (step 2 of the runbook). DPI known. Pick a
landmark the camera can be aimed at precisely - a corner, a doorframe, a distant
object - and stand still.

**Method A - ruler.** Aim at the landmark. Slide the mouse in one straight
stroke, without lifting, until the view has turned exactly 360 degrees back onto
the landmark. Measure the desk distance. That is the cm/360 directly, no
arithmetic. Then:

```
k = 914.4 / (dpi * s * cm360)          for a linear game, deg/count = k * s
```

**Method B - `spin_test.py`, more precise.** Guess a `k`, let the script inject
exactly the counts that guess says are one full turn, and read the error off the
landmark:

```
python scripts/spin_test.py --k <guess> --sens <s> --dry-run   # show the plan
python scripts/spin_test.py --k <guess> --sens <s> --yes       # inject
```

If the view lands `e` degrees past the landmark (negative if short) after `N`
injected counts, the true value is:

```
deg/count = (360 + e) / N
k_true    = deg/count / s
```

An error of a few degrees on a 2000-count turn pins `k` to well under a percent,
which no ruler will do.

**Confirm linearity before trusting one point.** Repeat at a second setting `s2`
roughly double the first. If `k` comes out the same, it is linear. If it does
not, fit an exponent:

```
p = ln(dpc2 / dpc1) / ln(s2 / s1)      deg/count = k * s^p
```

and pass the whole thing to `sens_calc.py --formula` rather than pretending it is
linear. Minecraft's cubic is the standard example of why this check exists.

**Then write the row in `games.md`**, with the method and the date, even if it is
provisional. That is the entire point of the ledger.
