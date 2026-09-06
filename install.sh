#!/usr/bin/env bash
# Copies each skill folder under ./skills/ into ~/.claude/skills/. Idempotent: existing folders are skipped (FORCE=1 to overwrite).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/skills"
dst="$HOME/.claude/skills"
mkdir -p "$dst"
n=0; skipped=()
for d in "$src"/*/; do
  name="$(basename "$d")"
  if [ -e "$dst/$name" ] && [ "${FORCE:-0}" != "1" ]; then skipped+=("$name"); continue; fi
  rm -rf "$dst/$name"
  cp -R "$d" "$dst/$name"
  n=$((n+1))
done
echo "Installed $n skill(s) into $dst"
if [ "${#skipped[@]}" -gt 0 ]; then echo "Skipped (already present, FORCE=1 to overwrite): ${skipped[*]}"; fi
