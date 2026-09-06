# Builds dist\<skill>.zip for every folder under .\skills\, with the skill folder as the ZIP root
# (the layout claude.ai / Cowork expect under Customize > Skills > Upload a skill).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$src = Join-Path $PSScriptRoot "skills"
$dist = Join-Path $PSScriptRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
foreach ($d in Get-ChildItem $src -Directory) {
  $zip = Join-Path $dist ($d.Name + ".zip")
  if (Test-Path $zip) { Remove-Item $zip }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($d.FullName, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
  Write-Host "built $zip"
}
