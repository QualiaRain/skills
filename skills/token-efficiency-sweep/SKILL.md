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

Claude Code writes **several `.jsonl` records per API response** — one for the thinking block, one for text, one for each tool_use — and **every one of them carries the same `usage` object**. Summing usage per record triple-counts. The author measured it wrong in exactly this way once (a routine "cost 12.0M read over 77 turns"; deduped it was 4.7M over 30 calls) before the error was caught.

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

import glob
for f in sorted(glob.glob("*.jsonl")):
    print(f, "calls=%d out=%d cache_create=%d read=%d read_per_call=%d" % measure(f))
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

Field names are as observed by the author; check one record before trusting a parser. To read the initial skill listing of a session:

```python
import json, sys
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try: a = (json.loads(line).get("attachment") or {})
    except Exception: continue
    if a.get("type") == "skill_listing" and a.get("isInitial"):
        print(a.get("skillCount"), "skills,", len(a.get("content") or ""), "chars")
```

Always filter on `isInitial` — later `skill_listing` records are single-skill re-injections, not the budget. Startup context is snapshotted at session start, so **no settings edit is visible to the session that made it**; measure a session that opened *after* the change. Plugin skills are listed separately and are not governed by the local budget or `skillOverrides`, so split local (`~/.claude/skills`) from plugin entries before judging a result.

The rest of turn 1 is the base system prompt plus built-in tool schemas, which is fixed and not worth attacking.

### Census an instruction file before editing it

Split on `## ` headings and count characters. The fat is reliably somewhere you did not expect:

```bash
awk '/^#/{if(h!=""){printf "%6d  %s\n", c, h} h=$0; c=0} {c+=length($0)+1} END{printf "%6d  %s\n", c, h}' FILE
```

Long unwrapped lines make `wc -l` useless here (rendered prose is one line per paragraph on purpose), so count chars, and map a section's lines with `awk 'NR>=A && NR<=B {printf "%3d %5d %s\n", NR, length($0), substr($0,1,95)}'` before deciding what moves.

## The levers, cheapest first

**0. Delete the work before optimising it.** The cheapest turn is the one that never runs. In one measured day, cutting an unattended fleet from 5 runs a day to 2 dwarfed every per-turn saving available anywhere else. Before censusing a surface, ask whether the thing that reads it needs to run at all, or that often. This lever is first because it is the only one that removes whole sessions rather than shaving their floor.

**1. Cap the skill listing where descriptions do nothing (routines only).** Descriptions exist to make a skill *auto-trigger*. A scheduled routine follows a fixed SKILL.md and names the skill it wants, so every description is dead weight re-read on every call. Settings, scoped per directory in `.claude/settings.local.json` (full key table under *Measuring the skill listing* below):

- `"skillListingBudgetFraction": 0.0005` — fraction of the context window (in characters) reserved for the listing; over budget, descriptions are dropped to fit. Default 0.01.
- `env.SLASH_COMMAND_TOOL_CHAR_BUDGET: "1000"` — the same budget as a hard char number; it overrides the fraction.
- `"skillOverrides": {"<skill>": "name-only"}` — the surgical, per-skill form. Use this instead of a budget in any **interactive** project: a tight budget silences skills you cannot choose (see *The budget is a ceiling* below).

**Names stay listed at any budget.** That is what makes this safe: nothing loses the ability to be invoked, only the ability to fire on its own. Before applying it anywhere, grep the routine's SKILL.md for skill names it calls, and confirm none of them depends on description-triggering.

When a project `env` block is added, check your user-level `env` vars still apply in that project afterwards (the author copies the user-level block in verbatim, to be safe against a replace-style merge dropping them).

**2. Suppress SessionStart injections for sessions that cannot use them.** A hook that orients a *person* is pure cost in an unattended run. Gate inside the hook on cwd and return a two-line pointer instead of the block, so a person who does open a chat there is not stranded. Measured: 10,270 chars -> 291.

**3. Extract, do not delete.** A rule that fires in a SITUATION moves to a snippet or sibling file with a one-line trigger left inline, so it still ARRIVES. A rule that fires EVERY turn stays. Pure rationale and receipts — the "why we chose this mechanism" paragraphs — have no runtime consumer at all and should always move out.

Verify the move mechanically, every time:

```python
orig = open(BACKUP, encoding="utf-8").read().split("\n")
new  = set(open(TRIMMED, encoding="utf-8").read().split("\n"))
for f in EXTRACTED_FILES: new |= set(open(f, encoding="utf-8").read().split("\n"))
print([l[:120] for l in orig if l.strip() and l not in new])   # must be []
```

**4. Move payloads out of the always-on path.** Lookup tables, maps, history, receipts -> a pointed-at file. Bulk payloads for another model -> a file it reads once, not a page body that a connector re-fetches into context each time.

**5. Fewer calls beats fewer chars.** One call at 150k context costs more than 3k chars of standing text does across a whole session. Batch independent tool calls into one message; do not re-derive what a log already says; do not spawn a subagent for a two-call job.

### Two things that look like levers and are not

- **Extracting a phase that runs every time.** If the routine has to read the file at step 3, the payload is resident from turn 3 onward and you saved almost nothing while adding a step that can be skipped. Extract *conditional* and *never-needed-at-runtime* text only.
- **Re-emitting a section to compress it.** Rewriting whole sections to save characters burned ~15k output tokens for ~700 chars once already. Prefer targeted fragment replacement, or move the text verbatim.

## Hard limits on this work

- **Never buy a saving by skipping retrieval, verification, or certainty.** Savings come from cutting re-derivation and overkill process, never from cutting the checks. Spend on correctness is effectively unbounded; spend on re-deriving what was already established is the waste.
- **A budget checked against today's content is a measurement, not a bound.** Make the arithmetic hold whatever the content becomes.
- **Do not optimize the optimizer.** If a sweep is costing more than the surface it is trimming will ever save, stop and say so.

## Before you close: write the finding back

The ledger lives in [`references/findings-ledger.md`](references/findings-ledger.md) (the author's dated measurements; read it before re-running a measurement). Append one dated line there — what you measured, what you changed, what it saved, and whether it is verified or still waiting on a run. A finding that only exists in a closed chat's scrollback is not a finding.

Bound it: past ~25 entries, keep the newest ~15 and fold anything that has held three separate times up into this skill body as a rule. An unbounded ledger becomes the waste it was written to prevent.
If this skill is installed as a read-only copy (e.g. synced from claude.ai/Cowork), append to the source copy instead, or give the user the line to add.

## Measuring the skill listing: two free ground-truth methods

Never accept a prior session's claim about how the harness behaves. Both of these
cost nothing and settle it in one call. A session that skipped them shipped a
"fix" for a bug that did not exist.

**1. What the harness actually sent the model** — the `skill_listing` attachment
record (snippet under *Where the floor actually comes from* above). It is the only
way to prove a skill was silenced rather than infer it.

**2. What the harness will accept.** The installed CLI binary has its JS bundle
embedded and carries its own settings schema as literal strings. This outranks the
docs, because it is the code that will actually run. The binary's path varies by
install (`which claude` / `where claude`; a native install is usually
`~/.local/bin/claude`, an npm install has a `cli.js` instead):

```
grep -a -o ".\{0,160\}skillOverrides.\{0,400\}" "$(which claude)" | head
```

The author verified these keys this way on v2.1.233, cross-checked against code.claude.com/docs/en/skills; re-run the grep on your version:

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
description **content**; keep the ceiling well above it (the author sets
`SLASH_COMMAND_TOOL_CHAR_BUDGET` to 100000 at user level for exactly that reason).

### What actually costs what

Measure before optimising - in one of the author's sweeps, three of four premises
in the brief were stale or false, and all three overstated the win. Count every
startup component, not just the one you were pointed at:

```python
# description chars per installed personal skill, largest first
import glob, os, re
rows = []
for f in glob.glob(os.path.expanduser("~/.claude/skills/*/SKILL.md")):
    fm = open(f, encoding="utf-8").read().split("---")[1]
    m = re.search(r"^description:(.*?)(?=^\S|\Z)", fm, re.S | re.M)
    if m: rows.append((len(m.group(1).strip()), f))
print("total", sum(n for n, _ in rows))
for n, f in sorted(rows, reverse=True)[:15]: print(n, f)
```

```
wc -c ~/.claude/CLAUDE.md ./CLAUDE.md ~/.claude/projects/<slug>/memory/MEMORY.md
```

Also count the SessionStart hook's injection - read it out of the session's own
transcript rather than re-running the hook, which can block. On the author's setup the
skill listing was 59% of startup, but the auto-memory `MEMORY.md` was second at
17% and had never been looked at. Only `MEMORY.md` loads at startup; the
individual memory files load on recall and cost nothing until then.

### Moving a skill out of `~/.claude/skills`

Project skills live in `<project>/.claude/skills/<name>/` and load only when cwd
is that project (or a parent) - that is the biggest single lever, because it
removes the description from every *other* chat. Two traps before moving any:

- **Backup orphaning.** If you back up or sync `~/.claude/skills` (a dotfiles
  repo, a sync script), check its inclusion rule first; a move can silently drop a
  skill from backup.
- **Broken chains.** Grep every `SKILL.md`, hook, and scheduled routine for the
  name first. A routine's cwd decides which skills it can see, so a moved skill
  silently stops firing for it, with no error.

Personal skills outrank project ones of the same name, so a leftover copy in
`~/.claude/skills` shadows the moved one.

### If headless fails

On the author's machine `claude -p` failed with "OAuth session expired and could not
be refreshed", so a fresh-session probe could not be scripted. If yours does too,
measure from transcripts instead.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
