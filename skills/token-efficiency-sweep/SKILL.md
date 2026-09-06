---
name: token-efficiency-sweep
description: Measure and cut what a session or a scheduled routine re-bills on EVERY turn. Use whenever the ask is token efficiency, cost per turn, cutting spend, "why is this chat/routine so expensive", shrinking CLAUDE.md or the skill listing, or a routine costing too much - and append what you learned before the chat closes. Not for model choice (phase-gated-model-routing) or fan-out cost (workflow-cost-discipline).
---

# Token-efficiency sweep

This skill accumulates. Every session that uses it adds what it measured to the Findings ledger at the bottom, so the next session starts from a number instead of a guess. If you finish a sweep and write nothing back, the skill got worse, not better.

## The one thing to understand first

**Cost is not the length of what you write. It is the resident context, re-billed on every API call.**

```
session cost  ~=  api_calls  x  resident_context_per_call
```

Every always-on surface is paid again on every call. A 3,000-char rule in a file that loads every turn costs ~750 tokens x 40 calls = 30k tokens in one session, and again in the next one. That is why a small standing cut beats a large one-off cut, and why a *saved call* beats both — it removes a whole context re-read.

Two levers, in the owner's words: **shorter chats, and fewer standing instructions.**

## Measure before you cut. The census is never where it feels like it is.

### Landmine: dedup by `requestId` or you will overcount ~2.5x

Claude Code writes **several `.jsonl` records per API response** — one for the thinking block, one for text, one for each tool_use — and **every one of them carries the same `usage` object**. Summing usage per record triple-counts. This was measured wrong in this exact way on 2026-08-21 (a routine "cost 12.0M read over 77 turns"; deduped it was 4.7M over 30 calls) before the error was caught.

```python
# Real per-session cost. Run from ~/.claude/projects/<slug>/
import json
def measure(f):
    seen = {}
    for line in open(f, encoding="utf-8", errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") or {}
        u = m.get("usage")
        if not u: continue
        seen[d.get("requestId") or m.get("id")] = u          # <- the dedup
    calls = len(seen)
    read  = sum(u.get("cache_read_input_tokens", 0) + u.get("input_tokens", 0) for u in seen.values())
    cc    = sum(u.get("cache_creation_input_tokens", 0) for u in seen.values())
    out   = sum(u.get("output_tokens", 0) for u in seen.values())
    return calls, out, cc, read, read // max(calls, 1)
```

`output + cache_creation` are the expensive tokens; `cache_read` bills at roughly a tenth the rate but is the biggest raw number and the one that responds to standing cuts.

### Where the floor actually comes from: read the harness's own attachments

The transcript records what the harness injected, as `attachment` records. This is ground truth, and the only way to prove a surface was withheld rather than assume it:

| `attachment.type` | what it is |
|---|---|
| `skill_listing` | the exact skill listing sent — has `content`, `names`, `skillCount`, `isInitial` |
| `deferred_tools_delta` | the deferred-tool name list |
| `agent_listing_delta` | the available-agent-types block |
| `mcp_instructions_delta` | per-MCP-server instructions |
| `hook_additional_context` | whatever a SessionStart hook injected |

`~/Claude/Token Efficiency/skill-listing-probe/probe.py` parses the first of these. Always filter on `isInitial` — later `skill_listing` records are single-skill re-injections, not the budget.

The rest of turn 1 is the base system prompt plus built-in tool schemas, which is fixed and not worth attacking.

### Census an instruction file before editing it

Split on `## ` headings and count characters. The fat is reliably somewhere you did not expect:

```bash
awk '/^#/{if(h!=""){printf "%6d  %s\n", c, h} h=$0; c=0} {c+=length($0)+1} END{printf "%6d  %s\n", c, h}' FILE
```

Long unwrapped lines make `wc -l` useless here (rendered prose is one line per paragraph on purpose), so count chars, and map a section's lines with `awk 'NR>=A && NR<=B {printf "%3d %5d %s\n", NR, length($0), substr($0,1,95)}'` before deciding what moves.

## The levers, cheapest first

**1. Cap the skill listing where descriptions do nothing.** Descriptions exist to make a skill *auto-trigger*. A scheduled routine follows a fixed SKILL.md and names the skill it wants, so every description is dead weight re-read on every call. Two settings, both scoped per directory in `.claude/settings.local.json`:

- `"skillListingBudgetFraction": 0.0005` — fraction of the context window (in characters) reserved for the listing; over budget, descriptions are shortened to fit. Default 0.01.
- `env.SLASH_COMMAND_TOOL_CHAR_BUDGET: "1000"` — the same budget as a hard char number, and it overrides the fraction. User-level default on this machine is 100000.
- `"skillOverrides": {"<skill>": "name-only"}` — the surgical form: `on` | `name-only` | `user-invocable-only` | `off`. `name-only` lists the skill without its description, so `Skill(<name>)` still resolves. Prefer it when you need a few skills to keep triggering.

**Names stay listed at any budget.** That is what makes this safe: nothing loses the ability to be invoked, only the ability to fire on its own. Before applying it anywhere, grep the routine's SKILL.md for skill names it calls, and confirm none of them depends on description-triggering.

When a project `env` block is added, copy the user-level `env` verbatim first — a wholesale-replace merge would otherwise silently drop `PYTHONUTF8` and the privacy flags.

**2. Suppress SessionStart injections for sessions that cannot use them.** A hook that orients a *person* is pure cost in an unattended run. Gate inside the hook on cwd and return a two-line pointer instead of the block, so a person who does open a chat there is not stranded. Measured: 10,270 chars -> 291.

**3. Extract, do not delete.** A rule that fires in a SITUATION moves to a snippet or sibling file with a one-line trigger left inline, so it still ARRIVES. A rule that fires EVERY turn stays. Pure rationale and receipts — the "why we chose this mechanism" paragraphs — have no runtime consumer at all and should always move out.

Verify the move mechanically, every time:

```python
orig = open(BACKUP, encoding="utf-8").read().split("\n")
new  = set(open(TRIMMED, encoding="utf-8").read().split("\n"))
for f in EXTRACTED_FILES: new |= set(open(f, encoding="utf-8").read().split("\n"))
print([l[:120] for l in orig if l.strip() and l not in new])   # must be []
```

**4. Move payloads out of the always-on path.** Lookup tables, maps, history, receipts -> a pointed-at file. Bulk payloads for another model -> a Drive file, never a Notion page body (a page body is re-fetched and re-billed; a Drive file is not).

**0. Delete the work before optimising it.** The cheapest turn is the one that never runs. Measured 2026-08-21: cutting the unattended fleet from 5 runs a day to 2 dwarfed every per-turn saving available anywhere else that day. Before censusing a surface, ask whether the thing that reads it needs to run at all, or that often. This lever is first because it is the only one that removes whole sessions rather than shaving their floor.

**5. Fewer calls beats fewer chars.** One call at 150k context costs more than 3k chars of standing text does across a whole session. Batch independent tool calls into one message; do not re-derive what a log already says; do not spawn a subagent for a two-call job.

### Two things that look like levers and are not

- **Extracting a phase that runs every time.** If the routine has to read the file at step 3, the payload is resident from turn 3 onward and you saved almost nothing while adding a step that can be skipped. Extract *conditional* and *never-needed-at-runtime* text only.
- **Re-emitting a section to compress it.** Rewriting whole sections to save characters burned ~15k output tokens for ~700 chars once already. Prefer targeted fragment replacement, or move the text verbatim.

## Hard limits on this work

- **Never buy a saving by skipping retrieval, verification, or certainty.** Savings come from cutting re-derivation and overkill process, never from cutting the checks. Spend on correctness is effectively unbounded; spend on re-deriving what was already established is the waste.
- **A budget checked against today's content is a measurement, not a bound.** Make the arithmetic hold whatever the content becomes.
- **Do not optimize the optimizer.** If a sweep is costing more than the surface it is trimming will ever save, stop and say so.

## Before you close: write the finding back

Append one dated line to `references/findings-ledger.md` — what you measured, what you changed, what it saved, and whether it is verified or still waiting on a run. A finding that only exists in a closed chat's scrollback is not a finding.

Bound it: past ~25 entries, keep the newest ~15 and fold anything that has held three separate times up into this skill body as a rule. An unbounded ledger becomes the waste it was written to prevent. Related surfaces that must not drift from this one: `~/.claude/snippets/token-budget-discipline.md` (estimate-before-heavy-work behaviour) and the per-close ledger in memory `feedback_efficiency_compounds_per_chat`.

---

## Findings ledger

Lives in `references/findings-ledger.md` (24 dated entries as of 2026-09-05). Read it when you want prior measurements before re-running one; append your own there, not here.

## Measuring the skill listing: two free ground-truth methods (added 2026-08-28)

Never accept a prior session's claim about how the harness behaves. Both of these
cost nothing and settle it in one call. A session that skipped them shipped a
"fix" for a bug that did not exist.

**1. What the harness actually sent the model.** It writes its own listing into the
session transcript as an `attachment` record of `type: "skill_listing"`. That is
ground truth - it is the only way to prove a skill was silenced rather than infer it.

```
python "<root>/Token Efficiency/skill-listing-probe/probe.py"
python "<root>/Token Efficiency/skill-listing-probe/probe.py" --slug <project-slug>
```

Filter on `isInitial` - later records are mid-session re-injections of one skill,
not a budget measurement. Startup context is snapshotted at session start, so
**no settings edit is ever visible to the session that made it**; probe a session
that opened *after* the change, or you are measuring the old state.

**2. What the harness will accept.** The installed CLI is a large PE with its JS
bundle embedded, and it carries its own settings schema as literal strings. This
outranks the docs, because it is the code that will actually run:

```
grep -a -o ".\{0,160\}skillOverrides.\{0,400\}" ~/.local/bin/claude | head
```

Verified this way on v2.1.233, and cross-checked against code.claude.com/docs/en/skills:

| key | effect |
|---|---|
| `skillOverrides: "on"` | name + description listed (default when absent) |
| `skillOverrides: "name-only"` | name listed, description dropped; **still model-invocable** |
| `skillOverrides: "user-invocable-only"` | absent from the model's listing; **model cannot invoke it** (errorCode 7); owner can still type `/name` |
| `skillOverrides: "off"` | hidden from model and from the `/` menu |
| frontmatter `disable-model-invocation: true` | forces `user-invocable-only` for that skill everywhere, no settings entry needed |
| `skillListingMaxDescChars` | per-skill description cap, default **1536**; truncates with an ellipsis |
| `skillListingBudgetFraction` | fraction of the context window **in chars**, default 0.01 |
| `SLASH_COMMAND_TOOL_CHAR_BUDGET` | env override for that budget |

Pick `name-only` when the model should still be able to reach the skill; pick
`user-invocable-only` when it genuinely never applies in that project.

### The budget is a ceiling, not a fill target

When the listing exceeds the budget the harness does not truncate evenly - it
switches to priority mode and **silently degrades the lowest-priority skills to
bare names**, so they can no longer auto-trigger. A tight ceiling therefore
starves skills at random as the collection grows. Control cost by controlling
description **content**; keep the ceiling well above it. This machine sets the
budget to 100,000 chars for exactly that reason.

### What actually costs what

Measure before optimising - three of the four premises in the 2026-08-28 brief
were stale or false, and all three overstated the win. Count every startup
component, not just the one you were pointed at:

```
python ~/.claude/skills/desc-census.py          # live description chars on disk
wc -c ~/.claude/CLAUDE.md <root>/CLAUDE.md \
      ~/.claude/projects/<slug>/memory/MEMORY.md
```

Also count the SessionStart hook's injection - read it out of the session's own
transcript rather than re-running the hook, which can block. On this machine the
skill listing was 59% of startup, but the auto-memory `MEMORY.md` was second at
17% and had never been looked at. Only `MEMORY.md` loads at startup; the
individual memory files load on recall and cost nothing until then.

### Moving a skill out of `~/.claude/skills`

Project skills live in `<project>/.claude/skills/<name>/` and load only when cwd
is that project (or a parent) - that is the biggest single lever, because it
removes the description from every *other* chat. Two traps before moving any:

- **Backup orphaning.** The config-sync copy set is keyed to `~/.claude/skills`.
  Read its inclusion rule first; a move can silently drop a skill from backup.
- **Broken chains.** Grep every `SKILL.md`, hook, and scheduled routine for the
  name first. A routine's cwd decides which skills it can see, so a moved skill
  silently stops firing for it, with no error.

Personal skills outrank project ones of the same name, so a leftover copy in
`~/.claude/skills` shadows the moved one.

### headless is not available here

`claude -p` fails with "OAuth session expired and could not be refreshed", so a
fresh-session probe cannot be scripted. Measure from transcripts instead.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
