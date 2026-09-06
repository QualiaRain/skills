#!/usr/bin/env python3
"""Read the Logitech G HUB DPI table out of settings.db. READ-ONLY. INTENT ONLY.

G HUB keeps everything in one SQLite file, %LOCALAPPDATA%\\LGHUB\\settings.db,
in table `data`, column `file`, as a single giant JSON blob. The chain to the
number you want is TWO hops, not one (verified 2026-09-01, G PRO-series wireless):

    profiles.profiles[i].assignments[j]  where slotId ends `_mouse_sensitivity`
      -> cardId
      -> cards.cards[] entry with that id, attribute MOUSE_SENSITIVITY
         it holds only mouseSensitivity.{activeDpiIndex, presetId}
      -> cards.cards[] entry with id == presetId, attribute MOUSE_SETTINGS_ADVANCED
         mouseSettings.advancedDpiTable
           entries      dict keyed "1".."N", each {dpi, dpiX, dpiY, lod, disabled}
           defaultIndex the preset's own active step
           shiftIndex   the sniper/shift-DPI step
         mouseSettings.reportRate  {value, wirelessRate} in Hz

Stopping at the first card gets you an index and no numbers; that is the easy
mistake here. Watch too for a step whose `dpi` disagrees with its `dpiX`/`dpiY`
- the mouse follows X/Y, so `dpi` can be a stale label. This script flags it.

Read all of it as SOFTWARE INTENT, never as ground truth. The mouse stores its
own onboard DPI. If `lghub_agent` is not running (this script tells you), the
mouse is on whatever was last pushed to it, which can be a different number.
Ground truth is the HID++ read:
    uv run --with hidapi python scripts/logi_dpi.py read

Read-only: the DB is opened with SQLite's `mode=ro`, retried with
`mode=ro&immutable=1` when a live agent holds a write lock, and if both fail it
prints a VERDICT line rather than a traceback. Nothing here writes.

Usage
-----
  python ghub_dpi.py                 # the assigned DPI card, human readable
  python ghub_dpi.py --all           # plus G HUB's read-only prefab presets
  python ghub_dpi.py --json          # machine readable
  python ghub_dpi.py --db <path>     # a settings.db from somewhere else

Every outcome ends with a `VERDICT:` line - including the unopenable-database
path - so a caller never has to parse the block above it; an argparse usage error
prints usage on stderr instead. Under --json the same text is also a `verdict` key inside the
payload, so a machine reader drops that final line and reads the key (the same
shape logi_dpi.py uses).

Exit codes: 0 read a DPI table, 1 G HUB present but unusable (no assigned card,
or settings.db would not open read-only), 2 no G HUB installed here (not an
error - see the message it prints).

Smoke test (read-only):
  python ghub_dpi.py
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys

SENS_SLOT_HINT = "mouse_sensitivity"


def default_db_path() -> str:
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        raise SystemExit("error: LOCALAPPDATA is not set; pass --db explicitly")
    return os.path.join(local, "LGHUB", "settings.db")


def open_ro(uri: str, query: str):
    """Open read-only and force the file open now, not on the first query.

    sqlite3.connect is lazy: a locked or busy file connects fine and then raises
    OperationalError several lines later. Running one statement here means the
    fallback below actually gets a chance to fire.
    """
    con = sqlite3.connect(uri + query, uri=True)
    try:
        con.execute("SELECT name FROM sqlite_master WHERE type='table' LIMIT 1")
    except sqlite3.Error:
        con.close()
        raise
    return con


def load_blob(db_path: str) -> tuple[dict, str]:
    """Return (parsed json, description of the row it came from)."""
    uri = "file:" + db_path.replace("\\", "/").replace("?", "%3f").replace("#", "%23")
    try:
        con = open_ro(uri, "?mode=ro")
    # OperationalError is the locked/busy/unopenable case that the immutable
    # retry exists for; the wider DatabaseError also catches "file is not a
    # database", which is otherwise a traceback in the caller's face.
    except sqlite3.DatabaseError as first:
        # A live agent holds a write lock; immutable=1 reads straight past it.
        try:
            con = open_ro(uri, "?mode=ro&immutable=1")
        except sqlite3.DatabaseError as second:
            print(f"settings.db  {db_path}")
            print(f"open         mode=ro failed: {first}")
            print(f"open         mode=ro&immutable=1 also failed: {second}")
            print("  G HUB may be mid-write, the file may be corrupt, or --db "
                  "may not point at a SQLite database. Close G HUB and retry, "
                  "or pass a copy with --db.")
            print("  This source is software intent anyway. For the actual DPI:")
            print("    uv run --with hidapi python scripts/logi_dpi.py read")
            print("VERDICT: FAIL - cannot open G HUB settings.db read-only "
                  f"({second})")
            raise SystemExit(1) from second
    try:
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")]
        for table in ["data"] + [t for t in tables if t != "data"]:
            if table not in tables:
                continue
            cols = [r[1] for r in con.execute(f'PRAGMA table_info("{table}")')]
            if "file" not in cols:
                continue
            order = "_id" if "_id" in cols else cols[0]
            row = con.execute(
                f'SELECT "{order}", "file" FROM "{table}" ORDER BY "{order}" DESC LIMIT 1'
            ).fetchone()
            if not row or row[1] is None:
                continue
            raw = row[1]
            if isinstance(raw, (bytes, bytearray)):
                raw = raw.decode("utf-8", "replace")
            return json.loads(raw), f'{table}."file" row {order}={row[0]}'
        raise SystemExit(
            f"error: no table with a `file` column in {db_path} (tables: {tables})")
    finally:
        con.close()


def walk(node, path=""):
    yield path, node
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{path}[{i}]")


def sensitivity_assignments(blob) -> list[tuple[str, dict]]:
    return [(p, n) for p, n in walk(blob)
            if isinstance(n, dict) and SENS_SLOT_HINT in str(n.get("slotId", ""))]


def index_cards(blob) -> dict[str, tuple[str, dict]]:
    """Every card that carries an id, as {id: (json path, card)}."""
    out = {}
    for path, node in walk(blob):
        if isinstance(node, dict) and isinstance(node.get("id"), str) and (
                "mouseSettings" in node or "mouseSensitivity" in node):
            out.setdefault(node["id"], (path, node))
    return out


def has_dpi_table(card: dict) -> bool:
    ms = card.get("mouseSettings")
    return isinstance(ms, dict) and "advancedDpiTable" in ms


def describe_card(path: str, card: dict) -> dict:
    ms = card.get("mouseSettings") or {}
    adt = ms.get("advancedDpiTable") or {}
    entries = adt.get("entries") or {}
    steps = []
    for key in sorted(entries, key=lambda k: (len(str(k)), str(k))):
        e = entries[key] or {}
        dpi, dx, dy = e.get("dpi"), e.get("dpiX"), e.get("dpiY")
        steps.append({
            "index": key,
            "dpi": dpi,
            "dpiX": dx,
            "dpiY": dy,
            "lod": e.get("lod"),
            "disabled": bool(e.get("disabled")),
            "asymmetric": bool(e.get("asymmetric")) or (dx is not None and dx != dy),
            "label_mismatch": dx is not None and dpi is not None and dpi != dx,
        })
    return {
        "cardId": card.get("id"),
        "name": card.get("name"),
        "attribute": card.get("attribute"),
        "readOnly": card.get("readOnly"),
        "json_path": path,
        "advancedEnabled": adt.get("advancedEnabled"),
        "defaultIndex": adt.get("defaultIndex"),
        "shiftIndex": adt.get("shiftIndex"),
        "reportRate_hz": ms.get("reportRate"),
        "steps": steps,
    }


def resolve_preset(card: dict, by_id: dict) -> tuple[dict | None, int | None, str | None]:
    """A MOUSE_SENSITIVITY card points at a preset. Follow it.

    Returns (preset card or None, activeDpiIndex or None, presetId or None).
    """
    sens = card.get("mouseSensitivity")
    if not isinstance(sens, dict):
        return None, None, None
    pid = sens.get("presetId")
    entry = by_id.get(pid)
    return (entry[1] if entry else None), sens.get("activeDpiIndex"), pid


def agent_running():
    try:
        r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq lghub_agent.exe"],
                           capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    return "lghub_agent.exe" in (r.stdout or "")


def fmt_rate(rate) -> str:
    if isinstance(rate, dict):
        return (f"wired {rate.get('value')} Hz / wireless {rate.get('wirelessRate')} Hz")
    return f"{rate} Hz"


def print_card(c: dict, active_index=None) -> None:
    print(f"\npreset       {c['cardId']}  name={c['name']!r}  "
          f"attribute={c['attribute']}  readOnly={c['readOnly']}")
    print(f"path         {c['json_path']}")
    print(f"reportRate   {fmt_rate(c['reportRate_hz'])}    "
          f"advancedEnabled={c['advancedEnabled']}    shiftIndex={c['shiftIndex']}")
    if not c["steps"]:
        print("  (no entries in advancedDpiTable)")
        return
    active = active_index if active_index is not None else c["defaultIndex"]
    warn = []
    for s in c["steps"]:
        marks = []
        if str(s["index"]) == str(active):
            marks.append("<- ACTIVE")
        if str(s["index"]) == str(c["shiftIndex"]):
            marks.append("<- shift/sniper")
        if s["disabled"]:
            marks.append("(disabled step)")
        show_xy = s["asymmetric"] or s["label_mismatch"]
        asym = f"  dpiX={s['dpiX']} dpiY={s['dpiY']}" if show_xy else ""
        print(f"  step {str(s['index']):>2}   dpi={s['dpi']}{asym}  lod={s['lod']}  "
              + " ".join(marks))
        if s["label_mismatch"]:
            warn.append(
                f"  step {s['index']}: dpi label {s['dpi']} disagrees with "
                f"dpiX/dpiY {s['dpiX']}/{s['dpiY']} - the mouse follows X/Y, "
                "so the label is stale. Do not quote it as the DPI.")
    for w in warn:
        print(w)
    if str(active) not in {str(s["index"]) for s in c["steps"]}:
        print(f"  active index {active} is not in the table - treat as unknown")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="ghub_dpi.py",
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__[__doc__.index("Usage"):],
    )
    p.add_argument("--db", default=None, help="path to settings.db")
    p.add_argument("--all", action="store_true",
                   help="dump every DPI card, including G HUB's read-only prefabs")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    a = p.parse_args(argv)

    db = a.db or default_db_path()
    if not os.path.exists(db):
        print("  Not an error unless this is a Logitech rig with G HUB installed.")
        print("  This source is software intent anyway. For the actual DPI use:")
        print("    uv run --with hidapi python scripts/logi_dpi.py read   (Logitech)")
        print("    the mouse vendor's own software                        (others)")
        print("  and confirm either of those with scripts/rawinput_dpi_test.py.")
        print(f"VERDICT: SKIP - no G HUB settings.db at {db}")
        return 2

    blob, source = load_blob(db)
    cards = index_cards(blob)
    assigns = sensitivity_assignments(blob)

    assigned = []
    for apath, node in assigns:
        cid = node.get("cardId")
        entry = cards.get(cid)
        if not entry:
            continue
        path, card = entry
        preset, active_idx, pid = resolve_preset(card, cards)
        target_path, target_card = (cards.get(pid) or (path, card)) if preset else (path, card)
        if not has_dpi_table(target_card):
            continue
        d = describe_card(target_path, target_card)
        d["slotId"] = node.get("slotId")
        d["assignment_path"] = apath
        d["assignment_cardId"] = cid
        d["activeDpiIndex"] = active_idx
        d["presetId"] = pid
        assigned.append(d)

    others = [describe_card(path, card) for cid, (path, card) in cards.items()
              if has_dpi_table(card) and cid not in {d["cardId"] for d in assigned}]

    running = agent_running()
    result = {
        "db": db,
        "source_row": source,
        "lghub_agent_running": running,
        "authority": "INTENT ONLY - software state, not the mouse's onboard DPI",
        "assigned_cards": assigned,
        "other_cards": others if a.all else [],
        "other_card_count": len(others),
    }

    if a.json:
        # The verdict is BOTH a key in the payload and the last stdout line, so
        # a machine reader can take result["verdict"] after dropping that line,
        # and a human reading the terminal still gets a verdict last. This is the
        # same shape logi_dpi.py uses; a stderr-only verdict was tried and
        # rejected, because a merged stream does not preserve its position.
        result["verdict"] = (
            f"{len(assigned)} assigned DPI card(s) - INTENT ONLY. Confirm with: "
            "uv run --with hidapi python scripts/logi_dpi.py read")
        print(json.dumps(result, indent=2))
        print("VERDICT: " + result["verdict"])
        return 0

    print(f"settings.db  {db}")
    print(f"source       {source}")
    if running is None:
        print("lghub_agent  UNKNOWN (tasklist failed)")
    elif running:
        print("lghub_agent  RUNNING - software settings are probably live on the mouse")
    else:
        print("lghub_agent  NOT RUNNING - the mouse is on its ONBOARD / last-pushed DPI, "
              "which may not match anything below")

    if not assigned:
        seen = ", ".join(str(n.get("slotId")) for _p, n in assigns) or "none"
        print(f"\nno assigned mouse-sensitivity card found. Assignments seen: {seen}")
        print("Re-run with --all --json and look for advancedDpiTable by hand.")
        print("VERDICT: FAIL - G HUB is installed but no DPI card is assigned")
        return 1

    for c in assigned:
        print(f"\nslot         {c['slotId']}   ({c['assignment_path']})")
        print(f"card         {c['assignment_cardId']}  activeDpiIndex="
              f"{c['activeDpiIndex']}  -> preset {c['presetId']}")
        print_card(c, active_index=c["activeDpiIndex"])

    if a.all:
        print(f"\n--- {len(others)} other DPI cards (G HUB prefabs / unassigned) ---")
        for c in others:
            print_card(c)
    else:
        print(f"\n({result['other_card_count']} other DPI cards not shown; --all to see them)")

    # One-line verdict, so a caller does not have to parse the block above.
    first = assigned[0]
    active = first["activeDpiIndex"]
    if active is None:
        active = first["defaultIndex"]
    step = next((s for s in first["steps"] if str(s["index"]) == str(active)), None)
    if step is None:
        claim = "active step not in the table"
    else:
        claim = f"{step['dpiX'] if step['dpiX'] is not None else step['dpi']} DPI"
        if step["label_mismatch"]:
            claim += f" (X/Y; the stale `dpi` label says {step['dpi']})"
    trust = ("agent running, so this is probably live"
             if running else "agent NOT running, so the mouse may be elsewhere")
    print("\nConfirm with: uv run --with hidapi python scripts/logi_dpi.py read")
    print(f"VERDICT: G HUB intends {claim} - {trust}. INTENT ONLY.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
