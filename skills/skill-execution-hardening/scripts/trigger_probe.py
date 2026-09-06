#!/usr/bin/env python3
"""Windows-compatible skill-triggering probe (drop-in for skill-creator's broken run_eval.py).

skill-creator's run_eval.py uses select.select() on the claude -p subprocess pipe, which only
works on sockets on Windows (WinError 10038) -> every query errors and reads 0 triggers. This is a
thread-reader replacement: spawn `claude -p <query>` with stream-json, read its stdout on a
background thread (no select), decide from the FIRST tool_use whether the skill triggered, then kill
the process early (so a real trigger doesn't run the whole task).

Tests the REAL installed skill by name (no synthetic command, no moving the skill). Run from a
neutral cwd (no project CLAUDE.md) so only the skill's name+description drive the decision.

Usage: python trigger_probe.py --eval-set FILE --skill-name NAME [--runs 3] [--workers 6]
                               [--model claude-opus-4-8] [--timeout 70] [--only-id N]
  eval-set: JSON list of {"query": "...", "should_trigger": true|false}
  Tip: set PYTHONUTF8=1 on Windows so any UTF-8 reads/writes don't crash under cp1252.
"""
import argparse
import json
import os
import queue
import subprocess
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


class ProbeError(RuntimeError):
    """The claude subprocess produced no events at all -- auth failure, bad model, crash.

    This exists because a dead subprocess used to be indistinguishable from a genuine
    non-trigger: both surfaced as hits=0. On 2026-08-21 an expired CLI OAuth session made
    every probe fail and the run was misread as "the skill never fires". Never let a failed
    run be silently counted as a negative.
    """


_NEUTRAL_DIR = []


def neutral_cwd():
    """One empty temp dir, reused for every subprocess in the run."""
    if not _NEUTRAL_DIR:
        _NEUTRAL_DIR.append(tempfile.mkdtemp(prefix="skilltrig-"))
    return _NEUTRAL_DIR[0]


def probe_once(query, skill_name, model, timeout):
    """Run one claude -p and return True if the FIRST tool action consults skill_name."""
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    # Neutral cwd, ENFORCED (2026-08-21): the docstring asked the operator to run from a
    # directory with no project CLAUDE.md, but nothing made it true -- the subprocess
    # inherited whatever cwd the caller had. That silently changes what the probe measures:
    # a project CLAUDE.md is extra instruction the model reads, and a project
    # settings.local.json can carry `skillListingBudgetFraction`, which strips skill
    # DESCRIPTIONS from the listing -- exactly the text under test. Running the probe from
    # `Claude Eval Sandbox` or `To Do` would score every should-trigger query as a miss and
    # look like a bad description. A temp dir has neither.
    cmd = ["claude", "-p", query, "--output-format", "stream-json",
           "--verbose", "--include-partial-messages"]
    if model:
        cmd += ["--model", model]
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=env, cwd=neutral_cwd(), text=True, encoding="utf-8",
                         errors="replace", bufsize=1)
    q = queue.Queue()

    def reader():
        try:
            for line in p.stdout:
                q.put(line)
        except Exception:
            pass
        q.put(None)

    threading.Thread(target=reader, daemon=True).start()

    triggered = False
    saw_event = False
    saw_model_output = False
    raw_noise = []
    pending = None
    acc = ""
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            try:
                line = q.get(timeout=1.0)
            except queue.Empty:
                if p.poll() is not None:
                    break
                continue
            if line is None:
                break
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                if line.strip():
                    raw_noise.append(line.strip())
                continue
            saw_event = True
            et = ev.get("type")
            if et in ("stream_event", "assistant"):
                saw_model_output = True
            if et == "stream_event":
                se = ev.get("event", {})
                st = se.get("type", "")
                if st == "content_block_start":
                    cb = se.get("content_block", {})
                    if cb.get("type") == "tool_use":
                        nm = cb.get("name", "")
                        if nm in ("Skill", "Read"):
                            pending = nm
                            acc = ""
                        else:
                            triggered = False
                            break
                elif st == "content_block_delta" and pending:
                    d = se.get("delta", {})
                    if d.get("type") == "input_json_delta":
                        acc += d.get("partial_json", "")
                        if skill_name in acc:
                            triggered = True
                            break
                elif st in ("content_block_stop", "message_stop"):
                    if pending:
                        triggered = skill_name in acc
                        break
                    if st == "message_stop":
                        triggered = False
                        break
            elif et == "assistant":
                msg = ev.get("message", {})
                decided = False
                for ci in msg.get("content", []):
                    if ci.get("type") != "tool_use":
                        continue
                    nm = ci.get("name", "")
                    inp = ci.get("input", {})
                    if nm == "Skill" and skill_name in str(inp.get("skill", "")):
                        triggered = True
                    elif nm == "Read" and skill_name in str(inp.get("file_path", "")):
                        triggered = True
                    decided = True
                    break
                if decided:
                    break
            elif et == "result":
                break
    finally:
        if p.poll() is None:
            p.kill()
            try:
                p.wait(timeout=5)
            except Exception:
                pass
    # A negative is only trustworthy if the subprocess ran cleanly. The CLI prints a parseable
    # JSON error event on stdout before dying (so "we saw events" proves nothing) and puts the
    # real reason on stderr -- e.g. "Failed to authenticate: OAuth session expired". Treat any
    # stderr output on a negative as VOID rather than as evidence the skill did not fire.
    err = ""
    try:
        err = (p.stderr.read() or "") if p.stderr else ""
    except Exception:
        pass
    # Benign chatter ("Warning: ...") must not void a legitimate negative -- only real
    # failures do. Keep this filter narrow: when in doubt, void rather than report.
    err = chr(10).join([ln for ln in err.splitlines()
                   if ln.strip() and not ln.strip().startswith("Warning:")]).strip()
    # The discriminator that matters: a GENUINE non-trigger still produces model output (the
    # model just answers directly). A failed run produces none. The CLI prints its fatal error
    # as PLAIN TEXT on stdout, which the JSON reader above skips, so raw_noise is where an auth
    # failure actually shows up -- not stderr, and not as a missing event stream.
    if not triggered and not saw_model_output:
        detail = err or (raw_noise[0] if raw_noise else "") or "no model output from claude"
        raise ProbeError(detail[:200])
    return triggered


def preflight(model):
    """Prove the CLI can answer at all before probing anything.

    Per-run failure detection turned out to be unreliable: on an expired OAuth session the CLI
    still emits a plausible-looking event stream, so a dead run is very hard to tell apart from a
    genuine non-trigger, and every query reports 0 hits. That reads as "the skill never fires"
    and is completely wrong. A single up-front health check is cheap and unambiguous -- if the
    CLI cannot answer a trivial prompt, no probe result below means anything. (2026-08-21)
    """
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    cmd = ["claude", "-p", "reply with the single word READY"]
    if model:
        cmd += ["--model", model]
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=120, env=env,
                           cwd=neutral_cwd())
    except Exception as ex:
        return False, "could not run claude: %s" % ex
    out = (r.stdout or "") + (r.stderr or "")
    if "READY" in out.upper():
        return True, ""
    first = next((ln.strip() for ln in out.splitlines()
                  if ln.strip() and not ln.strip().startswith("Warning:")), "no output")
    return False, first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eval-set", required=True)
    ap.add_argument("--skill-name", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--model", default=None)
    ap.add_argument("--timeout", type=int, default=70)
    ap.add_argument("--only-id", type=int, default=None, help="run just one eval (1-based index)")
    args = ap.parse_args()

    ok, why = preflight(args.model)
    if not ok:
        print("PREFLIGHT FAILED -- refusing to run, because every probe would return 0 hits")
        print("and that is indistinguishable from 'the skill never fires'.")
        print("  reason: %s" % why)
        print("  most likely the claude CLI OAuth session expired -- run `claude` once")
        print("  interactively to re-authenticate, then repeat this probe.")
        raise SystemExit(2)

    evals = json.loads(Path(args.eval_set).read_text(encoding="utf-8"))
    if args.only_id is not None:
        evals = [evals[args.only_id - 1]]

    tasks = [(i, e) for i, e in enumerate(evals)]
    results = {}

    def run_query(idx, e):
        hits = 0
        errors = 0
        last_err = ""
        for _ in range(args.runs):
            try:
                if probe_once(e["query"], args.skill_name, args.model, args.timeout):
                    hits += 1
            except ProbeError as ex:
                errors += 1
                last_err = str(ex)
        return idx, hits, errors, last_err

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(run_query, idx, e) for idx, e in tasks]
        for f in as_completed(futs):
            idx, hits, errors, last_err = f.result()
            results[idx] = (hits, errors, last_err)

    passed = 0
    total_errors = 0
    first_err = ""
    out = []
    for idx, e in tasks:
        hits, errors, last_err = results[idx]
        total_errors += errors
        if last_err and not first_err:
            first_err = last_err
        rate = hits / args.runs
        fired = rate >= 0.5
        ok = (fired == e["should_trigger"])
        passed += ok
        out.append({"id": idx + 1, "should_trigger": e["should_trigger"],
                    "hits": hits, "runs": args.runs, "errors": errors,
                    "fired": fired, "pass": ok,
                    "query": e["query"]})
        print("  [%s] %d/%d fired=%s expected=%s: %s"
              % ("PASS" if ok else "FAIL", hits, args.runs, fired,
                 e["should_trigger"], e["query"][:64]))
    print("\nResults: %d/%d passed" % (passed, len(tasks)))
    if total_errors:
        print("")
        print("*** RESULTS VOID: %d probe run(s) failed before producing any output. ***"
              % total_errors)
        print("*** First error: %s" % (first_err or "unknown"))
        print("*** A failed run is NOT a non-trigger. Fix the cause and re-run.")
        print("*** Most common cause: the claude CLI OAuth session expired -- run `claude`")
        print("*** once interactively to re-authenticate, then repeat this probe.")
    print(json.dumps({"passed": passed, "total": len(tasks), "errors": total_errors,
                      "valid": total_errors == 0, "first_error": first_err,
                      "results": out}, indent=2))


if __name__ == "__main__":
    main()
