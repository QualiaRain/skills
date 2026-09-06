# Copies each skill folder under .\skills\ into ~/.claude/skills/. Idempotent: existing folders are skipped (use -Force to overwrite).
param([switch]$Force)
$src = Join-Path $PSScriptRoot "skills"
$dst = Join-Path $HOME ".claude\skills"
New-Item -ItemType Directory -Force $dst | Out-Null
$n = 0; $skipped = @()
foreach ($d in Get-ChildItem $src -Directory) {
  $target = Join-Path $dst $d.Name
  if ((Test-Path $target) -and -not $Force) { $skipped += $d.Name; continue }
  Copy-Item $d.FullName $target -Recurse -Force
  $n++
}
Write-Host "Installed $n skill(s) into $dst"
if ($skipped) { Write-Host "Skipped (already present, use -Force to overwrite): $($skipped -join ', ')" }
