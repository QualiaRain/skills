---
name: gh-safe-comment-edit
description: >-
  Programmatically edit or post a GitHub comment, PR body, or issue body from Windows WITHOUT corrupting it (cp1252 mojibake and CRLF doubling have both shipped to live upstream content). Use whenever a task creates or modifies GitHub body text via gh or the API. Triggers - edit or fix that comment, update the PR body, the comment looks mangled.
---

# Safe GitHub comment / body edits from Windows

Posting or editing GitHub body text programmatically from Windows has
corrupted **live upstream content** more than once. Both bugs are silent in a content-only
check (non-ASCII count, ``` fence count) and only show in GitHub's RENDER. Use the
bundled `ghsafe.py` for any programmatic create/modify of a GitHub body; never
hand-roll the `gh api` PATCH each time.

## The two traps it closes

1. **cp1252 mojibake.** `subprocess.run(..., text=True)` with no `encoding=` (or
   any locale-default capture) decodes gh's UTF-8 output as cp1252, turning `—`
   into `â€"`. Setting `PYTHONUTF8=1` (e.g. in the `env` block of Claude Code's
   `settings.json`) helps, **but** this tool decodes UTF-8 explicitly so it is
   correct with or without that setting, inside or outside Claude Code.
2. **CRLF doubling (`\r\r\n`).** Writing an already-CRLF body through a Windows
   **text-mode** file (`open(path,"w")` without `newline=""`) turns every `\r\n`
   into `\r\r\n`. GitHub reads the double-CR as a paragraph break and shatters
   fenced code blocks into one box per line. `PYTHONUTF8=1` does **not** fix this
   (it's newline translation, not encoding) - this tool's `normalize()` is the fix.

## Invariants (enforced by ghsafe.py on every write)

- fetch body as **bytes -> decode utf-8** (never the locale codec)
- **normalize to `\n`-only** before posting (strips `\r` and the doubled `\r\r\n`)
- PATCH/POST via **`gh api --input -`** with a JSON payload on stdin - **never a
  text-mode temp file** (that file write is exactly what doubled the CRs)
- **round-trip verify**: re-fetch, assert 0 carriage returns + content matches

## Use it

Needs Python 3 and an authenticated `gh` (`gh auth status` exits 0). Use `python`
on Windows, `python3` on macOS/Linux. `SKILL` is wherever this skill folder was
installed (for Claude Code usually `~/.claude/skills/gh-safe-comment-edit`).

```
SKILL=~/.claude/skills/gh-safe-comment-edit/ghsafe.py

# read a body (clean utf-8, lf) - safe to pipe/inspect
python "$SKILL" get     --repo OWNER/REPO --kind comment --id 1234567890

# replace a body from a file (file read as bytes+utf-8; output verified)
python "$SKILL" set     --repo OWNER/REPO --kind pr --id 4936 --body-file body.md

# prepend an edit/clarification note (idempotent with --if-absent)
python "$SKILL" prepend --repo OWNER/REPO --kind comment --id 123 \
       --note-file note.md --if-absent "Edit (clarification)"

# append text to the end of a body (--sep defaults to a blank line)
python "$SKILL" append  --repo OWNER/REPO --kind issue --id 42 --text-file more.md

# post a NEW comment on an issue/PR
python "$SKILL" post    --repo OWNER/REPO --issue 4936 --body-file comment.md
```

`--kind`: `comment` (conversation comment) | `review-comment` (inline code
comment) | `issue` (issue body) | `pr` (PR body). `--id` is the comment's numeric
id for the two comment kinds (the number after `#issuecomment-` or
`#discussion_r` in its URL), and the issue/PR number for `issue`/`pr`.

**How you know it worked:** each write prints a line ending `(verified: ...)` and
exits 0. Any failure raises (traceback, non-zero exit) - read it, don't retry
blindly. `post` prints the new comment id; keep it.

**Author body files with `\n` endings and UTF-8.** The tool normalizes anyway, but
don't paste through a tool that injects CRLF. After any write the tool re-fetches
and asserts `0` carriage returns - if that assert fires, GitHub stored CRs and the
render is at risk; investigate before trusting it.

## Substantive edits get a visible edit note

GitHub's "edited" marker sits on a comment permanently, but the history view does
NOT show a line diff — it renders the old and new bodies as two stacked markdown
blocks, so a replaced body is
unauditable even for a reader who opens the history. The edit note is what makes
the edit auditable at all — it is not just courtesy to prior readers. So ANY edit
that changes substance (adds/removes claims, rows, corrections) carries a
one-line note in the body: `**Edit:** added X, corrected Y` (or use `prepend
--if-absent` for a standalone note). Only typo/formatting-grade fixes a reader
wouldn't care to audit go noteless.

## Disclosure still applies

This tool handles MECHANICS only. Any upstream comment/PR/issue presenting
Claude-derived findings as fact still needs an AI-authorship disclosure check
(the original setup used an `ai-authorship-disclosure` skill
(not included in this pack)): a disclosure line, claims calibrated to what was actually verified, and no
stray "the owner". Do that on the CONTENT before using this tool to post it.

## After posting an upstream comment: arm the watch

Posting a NEW comment to an issue/PR the account owner doesn't own is only half
the job — arm the event-driven watch so follow-ups get handled: see the
**`gh-comment-watch`** skill (in this pack). It
sets up a persistent `Monitor` that fires on each new reply/state change and
handles on-topic answers (surfacing new-repo PRs / disagreements / anything
reputational) until the thread is resolved. Skip only for terminal sign-off
comments that expect no reply.

## Self-test

`python test_ghsafe.py` (run from this folder) - 13 offline checks locking the pure invariants (CRLF
collapse, 0-CR payload, utf-8 round-trip, prepend composition). Passes under both
the default and `PYTHONUTF8=1` environments. Run it after any edit to `ghsafe.py`.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
