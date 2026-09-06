---
name: windows-elevation-uac
description: "Elevated Windows commands and system mutations - RunAs, admin .reg imports, reg add, .reg authoring, BCDEDIT, diskpart, driver and INF installs, NIP/QoS profiles, BitLocker. UAC is fire-and-forget, so silent failure looks like a denied prompt: wait for an explicit go before each one, verify from a log written inside the elevated script, bundle under one UAC. And reg add exit 0 is NOT verification - diff before importing. Not for reg query."
---

# Elevation on Windows

`Start-Process -Verb RunAs` is fire-and-forget — stdout/exit code unreliable, and the elevated `cmd` opens in `C:\Windows\System32`, NOT your cwd.

- **Pause and warn before every UAC prompt — and wait for an explicit "go".** Before any `Start-Process -Verb RunAs` call: (1) describe in user-facing text what the prompt will do and why, (2) STOP your turn there and wait for the user to confirm (a "yes", "go", "ready", or equivalent), and (3) only then fire. Announcing without waiting is NOT enough — the auto-mode classifier will block it, correctly, because the user may be mid-keystroke and accidentally dismiss the prompt. Never fire two UAC prompts in quick succession even after an initial go-ahead; each one needs its own confirmation. If a prompt is canceled or declined, STOP and hand off; do not retry without explicit re-approval. **Exception:** if the user has just said something like "go ahead and fire the UAC" or "do it" in direct response to your warning, that *is* the confirmation — don't ask twice. (Established 2026-05-17 on PC Idle Power; reinforced after the classifier blocked an announce-but-don't-wait attempt.)
- A silent failure (System32 cwd, missing `cd /d` in a `.bat`, missing `-Wait`) looks identical to a denied UAC prompt. Do not conflate them.
- Before retrying, write to a known log file from inside the elevated script and read that log — silent ≠ declined.
- Never loop `-Verb RunAs` more than once without a log-based diagnosis. A re-prompt the user can't tie to the original work gets dismissed.
- After two indistinguishable failures, stop and hand off: a `.ps1` for the user to right-click → Run as administrator, or a one-liner for an already-elevated shell.
- Prefer `.ps1` with `#Requires -RunAsAdministrator` over `.bat` for elevated work. `cmd.exe`'s parser has landmines that burned ~25k tokens across past Phase-1 retries: `::` comments inside parens silently fail (use `REM`), unescaped `(` / `)` in `echo` text breaks parsing, and `pause` blocks `-Verb RunAs -Wait`.
- Remote/Dispatch sessions cannot be detected from inside the transcript — treat any UAC prompt as potentially un-clickable.
- **Bundle.** If multiple elevated operations are needed in a session, drive them from a SINGLE wrapper that does all the work under one UAC, instead of firing N prompts.

## System mutations: write → readback → diff (registry, .reg imports, NIP/QoS, INF, BitLocker)

Elevation gets the write attempted; this gets it *verified*. Past sessions repeatedly declared success before the change actually persisted: Game Bar `AppCaptureEnabled` didn't survive an app restart, an NIP import landed for 2 of 7 apps, CCD affinity got applied to the wrong CCD.

- **Diff before importing.** Never `reg import` a `.reg` without first reading the current value of every key it touches and showing the owner the diff. Past imports nearly clobbered `HDREnabled` and unrelated colour-profile values.
- **No guessing at undocumented values.** If you don't know what a value means or its valid range, say so and propose an empirical test — don't synthesize a plausible-looking write.
- **Identify before suspecting.** Before flagging a device or volume as suspicious (USB bootloader, unknown VID, rogue partition), check whether it is a known BitLocker, system, or recovery device. Unfamiliar is not malicious.
- **Round-trip verify.** After any registry write or config import: (1) read the value back, (2) diff against intent, (3) cross the persistence boundary that matters (app restart, sign-out, sleep/resume), (4) re-read. Only then report success. **`reg add` exit 0 is NOT verification.**

This does not apply to read-only queries (`reg query`, `Get-ItemProperty`) or application-level config files.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
