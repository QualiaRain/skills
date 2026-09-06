#!/usr/bin/env bash
# Builds dist/<skill>.zip for every folder under ./skills/, with the skill folder as the ZIP root
# (the layout claude.ai / Cowork expect under Customize > Skills > Upload a skill).
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$root/dist"
for d in "$root"/skills/*/; do
  name="$(basename "$d")"
  rm -f "$root/dist/$name.zip"
  (cd "$root/skills" && zip -qr "$root/dist/$name.zip" "$name" -x '*/__pycache__/*')
  echo "built dist/$name.zip"
done
