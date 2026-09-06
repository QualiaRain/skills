---
name: phase-gated-model-routing
description: "Budget-aware model and effort routing - phase the work, run each phase on the cheapest sufficient model, escalate on tripwires, verify with a fresh-context agent. Use at the START of a multi-phase task, on what model should this run on, tokens, usage, budget, running low, escalate or de-escalate, or a subagent's model. Also to design a cheap escalation-ladder eval instead of a full grid - do I need Opus or will Sonnet do, benchmark these models."
---

# Phase-Gated Model Routing

Spend Fable's intelligence where it's uniquely valuable (planning, synthesis, mistake-catching), and run everything else on the cheapest model+effort that can traverse it — without burning the savings on cache churn or interrupting the owner more than necessary.

## The economics this is built on (checked vs claude-api docs, 2026-06-12)

| Fact | Consequence |
|---|---|
| Prompt cache is **model-scoped** — switching models re-reads the whole conversation uncached at the new model's input rate, then re-caches (1.25× write premium) | Swap cost scales with context length. Swap down EARLY while the convo is short |
| Cache TTL is **5 minutes** — any human-paced pause usually expires it | At a phase boundary the full re-read happens on *either* model, so a swap there costs only the rate delta + re-write premium, not the whole re-read. The money-loser is **mid-phase** swapping/thrashing, which kills a live cache |
| Effort changes don't appear in the cache-invalidation hierarchy (reasoned 2026-06-12, not measured — `output_config` isn't part of the rendered prefix) | Prefer an effort change over a model change when either would do. But an effort rec still costs a halt + the owner's attention — batch it into an ask you're already making |
| Subagents start with **fresh, tiny context**; the Agent tool's `model` param accepts `sonnet`/`opus`/`haiku`/`fable` (verified 2026-06-12) | Delegating batch work to a cheap subagent costs nothing in cache and the cheap model never ingests the long conversation — usually beats a session downswap |
| Approx API $/MTok in/out: Fable $10/$50, Opus $5/$25, Sonnet $3/$15, Haiku $1/$5 (200k re-read ≈ $2 Fable / $0.60 Sonnet). Desktop usage metering assumed roughly proportional | Quantifies the swap-cost tradeoffs above |

## Hard constraints: who holds the knobs
- You cannot change your own model or effort — the picker is the owner's. "Pausing at a phase boundary" means ending the phase with a clickable AskUserQuestion (in a chat the owner is watching) whose options are model+effort combos for the next phase, recommended pick first (e.g. "Sonnet / medium (Recommended)").
- Spawned task-chips **inherit the owner's session setting at click time** — a tier written into the chip prompt does not bind. Always state the recommended model/effort to the owner in plain text alongside the chip.
- **Picker-mismatch handling:** at the start of every phase, check the model you're actually running as (your system prompt states it) against the plan's recommendation. On mismatch, proceed with ONE plain-text notice ("running this phase on X; plan said Y — fine to continue, or switch and say go") and don't re-ask. Attribute tripwires to the *actual* model, not the planned one.
- Effort caveat: `xhigh` exists at the API but may not be in the Desktop picker — only recommend effort levels the owner can actually click.

## The flow
In a coordination/orchestrator chat, do NOT run §2–§5 inline — spawn a track chip that carries this flow and stay available (the orchestrator no-long-loops rule).

**Scope limit:** §3 (delegate a batch) and §5's fresh-agent verifier need the Agent tool, available from a **top-level session or a track chip** but **not from inside an already-spawned subagent/workflow agent** (no nested agents in this harness). From within a subagent, fall back to inline execution + a script-based check (§5 first branch).

### 1. Fable-low opener (planning phase)
On Fable (low is usually enough for planning): clarify load-bearing assumptions, then produce a **phase plan written to a durable file** — named per task (e.g. `plan-<task>.md`, not a generic `PLAN.md` that collides/accretes) — containing per phase:
- what the phase does and what "done" looks like (**mechanical acceptance criteria** — the verifier and the cheap model both read this file cold)
- recommended model + effort
- a rough tool-call budget (powers the tripwires below)

Writing it to a file matters: the downswapped model and the final verifier must not depend on chat history to know what success means. At wrap, fold anything durable into the project's real docs (HANDOFF.md etc.) and delete the plan file (clean-up-scratch rule).

### 2. Downswap early
At the end of the opener — while the conversation is short and the swap is cheap — present the ask for the first execution phase. Defaults:

| Phase type | Recommendation |
|---|---|
| Planning, synthesis, architecture, ambiguous judgment | Fable low–medium |
| Complex implementation, debugging, gnarly integration | Opus high (max if correctness-critical) |
| Routine implementation, well-specified edits | Sonnet medium–high |
| Mechanical batches (renames, sweeps, per-file transforms) | don't downswap the session — delegate to Haiku/Sonnet **subagents** |
| End-of-task verification | Fable, **fresh context** (see §5) |

If the next phase's difficulty matches the current one, don't ask — continue.

### 3. Batch work goes to subagents, not session swaps
If a phase contains a parcelable batch, keep the session where it is and fan the batch out to subagents/workflows with an explicit cheap `model` param. The session model only needs to be as smart as the *coordination* requires. (`workflow-cost-discipline` owns per-agent routing detail for fan-outs — defer to it.)

### 4. Escalation tripwires (mechanical, not vibes)
A flailing model doesn't reliably know it's flailing — never rely on the executing model's self-assessment. Stop the phase and recommend escalation when any trip:
- **3 consecutive failures** of the same test/check with no new hypothesis between attempts
- **3 edit→run→same-error loops** on the same file/error with no new hypothesis AND no measurable progress toward the acceptance criteria (deliberate TDD red-to-green does NOT trip this)
- phase exceeds **~2× its planned tool-call budget** with <half the acceptance criteria met
- a verification pass rejects the same deliverable **twice**

On a trip: halt, state plainly what tripped, present the ask. **Escalate effort first, model second** — ladder: effort +1 → next model up at medium → that model high.

**De-escalation only at phase boundaries, never mid-phase.** Escalate eagerly, de-escalate lazily (hysteresis): being stuck wastes more than an oversized model does, and mid-phase flips are where cache churn costs.

### 5. Verify the wrap — script if checkable, fresh Fable agent if it needs judgment
Branch on what the acceptance criteria require:
- **Mechanically checkable** (exact string match, file/row counts, exit codes, schema validation, diff-clean) → verify with a **script** (`grep -c`, PowerShell, a test run), not an LLM — deterministic, no hallucination risk, costs nothing (boring-over-clever applied to verification).
- **Judgment** (does this read naturally, is the architecture sound, did it solve the user's intent vs. the literal spec) → the fresh Fable agent below.

Most phases have both — script the mechanical part, send only judgment to the agent.

For the judgment path: do NOT swap the long conversation back to Fable (it re-reads the *entire* conversation at Fable's rate + re-cache premium). Spawn a **Fable subagent** (Agent tool, `model: "fable"`) that cold-reads only (1) the plan/acceptance-criteria file and (2) the deliverables on disk (~10k tokens vs 200k), returning pass/fail per criterion with evidence. **Require the verifier to state which model it's running as in its first line, and check it** — else verification could silently run on the cheap session model. Cold verification is also a better test (a fresh reader isn't marinated in the session's assumptions — same logic as the cold-start doc audit in `headless-instruction-selftest`).

If the verifier finds problems: emit a new mini phase-plan with a model rec per fix, repeat from §2. **Terminal exit:** after the ladder tops out (Fable high) and verification still fails, or after **3 total verify-fix cycles**, STOP and surface the failing criteria with evidence to the owner. Never loop indefinitely.

## Finding the cheapest model that reliably does a task (escalation-ladder eval)

### The question this answers

"What is the *cheapest* model that **reliably** does this task?" — across a ladder of
models ordered cheap→expensive (the canonical one is Haiku < Sonnet < Opus 4.8, but
any cost-ordered set works). The deliverable is a per-task verdict: the cheapest model
that clears the reliability bar, plus the tasks where *no* model does.

### Why not the naive grid

The obvious design runs **all N models × all tasks × K trials** — most of that spend is wasted. Once a cheap model reliably aces a task, running the expensive models on it tells you nothing new and burns your priciest tokens on your easiest work. Only pay Opus prices on the tasks that genuinely *need* Opus.

### The ladder: escalate one tier at a time, only on the failures

```
Wave 1  cheapest model  on ALL tasks         → tasks it aces (K/K) are DONE (cheapest is sufficient)
Wave 2  next tier       on Wave 1's misses   → tasks it aces are DONE (this tier is sufficient)
Wave 3  next tier       on Wave 2's misses   → aces: this tier;  misses: "no model reliable (under this task framing)"
...repeat for as many tiers as you have
```

Each wave runs on a **strictly smaller** set. If the cheapest model aces everything,
the later waves run on zero tasks and cost nothing. Worst case (everything escalates)
you pay the full grid — but you pay each expensive tier *only* on the tasks that
defeated every cheaper tier, which is exactly the spend you wanted to make.

The ladder's **monotonicity assumption** — *if a cheaper model reliably passes, a stronger one would too* — is the same assumption baked into the "cheapest sufficient" question itself; the ladder just stops measuring once it's answered. **Fall back to the full grid** when you need to *prove* monotonicity or rank every model on every task (monotonicity can fail — a stronger model occasionally regresses on a specific item). Note this caveat to the user rather than silently assuming it away.

### Implement it as one cascade workflow, not a subagent fan-out

The waves are **dependent** (each gated on the previous wave's results) and the savings
come entirely from **per-stage model routing** — both are exactly what a `Workflow`
script gives you and a flat subagent fan-out does not. One launch, deterministic,
byte-identical prompts per model, later waves computed from earlier results inside the
script. See the `workflow-cost-discipline` skill for why a workflow (not parallel
agents) is the right tool when per-stage model routing is the whole point.

**Run the trials sequentially with early-exit — don't batch K up front.** The
reliability bar is K/K, so a model only stays in the running while it keeps passing.
The instant one trial fails, that model is out for this task and you escalate — so the
remaining trials (both the solver attempt *and* its judge call) are wasted work. Run
trial 1, grade it; only if it passes run trial 2; and so on. A model that's going to
fail costs you ~1 trial instead of K; a model that's reliable costs the full K (which
you genuinely need to confirm K/K). This applies the ladder's "stop measuring once the
answer is known" logic recursively, at the trial level. It trades wall-clock parallelism
for token cost — the right trade when the goal is the cheapest possible run, and "more
trials survived without a fail" is exactly what earns the higher confidence.

Sketch of the control flow (real one lives in
`Claude Eval Sandbox/model-escalation-eval/eval.workflow.js`):

```js
const LADDER = ['haiku', 'sonnet', 'opus']        // cheap → expensive
const verdict = {}
for (const task of allTasks) {
  let assigned = null
  for (const model of LADDER) {                   // try each tier, cheapest first
    let reliable = true
    for (let k = 0; k < K; k++) {                  // sequential trials, early-exit
      const candidate = await solve(task, model)
      const ok = await judge(task, candidate)      // strong-model judge, one trial
      if (!ok) { reliable = false; break }         // first fail → skip rest, escalate
    }
    if (reliable) { assigned = model; break }      // K/K survived → cheapest-sufficient, DONE
  }
  verdict[task.id] = assigned ?? 'none-reliable'   // defeated every tier
}
```

(Tasks are independent, so the outer `for (task of allTasks)` can still be a
`parallel(...)` for wall-clock if you have budget — the per-task *inner* loop stays
sequential, because that's where the early-exit savings live.)

### Keep the judge cheap — it's the dominant cost

The **strong-model judge is the most expensive part of the eval** (observed on the sandbox run: Opus grading dwarfed solver spend), so save on the *number* of judge calls, not the judge's strength. Main lever: the sequential early-exit loop above — a model that's going to fail gets graded ~once instead of K times. Secondary lever: if several verdicts must happen together, batch them into one judge call with structured per-candidate output.

Do **not** economize by swapping the judge down to a weak model — the verdict is what the user acts on, and a wrong "Haiku is sufficient" is the costliest error this eval can make.

### The pieces that make the verdict trustworthy

These matter as much as the ladder — a cheap eval that measures the wrong thing is worse
than no eval.

- **Reliability bar = K trials, pass only on K/K.** "Reliably" means it doesn't flake.
  K=3 with a 3/3 bar is the sensible default. Record the actual pass count (2/3 is a
  *borderline* result worth surfacing, not a clean fail) so the user sees near-misses.
  A single lucky pass is not "reliable" — that's the entire reason for K>1.
- **No answer leakage.** What the solver sees and what the grader sees must be different
  files. The solver gets the *symptom / task statement + the relevant code* and nothing
  that reveals the intended answer; the grader additionally gets the ground-truth
  reference. Describe problems by their *observable* symptom, never by their fix. If the
  solver could "explore" its way to the answer (e.g. the answer key sits in the same
  repo), isolate the workspace so it can't.
- **Grade with a strong model, and accept different-but-correct answers.** The verdict is
  the thing the user acts on, so spend intelligence on *verification*: use the strongest
  model on the ladder as the judge, regardless of which model produced the candidate. The
  judge compares candidate vs. ground truth and returns a structured verdict (e.g.
  `{solves, understands_root_cause, reason}`). A solution that differs from the reference
  but is genuinely correct must pass — you're grading the outcome, not string-matching the
  reference.
- **Pick a clear task bar and state its scope limits.** Decide deliberately what you're
  measuring. A *self-contained* bar (hand the model the exact code + symptom, ask for a
  fix) isolates "reasoning on the right code" and is cheap, but it does NOT measure
  *finding* the bug across a repo. Whatever you choose, tell the user what it does and
  doesn't cover so the verdict isn't over-read.

### How to apply, step by step

1. **Order the ladder** cheap→expensive and confirm the cost order with the user.
2. **Assemble tasks** with a ground-truth answer key per task (e.g. the fix commit on a
   branch). Stratify easy→hard if you can — it makes the escalation pattern legible.
3. **Split solver-view vs. grader-view fixtures** so there's no answer leakage.
4. **Set K and the reliability bar** (default K=3, pass on K/K).
5. **Write the cascade workflow** with per-wave `model` routing and a strong-model judge.
6. **Run once, save the cost-vs-reliability table** (per task: cheapest sufficient model,
   pass counts at each tier tried).
7. **Report the verdict and its caveats** — the per-task cheapest-sufficient model, the
   monotonicity caveat, and the task-bar scope limit.

### Worked reference

A complete, runnable instance — 8 real bugs, the cascade workflow, the leak-proof fixture
split, the Opus judge — lives in this machine's eval sandbox at
`~/Claude/Claude Eval Sandbox/model-escalation-eval/`
(`README.md` for the method, `eval.workflow.js` for the cascade). Read it when you need a
concrete template to adapt rather than building from this sketch.

## Exceptions — never downswap these
Per the global "spend intelligence in proportion to blast surface" rule, these always run at max intelligence however mechanical they look: **self-modification** (CLAUDE.md, skills, hooks, settings, deny list), **security-relevant changes**, and anything whose failure is expensive to unwind (wide refactors, until verified). The Ferrari always drives these.

## Quick self-check before any phase transition
1. Is the next phase's difficulty different from the current one? If not, don't ask — continue.
2. Could an effort change do what I'm about to recommend a model change for? Prefer it — batch it into an ask already being made.
3. Is the batch parcelable? Subagents, not a session swap.
4. Is the acceptance-criteria file current? The verifier reads it cold.
5. Am I actually running on the model the plan assumes? Check before attributing failures.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
