# skills

17 Claude Code skills, exported from one person's working setup and de-personalized so they run on yours.
They are Markdown instruction files (plus a few small scripts) that Claude Code loads by name; nothing here runs on its own.

## Install

Option A (one command, idempotent — copies each skill folder into `~/.claude/skills/`, skipping any folder you already have):

    # Windows (PowerShell)
    .\install.ps1
    # macOS / Linux
    ./install.sh

Option B (manual): copy any folder under `skills/` into `~/.claude/skills/`. No settings changes are needed; a skill triggers from its own description.

Or just clone this repo and ask Claude Code: "what is this and how do I set it up?"

## The 17 skills

Claude Code craft (portable, any OS):

- `sonnet-fabrication-calibration` — when to trust a cheap model's confident output, and how to check it.
- `phase-gated-model-routing` — run each phase of a task on the cheapest sufficient model; escalate on tripwires.
- `workflow-cost-discipline` — model-routing and cost judgment BEFORE launching a fan-out, audit, or deep-research run.
- `headless-instruction-selftest` — prove a CLAUDE.md rule or doc actually reaches a fresh session, with headless probes.
- `skill-execution-hardening` — stress-test a skill blind on a weak subagent; find where it breaks; re-test on a fresh one.
- `hook-engineering` — write and debug hooks; move always-on CLAUDE.md rules into once-per-session hooks.
- `token-efficiency-sweep` — measure and cut what a session or scheduled routine re-bills on every turn.
- `loop-engineering` — self-verifying agentic loops: a measurable goal, a separate cheaper verifier, a mechanical stop.
- `llm-legible-project-docs` — structure project docs so fast, cheap inference reads them correctly and acts on them.

Windows practical:

- `bash-on-windows` — the Bash tool (Git Bash/MSYS2) silently halves doubled backslashes; quoting and capture traps.
- `powershell-scripting-encoding` — PS 5.1 reads BOM-less `.ps1` as ANSI; encoding and cross-shell quoting gotchas.
- `gh-safe-comment-edit` — post or edit GitHub comments from Windows without cp1252 mojibake or CRLF doubling.
- `windows-elevation-uac` — elevated commands and system mutations (RunAs, `.reg` imports, BCDEDIT, drivers) that fail silently under UAC.
- `windows-display-fault-triage` — find WHY a display looks wrong by measuring the colour stack, not guessing.
- `pc-health-sweep` — one read-only, privacy-redacted Windows sweep turned into a ranked verdict.
- `mouse-dpi` — find a mouse's real DPI and set in-game sensitivity to a target cm/360.

Utility:

- `youtube-transcript-captions` — get a YouTube video's text via yt-dlp captions in seconds; fall back to a diarized transcript.

## Read before running (budget)

Context size, not "effort", is what makes an agent expensive: cost ≈ turns × context per turn. Four skills here spawn subagents or headless runs and can spend a lot if pointed at a big target: `workflow-cost-discipline`, `loop-engineering`, `headless-instruction-selftest`, `token-efficiency-sweep`. Each carries its own launch gate and budget warnings in the body — read them first, start on something small.

## What might clash with your setup

- Skill names referenced but not shipped are marked `(not included in this pack)` inline. Ignore those pointers or drop them.
- "the owner" in a skill means you, the person running Claude Code.
- Seven skills are Windows-specific (listed above). They are noise on macOS/Linux; skip them.
- A few skills mention the Claude Desktop app, scheduled routines, or hooks. If you don't use those, ignore that section.
- If you already have a folder with the same name under `~/.claude/skills/`, the installer skips it — rename one of them.
- Numbers quoted inside the skills (token savings, timings) were measured on the author's machine. Don't take them on trust; run the skill and see.

## License

MIT — see [LICENSE](LICENSE).
