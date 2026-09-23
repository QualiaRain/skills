#!/usr/bin/env python3
"""Lint the skill pack. No dependencies; exits 1 on any error.

Checks, per skills/<name>/SKILL.md:
  - frontmatter present, `name` matches the folder, `description` 1..1024 chars
  - the frontmatter description names no skill that is missing from this pack
  - body mentions of an unshipped skill carry "(not included in this pack)"
  - relative links to bundled files resolve
  - bundled Python / shell / JS scripts pass a syntax check (when the tool exists)
And pack-wide: README skill count and the issue-template dropdown match the folders.

Usage: python3 validate.py
"""
import json, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SKILLS = os.path.join(ROOT, "skills")
# Skill names the author has but this pack does not ship. Add to this list when a skill
# body starts pointing at a new one; the check then enforces the inline marker.
KNOWN_UNSHIPPED = {
    "game-perf-tuning-windows", "windows-audio-endpoints", "whispr-transcribe",
    "delegated-scan-scoping", "pace-check", "efficient-bug-hunt", "git-checkpoint-discipline",
    "security-review-local", "ai-authorship-disclosure", "private-systems-protocol", "handoff",
    "orchestrator-delegation-model",
}
MARKER = "(not included in this pack)"

errors = []


def err(where, msg):
    errors.append(f"{where}: {msg}")


def frontmatter(text):
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    if not m:
        return None, text
    fm, fields, key = m.group(1), {}, None
    for line in fm.splitlines():
        km = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if km:
            key, val = km.group(1), km.group(2).strip()
            fields[key] = "" if val in (">-", ">", "|", "|-") else val.strip('"').strip("'")
        elif key:
            fields[key] = (fields[key] + " " + line.strip()).strip()
    return fields, text[m.end():]


names = sorted(d for d in os.listdir(SKILLS) if os.path.isfile(os.path.join(SKILLS, d, "SKILL.md")))
_alt = "|".join(map(re.escape, sorted(KNOWN_UNSHIPPED)))
unshipped_re = re.compile(r"\b(" + _alt + r")\b")
# In bodies only a backticked name counts as a skill pointer ("handoff" is also an English word).
unshipped_ref_re = re.compile(r"`(" + _alt + r")`")

for name in names:
    folder = os.path.join(SKILLS, name)
    where = f"skills/{name}/SKILL.md"
    text = open(os.path.join(folder, "SKILL.md"), encoding="utf-8").read()
    fm, body = frontmatter(text)
    if fm is None:
        err(where, "missing YAML frontmatter")
        continue
    if fm.get("name") != name:
        err(where, f"name {fm.get('name')!r} does not match folder {name!r}")
    desc = fm.get("description", "")
    if not desc:
        err(where, "empty description")
    elif len(desc) > 1024:
        err(where, f"description is {len(desc)} chars (max 1024)")
    for m in unshipped_re.finditer(desc):
        err(where, f"description names unshipped skill {m.group(1)!r}")
    offset = text[: len(text) - len(body)].count("\n")
    for i, line in enumerate(body.splitlines(), offset + 1):
        for m in unshipped_ref_re.finditer(line):
            tail = line[m.end():m.end() + len(MARKER) + 2]
            if MARKER not in tail:
                err(f"{where}:{i}", f"{m.group(1)!r} lacks {MARKER!r}")
    for target in re.findall(r"\]\(([^)#\s]+)\)", body):
        if re.match(r"^[a-z]+:", target):
            continue
        if not os.path.exists(os.path.join(folder, target)):
            err(where, f"broken relative link {target!r}")

    for dirpath, _, files in os.walk(folder):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ROOT)
            cmd = None
            if f.endswith(".py"):
                cmd = [sys.executable, "-c", "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())", p]
            elif f.endswith(".sh") and shutil.which("bash"):
                cmd = ["bash", "-n", p]
            elif f.endswith(".js") and shutil.which("node"):
                cmd = ["node", "--check", p]
            elif f.endswith(".json"):
                try:
                    json.load(open(p, encoding="utf-8"))
                except ValueError as e:
                    err(rel, f"invalid JSON: {e}")
            if cmd:
                r = subprocess.run(cmd, capture_output=True, text=True)
                if r.returncode:
                    err(rel, "syntax check failed: " + (r.stderr or r.stdout).strip().splitlines()[-1])

readme = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
for n in re.findall(r"\b(\d+) (?:Claude Code )?skills\b", readme):
    if int(n) != len(names):
        err("README.md", f"says {n} skills, pack has {len(names)}")
for name in names:
    if f"`{name}`" not in readme:
        err("README.md", f"skill {name!r} not listed")

tmpl = os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", "skill-report.yml")
if os.path.exists(tmpl):
    m = re.search(r"options:\s*\[(.*?)\]", open(tmpl, encoding="utf-8").read())
    listed = {o.strip() for o in m.group(1).split(",")} if m else set()
    for name in names:
        if name not in listed:
            err(".github/ISSUE_TEMPLATE/skill-report.yml", f"dropdown missing {name!r}")

if errors:
    print("\n".join(errors))
    print(f"\n{len(errors)} problem(s) in {len(names)} skills.")
    sys.exit(1)
print(f"OK: {len(names)} skills valid.")
