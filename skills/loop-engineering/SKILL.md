---
name: loop-engineering
description: "Run Claude in a self-verifying agentic loop via /goal and /loop - a measurable goal, a separate cheaper verifier (writer is not grader), a mechanical stop. Triggers - set this up as a loop, keep going until X, loop until this is met, leave it running while I'm away, Ralph loop, bare /goal or /loop. Also when done is subjective (video, writing, design) - how do I measure X, I can't define done, what's the success criterion. Not one-shot tasks."
---

# Loop engineering — running Claude in a self-verifying loop (the owner)

## What this is, and why it works

The "write loops, not prompts" style (Boris Cherny, Claude Code lead, June 2026): the progression is **source code → agent → loop** — you now write the *loop* that drives an agent toward a goal and checks its own work, built on **the primitives the owner's machine already ships** (no hand-rolled bash).

**The four parts (this is the whole pattern):**
1. **A loop** — Claude keeps taking turns toward a goal instead of you re-prompting each step.
2. **A skill inside the loop** — holds the checklist / rules so the loop doesn't re-spend context describing the task every turn.
3. **A separate verifier — writer ≠ grader**, usually a **cheaper** model than the worker. The load-bearing part: a loop that grades its own work is just the agent agreeing with itself.
4. **A measurable stop condition** — a mechanical predicate ("all tests in `tests/auth` pass and lint is clean"), plus a turn/budget cap so it can't run away.

## First gate: should this even be a loop?

A loop earns its keep only when the work is **open-ended toward a checkable finish line**. Don't loop a one-shot task — just do it.

**Loop when:** iterate-until-green (tests/lint/build/typecheck must pass), a repetitive backlog to grind (migrate N files, fix N findings), or an unattended run while the owner is away. **Don't loop when:** the task finishes in one pass, it's a single coherent edit, or there's no mechanical way to tell when it's done (a loop with no real check is the agent agreeing with itself — see part 3).

**"But my finish line is subjective" (video editing, writing/design quality, "is this *good*?") is NOT a reason to give up on looping** — it usually means the anchor lives lower in the task, not nowhere. Before concluding there's no mechanical check, see *Finding the anchor when 'done' is subjective* below: decompose the goal until a mechanical leaf appears (a count/boundary/threshold/structural-match, or a diff against a known-good reference), then loop at *that* level. That skill is the front-half of this one; come back here to run the loop once it hands you an anchor.

## Pick the mechanism (cheapest sufficient one wins)

**"Loop" is an umbrella, not one command.** Most "loops" people mean are really *loop-until-a-goal-is-met* — which is exactly what `/goal` is, so it reads and behaves as a loop even though it's a distinct command (it just self-terminates when the condition holds instead of running forever). `/loop` is the *recurring / interval* form. Both are loops; pick by shape:

the owner's machine has Claude Code **v2.1.170**, so all of these are available.

| Mechanism | Reach for it when | Notes |
|---|---|---|
| **`/goal`** *(default)* | "Keep working until `<condition>` is true" in **one** workspace, attended-ish. | Sets a completion condition; **after each turn a small fast model checks it** (the built-in writer≠grader verifier — parts 1+3 for free) and starts another turn if not met. Stop with the condition, `Ctrl+C`, or `/goal clear`. **No built-in token budget — put a turn cap IN the condition** ("…or stop after 15 turns"). Needs a **trusted workspace** (the evaluator runs via hooks). [Docs](https://code.claude.com/docs/en/goal) |
| **`/loop`** | Recurring / scheduled / self-paced upkeep ("every 15m re-run X", "keep babysitting the PRs"). | `/loop 5m <prompt>` = interval; `/loop <prompt>` = self-paced (Claude picks the wait, can end when provably complete); bare `/loop` = default maintenance. `Esc` to stop; interval loops auto-expire after 7 days. [Docs](https://code.claude.com/docs/en/scheduled-tasks) |
| **Dynamic workflow** | Scripted generator→verifier at **scale** (dozens+ items, fan-out, results piped agent→agent, a codified verify panel). | Lets you pin a **different model per stage** (cheap workers, one stronger verifier). **Read `workflow-cost-discipline` BEFORE writing one** — don't silently fan out an all-Opus loop. |
| **goalkeeper** *(off-the-shelf, 3rd-party)* | You want durable, **contract-driven** run-until-done with a written Definition of Done and a fresh independent judge subagent — without building it. | See last section. Review before installing. |

**Custom verifier subagent (any mechanism):** spawn the grader as a subagent pinned to a cheaper model — frontmatter `model:` in a `.claude/agents/*.md`, or the Agent tool's `model` param (`sonnet`/full ID; `model: inherit` matches the session). **Sonnet is the grader floor — never Haiku** (see the rule below).

## The verifier: writer ≠ grader

The separate grader is what makes a loop trustworthy. Two rules for choosing its model (defer to `phase-gated-model-routing` + `workflow-cost-discipline`):

- **Fully-mechanical anchor → cheap model OK.** If "done" is a check a *script* could almost make — tests pass, lint clean, `tsc` green, output exact-matches a spec/reference — the judgment is bounded; `/goal`'s built-in small evaluator is ideal. **Haiku is acceptable ONLY in this case.**
- **Any judgment in the grade → Sonnet floor, NEVER Haiku.** The moment grading requires *reading and interpreting* (does this config make sense, is this setup good, is this finding real, would the user be happy), Haiku is unreliable — it false-flags correct work and mislabels artifacts/by-design choices as defects. Confirmed twice on 2026-06-17 (the whispr-event detection grader, and a local-app setup-grader loop that burned several rounds on Haiku false-positives about that app's mechanics). Use **Sonnet as the floor**; Opus only for genuinely subtle correctness/design. One strong grader, not an Opus-on-Opus loop.

**Verify the real thing, not a proxy.** Boris's emphasis: *"can the agent run the thing?"* — prefer an actual test/build/run (or computer-use to click the real UI) over the worker asserting "looks done." A green checkable gate beats self-attestation every time.

## Write a stop condition that can't run away

`/goal` has **no token budget** — on the owner's metered Max plan a conditionless loop is a usage bonfire. You launch it literally as `/goal <condition>`; always make that predicate mechanical AND bounded:

- ✅ `/goal all tests in tests/auth pass AND ruff check is clean, OR stop after 15 turns`
- ✅ `/goal every file under src/legacy/ migrated AND tsc --noEmit passes, OR stop after 25 turns`
- ❌ `the code is good` (unmeasurable — never terminates cleanly)

Add a **no-progress guard** ("stop if the same error repeats N turns") so it doesn't spin on a wall. Cap turns/budget *first*, then trust the loop.

## Guardrails (the owner)

- **Never let a loop take an irreversible / outward-facing action unattended.** The confirm-first gate from CLAUDE.md still applies inside a loop: scope loops to **reversible/internal** work (code, tests, refactors, migrations, docs). If the goal implies publishing, sending, spending, or deleting non-recreatable data, the loop must **stop and surface**, not act. State this in the goal/skill the loop runs.
- **Commit each iteration** so a bad turn is cheap to undo and a restarted loop can read prior progress from git — per `git-checkpoint-discipline` (not included in this pack). (This is also how the Ralph pattern recovers: a fresh turn re-reads filesystem + git state.)
- **Cost is real** — a loop multiplies per-turn spend by iteration count. Budget it like a workflow (`workflow-cost-discipline`); prefer a cheap worker + cheap anchored grader.
- **Unattended loops stall on permission prompts.** A loop running while the owner is away blocks at the first tool that needs approval (his deny-list / ask-first defaults) — it silently waits instead of working. For genuinely unattended runs, pre-authorize the tools the loop needs (or pick an appropriate permission mode) before walking away.
- **Security-relevant loop?** If the loop builds or changes an access control / guard / auth / validation boundary, run `/security-review` (or `security-review-local` (not included in this pack) if no remote) on the result — per CLAUDE.md.

## Windows note

The famous Ralph one-liner `while :; do cat PROMPT.md | claude; done` is a **bash** idiom. You rarely need it now: `/goal` and `/loop` are native, safer (built-in evaluator + clean stop handling), and cross-platform. If you genuinely must shell-loop on this machine, it's pwsh: `while ($true) { Get-Content PROMPT.md | claude }` — but **prefer the native commands** (Anthropic's purpose-built primitives over a hand-rolled loop).

## Off-the-shelf: goalkeeper

[`itsuzef/goalkeeper`](https://github.com/itsuzef/goalkeeper) is the closest packaged version of this exact pattern: *durable contract-driven goal execution — a subagent judge gates completion against an explicit Definition of Done.* It's Ralph-loop + validators (compile/test/lint) + a **fresh independent judge subagent** that reviews the diff and progress log against a written DoD and returns approve-or-fix-list. Reach for it when the owner wants the heavyweight, resumable, contract-first version rather than a few lines of `/goal`. **Third-party — review the code and confirm it behaves on Windows before installing** (it's not vetted by this setup).

## Finding the anchor when 'done' is subjective

### Why this exists

`loop-engineering` assumes you already HAVE a mechanical anchor ("tests pass", "lint clean"). But the tasks you most want to loop usually have none: *is this a good video edit? does this read well? is this fix actually right?* — and "I can't tell" is exactly where people abandon the loop. This skill is the missing step before `loop-engineering`: **how to find the anchor when you don't have one.** Once you have it, hand off to `loop-engineering` to run the loop.

### The core principle

**Every task is a decomposition tree, and the leaves are always mechanical.**

"Is this a good edit?" has no direct test. But it breaks into sub-questions ("do the cuts land cleanly? is the pacing right? are the transitions preserved?"), and those break further, and at the **leaves** there is always something you can check without judgment: a boundary, a count, a threshold, a structural property, or a match against a reference. The whole skill is one sentence:

> **Decompose the task until a mechanical anchor appears. Then loop at that level.**

This terminates because the tree is finite -- keep splitting and you always hit a checkable leaf. The reason it feels impossible at the start is that you are staring at the *root* ("is it good?") where no anchor lives, and concluding none exists anywhere. It lives lower down.

### Anchor-finding is INSIDE the loop, not before it

The mistake is treating "define the success metric" as a one-time setup step you must finish before looping. You usually can't -- you don't yet know which sub-properties will fail. So fold the search into the loop itself. Each turn is in one of two modes:

```
            run the task / look at the output
                          |
              does it match what "done" means?
                   /                      \
                YES                        NO
                 |                          |
               DONE          is the gap pinned to a MECHANICAL leaf?
                                /                          \
                             YES                            NO
                              |                              |
                   fix -> verify against            DECOMPOSE the failing
                   that leaf's test                 branch one level ->
                   -> recheck                        recheck (find the leaf)
```

"Decompose further" is a legal, expected loop iteration -- not a failure of planning. The loop converges on the anchor and the fix at the same time.

### The accelerant: diff against a ground-truth library

The fastest way to decompose is to **stop reasoning abstractly about "good" and diff against a known-good example.**

If you have (or can assemble) pairs of **source input + the known-good output you actually shipped**, then the goal becomes the anchored, concrete *"reproduce this output from this source"* instead of the unanchored *"make something good"*. And the move that makes it a loop:

1. Run the task on the source.
2. **Diff** the result against the known-good output.
3. The diff is not just a pass/fail -- it tells you **which branch to decompose next**. Classify the *type* of mismatch (e.g. "cut landed mid-word", "scene transition dropped", "pacing too slow").
4. For that failure type, **derive the mechanical test** ("every cut is within 50 ms of a transcribed word boundary"). The failure classification *hands you* the stop condition -- you did not have to invent it up front.
5. Fix until that test passes, then diff again for the next mismatch type.

You never have to answer "is this good?" -- only "does it match, and if not, what KIND of mismatch?", which is a far smaller, checkable question. A library of your own past work is the cheapest anchor generator there is.

### Recipe

1. **Try for a top-level anchor first.** If "done" already has a mechanical test, you don't need this skill -- go straight to `loop-engineering`. Don't decompose for its own sake.
2. **No anchor? Decompose one level.** Split the subjective goal into the sub-properties it's actually made of. Ask "what would make me say this is NOT done?" -- each answer is a branch.
3. **At each leaf, apply the mechanical test:** can a script (or a cheap model with no taste) check this without judgment -- *and* is the check **independent of whatever produced the output** (not the generator grading its own homework -- see the circular-anchor anti-pattern)? Count, threshold, boundary, regex/structure match, diff-against-an-independent-reference, does-it-run/compile/parse. If yes -> that's an anchor. If no -> decompose that leaf again.
4. **Prefer the ground-truth-diff shortcut** (section above) whenever you have or can cheaply build source -> known-good pairs. Reproducing a reference is almost always more anchored than judging in the abstract.
5. **Hand the anchor to `loop-engineering`** to run the loop (stop condition + turn cap + writer != grader verifier). The anchor you found IS the stop condition.
6. **Surface the residual.** Some leaves genuinely have no mechanical test (true taste calls). Don't fake one. Loop the anchored parts, and **stop-and-surface** the unanchored remainder for a human -- that honest split is the deliverable, not a failure.

### Anti-patterns

- **Giving up at the root.** Concluding "this is subjective, can't be looped" without decomposing. The root is always subjective; the leaves are not.
- **Faking an anchor (optimizing a proxy that doesn't track the goal).** Picking a measurable thing that is *not* what you care about, just because it's measurable. The tell: the anchor goes green but the output still feels wrong. That feeling is real signal -- it means the leaf you anchored on is too high; **decompose THAT leaf further** rather than trusting the green or abandoning anchoring entirely. (Word-boundary cuts that still feel off -> decompose "good cut" past "lands on a word" into "lands on a word AND preserves the breath/beat".)
- **The CIRCULAR anchor (verifying an artifact against the thing that produced it).** The subtler, more dangerous cousin of faking -- and worse, because a circular anchor *looks* rigorous and goes green. Checking a rendered output against the spec that generated it, against the generator's own self-tests, or against any tool in the producing pipeline proves only *"the producer obeyed itself"* -- never *"the result is correct"*. The two coincide only if the spec AND the generator were already right, which is exactly what's in doubt. **An anchor derived from the producer is a tautology, not a test.** Re-derive the ground truth from a source the producer never touched: the **raw inputs**, an **independent fresh measurement of the output artifact** (a different tool re-reading the rendered file), or an **external / client-supplied spec**. This is writer != grader applied to the ANCHOR, not just the verifying model. (Worked tell, 2026-06-17: a video edit's `event.json` was proposed as the anchor for auditing the rendered video -- but `event.json` was the render's *input*; the real audit re-derives every check from a fresh transcription of the output, a direct `ffprobe`, the raw source media, and the client's own timecodes.)
- **Treating anchor-finding as pre-work.** Insisting on a complete metric before the first turn. You discover the failure modes by running; let the loop find them.
- **Anchoring everything or nothing.** Either pretending a taste call is mechanical, or refusing to anchor anything because *some* of it is taste. Split it: anchor what you can, surface the rest.
- **Writer == grader on the leaf.** Once you have the anchor, the thing checking it should not be the thing producing the work (see `loop-engineering` part 3 and `skill-execution-hardening`).

### Worked example: video editing (provenance — this skill was born here, 2026-06-17)

"Is this a good edit?" has no anchor. The first proxy was **"every cut lands on a transcribed word boundary"** — mechanical, caught the worst cuts, but some boundary-correct cuts still felt wrong (per the anti-pattern, the leaf was too high). The real unlock was a **ground-truth library**: the editor's own *source footage + final shipped edit* pairs, turning the goal into **"recreate this known-good output from this source"** — fully anchored. The loop: run the auto-edit → **diff against the shipped cut** → classify the *failure type* (cut placement vs missing transition vs pacing) → derive that type's mechanical test → fix → diff again. General lesson: when a domain has no top-level metric but you have examples of done-right, **diff against the examples and let the mismatches name your anchors.**

## Anti-patterns

- **Hand-rolling a bash Ralph loop when `/goal` exists** — you lose the built-in verifier, stop handling, and trust gating.
- **Writer == grader** — the worker model judging its own output. Use the separate (cheaper) verifier; that's the whole point.
- **No stop condition / no turn cap** — burns the usage budget with nothing to show. `/goal` won't stop itself on tokens.
- **Looping an unattended irreversible action** — publishing/sending/deleting inside a loop. Scope to reversible work; stop-and-surface otherwise.
- **All-Opus loop** — defaulting every turn + the grader to Opus. Cheap worker + cheap anchored grader is usually identical quality at a fraction of the cost (`workflow-cost-discipline`).

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
