#!/usr/bin/env python3
"""Mouse sensitivity calculator: cm/360 <-> in-game setting. Pure stdlib.

Read-only arithmetic. It touches no hardware, no config files and no registry,
so it is always safe to run - including while a game is up.

The whole problem reduces to one chain:

    counts per 360 = 360 / (degrees per count)
    cm per 360     = counts per 360 * 2.54 / dpi

so                 cm/360 = (360 * 2.54) / (dpi * deg_per_count)
                          = 914.4 / (dpi * deg_per_count)

Everything a game does lives in `deg_per_count`, a function of the in-game
setting `s`. Most games are linear (deg/count = k * s); some are not (Minecraft
cubes its slider). Supply the game's formula and the rest is arithmetic.

The built-in FORMULAS below must stay in step with the ledger in `games.md` -
one constant with two homes is how a tool starts giving confidently wrong
answers. `--list` prints what this file currently believes, with provenance.

Examples
--------
  # what cm/360 am I on right now?
  python sens_calc.py --dpi 1600 --game source --setting 1.5

  # what setting hits 30 cm/360?
  python sens_calc.py --dpi 1600 --game source --target-cm360 30

  # match a known-good feel from another game and/or another dpi
  python sens_calc.py --dpi 400 --game howtofish \
      --ref-dpi 1600 --ref-game arcraiders --ref-setting 50

  # a game with a linear constant you measured yourself
  python sens_calc.py --dpi 1600 --k 0.0141 --target-cm360 30

  # a nonlinear game formula: any python expression in s
  python sens_calc.py --dpi 1600 --formula "(s*0.6+0.2)**3 * 8 * 0.15" --setting 0.5

  # what the calculator believes, and whether its own arithmetic is right
  python sens_calc.py --list
  python sens_calc.py --selftest

Smoke test (no arguments needed, exits non-zero if the math is wrong):
  python sens_calc.py --selftest
"""

from __future__ import annotations

import argparse
import contextlib
import io
import math
import sys

CM_PER_INCH = 2.54
DEG_PER_TURN = 360.0
# 360 deg * 2.54 cm/in - the numerator of every cm/360 in this skill.
TURN_CM_NUMERATOR = DEG_PER_TURN * CM_PER_INCH  # 914.4

# ---------------------------------------------------------------------------
# Built-in game formulas: in-game setting -> degrees of yaw per mouse count.
# Each entry is (callable, description, provenance, (min_setting, max_setting),
# range_verified).
# The range is what the game's own slider accepts - it is what stops this tool
# handing back a setting the game will refuse or clamp. `None` means unbounded.
# range_verified says whether that range has a checkable source behind it: True
# means an out-of-range answer is an ERROR (exit 3), False means it is only a
# WARNING (exit 0), because refusing an answer on the strength of an uncited
# range is worse than handing it over flagged.
# Keep all five fields in step with the matching row in games.md.
# ---------------------------------------------------------------------------
FORMULAS = {
    # Source engine (CS, TF2, L4D, Apex, most idTech descendants): the engine's
    # m_yaw is 0.022 degrees per count, scaled by the `sensitivity` cvar. The
    # cvar has no practical upper bound, hence None.
    "source": (
        lambda s: 0.022 * s,
        "0.022 * s   (m_yaw 0.022 deg per count, linear)",
        "public knowledge of the engine, recorded 2026-09-01; not measured here",
        (0.0, None),
        True,  # the cvar is unbounded above; nothing to get wrong
    ),
    # Minecraft Java (and RLCraft, and anything else on vanilla's mouse code):
    # f = s*0.6 + 0.2; per-count yaw = f^3 * 8 * 0.15.  NONLINEAR - a DPI change
    # cannot be corrected by scaling s, it has to be re-solved.
    "minecraft": (
        lambda s: (s * 0.6 + 0.2) ** 3 * 8 * 0.15,
        "(s*0.6+0.2)^3 * 8 * 0.15   (s = options.txt 0-1; the in-game slider "
        "shows s*200 percent, so 0.5 displays as 100%. NONLINEAR)",
        "public knowledge of the engine, recorded 2026-09-01; not measured here",
        (0.0, 1.0),
        True,  # options.txt mouseSensitivity is a documented 0.0-1.0 float
    ),
    # How to Fish (Dazed Games), Unity new Input System, hipfire.
    # PlayerCamera.cs:268 multiplies <Mouse>/delta by sensitivity * 0.025f
    # straight into Euler degrees, with no processors and no Time.deltaTime.
    # The loader clamps the PlayerPrefs value to 0.01-10 on launch.
    "howtofish": (
        lambda s: 0.025 * s,
        "0.025 * s   (hipfire, both axes, linear; ADS scales by curFov/origFov)",
        "decompiled PlayerCamera.cs:268 via ilspycmd, 2026-09-01",
        (0.01, 10.0),
        True,  # the loader's own clamp, read out of the decompile
    ),
    # ARC Raiders (Embark, UE5). PROVISIONAL: back-solved from a single forum
    # datapoint, sens 44 = 38.1 cm/360 at an assumed 800 DPI. The game also
    # applies polling-rate-dependent smoothing, so this is a nominal figure -
    # read the ARC section of games.md before quoting it.
    "arcraiders": (
        lambda s: 0.000682 * s,
        "0.000682 * s   (PROVISIONAL, one datapoint; hipfire only, and the game "
        "has polling-rate-dependent smoothing)",
        "back-solved from one forum report, 2026-09-01; NOT measured",
        (1.0, 100.0),
        True,  # range from mouse-sensitivity.com's ARC game-update page r1627,
               # 2025-11-18 (allthings.how says 5-100; the low end is the only
               # disputed part and 1-100 is the wider, safer bound)
    ),
    # Valorant (Riot). 0.07 degrees of yaw per count per unit of sensitivity.
    # The settings file (RiotUserSettings.ini) is an opaque blob, so the in-game
    # slider is the only route in. Vanguard is a kernel-level anti-cheat driver:
    # NEVER spin_test.py this game, not even in the practice range.
    # The 0.1-10 range below is UNVERIFIED - see the games.md row.
    "valorant": (
        lambda s: 0.07 * s,
        "0.07 * s   (linear; set it with the in-game slider - the settings file "
        "is opaque. Vanguard: no spin test, use the hand-distance check)",
        "yaw 0.07: MouseTester.io 'Valorant (VAL) Sensitivity Conversion', "
        "https://mousetester.io/sensitivity/valorant/, read 2026-09-02 - 'each "
        "unit of sensitivity corresponds to 0.07 deg of camera rotation per "
        "mouse count'; community converter, not measured here. RANGE "
        "UNVERIFIED: that page says 0.1-1 (default 0.3), guide articles say "
        "0.01-10, nothing checkable resolves it",
        (0.1, 10.0),
        False,  # range unverified -> warn, never refuse
    ),
    # Overwatch 2 (Blizzard). 0.0066 degrees of yaw per count per unit of
    # sensitivity. The 1-100 range below is UNVERIFIED - see the games.md row.
    "overwatch2": (
        lambda s: 0.0066 * s,
        "0.0066 * s   (linear; in-game slider, applies instantly - slider range "
        "unverified, so an out-of-range answer here is a warning, not an error)",
        "yaw 0.0066: MouseTester.io 'Overwatch 2 Sensitivity Conversion', "
        "https://mousetester.io/sensitivity/overwatch-2/, read 2026-09-02 - "
        "'each unit of sensitivity corresponds to 0.0066 deg of camera rotation "
        "per mouse count'; community converter, not measured here. RANGE "
        "UNVERIFIED: that page says 2-15 (default 5), aiming.pro's OW2 "
        "calculator states no range, and the 1-100 here is uncited",
        (1.0, 100.0),
        False,  # range unverified -> warn, never refuse
    ),
}

ALIASES = {
    "arc": "arcraiders",
    "arc-raiders": "arcraiders",
    "arc_raiders": "arcraiders",
    "how-to-fish": "howtofish",
    "how_to_fish": "howtofish",
    "mc": "minecraft",
    "goldsrc": "source",
    "idtech": "source",
    "val": "valorant",
    "ow": "overwatch2",
    "ow2": "overwatch2",
    "overwatch": "overwatch2",
    "overwatch-2": "overwatch2",
}


def resolve_game(name: str) -> str:
    key = name.strip().lower().replace(" ", "")
    return ALIASES.get(key, key)


def make_formula(game, expr, k, what="--game / --formula / --k"):
    """Return (fn, label, (smin, smax), range_verified) for deg/count as f(s).

    The range is only known for built-in games; a hand-supplied --k or --formula
    describes the curve but says nothing about what the game's slider accepts,
    so those come back unbounded and no range warning is possible.
    range_verified is False for a built-in whose range has no checkable source -
    the arithmetic is unaffected, only whether an out-of-range answer is an
    error or a warning.
    """
    picked = [x for x in (game, expr, k) if x is not None]
    if len(picked) > 1:
        raise SystemExit(f"error: pick only one of {what}")
    if game is not None:
        key = resolve_game(game)
        if key not in FORMULAS:
            raise SystemExit(
                f"error: unknown game '{game}'. known: {', '.join(sorted(FORMULAS))}. "
                "Use --k for a linear game or --formula for anything else, and "
                "record it in games.md."
            )
        fn, desc, _prov, rng, verified = FORMULAS[key]
        return fn, f"{key}: {desc}", rng, verified
    if k is not None:
        if k <= 0:
            raise SystemExit("error: --k must be positive")
        return ((lambda s, _k=k: _k * s),
                f"linear, k={k} deg/count per unit s", (None, None), False)
    if expr is not None:
        try:
            code = compile(expr, "<formula>", "eval")
        except SyntaxError as exc:
            raise SystemExit(f"error: --formula is not a valid expression: {exc}")
        env = {"__builtins__": {}, "math": math, "abs": abs, "pow": pow,
               "min": min, "max": max}

        def fn(s, _code=code, _env=env):
            try:
                return float(eval(_code, _env, {"s": s}))
            except Exception as exc:  # noqa: BLE001 - user-supplied expression
                raise SystemExit(f"error: --formula failed at s={s}: {exc}")

        return fn, f"expr: deg/count = {expr}", (None, None), False
    raise SystemExit(f"error: need one of {what}")


def cm360(dpi: float, deg_per_count: float) -> float:
    if dpi <= 0:
        raise SystemExit("error: --dpi must be positive")
    if deg_per_count <= 0:
        raise SystemExit(
            "error: degrees per count came out <= 0 - check the formula and the "
            "setting (a negative or zero setting has no cm/360)"
        )
    return TURN_CM_NUMERATOR / (dpi * deg_per_count)


def solve_setting(fn, dpi: float, target_cm360: float) -> float:
    """Find s such that cm/360 == target. Assumes deg/count rises with s."""
    if target_cm360 <= 0:
        raise SystemExit("error: --target-cm360 must be positive")
    want_dpc = TURN_CM_NUMERATOR / (dpi * target_cm360)

    def safe(s):
        try:
            v = fn(s)
        except SystemExit:
            raise
        except Exception:
            return None
        return v if isinstance(v, (int, float)) and math.isfinite(v) else None

    lo, hi = 1e-9, 1e-9
    bracketed = False
    for _ in range(400):
        hi *= 1.5
        v = safe(hi)
        if v is None:
            break
        if v >= want_dpc:
            bracketed = True
            break
        lo = hi

    if not bracketed:
        raise SystemExit(
            "error: no setting reaches that cm/360 - the target is probably "
            "faster than the game's formula can go, or the formula is not "
            "monotonic in s. Check it with --setting at a couple of values."
        )

    for _ in range(200):
        mid = (lo + hi) / 2.0
        v = safe(mid)
        if v is None or v < want_dpc:
            lo = mid
        else:
            hi = mid
    setting = (lo + hi) / 2.0
    # Bisection can stop at the positive lower bound even when no solution
    # exists (e.g. Minecraft targets slower than its minimum sensitivity).
    actual = safe(setting)
    if actual is None or not math.isclose(actual, want_dpc, rel_tol=1e-9):
        # Zero is outside the positive search interval, but can be a valid
        # endpoint. Custom formulas (e.g. log(s)) need not be defined there.
        try:
            zero = safe(0.0)
        except SystemExit:
            zero = None
        if zero is not None and math.isclose(zero, want_dpc, rel_tol=1e-9):
            return 0.0
        raise SystemExit("error: no positive setting reaches that cm/360 - "
                         "check the target and the game's formula")
    return setting


def fmt(x: float, places: int = 4) -> str:
    s = f"{x:.{places}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s or "0"


def run_capture(argv):
    """Run main() with argv, returning (exit code, captured stdout).

    The selftest asserts on real exit codes rather than on a private helper:
    error (exit 3) versus warning (exit 0) is the entire point of the
    range_verified flag, and only the entry point proves which one happened.
    """
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = main(argv)
    except SystemExit as exc:  # argparse or one of the guards bailed out
        rc = exc.code if isinstance(exc.code, int) else 2
    return rc, buf.getvalue()


def selftest() -> int:
    """Hand-checkable arithmetic. Exits non-zero if any of it drifts."""
    cases = [
        # (label, dpi, formula key, setting, expected cm/360)
        # 914.4 / (800 * 0.022 * 1.5) = 914.4 / 26.4 = 34.636...
        ("source s=1.5 @ 800 dpi", 800, "source", 1.5, 34.6364),
        # f = 0.5 -> 0.5^3 * 1.2 = 0.15 deg/count; 914.4 / (800*0.15) = 7.62
        ("minecraft s=0.5 @ 800 dpi", 800, "minecraft", 0.5, 7.62),
        # 914.4 / (800 * 0.025 * 0.5) = 914.4 / 10 = 91.44
        ("howtofish s=0.5 @ 800 dpi", 800, "howtofish", 0.5, 91.44),
        # 914.4 / (800 * 0.000682 * 50) = 914.4 / 27.28 = 33.518...
        ("arcraiders s=50 @ 800 dpi", 800, "arcraiders", 50.0, 33.5191),
    ]
    failures = 0
    for label, dpi, key, s, expect in cases:
        fn = FORMULAS[key][0]
        got = cm360(dpi, fn(s))
        ok = abs(got - expect) < 0.01
        failures += 0 if ok else 1
        print(f"{'ok  ' if ok else 'FAIL'} {label}: {got:.4f} cm/360 "
              f"(expected {expect})")

    # Round trip: solving for a target and reporting it back must agree, on a
    # linear formula and on the nonlinear one.
    for key, dpi, target in (("source", 800, 30.0), ("minecraft", 400, 16.3),
                             ("howtofish", 400, 16.3)):
        fn = FORMULAS[key][0]
        s = solve_setting(fn, dpi, target)
        back = cm360(dpi, fn(s))
        ok = abs(back - target) < 1e-6
        failures += 0 if ok else 1
        print(f"{'ok  ' if ok else 'FAIL'} {key} round trip @ {dpi} dpi: "
              f"target {target} -> s={s:.4f} -> {back:.6f} cm/360")

    # cm/360 must be independent of dpi when the setting is scaled with it, for
    # a LINEAR formula only - and must NOT be, for the cubic one. This is the
    # landmine the skill documents, asserted in code so it cannot rot.
    lin = FORMULAS["source"][0]
    a = cm360(1600, lin(1.0))
    b = cm360(400, lin(4.0))
    ok = abs(a - b) < 1e-9
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} linear ratio rule holds: "
          f"{a:.4f} vs {b:.4f} cm/360")

    cub = FORMULAS["minecraft"][0]
    a = cm360(1600, cub(0.18))
    b = cm360(400, cub(0.72))
    ok = abs(a - b) > 1.0  # they must NOT match; the doc says 16.30 vs 7.5
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} nonlinear ratio rule correctly fails: "
          f"{a:.2f} vs {b:.2f} cm/360 (naive x4 is wrong, as documented)")

    # A target the game's slider cannot reach must be caught, not handed back.
    fn, _d, _p, (smin, smax), verified = FORMULAS["minecraft"]
    s = solve_setting(fn, 800, 1.0)  # 1 cm/360 is far past Minecraft's max
    ok = out_of_range(s, smin, smax)
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} out-of-range guard: minecraft @ 800 dpi "
          f"needs s={s:.4f}, slider maxes at {smax} -> "
          f"{'flagged' if ok else 'NOT FLAGGED'}")

    # ...and one that IS reachable must not be flagged.
    s = solve_setting(fn, 800, 30.0)
    ok = not out_of_range(s, smin, smax)
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} in-range not flagged: minecraft @ 800 dpi "
          f"30 cm/360 -> s={s:.4f}")

    # A VERIFIED range that is exceeded is an ERROR: exit 3, and the answer is
    # withheld. Run the real entry point so the exit code itself is asserted.
    rc, out = run_capture(["--dpi", "800", "--game", "minecraft",
                           "--target-cm360", "1"])
    ok = rc == 3 and "OUT OF RANGE" in out
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} verified range errors: minecraft 1 cm/360 "
          f"-> exit {rc} (want 3), verdict says OUT OF RANGE: "
          f"{'yes' if 'OUT OF RANGE' in out else 'NO'}")

    # An UNVERIFIED range that is exceeded is only a WARNING: the number is
    # handed over, the verdict says so, and the exit code stays 0. Refusing an
    # answer on the strength of an uncited range is the worse failure.
    rc, out = run_capture(["--dpi", "800", "--game", "valorant",
                           "--target-cm360", "1"])
    ok = rc == 0 and "range unverified" in out and "SET s =" in out
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} unverified range only warns: valorant "
          f"1 cm/360 -> exit {rc} (want 0), verdict says 'range unverified': "
          f"{'yes' if 'range unverified' in out else 'NO'}")

    # ...and inside the recorded range, the unverified game behaves normally.
    rc, out = run_capture(["--dpi", "800", "--game", "valorant",
                           "--target-cm360", "30"])
    ok = rc == 0 and "range unverified" not in out
    failures += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} unverified range quiet in range: valorant "
          f"30 cm/360 -> exit {rc} (want 0), no range note: "
          f"{'yes' if 'range unverified' not in out else 'NO'}")

    print("VERDICT: SELFTEST PASS" if not failures
          else f"VERDICT: SELFTEST FAIL ({failures})")
    return 0 if not failures else 1


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="sens_calc.py",
        description="Convert between in-game sensitivity and cm/360. Read-only.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples" + __doc__.split("Examples")[-1],
    )
    p.add_argument("--dpi", type=float, help="mouse DPI for the target game")
    p.add_argument("--game", help=f"built-in formula: {', '.join(sorted(FORMULAS))}")
    p.add_argument("--formula", help="python expression in s for degrees per count")
    p.add_argument("--k", type=float, help="linear formula: deg/count = k * s")
    p.add_argument("--setting", type=float, help="current in-game setting s")
    p.add_argument("--target-cm360", type=float, help="cm per 360 you want")
    p.add_argument("--ref-dpi", type=float, help="reference: dpi it was measured at")
    p.add_argument("--ref-game", help="reference: built-in formula name")
    p.add_argument("--ref-formula", help="reference: python expression in s")
    p.add_argument("--ref-k", type=float, help="reference: linear k")
    p.add_argument("--ref-setting", type=float, help="reference: the setting there")
    p.add_argument("--list", action="store_true",
                   help="list built-in formulas with provenance and exit")
    p.add_argument("--selftest", action="store_true",
                   help="verify this file's own arithmetic and exit non-zero if wrong")
    a = p.parse_args(argv)

    if a.list:
        for name, (_fn, desc, prov, rng, verified) in sorted(FORMULAS.items()):
            lo = "0" if rng[0] is None else fmt(rng[0])
            hi = "no max" if rng[1] is None else fmt(rng[1])
            flag = "" if verified else "   [RANGE UNVERIFIED - warns, never errors]"
            print(f"{name:12s} deg/count = {desc}")
            print(f"{'':12s} setting range: {lo} to {hi}{flag}")
            print(f"{'':12s} provenance: {prov}")
        print("\nAliases: " + ", ".join(f"{k} -> {v}" for k, v in sorted(ALIASES.items())))
        print(f"VERDICT: {len(FORMULAS)} built-in formulas - these must match the "
              "rows in games.md. If they do not, one of the two is lying and the "
              "ledger is the one to trust.")
        return 0

    if a.selftest:
        return selftest()

    if a.dpi is None:
        p.error("--dpi is required (get it from the HID++ read, not from memory)")
    if a.setting is None and a.target_cm360 is None and a.ref_setting is None:
        p.error("give --setting (report current) and/or --target-cm360 / --ref-* (solve)")
    if a.target_cm360 is not None and a.ref_setting is not None:
        p.error("--target-cm360 and --ref-setting both set a target; pick one")
    # A --ref-* without --ref-setting is silently ignored otherwise: the answer
    # comes back computed from something the caller did not ask for.
    if a.ref_setting is None:
        stray = [n for n, v in (("--ref-dpi", a.ref_dpi), ("--ref-game", a.ref_game),
                                ("--ref-formula", a.ref_formula), ("--ref-k", a.ref_k))
                 if v is not None]
        if stray:
            p.error(f"{', '.join(stray)} needs --ref-setting - a reference game "
                    "or dpi with no setting to read at is not a target")

    fn, label, (smin, smax), range_verified = make_formula(a.game, a.formula, a.k)

    target = a.target_cm360
    ref_line = None
    if target is None and a.ref_setting is not None:
        rfn, rlabel, _rrng, _rver = make_formula(
            a.ref_game, a.ref_formula, a.ref_k,
            what="--ref-game / --ref-formula / --ref-k")
        rdpi = a.ref_dpi if a.ref_dpi is not None else a.dpi
        target = cm360(rdpi, rfn(a.ref_setting))
        ref_line = (
            f"reference   {rlabel} @ s={fmt(a.ref_setting)} dpi={fmt(rdpi, 0)} "
            f"-> {fmt(target, 2)} cm/360"
        )

    print(f"formula     {label}")
    print(f"dpi         {fmt(a.dpi, 0)}")
    if ref_line:
        print(ref_line)

    # The last line printed always starts with VERDICT:, so a caller never has to
    # parse the detail block above it.
    verdict = None

    if a.setting is not None:
        dpc = fn(a.setting)
        cur = cm360(a.dpi, dpc)
        print(
            f"current     s={fmt(a.setting)}  eDPI={fmt(a.dpi * a.setting, 1)}  "
            f"{fmt(dpc, 6)} deg/count  {fmt(cur, 2)} cm/360  "
            f"({fmt(cur / CM_PER_INCH, 2)} in/360)"
        )
        if out_of_range(a.setting, smin, smax):
            if range_verified:
                print(f"note        s={fmt(a.setting)} is outside this game's slider "
                      f"range ({range_text(smin, smax)}) - the game will clamp or "
                      "reject it, so the line above is hypothetical")
            else:
                print(f"note        s={fmt(a.setting)} is outside the range recorded "
                      f"here ({range_text(smin, smax)}), but that range is "
                      "UNVERIFIED (see games.md) - the setting may well be fine")
        verdict = (f"VERDICT: s={fmt(a.setting)} at {fmt(a.dpi, 0)} DPI is "
                   f"{fmt(cur, 2)} cm/360")

    rc = 0
    if target is not None:
        s = solve_setting(fn, a.dpi, target)
        dpc = fn(s)
        got = cm360(a.dpi, dpc)
        print(
            f"target      {fmt(target, 2)} cm/360  ->  s = {fmt(s, 4)}  "
            f"(eDPI {fmt(a.dpi * s, 1)}, {fmt(dpc, 6)} deg/count, "
            f"lands {fmt(got, 2)} cm/360)"
        )
        if a.setting is not None and a.setting > 0:
            ratio = s / a.setting
            word = "faster" if ratio > 1 else "slower"
            print(f"change      x{fmt(ratio, 3)} {word} than s={fmt(a.setting)}")
        verdict = (f"VERDICT: SET s = {fmt(s, 4)}  ->  {fmt(got, 2)} cm/360 at "
                   f"{fmt(a.dpi, 0)} DPI")
        if out_of_range(s, smin, smax):
            edge = smax if (smax is not None and s > smax) else smin
            need_dpi = TURN_CM_NUMERATOR / (target * fn(edge))
            if range_verified:
                # Do not hand back a number the game will refuse. Say what DPI
                # would put the target back inside the slider instead - that is
                # the only move left, and it is the one a caller would otherwise
                # have to work out from scratch.
                print(f"range       the game cannot reach {fmt(target, 2)} cm/360 at "
                      f"{fmt(a.dpi, 0)} DPI; at its limit s={fmt(edge)} it would need "
                      f"{need_dpi:.0f} DPI instead")
                verdict = (f"VERDICT: OUT OF RANGE - s={fmt(s, 4)} is outside this "
                           f"game's slider ({range_text(smin, smax)}). Change the "
                           f"DPI to about {need_dpi:.0f}, or pick a target the "
                           "slider can reach.")
                rc = 3
            else:
                # The range itself has no checkable source (games.md says so), so
                # refusing on the strength of it would be worse than answering.
                # Flag it, hand the number over, and exit 0.
                print(f"range       s={fmt(s, 4)} is outside the range recorded here "
                      f"({range_text(smin, smax)}), but that range is UNVERIFIED "
                      f"(see games.md). If the game does clamp at s={fmt(edge)}, "
                      f"{need_dpi:.0f} DPI would reach the target instead")
                verdict = (f"VERDICT: SET s = {fmt(s, 4)}  ->  {fmt(got, 2)} cm/360 "
                           f"at {fmt(a.dpi, 0)} DPI - outside the recorded "
                           f"{range_text(smin, smax)}, range unverified, so check "
                           "what the game actually accepts before trusting it")

    if verdict:
        print(verdict)
    return rc


def range_text(smin, smax) -> str:
    lo = "0" if smin is None else fmt(smin)
    hi = "no max" if smax is None else fmt(smax)
    return f"{lo} to {hi}"


def out_of_range(s, smin, smax) -> bool:
    if smin is not None and s < smin:
        return True
    return smax is not None and s > smax


if __name__ == "__main__":
    sys.exit(main())
