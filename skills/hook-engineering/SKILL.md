---
name: hook-engineering
description: Write, test, wire, or debug a Claude Code hook, and move always-on CLAUDE.md rules into just-in-time hooks that fire once per session. Use when authoring or fixing a hook, cutting per-turn context cost, enforcing a rule by mechanism instead of prose, or when a rule keeps failing to fire. Not plain settings.json or permission edits (update-config).
---

# Hook engineering

Hooks are the answer to a recurring failure mode: **rules fail to ARRIVE at the point of use.** Prose in `CLAUDE.md` is read once at session start, competes with everything else in context, and is paid for on every turn whether or not the session ever does the thing the rule governs. A hook arrives at the exact moment of the action, costs nothing until then, and cannot be forgotten.

User-level hooks are wired in `~/.claude/settings.json` (project-level: `.claude/settings.json`); the scripts can live anywhere, conventionally `~/.claude/hooks/`. If hooks already exist there, read a neighbouring one before writing a new one and match its style. The file names below (`context-router.py`, `privacy-fence.py`, ...) are from the author's setup and are **not shipped with this pack** — they are described so you can build your own.

Minimal wiring (every hook: JSON event on stdin, output on stdout, exit 0):

```json
{"hooks": {"PreToolUse": [
  {"matcher": "*",
   "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/context-router.py"}]}
]}}
```

`matcher` is a tool-name pattern (e.g. `"Bash"`, `"Edit|Write"`, `"*"` for all) and applies to the tool events; `UserPromptSubmit`, `SessionStart` and `Stop` entries can omit it. Merge into the existing `"hooks"` object rather than replacing it. Run `/hooks` in a session to confirm the hook is registered.

## The one thing that breaks hooks silently

**A bare `systemMessage` reaches the terminal, not the model.** It is recorded in the transcript as a `hook_system_message` attachment and shown to the user. The running session never sees it. One of the author's hooks had this defect for two months — every warning it raised in that time was invisible to the session it was warning.

If a hook exists to change what the session *does*, emit both channels:

```python
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",   # must match the event that fired
        "additionalContext": text,
    },
    "systemMessage": text,               # so the user sees it too
}))
```

`additionalContext` is what acts; `systemMessage` is what the user reads. The author confirmed `additionalContext` model-visible for `UserPromptSubmit` and for `PreToolUse` (the text arrived labelled `PreToolUse:Edit hook additional context`).

**Verify delivery on any event you haven't personally seen work.** Fire the hook for real, then check whether the text landed in your own context. In the session's transcript JSONL (under `~/.claude/projects/`), text that shows up only as a `type: "attachment"` with `attachment.type == "hook_system_message"` went to the terminal and nowhere else. In the author's version of Claude Code, newly-added hooks took effect immediately without a fresh session (unlike custom agent types, which snapshot at session start); if yours does not fire, check `/hooks` or restart the session before debugging the script.

## Just-in-time context: the pattern worth reaching for

Session cost ≈ **turns × resident context**. A rule sitting in `~/.claude/CLAUDE.md` is re-billed on every turn of every chat, including the chats that never do the thing it governs. Delivered by a hook, it is paid for once, and only in sessions that actually reach for the matching tool.

In the author's setup, the delegation and model-tier rules were 3,041 chars of always-on CLAUDE.md that only ever mattered to a session about to call `Agent`. Moved into a hook, they cost ~664 tokens/turn less in every session, and the sessions that do delegate pay that once.

The author's general mechanism is one `PreToolUse` hook, `context-router.py` (not shipped), that reads rule blocks from `context-rules.json` and emits the matching block's `text` as `additionalContext`. Once such a router exists, adding a just-in-time rule is a **config edit**, not new code — append a block like:

```json
{"id": "delegation",
 "tools": ["Agent"],
 "once_per_session": true,
 "source": "~/.claude/CLAUDE.md '## Section name', moved <date>",
 "text": "..."}
```

`tools` matches the tool name; an optional `input_pattern` (a regex over the tool input, e.g. `"-Verb\\s+RunAs"` on a `Bash` block) is ANDed with it when both appear; a block with neither selector should be refused rather than fire on everything. Leave a stub in `CLAUDE.md` naming the block `id`, so a reader who wonders where a rule went can find it. Move text **verbatim** — never reword on extraction.

### Two rules that decide whether this saves or costs

**1. Fire once per session, essentially always.** `additionalContext` is not a transient notice — it is appended to the conversation and re-billed on every later call in that chat. A 3k-char block that fires on all ten of a session's `Agent` calls costs *ten times* what leaving it in `CLAUDE.md` would have. Claim a per-session marker file keyed to `session_id` + block id. `once_per_session: false` exists for genuine per-call gates and should stay rare.

**2. Only move rules that govern the ACTION.** `PreToolUse` fires after the model has already decided what to do and drafted the arguments. That makes it the right place for *"this spawn must route down a tier"* (governs the call) and the wrong place for *"never write in the user's first-person voice"* (governs composition that already happened). A rule about how to **think** arrives too late and must stay inline; a rule about what an action must **satisfy** belongs in the hook.

This is the test to apply before moving anything. Most of a typical `CLAUDE.md` fails it, and that is fine — those rules belong inline.

**Maintenance.** Adding a block, retuning one, or pulling a block back inline is reversible — if the user has agreed to that kind of upkeep, do it when you see the need. A block that arrives too late, fires too often, or turns out to have been governing thinking rather than action is a bug to fix that session. Record the why in the commit message; that is the block's record. Trim in small passes rather than one sweep.

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

Measured on the author's Windows machine: each Python hook costs **~65 ms of interpreter startup**, near enough regardless of what it does. A five-hook `PreToolUse` chain totalled ~360 ms per tool call. On a 100-call session that is ~36 seconds of pure overhead.

The consequence for design: **prefer one config-driven router over N single-purpose hooks.** Once you have a router, a new rule should almost always be a block in its config, not a new hook script. Write a separate hook only when it needs real computation (e.g. computing an edit's size delta, which no static block can express).

## Non-negotiables

- **Never block a turn.** Always `sys.exit(0)`, always wrap `main()` in a bare `except`. A hook that raises takes the session with it.
- **Advisory unless it is a safety gate.** Setting `permissionDecision` (in `PreToolUse`'s `hookSpecificOutput`) prompts or blocks the user. Informing is the default; blocking is for privacy fences and destructive-op gates.
- **Degrade silently.** Missing config, malformed JSON, unreadable file → return nothing, exit 0. Never surface a hook's own plumbing failure as a warning to the session.
- **Self-filter rather than rely on `matcher`** (the author's house style). Each hook runs on every event of its type (`"matcher": "*"`) and returns early when the input is not its concern — easier to test, since the filter lives in code.
- **Tests live beside the hook.** `test_<hook>.py` in the same folder, driving the real subprocess with real JSON on stdin. That is where acceptance criteria belong — not in a chat. Give every hook one.

## Patterns from the author's setup (not shipped)

- `context-router.py` + `context-rules.json` — the just-in-time deliverer, config-driven, once-per-session.
- `claude-md-accretion-gate.py` — computed state: warns only when an edit *grows* a `CLAUDE.md`, silent on trims, and carries the extraction menu it replaced.
- `context-tripwire.py` — banded thresholds over the live transcript, one fire per band.
- `privacy-fence.py` — a real blocking safety gate, for contrast.

## Landmines

- A test that copies the hook to a temp dir also needs its config copied, or the hook silently reads the live one.
- A large `settings.json` (the author's carries hundreds of deny entries) is easy to corrupt. Edit it with a script that asserts a unique anchor and re-parses the JSON before writing — never by rewriting the whole file from memory.
- If you run content-guard hooks, text *about* a destructive command can trip them and hang the session. Never build such text inside a shell command; `Write` the file, then `git commit -F`.
- A hook that fires on every turn is itself a per-turn tax. Gate on a band, a threshold, or a once-per-session marker before you ship it.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
