<#
.SYNOPSIS
  Install the mouse-dpi skill into your Claude Code skills folder.

.DESCRIPTION
  Idempotent: copies this folder to ~/.claude/skills/mouse-dpi (creating it or
  refreshing it), skipping the repo's own .git and tools folders. Changes no
  settings, no hooks, no permissions; Claude Code picks the skill up on its
  next session start. Re-run any time to update after a git pull.

  Requirements the skill itself needs: Windows 10/11, Python 3.11+, and uv
  (https://docs.astral.sh/uv/) for the one script that needs a package.
  Nothing here runs on its own; read it before you run it.
#>
[CmdletBinding()]
param([string]$Target = (Join-Path $HOME '.claude\skills\mouse-dpi'))
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not (Test-Path (Join-Path $src 'SKILL.md'))) { throw "run this from the mouse-dpi folder (SKILL.md not found next to install.ps1)" }
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Get-ChildItem $src -Force | Where-Object { $_.Name -notin @('.git', 'tools', 'install.ps1') } | ForEach-Object {
    Copy-Item $_.FullName -Destination $Target -Recurse -Force
}
"installed to $Target"
"next: start a new Claude Code session and ask it: what dpi am I on?"
"verify: pwsh -File `"$Target\scripts\smoke.ps1`""
