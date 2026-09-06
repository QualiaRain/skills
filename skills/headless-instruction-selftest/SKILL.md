---
name: headless-instruction-selftest
description: "Test whether an instruction or a doc actually reaches a FRESH session. RULE side - after editing a CLAUDE.md rule, skill body or setting meant to change future behaviour, spawn headless claude -p probes that read current disk state and grade the output: does this fire, loop until it triggers. DOC side - after editing a CLAUDE.md, README or scaffold, fan Haiku subagents at it from a sloppy prompt with no pointers, before calling docs done."
---

# Headless instruction self-test

> **PRECONDITION — check this first, it costs one command.** Every probe here is a
> `claude -p` run, and the CLI keeps its own OAuth session separate from Claude
> Desktop. On this machine that session **expired 2026-08-08**: `claudeAiOauth`
> in `~/.claude/.credentials.json` has `expiresAt: 0` and a
> `refreshTokenExpiresAt` in the past, and every probe returns
> `Failed to authenticate: OAuth session expired and could not be refreshed`
> with all usage counters at zero — which looks like a probe result, not an
> auth failure, so a session can spend several runs before noticing. Verify with
> `claude -p "Reply with exactly: ok" --output-format json` and read `is_error`
> before trusting any probe. Recovery is `claude /login` in an interactive
> terminal — the owner's click; a session cannot do it. Do not try to sandbox a
> copy of the credentials file into a scratch `CLAUDE_CONFIG_DIR` to work around
> it; that path was tried 2026-08-22 and fails the same way, because the copied
> refresh token is what expired.

Verify a global behavioral instruction **fires** in a fresh session — then loop
on the instruction's wording until it fires reliably. Built on Claude Code's
headless mode (`claude -p`), which spawns a **fresh top-level process** that
loads global + project CLAUDE.md from **current disk**.

## Why not a subagent (the whole reason this skill exists)

An `Agent`-tool subagent is assembled from the **session-start snapshot**, not a
per-spawn disk read. So a subagent spawned right after you edit a CLAUDE.md rule
**cannot see the edit** and is the wrong test. `claude -p` is a real new process:
it reads the edited file and runs the rule for real.

(Global `~/.claude/CLAUDE.md` **does** load into Agent-tool subagents — verified
2026-06-25: a subagent reproduced it verbatim with file-reads disabled. The prior
"≈0 in subagents" claim was false. The session-start *snapshot* is why edits are
invisible, NOT non-loading — the subagent has the global file, just the stale
pre-edit version.)

### CORRECTION 2026-08-28 (owner): "cannot test this" is OVERBROAD — use `Explore`

The blanket claim above is wrong for one agent type, and the owner has said so
before: *"just use regular subagents for such testing. we've discussed this
prior."*

**`Explore` subagents get NO auto-injected CLAUDE.md at all**, so they carry no
stale snapshot to be contaminated by — they must read the file from disk, which
means they read the CURRENT disk. That is exactly the property this skill was
built to get from `claude -p`. Verified 2026-08-25: every `Explore` probe in that
session opened `CLAUDE.md` as an explicit tool call.

The accurate rule is per agent type, not blanket:

| agent type | sees a just-made edit? | valid cold reader? |
|---|---|---|
| `general-purpose`, `readonly-worker`, most others | no — session-start snapshot | no |
| **`Explore`** | **yes** — no injection, reads from disk | **yes** |
| `claude -p` (headless) | yes — real new process | yes, when it runs |

Prepending the new text directly into an `Explore` probe's prompt is likewise a
clean efficacy test, since there is no stale copy to contaminate.

**This matters because headless is not always available.** `claude -p` on this
machine has repeatedly returned "OAuth session expired and could not be
refreshed" (2026-08-25, again 2026-08-28). When it does, that is NOT grounds for
reporting a rule change as untestable — reach for an `Explore` probe. Reporting
"untestable" while a working method exists is the exact failure this correction
fixes.

Caveat that keeps the original warning alive: `Explore` tests whether a rule is
FOLLOWED WHEN READ. It does not reproduce auto-injection, so it cannot prove a
rule ARRIVES on its own, unprompted, in a fresh session. For arrival specifically,
headless remains the stronger test.

## The harness

```bash
claude -p "<BLIND PROBE PROMPT>" \
  --model haiku|sonnet|opus \
  --effort low|medium|high \
  --max-budget-usd 0.25 \
  --output-format text \
  --disallowed-tools "Bash" "Edit" "Write" "Read" "Glob" "Grep" "Task" "WebFetch" "WebSearch" \
  > results/<probe>.txt 2>&1
```

Run probes in the **background** (`run_in_background: true`) and fan several out
at once — each is an independent fresh session. Grade by reading the output head.

### Probe design — keep it BLIND

The probe must NOT mention the behavior you're testing (don't say "recommend a
model" when testing a model-rec rule) — that contaminates it into measuring
instruction-following-when-told, not spontaneous firing. Give a realistic task;
check whether the rule's effect appears unprompted. Make the expected effect
**mechanical to grade** (a literal prefix like `Routing:`, a count, a structure)
so grading is a `grep`/`head`, not a judgment call.

Cover the rule's branches: a case that SHOULD trigger, a case that should be
SUPPRESSED, and the weakest model you care about (Haiku is the harsh bar).

## Gotchas discovered (2026-06-17, the chat-open routing-line rule)

1. **`claude -p` DOES load user CLAUDE.md** — confirmed by a probe that quoted the
   rule's heading verbatim. So "didn't fire" is a *behavioral* miss, not a load
   failure. Run this load-check first if unsure.
2. **Disabling ALL tools contaminates ACTION-phrased probes.** A "go do X" probe
   with every tool denied leads with the tool-block error ("I can't use tools"),
   which hijacks the opening and hides the rule's effect. For action probes,
   **allow read-only tools** (`--allowed-tools "Read" "Glob" "Grep"`) on a repo
   that actually has relevant code, and capture the **first assistant message**
   via `--output-format stream-json --verbose` (parse the first `assistant`
   event's first `text` block, or note if it's a `tool_use` instead). Tool-free
   probes are clean only for question/advice/conversational tasks.
3. **Headless `-p` is a HARSH proxy** — it's task-runner mode, biased toward
   doing over meta-commentary. Passing headless ⇒ very likely passes interactive;
   failing headless is *inconclusive* for interactive (the owner's real surface). State
   this caveat; don't over-tune the global rule against a headless-only miss
   (that's the "simulate blind, don't optimize the wrong proxy" trap).
4. **Run-to-run variance is real** (esp. Sonnet) — run a flaky probe ≥2× before
   concluding it fires/doesn't.
5. **Behaviors that depend on Desktop-session MCP tools are NOT headless-testable.**
   Tools like `mcp__ccd_session__spawn_task` (firing a chip), session-mgmt, or any
   server tied to the Desktop app are **not connected in `claude -p`**, so a probe
   shows "tool unavailable" — a false negative that says nothing about the
   interactive surface. A rule whose effect is "call <session-MCP tool>" can only
   be validated **live**; headless can validate the *text* the rule emits but not
   the *tool call*. Don't report a headless miss as a rule failure in that case.

## The reliability lesson (reuse it)

A rule that asks the model to make a **fuzzy judgment about whether to act**
("skip if trivial") fires unreliably — the judgment is the weak link, causing
both misses on real cases and over-fires on the ones it should skip. **Prefer
"always emit, with a cheap explicit null case"** (always print `Routing:`; for a
trivial open it says `none needed`). Deterministic to produce, trivial to grade,
robust on weak models. This generalizes: when an instruction fires unreliably,
remove the gating judgment before strengthening the wording.

## Loop

1. Edit the instruction. 2. Fan out blind probes (background). 3. Grade
mechanically. 4. If it under-fires → strengthen wording / remove a gating
judgment / reconcile with any competing rule (the chat-open rule lost to
"lead with the answer" until carved out explicitly). If it over-fires →
tighten. 5. Re-probe with FRESH `claude -p` sessions. Repeat until reliable
across your probe set + weakest model. Stop when it's reliable in headless (the
harsh proxy) or when remaining misses are provably headless-only artifacts —
then dogfood live.

A worked instance (the chat-open `Routing:` rule, three rule versions, the
probe battery) lives in the sandbox at
`~/Claude/Claude Eval Sandbox/model-routing-selftest/`.

## Cold-start doc audit: does a fresh session find what it needs?

When closing a chat that documented anything for future sessions — a new README, an updated CLAUDE.md, a refreshed plan file, a project scaffold — **deploy a Haiku subagent cold-start audit before declaring docs done**. Cheap, fast, and a reliable proxy for whether the project will endure chat transitions without dropping essentials.

> **Scope limit — this audits *additions*, not *removals*.** It validates that content now in a doc is *discoverable* from cold. It does NOT validate a change that *removed or migrated* content out of CLAUDE.md (e.g. extraction into a skill, leaving a pointer): Agent-tool subagents still carry the pre-edit CLAUDE.md in their session-start cache and literally cannot see the deletion — so a removal audit is meaningless (full mechanism in *Workaround: testing mid-session edits* at the bottom). Validate a removal **statically** instead — confirm each migrated nugget survives in its skill, references resolve, and the skill self-triggers — or drive a genuinely fresh `claude -p` process.

### Audit protocol — minimal scaffolding to override the subagent's defer-to-delegator default

**Pre-flight gate — run this check BEFORE spawning anything; it is the single most-forgotten step.** Did THIS session create or edit the project CLAUDE.md?
- **Edited a pre-existing CLAUDE.md** → every subagent still holds the *session-start* (stale) copy, and saving/merging to disk does NOT refresh it. You MUST prepend the new section to any CLAUDE.md-dependent prompt (efficacy form, bottom) — else the audit silently grades the OLD docs and reports a false pass/fail.
- **Created CLAUDE.md fresh this session** (absent at session start) → subagents have NO cached copy, so they read current disk by investigation; discoverability testing is valid as-is, no prepend needed.
- **Didn't touch CLAUDE.md** → no special handling; other docs are always read fresh from disk.

- Spawn 1–3 general-purpose subagents with `model: 'haiku'`.
- The `prompt` field on the Agent tool should be **exactly this shape and nothing more**:

  ```
  You are a new Claude Code chat with no prior context. The user just typed:

  <verbatim sloppy user message>

  Respond as you would. SMOKE-TEST CONSTRAINT: investigate with read-only tools only — do NOT edit, create, or delete files; do NOT run state-changing commands (e.g., `Stop-ScheduledTask`/`Start-ScheduledTask`, registry edits, service restarts, `Remove-Item`, package installs); do NOT restart processes or services. If you'd take an action, describe what you'd do instead of doing it.
  ```

- That framing reproduces fresh-chat behavior. The opening line ("You are a new Claude Code chat...") and the closing "Respond as you would" reframe the subagent's mental model. **The SMOKE-TEST CONSTRAINT line is the one sanctioned addition** — it must always be present when *you* (the orchestrator) deploy these subagents, regardless of whether the parent session is in auto mode. Anything else (e.g., "get oriented," "report back on where you looked," "read bot/README.md first," any doc pointer) defeats the test by doing the discoverability half of the agent's job. Discoverability is the harder problem than coverage.
- **Why the smoke-test constraint is non-negotiable.** Subagents inherit the parent's tool permissions; in an auto-mode session a Haiku agent given a vague action prompt ("the X isn't working, fix it") will **confidently act on a plausible-but-wrong diagnosis**. (Observed 2026-05-18, Power optimization: a re-test agent rewrote `Test-GameRunning` in a live `power-logger.ps1` for a non-existent bug and restarted the live scheduled task, reporting success.) The constraint keeps the audit observational — it surfaces the same misdiagnosis as a written "I'd do X", which is what you want to read post-hoc anyway.
- The audit happens **post-hoc** by reading what the agent actually did — file reads, tool counts, where it landed, what conclusions it reached. **Pass = the agent produced an accurate answer matching your canonical doc.** Usually that takes investigation (≥1 tool use); but a *correct* 0-tool-use answer is ALSO a pass when the fact lives in the auto-loaded project CLAUDE.md — a real fresh session has that CLAUDE.md auto-loaded too, so answering straight from it is exactly what a real session does (observed 2026-05-29: Haiku answered the Eden-triplet gotcha and the 5x render cap correctly with 0 tool uses, both from auto-loaded CLAUDE.md — genuine passes). **Fail = the agent punted / asked for clarification with 0 tool uses, OR confidently asserted wrong/incomplete info, OR confabulated (invented a value because the authoritative one wasn't discoverable).** The tool-count alone doesn't decide it — the *correctness of where it landed* does.
- **If this session edited CLAUDE.md, feed the new CLAUDE.md section into the subagent prompt** (see "Workaround: testing mid-session edits" below). Subagents inherit the parent's *session-start cached* CLAUDE.md — they will NOT see your CLAUDE.md edits via a fresh disk read, and (when this audit runs at a checkpoint/wrap) merging to `master` doesn't help either, because the stale copy lives in the parent's cache, not on disk. Skip this and the audit silently tests the pre-edit CLAUDE.md and reports a false pass/fail. Other docs (README, chapter files, scaffolds) ARE read fresh from disk — for those, just make sure they're on the branch the agent will read (i.e. merged to `master` first).
- Fix actionable findings (missing top-level CLAUDE.md, missing pointers, stale info) and re-run if any agent failed.

### Two scopes: change-targeted vs broad-roster

Two distinct ways to deploy this audit — pick by stakes.

**Change-targeted (default, 1–3 agents).** Sloppy prompts aimed at the *deltas this chat made* — does the new/edited info land? Cheap; run whenever docs changed. Most post-edit audits want this.

**Broad-roster (archival durability, ~5–8 agents).** A *curated set of diverse, realistic returning-user prompts* spanning the project's MAJOR surfaces — orient/"what is this", run-the-main-thing, a secondary feature, a known gotcha, troubleshooting/"X is broken", locate-a-thing, the config/spec format. **Why it's worth the extra agents:** change-targeting has a structural blind spot — it only re-validates what the current chat touched, so rot in *untouched* areas (a renamed file, a removed code path, a default documented ten chats ago) is never caught by any archive audit. The broad roster is the periodic *full* re-validation that catches accumulated rot. Gate it to substantial archive/checkpoint boundaries (see `~/.claude/CLAUDE.md` 'Chats & projects'), not every trivial one-line-fix close.

- **Scale the roster to the project's surface diversity** (small → 4–5 prompts; feature-rich → 8–10). Do NOT do literal one-agent-per-feature: past ~8 the marginal agent just re-confirms orientation, and per-feature prompts ("how do I use feature X") drift into artificial doc-existence checks that lose the discoverability realism that makes the audit valid. A handful of *genuinely different intents* beats exhaustive narrow probes.
- **Completeness-critic (the coverage net).** After the roster, spawn ONE agent that — given the roster prompts — inventories the project's major surfaces (reads CLAUDE.md/STATUS/README) and reports which surfaces *no* prompt exercised; then a small targeted second round on the gaps. Coverage-of-everything without per-feature scripting.
- **Haiku is the right instrument precisely because it's weak** — a *lower-bound probe*: if the dumbest model orients correctly from cold, every stronger model will. Haiku failures are high-signal (a real doc gap, not model weakness); Haiku passes are strong guarantees. Cheap, so a broad sweep earns its keep on durability insurance.

#### Doc gap vs model noise — don't fix clear docs

A broad sweep surfaces two different things; treat them differently.
- **Doc gap (fix it):** the agent lands on wrong/incomplete info, OR *confabulates* an authoritative value because it isn't discoverable/inline (observed 2026-05-29: an agent invented sweep-scene names and a Ryujinx key format because the valid values lived in prose elsewhere, not inline in the example it copied). Fix by making the authoritative info **discoverable and inline** — valid-values as comments in the example a cold session copies; a troubleshooting-order entry; a bolded one-line takeaway — not merely by adding more prose somewhere else.
- **Model noise (leave it):** a dumb model garbles a *summary* while the detail/conclusion it read from a *clear* doc is correct (observed 2026-05-29: Haiku mis-stated a multiplier in its preamble but the doc's table + bolded takeaway were right, and it cited them). Don't "fix" a correct, clear doc to chase model wobble — that's over-fitting to one weak run.

**The broad sweep only earns its keep if you FIX the gaps it surfaces** — the real cost is the doc work, not the Haiku tokens. Budget for it.

### Why the minimal-but-nonzero scaffolding matters

Subagents (`Agent` tool) are instruction-tuned to defer to the delegating agent — given a verbatim sloppy prompt with no framing, they default to asking for clarification regardless of how discoverable the project is (empirically: 0 tool uses across three Haiku subagents on three different sloppy prompts in a well-documented project). The "you are a new Claude Code chat" line reframes the subagent's mental model to match what a real fresh session does: investigate cwd, read CLAUDE.md if present, follow pointers. Validated 2026-05-17: the same three Haiku subagents that produced 0 tool uses with zero scaffolding produced 1, 5, and 19 tool uses with the minimal framing — and one of them executed a full feature change correctly from the prompt "the dms should be friendlier."

**Failure mode to watch for:** if a minimal-scaffold agent still defaults to asking for clarification, the project lacks self-description at first contact. The fix is usually a top-level project CLAUDE.md (not just `subfolder/README.md` — at the *project root*) containing a one-paragraph "this is what this project is, and here's where the canonical docs live." Save-memory files at the project level also auto-load and reinforce standing protocols.

**Project-level CLAUDE.md is the highest-leverage discoverability artifact.** Even one paragraph at the root telling future sessions what the project is and where to look next dramatically improves cold-start.

**User's exact framing:** "I should be able to phrase my request very sloppily and it can still get established."

Applies to documentation hand-offs in any project — bot README rewrites, investigation-folder scaffolds, plan-file finalization, CLAUDE.md updates. For high-stakes hand-offs where extra rigor is warranted, you can also drive a real fresh Claude Code chat in the project's cwd (Haiku for strictness), type a verbatim sloppy prompt, and read its transcript via `mcp__ccd_session_mgmt__list_sessions` + `mcp__ccd_session_mgmt__search_session_transcripts`. The minimal-scaffold subagent protocol is the cheap default; the real-chat protocol is the belt-and-suspenders.

### Workaround: testing mid-session edits

Subagents spawned via the `Agent` tool inherit the parent session's cached CLAUDE.md from session-start — they do NOT see edits you applied earlier in the same session unless they do a fresh disk read (`Grep` / `Read`). For **discoverability** testing this is fine: the agent's tool uses are what you're measuring, and a successful audit means the agent found the new content via investigation. For **efficacy** testing (does the agent actually ACT on the new text once it's in context?) of a just-applied edit, you can simulate auto-load by prepending the new section to the prompt:

```
You are a new Claude Code chat. Your `~/.claude/CLAUDE.md` includes (among
other sections) the following standing rule, which auto-loads at session
start:

---
<paste the new CLAUDE.md section verbatim>
---

The user just typed:

<sloppy user message>

Respond as you would. SMOKE-TEST CONSTRAINT: <as above>
```

This is functionally equivalent to the auto-load case for the change-in-question — real future sessions WILL load CLAUDE.md fresh from disk at their own session-start, so they see the new text via auto-load just as the test agent sees it via the prepended block. Use it when you've just edited CLAUDE.md and want to verify the new text actually moves the agent's behavior, without waiting for a session restart.

Caveat: this tests efficacy only. Discoverability testing still needs the bare minimal-scaffolding form (no doc pointers, no fed content) because fed content does the discoverability half for the agent. The two tests are complementary: discoverability proves "the agent finds the doc," efficacy proves "the doc moves the agent" — both matter, and together they cover the cold-start-quality question end-to-end.

**The prepend workaround adds context — it can't subtract it, so removals/migrations need a different test.** If this session *removed* or *migrated* content out of CLAUDE.md (e.g. into a skill, leaving a pointer), every subagent still carries the OLD full text in its session-start cache: (1) a with-vs-baseline comparison is contaminated (both arms have the old content, baseline "passes" on cached knowledge); (2) prepending can't help — the problem is present-but-stale context, not missing context. Test cleanly with a process that reads current disk with no parent cache: a fresh `claude -p` invocation (e.g. `skill-creator`'s description optimizer spawns fresh `claude -p` processes) or a genuinely fresh chat. **`general-purpose` and `readonly-worker` subagents cannot validate a this-session removal — don't try. `Explore` CAN** (2026-08-25): `Explore` gets no auto-injected CLAUDE.md at all, so it has no stale copy to be contaminated by and must read the file from disk. Confirmed on a root-router split — every `Explore` probe opened `CLAUDE.md` as an explicit tool call, and the probes disagreed with each other in exactly the way a real cold reader would. Prepending the new text to an `Explore` probe is likewise a clean efficacy test for the same reason. Two caveats: `Explore` reads excerpts rather than whole files, and it UNDERSTATES discoverability, because a real chat gets CLAUDE.md auto-loaded for free while `Explore` only sees it if it chooses to read it — so a probe that never opens any doc is INCONCLUSIVE, not a fail. (Learned 2026-05-27: a skill-migration audit came back all-pass because every subagent still had the pre-migration CLAUDE.md cached — meaningless until re-run in fresh processes.)

Validated 2026-05-28: a Haiku subagent given a sloppy prompt about granting AppData access without the new CLAUDE.md text in context referenced only `permissions.deny` / `permissions.allow` direct edits (0 tool uses, no disk read). The same prompt with the new text prepended as auto-load context correctly named `~/.claude/skills/deny-list-rebuild/gen_deny_list.py` and the regenerator workflow. Efficacy of the edit confirmed; the bare-prompt result reflected pre-edit cached context, not a docs failure.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
