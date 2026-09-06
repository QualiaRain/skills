---
name: powershell-scripting-encoding
description: >-
  Encoding and cross-shell quoting gotchas when writing PowerShell on this machine - PS 5.1 reads a BOM-less .ps1 as ANSI so em-dashes and smart quotes mojibake, and Out-File defaults break downstream parsers (Python csv, Import-Csv, jq). Use when generating a .ps1, when PowerShell output will be parsed by another tool, or when chaining Bash into pwsh.
---

# PowerShell scripting: encoding & cross-shell quoting on Windows

This machine runs `pwsh` 7.6.2 (the default shell tool) and `powershell` 5.1 (only for 5.1-only modules). Three things bite when a script crosses an encoding or shell boundary.

## Writing a `.ps1` via the Write tool — stick to ASCII

PS 5.1 reads script files as ANSI / UTF-16 unless a BOM says otherwise. An em-dash (`—`), smart quote (`"` `'`), or other non-ASCII character written without a BOM **mojibakes** when 5.1 executes the script. When authoring a `.ps1` with the Write tool, keep the content ASCII: use `-` not `—`, straight quotes not curly. (pwsh 7+ assumes UTF-8, so it's more forgiving — but ASCII is robust across both hosts.)

## PowerShell output another tool parses — pass `-Encoding utf8` explicitly

PS 5.1 defaults to **UTF-16 LE with BOM** for `Out-File`, `>`, and `Tee-Object`, and **ANSI** for `Set-Content`. Both break downstream parsers that expect UTF-8 (Python `csv.reader` / `open`, `Import-Csv`, `jq`). Whenever PowerShell writes a file or stream that another tool will read, pass `-Encoding utf8`:

```powershell
$rows | Export-Csv out.csv -Encoding utf8 -NoTypeInformation
"data" | Out-File log.txt -Encoding utf8
```

pwsh 7+ defaults to UTF-8 no-BOM (so it bites less), but `-Encoding utf8` is correct on both — be explicit rather than relying on which host runs the script.

## Chaining Bash → pwsh — single-quote the PS snippet

`$_`, `$1`, `$?` are special in **both** bash and PowerShell. When you invoke a pwsh snippet from the Bash tool, single-quote it so bash doesn't expand `$_` (etc.) before pwsh ever sees it:

```bash
pwsh -c 'Get-ChildItem | ForEach-Object { $_.Name }'   # single quotes: $_ reaches pwsh intact
```

Double-quoting lets bash eat `$_` first, handing pwsh a broken snippet.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
