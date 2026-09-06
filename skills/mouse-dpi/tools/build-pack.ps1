<#
.SYNOPSIS
  Build the shareable mouse-dpi pack from the local skill folder.

.DESCRIPTION
  Copies ~/.claude/skills/mouse-dpi into this repo's root (the repo root IS the
  skill folder, so a recipient installs with one clone or install.ps1), leaving
  out the owner's personal files, then runs the two ship gates from the
  export-skill-pack method:
    1. scrub gate  - greps the result for personal markers and FAILS on any hit
    2. frontmatter - parses SKILL.md's YAML with a real parser and checks that
                     name and the full description survive
  Exit 0 only when both gates pass. Run from anywhere:
    pwsh -File tools\build-pack.ps1 [-Source <skill dir>] [-Markers a,b,c]
#>
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $HOME '.claude\skills\mouse-dpi'),
    # Extra personal markers to reject, on top of the built-in set. Keep the
    # owner's real identifiers OUT of this file: pass them on the command line.
    [string[]]$Markers = @()
)
$ErrorActionPreference = 'Stop'
$Dest = Split-Path -Parent $PSScriptRoot   # repo root
if (-not (Test-Path (Join-Path $Source 'SKILL.md'))) { throw "no SKILL.md under $Source" }

# 1. copy, excluding personal + generated files
$exclude = @('baseline.md', '__pycache__', '.git', 'tools', '.gitignore')
Get-ChildItem $Dest -Force | Where-Object { $_.Name -notin @('.git', 'tools', 'install.ps1', 'LICENSE') } | Remove-Item -Recurse -Force
Get-ChildItem $Source -Force | Where-Object { $_.Name -notin $exclude } | ForEach-Object {
    Copy-Item $_.FullName -Destination $Dest -Recurse -Force
}
Get-ChildItem $Dest -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force

# baseline.md is deliberately absent from the pack: it is the owner's personal
# data. The skill ships baseline.template.md and README tells the recipient to
# copy it. Guard against a stale copy from an earlier build:
Remove-Item (Join-Path $Dest 'baseline.md') -Force -ErrorAction SilentlyContinue

# baseline.md is ignored so a recipient who follows the README and creates their
# own baseline inside the cloned pack never commits their personal data.
@'
__pycache__/
*.pyc
baseline.md
'@ | Set-Content -Path (Join-Path $Dest '.gitignore') -Encoding UTF8

# 2. scrub gate
# UNC marker matches a real network share path (double backslash, host, share), not Python's escaped backslashes in strings
# Generic markers only. Names, usernames, emails and the machine name go in
# -Markers on the command line so this file never carries them.
$builtin = @('C:\\Users\\', 'Z:\\', 'D:\\', '(^|[\s"''(])\\\\[A-Za-z0-9-]+\\[A-Za-z0-9$-]+', '@gmail', '@outlook', 'Users\\[A-Za-z]+\\', 'DESKTOP-[A-Z0-9]{7}')
$all = $builtin + $Markers
$files = Get-ChildItem $Dest -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\tools\\' }
$hits = @()
foreach ($f in $files) {
    foreach ($m in $all) {
        $h = Select-String -Path $f.FullName -Pattern $m -CaseSensitive:$false -ErrorAction SilentlyContinue
        if ($h) { $hits += $h | ForEach-Object { "{0}:{1} [{2}] {3}" -f $_.Path.Replace($Dest, '.'), $_.LineNumber, $m, $_.Line.Trim().Substring(0, [Math]::Min(100, $_.Line.Trim().Length)) } }
    }
}
if ($hits) { "SCRUB GATE FAIL:"; $hits | ForEach-Object { "  $_" }; exit 1 } else { "SCRUB GATE PASS ($($files.Count) files, $($all.Count) markers)" }

# 3. frontmatter gate (real YAML parser via uv, PYTHONUTF8 so dashes never crash it)
$env:PYTHONUTF8 = '1'
$py = @'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
assert text.startswith("---"), "no frontmatter"
block = text.split("---", 2)[1]
fm = yaml.safe_load(block)
name, desc = fm.get("name"), fm.get("description")
assert name == "mouse-dpi", f"name parsed as {name!r}"
assert isinstance(desc, str) and len(desc) > 200, f"description parsed short/empty: {desc!r}"
# the parser must have kept the whole description: rebuild the raw text (plain
# scalar, quoted scalar, or a > / | block with indented continuation lines) and
# compare with whitespace folded, so a stray ': ' or ' #' cannot hide a cut
lines = block.splitlines()
i = next(n for n, l in enumerate(lines) if l.startswith("description:"))
first = lines[i].split(":", 1)[1].strip()
if first[:1] in (">", "|"):
    body = []
    for l in lines[i + 1:]:
        if l.strip() == "" or l.startswith((" ", "\t")):
            body.append(l.strip())
        else:
            break
    raw = " ".join(x for x in body if x)
else:
    raw = first.strip('"').strip("'")
norm = lambda s: " ".join(s.split())
assert norm(desc) == norm(raw), f"description truncated by YAML parsing: parsed {len(norm(desc))} vs raw {len(norm(raw))} chars"
print(f"FRONTMATTER GATE PASS: name={name} description={len(desc)} chars")
'@
$py | uv run --with pyyaml python - (Join-Path $Dest 'SKILL.md')
if ($LASTEXITCODE -ne 0) { "FRONTMATTER GATE FAIL"; exit 1 }
"pack built at $Dest"
