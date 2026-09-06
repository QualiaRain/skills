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

Using claude.ai or Cowork instead of the terminal? See "How skills work on each surface" below — those need a ZIP upload, not a file copy.

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

Context size, not "effort", is what makes an agent expensive: cost ≈ turns × context per turn. Five skills here can spawn subagents or headless runs and spend a lot if pointed at a big target: `workflow-cost-discipline`, `loop-engineering`, `headless-instruction-selftest`, `token-efficiency-sweep`, and `pc-health-sweep`'s optional analysis workflow (the sweep itself is cheap; the workflow is not). Each carries its own launch gate and budget warnings in the body — read them first, start on something small.

## Not everything is read-only

Installing is a pure file copy. Running is mostly read-only, but a few scripts change live state and are gated behind explicit flags: `mouse-dpi` (`--set`, `--yes`), `windows-display-fault-triage` (`-FixRange`, `set_hz.ps1`), and everything in `windows-elevation-uac`. Read the flag before you pass it.

## What might clash with your setup

- Skill names referenced but not shipped are marked `(not included in this pack)` inline. Ignore those pointers or drop them.
- "the owner" in a skill means you, the person running Claude Code.
- Seven skills are Windows-specific (listed above). They are noise on macOS/Linux; skip them.
- A few skills mention the Claude Desktop app, scheduled routines, or hooks. If you don't use those, ignore that section.
- If you already have a folder with the same name under `~/.claude/skills/`, the installer skips it — rename one of them.
- Numbers quoted inside the skills (token savings, timings) were measured on the author's machine. Don't take them on trust; run the skill and see.

## How skills work on each surface

A skill is just a folder: `SKILL.md` (YAML frontmatter with `name` and `description`, then instructions) plus optional scripts and reference files. That one folder format is used everywhere, but each surface finds skills in a different place, and the copies do not stay in sync with each other.

| Surface | Where it reads skills from | How to install this pack |
|---|---|---|
| **Claude Code** (terminal, local) | `~/.claude/skills/<name>/` (personal), `<repo>/.claude/skills/<name>/` (project, committed to git), plugin skills (`/plugin:skill`), and enterprise-managed skills. Precedence: enterprise > personal > project. Edits are picked up live. | `install.ps1` / `install.sh` (copies into personal). Or commit folders into a repo's `.claude/skills/` so everyone who clones gets them. |
| **claude.ai chat** (web + desktop app) and **Cowork** | Your account's skill list: **Customize > Skills > + > Create skill > Upload a skill**, one ZIP per skill with the skill folder as the ZIP root. Same list serves chat, Cowork, and the Word/Excel/PowerPoint/Outlook add-ins. Cowork also gets skills from installed plugins. Nothing is read from your disk. | Run `zip-skills.ps1` / `zip-skills.sh` to get `dist/<name>.zip` for each skill, then upload the ones you want. |
| **Claude Code on the web / cloud sessions** | Your account-enabled skills, plus the cloned repo's committed `.claude/skills/`. Your machine's `~/.claude/skills/` is never read. | Upload to your account, or commit into the repo. |
| **API / Agent SDK** | The Skills API, used with the code execution tool. | See Anthropic's Agent Skills docs. |

Sync is one-way and partial:

- Account skills flow **down** into Claude Code: Cowork and cloud sessions sync them automatically into `~/.claude/skills/synced/`; a local terminal session pulls them only if started with `CLAUDE_CODE_SYNC_SKILLS=1`. Those synced copies are a read-only cache — editing them changes nothing. Edit the source folder and re-upload.
- Nothing flows **up**: a folder in `~/.claude/skills/` never appears in claude.ai or Cowork by itself.
- Synced skills running in a local (non-Cowork) session do not execute `!` shell commands, `@` file references, or `${CLAUDE_PROJECT_DIR}`; Claude sees those as plain text. The skills in this pack rely on none of them.
- Anthropic's upload guide states a 200-character limit on `description`. Most descriptions here are longer, and it is unclear whether the limit is enforced at upload. If an upload is rejected or the description looks cut off, shorten it in the frontmatter and re-zip.

Treat this repo as the source of truth and every installed copy as a deployment. Change a skill here, then re-install / re-upload; do not edit the installed copies.

Docs: [Claude Code skills](https://code.claude.com/docs/en/skills) · [Use skills in Claude](https://support.claude.com/en/articles/12512180-use-skills-in-claude) · [Create custom skills](https://support.claude.com/en/articles/12512198-how-to-create-custom-skills)

## License

MIT — see [LICENSE](LICENSE).
