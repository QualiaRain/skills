---
name: hook-engineering
description: Write, test, wire, or debug a Claude Code hook, and move always-on CLAUDE.md rules into just-in-time hooks that fire once per session. Use when authoring or fixing a hook, cutting per-turn context cost, enforcing a rule by mechanism instead of prose, or when a rule keeps failing to fire. Not plain settings.json or permission edits (update-config).
---

# Hook engineering

Hooks are the machine's answer to the failure mode the harness reliability audit keeps naming: **rules fail to ARRIVE at the point of use.** Prose in `CLAUDE.md` is read once at session start, competes with everything else in context, and is paid for on every turn whether or not the session ever does the thing the rule governs. A hook arrives at the exact moment of the action, costs nothing until then, and cannot be forgotten.

Existing hooks live in `~/.claude/hooks/`, wired in `~/.claude/settings.json`. Read a neighbouring hook before writing a new one — they share a house style.

## The one thing that breaks hooks silently

**A bare `systemMessage` reaches the terminal, not the model.** It is recorded in the transcript as a `hook_system_message` attachment and shown to the owner. The running session never sees it. `orient-check.py` had this defect from 2026-06-25 to 2026-08-21 — every zombie-baton warning it raised in fourteen months was invisible to the session it was warning.

If a hook exists to change what the session *does*, emit both channels:

```python
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",   # must match the event that fired
        "additionalContext": text,
    },
    "systemMessage": text,               # so the owner sees it too
}))
```

`additionalContext` is what acts; `systemMessage` is what the owner reads. Confirmed model-visible for `UserPromptSubmit` (2026-08-21) and for `PreToolUse` (2026-08-21, probed live on a scratch `CLAUDE.md`; the text arrived labelled `PreToolUse:Edit hook additional context`).

**Verify delivery on any event you haven't personally seen work.** Fire the hook for real, then check whether the text landed in your own context. If it shows up only as a `type: "attachment"` with `attachment.type == "hook_system_message"`, it went to the terminal and nowhere else. Newly-added hooks take effect immediately — you do not need a fresh session to test one (measured 2026-08-21; unlike custom agent types, which snapshot at session start).

## Just-in-time context: the pattern worth reaching for

Session cost ≈ **turns × resident context**. A rule sitting in `~/.claude/CLAUDE.md` is re-billed on every turn of every chat, including the chats that never do the thing it governs. Delivered by a hook, it is paid for once, and only in sessions that actually reach for the matching tool.

The delegation and model-tier rules were 3,041 chars of always-on floor that only ever mattered to a session about to call `Agent` or `Workflow`. Moved into `context-router.py` on 2026-08-21, they cost ~664 tokens/turn less in every session, and the sessions that do delegate pay that once.

`hooks/context-router.py` is the general mechanism. Adding a just-in-time rule is a **config edit**, not new code — append a block to `hooks/context-rules.json`:

```json
{"id": "delegation",
 "tools": ["Agent", "Workflow"],
 "input_pattern": "-Verb\\s+RunAs",
 "once_per_session": true,
 "source": "~/.claude/CLAUDE.md '## Section name', moved 2026-08-21",
 "text": "..."}
```

`tools` and `input_pattern` are ANDed when both appear; a block with neither selector is refused rather than firing on everything. Leave a stub in `CLAUDE.md` naming the block `id`, so a reader who wonders where a rule went can find it. Move text **verbatim** — never reword on extraction, the same contract `snippets/situational-rules.md` follows.

### Two rules that decide whether this saves or costs

**1. Fire once per session, essentially always.** `additionalContext` is not a transient notice — it is appended to the conversation and re-billed on every later call in that chat. A 3k-char block that fires on all ten of a session's `Agent` calls costs *ten times* what leaving it in `CLAUDE.md` would have. Claim a per-session marker file keyed to `session_id` + block id. `once_per_session: false` exists for genuine per-call gates and should stay rare.

**2. Only move rules that govern the ACTION.** `PreToolUse` fires after the model has already decided what to do and drafted the arguments. That makes it the right place for *"this spawn must route down a tier"* (governs the call) and the wrong place for *"never write in his first-person voice"* (governs composition that already happened). A rule about how to **think** arrives too late and must stay inline; a rule about what an action must **satisfy** belongs in the hook.

This is the test to apply before moving anything. Most of `CLAUDE.md` fails it, which is why the file is still 25k chars and should be.

**Standing grant (owner, 2026-08-21: "adjust as needed over time").** Adding a block, retuning one, or pulling a block back inline is reversible desk work — do it when you see the need, no per-instance ask. A block that arrives too late, fires too often, or turns out to have been governing thinking rather than action is a bug to fix that session, not an audit item. Record the why in the commit message; that is the block's record. Trim in small passes rather than one sweep, which is how the owner asked for it.

## Choosing the event

| Event | Fires | Good for |
|---|---|---|
| `SessionStart` | before the first turn | orientation, injected state |
| `UserPromptSubmit` | each user message | thresholds on accumulated state, first-prompt checks |
| `PreToolUse` | before a tool runs | gates, just-in-time rules, blocking a dangerous call |
| `PostToolUse` | after a tool returns | scanning output, reacting to results |
| `Stop` | turn ends | durability, backups, rot checks |

Scheduled routines submit exactly one `UserPromptSubmit`, at call 0, when accumulated state is empty. Any hook keyed off accumulated state is therefore exempt from routines by construction — no cwd gate needed, and adding one is usually the wrong instinct.

## Cost: a hook is a process spawn

Measured on this machine, 2026-08-21: each Python hook costs **~65 ms of interpreter startup**, near enough regardless of what it does. The five-hook `PreToolUse` chain totals ~360 ms per tool call. On a 100-call session that is ~36 seconds of pure overhead.

The consequence for design: **prefer one config-driven router over N single-purpose hooks.** A new rule should almost always be a block in `context-rules.json`, not a new file in `hooks/`. Write a separate hook only when it needs real computation (`claude-md-accretion-gate.py` computes an edit's size delta, which no static block can express).

## Non-negotiables

- **Never block a turn.** Always `sys.exit(0)`, always wrap `main()` in a bare `except`. A hook that raises takes the session with it.
- **Advisory unless it is a safety gate.** Setting `permissionDecision` prompts or blocks the owner. Informing is the default; blocking is for privacy fences and destructive-op gates.
- **Degrade silently.** Missing config, malformed JSON, unreadable file → return nothing, exit 0. Never surface a hook's own plumbing failure as a warning to the session.
- **Self-filter rather than rely on `matcher`.** Every hook here runs on every event of its type and returns early. Consistent with the house style and easier to test.
- **Tests live beside the hook.** `test_<hook>.py` in the same folder, driving the real subprocess with real JSON on stdin. That is where acceptance criteria belong — not in a chat. Every hook in this folder has one; match that.

## Worked examples to read

- `context-router.py` + `context-rules.json` — the just-in-time deliverer, config-driven, once-per-session.
- `claude-md-accretion-gate.py` — computed state: warns only when an edit *grows* a `CLAUDE.md`, silent on trims, and carries the extraction menu it replaced.
- `context-tripwire.py` — banded thresholds over the live transcript, one fire per band.
- `privacy-fence.py` — a real blocking safety gate, for contrast.

## Landmines

- A test that copies the hook to a temp dir also needs its config copied, or the hook silently reads the live one.
- `settings.json` here carries 454 deny entries. Edit it with a script that asserts a unique anchor and re-parses the JSON before writing — never by hand, never by rewriting the file.
- Text *about* a destructive command trips the content guards and hangs the session. Never build such text inside a shell command; `Write` the file, then `git commit -F`.
- A hook that fires on every turn is itself a per-turn tax. Gate on a band, a threshold, or a once-per-session marker before you ship it.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
