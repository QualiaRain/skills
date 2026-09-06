---
name: skill-execution-hardening
description: "Stress-test a skill. EXECUTION - run it blind on a cheap weak subagent, find where the weak model stumbles, fix, re-test on a FRESH one. TRIGGERING - measure whether the description fires on the right prompts, using the bundled scripts/trigger_probe.py, since skill-creator's Unix-only run_eval.py and run_loop.py mis-measure here. Triggers - harden or pressure-test a skill, optimize a description, WinError 10038. Not authoring (skill-creator)."
---

# Hardening a skill's execution with a weak-model stress test

A skill's description controls whether it *fires*; its body controls whether the work is done *correctly* once it fires. This skill optimizes the body. The method: a weak/cheap model (Haiku) is a cheap proxy for "will fast inference read these instructions and do the right thing?" Where the weak model improvises badly, the skill is under-specified -- that gap is the bug, not the model.

Pairs with, does not replace:
- `anthropic-skills:skill-creator` -- authoring a skill, general improvement, benchmarking, and TRIGGERING/description eval.

## Reactive entry: a skill mis-guided you mid-task

The standing global rule "A skill that mis-guides you gets hardened" routes here. If a skill steered you wrong during real work -- a misleading step, a wrong default, a missing branch -- that incident IS your failing trace; you don't need to manufacture one. Repair it with two constraints from that rule:
- **Structural fix, not a landmine catalogue.** Correct the structural defect (misleading step / wrong default / missing branch / vague success word) so the skill stays LEAN. Do NOT append "watch out for X / also beware Y" entries until the body becomes a junk drawer -- that taxes every future load and buries the load-bearing steps. The landmine that prompted the fix goes in the **commit message** (`git log -- skills/<name>/` is its record -- records over forecasts), not the skill body. A genuinely recurring, structurally-illuminating failure may earn ONE line in the existing `Worked example (provenance)` section below -- never a new running list. **But if the only correct fix truly is a warning at a decision point** (not a rewrite), add it as an imperative directive per `llm-legible-project-docs` -- that IS structural; the catalogue ban is on *running lists of past landmines*, not on a single load-bearing warning the procedure needs.
- **Don't derail the current task.** Finish the user's immediate need first (with the corrected understanding); run the test on an Agent subagent (the hardening loop is Agent-tool-based, `model: "haiku"`). Applying the fix globally is self-modification -- the blast-surface rule (global CLAUDE.md) governs review depth.

Then run **The loop** below to verify the fix on a fresh weak subagent. If this skill's output is NOT cheaply checkable (subjective / prose -- see Scope), the weak-model test doesn't apply: make the structural fix, get an independent adversarial review, and surface the diff instead.

## Scope -- when this loop applies

ONLY when the skill's correct output is **cheaply checkable** -- you can derive ground truth (a count, a file list, a structured findings format, a pass/fail) without heavy effort. For skills with subjective / prose / creative output (no cheap ground truth), this loop does not apply; use skill-creator's judgement-based eval instead. (skill-creator draws the same carve-out.)

## The loop

1. **Pick a testable target + a concrete task** with an observable outcome a single subagent can attempt in one turn.
2. **Establish cheap ground truth FIRST.** Before running anything, derive the answer key the cheap way (grep counts, file lists, expected structure). Without it you cannot catch hallucinated coverage or fabricated numbers. If you cannot cheaply derive ground truth, this loop does not fit (see Scope).
3. **Run the skill blind with a weak subagent.** Spawn an Agent with `model: "haiku"`. Give it the skill (have it READ the skill file by absolute path -- faithful and cheap -- or inline the body), the target path, and the task. Do NOT give it the answer (no expected findings, no counts). This reproduces the real cold start; front-loading the answer inflates the result and hides the gap. Scope it READ-ONLY for audits and bake in machine hard rules (on this machine: "C: only, NEVER touch D:").
4. **Observe HOW it executed, using the non-forgeable signal first.** Each Agent result returns the subagent's final text PLUS a usage block: `tool_uses`, `subagent_tokens`, `duration_ms`. `tool_uses` is **non-forgeable** -- 0 or a handful of tool uses means it did not actually read the code, no matter what its report claims; treat it as the primary honesty check. You do NOT get a per-file trace, so ALSO require a final `## How I worked` section (files/globs opened, search total, opened-and-read vs inferred, fraction covered) for detail -- but that prose is **forgeable**, so trust `tool_uses` over it when they disagree. Grade the output against your ground truth.
5. **Diagnose: every failure is a candidate skill fix.** Classify what went wrong (scope ignored, counts fabricated, coverage over-claimed, steps skipped, format violated, hallucinated-instead-of-read, false positives on intentional patterns). Each is usually an *ambiguity the weak model filled badly* -- a place the skill under-specifies.
6. **Fix the skill -- map each edit to an observed failure.** Do not speculatively rewrite -- a STRUCTURAL fix, not an accreting warning (see Reactive entry). Turn load-bearing guidance into imperative directives at the decision point (see `llm-legible-project-docs`): name the boundary, mandate the safe step, state the stakes. **Operationally define vague success words** ("audited", "complete", "checked") as concrete checkable actions, or the weak model satisfies the letter while violating the spirit. Show the `git diff`.
7. **Re-test with a FRESH subagent (writer != grader), >= 2-3 runs.** New agent(s), identical wrapper prompt, only the skill body changed. ONE trace lies -- weak models are inconsistent run to run (in the worked example the same skill's denominator came back 240 / 111 / 152 across runs). Confirm the specific failures are gone in the *majority* of runs and no new ones appeared.
8. **Stop deliberately -- the loop may NOT fully converge.** Failure modes are hydra-like: closing one form of a weakness often surfaces a subtler form of the *same* weakness. Cap at ~3-4 iterations (or 2 consecutive conditions that run clean across their multiple trials). If the same axis keeps mutating past the cap, DECLARE the residual and document it rather than chasing forever. Then capture the result (this skill) or, for a one-off, just report. A clean weak-model run is necessary-ish, not sufficient: it shows the instructions survive a weak reader, not that every real session is safe, and a fix that stops *Haiku* fabricating may not transfer to a different weak path.

## The blind-spawn wrapper (reusable -- adapt the paths)

```
You are <doing the skill's task> by following a SKILL specification.
STEP 1 - Read and follow this skill file exactly: <ABS PATH to SKILL.md>
STEP 2 - Perform its task against: <ABS PATH to target>, with NO focus argument (full default scope).
SAFETY: target is on C:. Only read under that path. NEVER read/list/touch any D:\ path.
Work from the real files on disk; do not guess. Produce output EXACTLY in the skill's reporting format.
After your report, append "## How I worked": (a) exact files/globs opened; (b) did you enumerate
with a search tool first and the raw total it returned; (c) for each item you marked OK, did you OPEN
and read its code or infer it from search output / a sibling pattern; (d) fraction truly audited vs sampled.
Be honest -- do not claim coverage you did not achieve.
```
Keep this wrapper byte-identical between baseline and re-test so the skill body is the only variable.

## Pinning the weak model + effort (read carefully)

- `model: "haiku"` on the Agent call sets the model tier.
- The Agent/Task tool has **NO effort parameter**. A subagent inherits the **session's** reasoning effort. The ONLY way to pin a floor effort is a custom agent definition (`.claude/agents/<name>.md`) with effort in its frontmatter, invoked via the agent-type. So either (a) accept session-effort inheritance and **state your session effort when you report results**, or (b) author a low-effort-pinned Haiku agent type and use it. Model tier is usually the larger lever, but effort can matter -- don't present a clean run as representative without naming the effort it ran at.

## Windows gotcha (cp1252)

This loop reads/pastes SKILL.md bodies, which often contain em-dashes/arrows. Any Python wrapper that reads a SKILL.md under Windows' default cp1252 locale crashes with `UnicodeDecodeError`. Run such helpers with `PYTHONUTF8=1` (see the triggering section below). Keep new skills ASCII-safe to avoid it entirely.

## Cost

Haiku subagents ran ~75-110k subagent tokens each in the worked example. Budget = (1 baseline + 2-3 re-tests) x iterations; with hydra re-iteration this can reach ~1M tokens for one skill, so set a hard iteration cap (step 8) and stop at it. Grading + the skill edits are the strong-model cost -- keep those tight.

## Worked example (provenance)

Target: `check-paths` (a fork of an upstream project; audits `from_pretrained`/`from_single_file` cache_dir routing). 2026-06-15, Haiku via the Agent tool.
- **Baseline:** ignored scope (flagged out-of-scope files "critical"), fabricated counts ("~200+"), skipped 61/63 `pipelines/` files, claimed "95%+ follows policy" having sampled ~60%.
- **Iter 1:** scope → imperative boundary with named tempters; enumeration-first with an exact grep denominator; truthful `Coverage: X of N`. Re-test: scope respected, exact counts, no false positives — but some runs narrowed `pipelines/**` and called the rest "out of scope" to fake 100%.
- **Iter 2:** glob is recursive (subdirs IN scope); deferred-in-scope is `X < N`, never "out of scope". Re-test x2: loophole closed — but both equated "grepped all N" with "audited all N".
- **Iter 3:** "enumeration is not audit". Re-test x2: both reported PARTIAL honestly (28/138, 156/173).

Net: 4 of 5 failure classes fixed cleanly; the 5th (coverage honesty) took three iterations because it kept mutating (fabricate → mis-scope → grep-as-audit) — the central lesson this skill encodes: hydra-like failure modes.

## Testing a skill's TRIGGERING (description), not its execution

The skill-creator's triggering harness does not work on Windows. This skill explains why and
ships a working replacement so you get a real measurement instead of a silently-wrong one.

### The bug (recognize it fast)
`skill-creator/scripts/run_eval.py` (and `run_loop.py`, which calls it for the Description
Optimization loop) streams each `claude -p` probe's output with **`select.select([process.stdout], …)`**.
On Unix that works on pipes; on **Windows, `select` only accepts sockets**, so it raises
`OSError: [WinError 10038] An operation was attempted on something that is not a socket`
immediately for **every** query. The harness catches it as `Warning: query failed: …` and records
each query as **0 triggers**.

Two symptoms, either one is the giveaway:
- A wall of `Warning: query failed: [WinError 10038] …` in the progress/stderr output.
- A results split where **all should-NOT-trigger queries "PASS" and all should-trigger queries
  "FAIL"** — because 0 triggers happens to match `should_trigger: false` and contradict
  `should_trigger: true`. It looks like a 50% score; it's actually **no measurement at all**.

There's also a second, separate Windows landmine in the same code path: `parse_skill_md` does
`Path(...).read_text()` with **no encoding**, so Python uses the locale default (**cp1252**) and
crashes with `UnicodeDecodeError: 'charmap' codec can't decode byte 0x90 …` on any SKILL.md that
contains em-dashes/arrows/other non-cp1252 UTF-8. Fix: run with **`PYTHONUTF8=1`** (forces UTF-8 as
the default text encoding). The bundled shim avoids the read entirely (it reads by `--skill-name`),
but keep `PYTHONUTF8=1` in mind for any skill-creator script on Windows.

### The fix — `scripts/trigger_probe.py`
A thread-reader replacement (no `select`). For each query it spawns `claude -p <query>
--output-format stream-json --verbose --include-partial-messages`, reads stdout on a **background
thread**, and decides from the **first tool action** whether the skill triggered, then **kills the
process early** so a genuine trigger doesn't run the whole task. It tests the **REAL installed
skill by name** (no synthetic command file, no moving the skill) — so it measures exactly what the
user experiences.

**Run it from a NEUTRAL cwd** (a dir with no project `CLAUDE.md`), so only the skill's own
name+description in `available_skills` drive the decision — not a project's instructions:

```bash
PY="C:/path/to/any/python.exe"            # stdlib only; any 3.8+ works
mkdir -p /c/tmp/neutral && cd /c/tmp/neutral
PYTHONUTF8=1 "$PY" /path/to/trigger_probe.py \
  --eval-set eval.json \
  --skill-name <the-installed-skill-name> \
  --runs 3 --workers 6 --model <session-model-id> --timeout 70
```

`eval.json` is a list of `{"query": "...", "should_trigger": true|false}` — generate it with the
skill-creator's Step-1 guidance (8-10 realistic should-trigger, 8-10 tricky near-miss should-NOT;
make them substantive multi-step asks — trivial one-step queries don't trigger skills regardless of
description). Output: a per-query `[PASS|FAIL] hits/runs fired=… expected=…` table to stdout plus a
JSON summary. A query "fired" if it triggered in ≥ half the runs (majority of 3).

**Smoke-test first**: run one obvious should-trigger and one obvious should-NOT with `--only-id N`
(1-based) before spending the full set. If an obvious trigger reads 0, something's off (wrong
`--skill-name`, skill not installed, model id wrong) — fix before the full run.

**Model fidelity vs cost**: use the model id that powers the user's real sessions (e.g.
`claude-opus-4-8`) for a faithful result; each probe is short because it's killed at the first
decision (~a few k tokens). A cheaper model is fine for clear-cut cases if cost matters — note the
caveat that triggering can be model-dependent.

### Where this fits in the skill-creator flow
Use the skill-creator (`anthropic-skills:skill-creator`) for everything else — designing the skill,
writing eval queries, the qualitative output viewer. Substitute **this shim for Step-3
`run_loop.py` / `run_eval.py`** when you're on Windows and just need the triggering numbers. The
shim does NOT auto-rewrite the description; if you want optimization, read the failures and edit the
`description:` by hand (a 19/20-style result with one defensible borderline usually needs no change).

### Caveat — recall under-reads (act-first behavior; model-dependent)
The probe counts a trigger only when the skill is consulted as the **first tool action**. But capable
models often **apply a skill while acting directly**: given a concrete task ("keep going until the
tests pass") they start working (Glob/Bash/Edit) instead of emitting a visible `Skill` consult, and
given a question they can answer outright ("/goal vs /loop?") they just answer — both read
`fired=False` even though the skill shaped the response. So **perfect precision + low recall, split
along "how do I set up X" (fires) vs "just do X / what's the difference" (doesn't), is usually
act-first behavior, not a description gap** — before "fixing" the description, capture one miss's full
`claude -p` output and check whether it references/applies the skill. It is also **model-dependent**:
on Sonnet, headless `claude -p` surfaces almost no consults (recall reads ≈ 0); Opus consults far more
readily — use the user's real session model and treat recall as a floor, not the true rate. (2026-06-14:
loop-engineering scored 10/10 precision but 3/10 recall on Opus; a captured "miss" showed Claude citing
loop-engineering and "setting up the loop" immediately after a Glob — i.e. applied, not ignored.)

### Provenance
Built + validated 2026-06-04 testing a bridge-content skill: the stock harness reported a bogus 10/20 (all-pass/all-fail signature); this shim reported a true 19/20 (lone "miss" a defensible borderline).

## Editing the skill is self-modification

Skill files are config. Keep the change reversible (tracked file -- show the `git diff`); for a global or high-blast-surface skill, surface the diff for review rather than committing silently; prefer an independent adversarial review over a self-review. Label any edit applied on the strength of an observed failure but not yet re-tested by the loop.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
