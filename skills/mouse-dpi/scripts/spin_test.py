#!/usr/bin/env python3
"""Inject exactly N mouse counts of horizontal motion, to prove a game's formula.

If the deg/count formula is right, injecting `360 / deg_per_count` counts turns
the view exactly one full circle and it lands back on the landmark it started on.
That is the only check in this skill that distinguishes "wrong formula" from
"wrong target", which otherwise feel identical to the player.

CONSENT-GATED. This moves the mouse on someone else's machine, so:
  * --dry-run prints the plan and injects nothing. Always run that first.
  * the real run needs --yes AND their explicit go in the current conversation.
  * never while a live match is on - injected input mid-match is indistinguishable
    from cheating, and a mis-aimed spin can get someone killed in game.
  * NEVER at all against a game with a kernel-level anti-cheat driver - Vanguard
    (Valorant), EAC, BattlEye, Javelin. Those watch for synthetic input and can
    flag it in a practice range or an offline mode just as readily as in a match,
    and the account is what is at risk. Use the hand-distance test on those
    instead (SKILL.md step 7).
It touches no hardware, no DPI, no registry and no files.

Usage
-----
  python spin_test.py --game source --sens 1.5 --dry-run     # safe preview
  python spin_test.py --game source --sens 1.5 --yes         # injects
  python spin_test.py --k 0.000682 --sens 50 --dry-run       # measured constant
  python spin_test.py --counts 2667 --yes                    # raw count
  python spin_test.py --counts 2667 --delay 8 --step 20 --interval-ms 2 --yes
  python spin_test.py --list                                 # known formulas

Reading the result: if the view stops `e` degrees PAST the landmark after `N`
counts, the true value is deg/count = (360 + e) / N (negative e if it stopped
short). See reference/finding-a-formula.md, method B.

Why SendInput relative moves work for raw-input games: an injected
MOUSEEVENTF_MOVE with no ABSOLUTE flag is delivered as a WM_INPUT raw mouse
event carrying the same dx, so Unity's <Mouse>/delta and every other raw-input
reader see exactly the counts sent. Counts go out in small steps at a short
interval so a per-frame delta clamp, if the game has one, is not tripped.

Caveat worth saying out loud before believing a null result: a game with mouse
smoothing or negative acceleration (ARC Raiders, for one) will NOT land back on
the landmark even with a correct constant, because its response depends on how
fast the counts arrive. On those, vary --step/--interval-ms and watch the answer
move; if it moves, the game is smoothing and no single cm/360 exists.

Smoke test (safe, injects nothing, exits non-zero if the plan cannot be built):
  python spin_test.py --game source --sens 1.5 --dry-run
"""

from __future__ import annotations

import argparse
import ctypes
import os
import sys
import time
from ctypes import wintypes

# One source of truth for game formulas: sens_calc.py, which games.md is kept in
# step with. Importing beats a second copy that silently drifts.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from sens_calc import FORMULAS, range_text, resolve_game  # noqa: E402
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        f"error: cannot import sens_calc.py from this script's directory: {exc}\n"
        "spin_test.py deliberately has no formulas of its own - keep the two "
        "files together."
    )

if sys.platform != "win32":
    raise SystemExit("error: Windows only (SendInput)")

user32 = ctypes.WinDLL("user32", use_last_error=True)

INPUT_MOUSE = 0
MOUSEEVENTF_MOVE = 0x0001

# ULONG_PTR: 8 bytes on x64, 4 on x86. wintypes.WPARAM is exactly that, and
# using a real pointer type here would be wrong on x86 by luck rather than
# design. Getting it wrong changes sizeof(INPUT) and SendInput then rejects
# every call with ERROR_INVALID_PARAMETER.
ULONG_PTR = wintypes.WPARAM


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class _INPUT_UNION(ctypes.Union):
    # The real INPUT union also holds KEYBDINPUT (24 B) and HARDWAREINPUT (8 B)
    # on x64, both smaller than MOUSEINPUT (32 B), so a union carrying only `mi`
    # has the correct size. Adding a keyboard path later means adding it here.
    _fields_ = [("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _INPUT_UNION)]


user32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
user32.SendInput.restype = wintypes.UINT


def send_move(dx: int) -> int:
    inp = INPUT()
    inp.type = INPUT_MOUSE
    inp.u.mi = MOUSEINPUT(dx, 0, 0, MOUSEEVENTF_MOVE, 0, 0)
    return user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def deg_per_count(game: str | None, k: float | None, sens: float) -> tuple[float, str]:
    if game is not None:
        key = resolve_game(game)
        if key not in FORMULAS:
            raise SystemExit(
                f"error: unknown game '{game}'. known: {', '.join(sorted(FORMULAS))}. "
                "Use --k with a constant you measured."
            )
        fn, desc, _prov, rng, verified = FORMULAS[key]
        if (rng[0] is not None and sens < rng[0]) or (
                rng[1] is not None and sens > rng[1]):
            if verified:
                print(f"note        sens {sens} is outside {key}'s slider range "
                      f"({range_text(*rng)}) - the game would clamp it, so the "
                      "count below is hypothetical")
            else:
                print(f"note        sens {sens} is outside the range recorded for "
                      f"{key} ({range_text(*rng)}), but that range is UNVERIFIED "
                      "(see games.md) - the setting may well be fine")
        return fn(sens), f"{key} ({desc})"
    return k * sens, f"linear k={k}"


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="spin_test.py",
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__[__doc__.index("Usage"):],
    )
    ap.add_argument("--counts", type=int,
                    help="total horizontal counts to inject (positive = turn right)")
    ap.add_argument("--game", help=f"derive counts from a built-in formula: "
                                   f"{', '.join(sorted(FORMULAS))}")
    ap.add_argument("--k", type=float,
                    help="derive counts from a linear constant: deg/count = k * sens")
    ap.add_argument("--sens", type=float,
                    help="the game's sensitivity setting, used with --game or --k")
    ap.add_argument("--turns", type=float, default=1.0,
                    help="full turns to inject when deriving counts (default 1)")
    ap.add_argument("--delay", type=float, default=5.0,
                    help="seconds of countdown before injecting (default 5)")
    ap.add_argument("--step", type=int, default=20,
                    help="counts per injected event (default 20)")
    ap.add_argument("--interval-ms", type=float, default=2.0,
                    help="pause between events in ms (default 2)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the plan and exit without injecting anything")
    ap.add_argument("--yes", action="store_true",
                    help="required to actually inject; the owner must have said go")
    ap.add_argument("--list", action="store_true",
                    help="list the built-in formulas and exit")
    args = ap.parse_args()

    if args.list:
        for name, (_fn, desc, prov, rng, verified) in sorted(FORMULAS.items()):
            flag = "" if verified else "  [RANGE UNVERIFIED]"
            print(f"{name:12s} deg/count = {desc}")
            print(f"{'':12s} setting range {range_text(*rng)}{flag}  [{prov}]")
        print(f"VERDICT: {len(FORMULAS)} built-in formulas, imported from "
              "sens_calc.py - this script keeps no copy of its own.")
        return 0

    if args.step < 1:
        ap.error("--step must be at least 1")
    if args.game and args.k is not None:
        ap.error("pick one of --game / --k")
    # --counts is the raw override; a formula alongside it would be computed and
    # then silently thrown away, so the caller would not know which number was
    # actually injected.
    if args.counts is not None and (args.game or args.k is not None):
        ap.error("--counts already says how far to turn; drop --game / --k, or "
                 "drop --counts and let the formula derive it")

    dpc_label = None
    if args.counts is None:
        if not ((args.game or args.k is not None) and args.sens is not None):
            ap.error("give --counts, or --sens together with --game or --k")
        dpc, dpc_label = deg_per_count(args.game, args.k, args.sens)
        if dpc <= 0:
            ap.error("that formula and setting give a non-positive deg/count")
        per_turn = 360.0 / dpc
        args.counts = int(round(per_turn * args.turns))
        print(f"formula     {dpc_label} at sens {args.sens} -> "
              f"{dpc:.6f} deg/count, {per_turn:.1f} counts per 360")
    if args.counts == 0:
        ap.error("counts must be non-zero")

    steps = abs(args.counts) // args.step
    rem = abs(args.counts) % args.step
    sign = 1 if args.counts > 0 else -1
    est = (steps + (1 if rem else 0)) * args.interval_ms / 1000.0
    print(f"plan        {steps} events x {args.step} counts + {rem} remainder = "
          f"{abs(args.counts)} counts, ~{est:.2f} s of motion, "
          f"turning {'right' if sign > 0 else 'left'}, "
          f"after a {args.delay:.0f} s countdown")
    print("check       aim at a landmark first; if it lands e degrees past it, "
          f"deg/count = (360 + e) / {abs(args.counts)}")

    if args.dry_run:
        print("anti-cheat  never against kernel anti-cheat: Vanguard, EAC, "
              "BattlEye, Javelin; hand-distance test there")
        print("VERDICT: dry run - plan built, nothing injected")
        return 0

    if not args.yes:
        print("  This moves the mouse. Re-run with --yes only after the owner has")
        print("  said go in the current conversation, and only once they have")
        print("  clicked into the game window. Never during a live match, and")
        print("  never at all against a game with kernel-level anti-cheat")
        print("  (Vanguard, EAC, BattlEye, Javelin) - injected input can be")
        print("  flagged even in a practice range. Use the hand-distance test.")
        print("VERDICT: refusing to inject without --yes")
        return 2

    print(f"injecting in {int(args.delay)}s - click into the game window NOW")
    for left in range(int(args.delay), 0, -1):
        print(f"  {left}...", flush=True)
        time.sleep(1)

    sent = 0
    t0 = time.perf_counter()
    for _ in range(steps):
        if send_move(sign * args.step) != 1:
            err = ctypes.get_last_error()
            print(f"VERDICT: FAIL - SendInput rejected after {sent} counts "
                  f"(GetLastError={err})")
            return 2
        sent += args.step
        time.sleep(args.interval_ms / 1000.0)
    if rem:
        if send_move(sign * rem) != 1:
            err = ctypes.get_last_error()
            print(f"VERDICT: FAIL - SendInput rejected after {sent} counts "
                  f"(GetLastError={err})")
            return 2
        sent += rem
    dt = time.perf_counter() - t0
    print(f"VERDICT: injected {sign * sent} counts in {dt:.2f} s. Back on the "
          "landmark means the formula holds; read the offset if not.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
