---
name: headless-instruction-selftest
description: "Test whether an instruction or a doc actually reaches a FRESH session. RULE side - after editing a CLAUDE.md rule, skill body or setting meant to change future behaviour, spawn headless claude -p probes that read current disk state and grade the output: does this fire, loop until it triggers. DOC side - after editing a CLAUDE.md, README or scaffold, fan Haiku subagents at it from a sloppy prompt with no pointers, before calling docs done."
---

# Headless instruction self-test

> **PRECONDITION — check this first, it costs one command.** Every probe here is a
> `claude -p` run. If the CLI's login has expired, every probe returns
> `Failed to authenticate: OAuth session expired and could not be refreshed`
> with all usage counters at zero — which looks like a probe result, not an
> auth failure, so a session can spend several runs before noticing. Run
> `claude -p "Reply with exactly: ok" --output-format json` and confirm
> `"is_error": false` and a result of `ok` before trusting any probe. Recovery is
> `/login` inside an interactive `claude` session — the user has to do it; a
> session cannot. Do not try to work around it by copying the credentials file
> into a scratch `CLAUDE_CONFIG_DIR`: the author tried, and it fails the same way,
> because the copied refresh token is what expired. If headless stays
> unavailable, use an `Explore` probe instead (next section).

Verify a global behavioral instruction **fires** in a fresh session — then loop
on the instruction's wording until it fires reliably. Built on Claude Code's
headless mode (`claude -p`), which spawns a **fresh top-level process** that
loads global + project CLAUDE.md from **current disk**.

## Which test process can see a just-made edit

In the author's testing, an `Agent`-tool subagent gets CLAUDE.md from the
parent's **session-start snapshot**, not a per-spawn disk read. Global
`~/.claude/CLAUDE.md` does load into subagents — just the stale pre-edit version.
So most subagents spawned right after you edit a CLAUDE.md rule **cannot see the
edit**, and saving or merging to disk does not refresh them. The rule is per
agent type:

| agent type | sees a just-made CLAUDE.md edit? | valid cold reader? |
|---|---|---|
| `general-purpose` and most custom types | no — session-start snapshot | no |
| **`Explore`** | **yes** — gets no auto-injected CLAUDE.md, so it must read the file from disk | **yes** |
| `claude -p` (headless) | yes — real new process | yes, when it runs |

Other docs (README, chapter files, scaffolds) are always read fresh from disk by
any agent — just make sure the edit is on the checkout/branch the agent will read.

**Headless is not always available** (see the precondition). When it isn't, that
is NOT grounds for reporting a rule change as untestable — use an `Explore`
probe. Prepending the new text directly into an `Explore` probe's prompt is a
clean efficacy test, since there is no stale copy to contaminate.

`Explore` caveats: it tests whether a rule is FOLLOWED WHEN READ; it does not
reproduce auto-injection, so it cannot prove a rule ARRIVES unprompted — for
arrival, headless is the stronger test. It reads excerpts rather than whole
files, and it UNDERSTATES discoverability (a real chat gets CLAUDE.md for free;
`Explore` only sees it if it chooses to read it), so a probe that never opens any
doc is INCONCLUSIVE, not a fail.

## The harness

```bash
claude -p "<BLIND PROBE PROMPT>" \
  --model haiku \
  --max-budget-usd 0.25 \
  --output-format text \
  --disallowed-tools "Bash" "Edit" "Write" "Read" "Glob" "Grep" "Task" "WebFetch" "WebSearch" \
  > results/<probe>.txt 2>&1
```

`--model` takes `haiku`, `sonnet` or `opus`. Some CLI versions also accept
`--effort low|medium|high`; check `claude --help` before relying on it.

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

## Gotchas

1. **`claude -p` DOES load user CLAUDE.md** — confirmed by a probe that quoted the
   rule's heading verbatim. So "didn't fire" is a *behavioral* miss, not a load
   failure. If unsure, run that load-check first (ask the probe to quote the
   rule's heading).
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
   failing headless is *inconclusive* for interactive (the user's real surface).
   State this caveat; don't over-tune the global rule against a headless-only miss.
4. **Run-to-run variance is real** (esp. Sonnet) — run a flaky probe ≥2× before
   concluding it fires/doesn't.
5. **Behaviors that depend on app-session MCP tools are NOT headless-testable.**
   Tools tied to the Claude Desktop app or another interactive surface are not
   connected in `claude -p`, so a probe shows "tool unavailable" — a false
   negative that says nothing about the interactive surface. Headless can
   validate the *text* such a rule emits but not the *tool call*; validate the
   call live. Don't report a headless miss as a rule failure in that case.

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
judgment / reconcile with any competing rule (in the author's worked instance, a
chat-open `Routing:` rule lost to "lead with the answer" until carved out
explicitly). If it over-fires → tighten. 5. Re-probe with FRESH `claude -p`
sessions. Repeat until reliable across your probe set + weakest model. Stop when
it's reliable in headless (the harsh proxy) or when remaining misses are provably
headless-only artifacts — then dogfood live.

## Cold-start doc audit: does a fresh session find what it needs?

When closing a chat that documented anything for future sessions — a new README, an updated CLAUDE.md, a refreshed plan file, a project scaffold — **deploy a Haiku subagent cold-start audit before declaring docs done**. Cheap, fast, and a reliable proxy for whether the project will endure chat transitions without dropping essentials.

> **Scope limit — this audits *additions*, not *removals*.** See *Testing removals* at the bottom.

### Audit protocol — minimal scaffolding to override the subagent's defer-to-delegator default

**Pre-flight gate — run this check BEFORE spawning anything; it is the single most-forgotten step.** Did THIS session create or edit the project CLAUDE.md?
- **Edited a pre-existing CLAUDE.md** → `general-purpose` subagents hold the stale session-start copy. Either use `Explore` subagents, or prepend the new section to the prompt (efficacy form, below). Skip this and the audit silently grades the OLD docs and reports a false pass/fail.
- **Created CLAUDE.md fresh this session** (absent at session start) → subagents have NO cached copy and read current disk; test as-is.
- **Didn't touch CLAUDE.md** → no special handling.

Then:
- Spawn 1–3 subagents with `model: 'haiku'`.
- The `prompt` field on the Agent tool should be **exactly this shape and nothing more**:

  ```
  You are a new Claude Code chat with no prior context. The user just typed:

  <verbatim sloppy user message>

  Respond as you would. SMOKE-TEST CONSTRAINT: investigate with read-only tools only — do NOT edit, create, or delete files; do NOT run state-changing commands (e.g., starting/stopping scheduled tasks or services, registry edits, deleting files, package installs); do NOT restart processes or services. If you'd take an action, describe what you'd do instead of doing it.
  ```

- The opening line ("You are a new Claude Code chat...") and the closing "Respond as you would" reframe the subagent to behave like a fresh chat. **The SMOKE-TEST CONSTRAINT line is the one sanctioned addition** and must always be present, whether or not the parent session is in auto mode. Anything else (e.g., "get oriented," "report back on where you looked," "read bot/README.md first," any doc pointer) defeats the test by doing the discoverability half of the agent's job.
- **Why the smoke-test constraint is non-negotiable.** Subagents inherit the parent's tool permissions; in an auto-mode session a Haiku agent given a vague action prompt ("the X isn't working, fix it") will **confidently act on a plausible-but-wrong diagnosis**. (The author saw a re-test agent rewrite a function in a live script for a non-existent bug and restart the live scheduled task, reporting success.) The constraint keeps the audit observational.
- **Grade post-hoc** by reading what the agent actually did — file reads, tool counts, where it landed, what it concluded. **Pass = an accurate answer matching your canonical doc.** Usually that takes ≥1 tool use, but a *correct* 0-tool-use answer is also a pass when the fact lives in the auto-loaded project CLAUDE.md — a real fresh session has it auto-loaded too. **Fail = punted / asked for clarification with 0 tool uses, OR asserted wrong/incomplete info, OR confabulated a value because the authoritative one wasn't discoverable.** Correctness of where it landed decides it, not the tool count.
- Fix actionable findings (missing top-level CLAUDE.md, missing pointers, stale info) and re-run if any agent failed.

### Two scopes: change-targeted vs broad-roster

**Change-targeted (default, 1–3 agents).** Sloppy prompts aimed at the *deltas this chat made* — does the new/edited info land? Cheap; run whenever docs changed.

**Broad-roster (archival durability, ~5–8 agents).** A *curated set of diverse, realistic returning-user prompts* spanning the project's MAJOR surfaces — orient/"what is this", run-the-main-thing, a secondary feature, a known gotcha, troubleshooting/"X is broken", locate-a-thing, the config/spec format. Change-targeting only re-validates what the current chat touched, so rot in *untouched* areas (a renamed file, a removed code path, a default documented ten chats ago) is never caught; the broad roster is the periodic full re-validation. Reserve it for substantial checkpoints (end of a project phase, before archiving), not every one-line fix.

- **Scale the roster to the project's surface diversity** (small → 4–5 prompts; feature-rich → 8–10). Do NOT do one-agent-per-feature: past ~8 the marginal agent just re-confirms orientation, and per-feature prompts ("how do I use feature X") lose the discoverability realism that makes the audit valid.
- **Completeness-critic (the coverage net).** After the roster, spawn ONE agent that — given the roster prompts — inventories the project's major surfaces (reads CLAUDE.md/STATUS/README) and reports which surfaces *no* prompt exercised; then run a small targeted second round on the gaps.
- **Haiku is the right instrument precisely because it's weak** — a lower-bound probe: if the weakest model orients correctly from cold, stronger ones will. Haiku failures are high-signal (a real doc gap); Haiku passes are strong guarantees.

#### Doc gap vs model noise — don't fix clear docs

- **Doc gap (fix it):** the agent lands on wrong/incomplete info, OR *confabulates* an authoritative value because it isn't discoverable/inline (the author saw an agent invent valid option names because they lived in prose elsewhere, not inline in the example it copied). Fix by making the authoritative info **discoverable and inline** — valid values as comments in the example a cold session copies; a troubleshooting-order entry; a bolded one-line takeaway — not by adding more prose somewhere else.
- **Model noise (leave it):** a weak model garbles a *summary* while the detail it read from a *clear* doc is correct (e.g. mis-states a multiplier in its preamble but cites the doc's correct table). Don't "fix" a correct, clear doc to chase one weak run.

**The broad sweep only earns its keep if you FIX the gaps it surfaces** — the real cost is the doc work, not the Haiku tokens. Budget for it.

### Why the minimal-but-nonzero scaffolding matters

Subagents are instruction-tuned to defer to the delegating agent — given a verbatim sloppy prompt with no framing, they default to asking for clarification regardless of how discoverable the project is (author's test: 0 tool uses across three Haiku subagents in a well-documented project). With the one-line "you are a new Claude Code chat" framing, the same three produced 1, 5, and 19 tool uses — one executed a full feature change correctly from the prompt "the dms should be friendlier."

**Failure mode to watch for:** if a minimal-scaffold agent still asks for clarification, the project lacks self-description at first contact. The fix is usually a top-level project CLAUDE.md (at the *project root*, not just `subfolder/README.md`) with one paragraph: what this project is, and where the canonical docs live. **That root CLAUDE.md is the highest-leverage discoverability artifact.** The goal: "I should be able to phrase my request very sloppily and it can still get established."

For high-stakes hand-offs you can also drive a real fresh Claude Code chat in the project's cwd (Haiku for strictness), type a verbatim sloppy prompt, and read its transcript. The minimal-scaffold subagent protocol is the cheap default; the real chat is belt-and-suspenders.

### Efficacy form: testing a just-made CLAUDE.md edit

Discoverability testing (the bare prompt above) measures whether the agent *finds* the doc. To test **efficacy** — does the agent ACT on the new text once it's in context — simulate auto-load by prepending the new section:

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

Real future sessions load CLAUDE.md fresh at their own start, so this is equivalent for the change in question. Fed content does the discoverability half for the agent, so this form tests efficacy only; the two tests are complementary. (Author's example: a Haiku subagent without the new text answered from stale cached context with 0 tool uses; with the text prepended it named the new script and workflow correctly — the edit worked, and the bare result was a cache artifact, not a docs failure.)

### Testing removals

The prepend trick adds context — it can't subtract it. If this session *removed* or *migrated* content out of CLAUDE.md (e.g. into a skill, leaving a pointer), every `general-purpose` subagent still carries the OLD full text: a with-vs-baseline comparison is contaminated (the baseline "passes" on cached knowledge), and prepending can't help. **Do NOT use `general-purpose` subagents to validate a this-session removal.** Instead use one of:
- `Explore` probes (no injected CLAUDE.md; mind the caveats above);
- a fresh `claude -p` process or a genuinely fresh chat;
- a static check — confirm each migrated piece survives in its new home, references resolve, and the new skill self-triggers.

(The author once got an all-pass skill-migration audit that was meaningless: every subagent still had the pre-migration CLAUDE.md cached.)

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
