---
name: bash-on-windows
description: >-
  Bash tool (Git Bash/MSYS2) on Windows: quoting and capture traps. It silently halves doubled backslashes, corrupting Windows paths, regex, and sed/grep patterns - read before ANY backslash or heredoc in a Bash command, a commit message with backticks or multiple lines, capturing gh/git output (cp1252 mojibake), or choosing Bash vs PowerShell.
---

# Bash tool on Windows — sharp edges

On Windows, Claude Code's Bash tool is Git Bash (MSYS2). If your Claude Code also has the dedicated **PowerShell tool** enabled, make that the default for Windows work — reach for Bash only when a task is genuinely POSIX-shaped (a pipeline of Unix text tools, an existing shell script). When you do use Bash, the traps below bite.

## The backslash-halving bug (the big one)

Claude Code's Bash tool has been measured to **silently halve runs of backslashes** in the `command` field before the shell ever sees it. This is a Claude Code preprocessing bug (issue #11225, closed not-planned; measured on Claude Code 2.1.x on Windows), not shell behavior.

**Check whether your install has it** (one Bash tool call):

```
printf '%s\n' 'a\\b'
```

Output `a\b` = the bug is active, follow this section. Output `a\\b` = your version/platform does not halve; the rest of this file still applies. Re-check after a Claude Code update.

### The exact rule (measured)

Method, repeatable if the harness changes: submit a **quoted** heredoc `<<'EOF'` (bash does no processing inside it) containing runs of 1–8 backslashes, and dump the bytes with `od -c`. Recorded input carried 1,2,3,4,5,6,7,8 backslashes; bash's stdin received **1,1,2,2,3,3,4,4**.

- **Every ADJACENT PAIR of backslashes collapses to one. N arrive as `ceil(N/2)`.** `2→1`, `3→2`, `4→2`, `8→4`. So doubling up to `\\\\` does NOT protect you — four arrive as two.
- **The character after the backslashes is irrelevant.** `\\n`, `\\Users`, `\\1` and `\\]` all halve. Only adjacency matters.
- **It applies everywhere in the command** — `python -c` args, `echo`/`grep`/`sed` strings, PowerShell content piped through, heredoc bodies — and **fires inside `<<'EOF'` and single quotes**, where the shell does nothing. `bash -c '...'` does **not** bypass it.
- **A LONE backslash is never touched.** `\n` `\t` `\r` `\x41` `\'` `\"` `\$` and a trailing `\` all arrive verbatim. Nothing is interpreted and no byte is substituted — the tool turns `\\n` into `\n`, and whatever reads it next does the interpreting. When debugging: the corruption is always one halving, never a translation.
- **Anything BEYOND `ceil(N/2)` is ordinary bash escaping, not this bug.** In double quotes or an *unquoted* heredoc, bash then eats a further layer (`\\`→`\`, `\$`→`$`). Measured: `"a\\\\b"` in the command field → tool halves to `a\\b` → double-quote rules → `a\b`.
- **The PowerShell tool and the Write tool do NOT do this.** Same 1–8 probe through PowerShell: all eight survived intact.

### Loud cases self-correct; the silent ones are a directive

When the halving breaks something it *usually* breaks **loudly**: `"\\Users"` becomes `\U`, a SyntaxError in a non-raw Python string, the command fails, you re-orient. Those are self-correcting — don't block over them.

**The directive is for the *silent* bucket — silent wrong data.** A `sed 's/\\n/X/g'` meant to match the two characters backslash-n silently becomes `s/\n/X/g` (matches a newline); a backslash echoed into a file just vanishes. No error, no failed exit code — just plausible-looking wrong output you will take as correct. **So BEFORE running any Bash command where a literal `\X` feeds sed/grep/awk, a non-raw string, or a file write: STOP and use the file route (below) — do NOT just fire it and check the exit code, because a 0 exit here means nothing.**

### Damage modes at a glance

- **Python (non-raw) — LOUD half:** `"\\Users"` → `\U` SyntaxError; `b"\\n"`, `re.compile("\\d+")` shift meaning or warn.
- **Python (non-raw) — SILENT half, and the one that actually costs time:** when the letter after the halved backslash forms a *valid* Python escape, there is no error at all — just wrong bytes. `'scripts\\auto_resume.py'` becomes `scripts\x07uto_resume.py` (BEL); `\\test` → tab, `\\new` → newline, `\\bin` → backspace. The corrupting letters are `a b f n r t v x u U N` and `0-7`; every other letter is inert and survives, so `'scripts\\hue_guard.py'` works perfectly **in the same command that silently mangles `\\auto_resume.py`**. That letter-dependence is the trap: the technique looks reliable because most paths happen to be fine. A string-match patch built this way does not throw — it just matches nothing, and a naive "0 rows changed" reads as "already done". **Assert the match count on every string patch, and prefer the Write-tool route for anything containing a Windows path.**
- **DATED paths — the same silent half, via the octal branch:** `0-7` are in the corrupting set, so a date folder is a live grenade. `'logs\\2026-08-18-meeting'` halves to `\2026-...`, Python reads `\202` as an octal escape, and you get `logs\x826-08-18-meeting`. No error. Every `logs\2026-*` or dated event folder is this shape, and a doc patched through one ships mangled paths that read fine in the diff. **A digit right after a backslash means Write-tool route, no exceptions.**
- **Windows paths in non-raw strings:** SyntaxError on `\U`, `\W`, etc.
- **sed/grep:** `s/\\n/X/g`, `\\d`, `\\b` quietly change what they match.
- **PowerShell-via-Bash:** literals with `\\Windows\\System32` get mangled.
- **Raw-string Windows paths** `r'C:\\Users\\...'` happen to survive because Windows tolerates consecutive backslashes — coincidence, not a guarantee.

### The fix

For any Bash command that needs a literal `\\X` to reach the shell, **write the script to a file with the Write tool, then execute the file.** The Write path preserves backslashes end-to-end; the Bash `command` field does not. For short, backslash-free one-offs, `python -c` and `printf` are fine.

**Don't:**

- Wrap with `bash -c` hoping to bypass — it doesn't.
- Double up to `\\\\X` to compensate — four arrive as two; you'll guess wrong.
- Assume a Python file passed via `-c` behaves "the same as" running it from disk — the `-c` arg goes through the same mangling; a file on disk doesn't.

- **Patching SOURCE CODE that contains string escapes is the same grenade, and it does not look like a path.** A patch adding `"...\n"` to a Python file halves to a real newline inside the literal, and the file dies with `SyntaxError: unterminated string literal` on a line you did not think you touched. **Any patch whose payload contains a backslash AT ALL — escape sequence, path, regex — goes in a `.py` file written with the Write tool, never a heredoc.**

- **A long PROSE/markdown document body goes in the Write tool, even with ZERO backslashes.** Every rule above keys on a backslash, so none of them fire on a doc that is all backticks, apostrophes and fenced code blocks — and that payload breaks the heredoc anyway (a `cat > doc.md <<'EOF'` of a long doc can die with "unexpected EOF while looking for matching quote"). If you are authoring a file's CONTENT, Write is the tool; Bash is for the file OPERATIONS around it (`ls`, `md5sum`, `git add`).

### The inline escape hatch: `chr(92)`, and no literal backslash at all

Route 1 is still the Write tool. But when the command genuinely must stay inline, there is a second route that works, and it is not "escape harder" — it is **put no literal backslash in the text at all, and build them at runtime.** The tool only transforms backslash characters; a `chr(92)` call contains none, so there is nothing to halve.

```
BS = chr(92)
needle = "launchers" + BS + BS + "RENDER"     # two literal backslashes
nl     = chr(10)                               # newline, never "\n" in a pattern
```

For regex, the same trick plus character classes: `"[" + BS + "]"` for a literal backslash, `chr(10)` for a newline, `"[0-9]"` instead of `\d`, `"[ " + chr(9) + "]"` instead of `\t`. A pattern with zero backslashes in the command text cannot be corrupted on the way in.

**Both routes are verifiable and the guessing route is not.** After route 2, assert the count — `assert n == expected` — because the whole failure class is a match that silently returns nothing.

### Two real failures, worked

Both happened in a session that had this skill available.

**Case 1 — the lucky one, because it threw.** Inside `python - <<'PYEOF'`, intending to count two literal backslashes in a file:

```
src.count('launchers\\\\RENDER')     # written: 4 backslashes
src.count('launchers\\RENDER')       # arrived: 2  -> ONE literal backslash
```

The file contains two, the needle had one, the count was 0, and an `assert` caught it. Correct version, no literal backslash anywhere:

```
BS = chr(92)
n = src.count("launchers" + BS + BS + "RENDER")
assert n > 0, "needle not found"
```

**Case 2 — THE DANGEROUS SHAPE. Read this one twice.** Inside another quoted heredoc, a regex meant to match a JSON-escaped newline — the two characters backslash and `n`:

```
re.findall(r'\\n- (...)', seg)       # written: 2 backslashes
re.findall(r'\n- (...)', seg)        # arrived: 1 -> regex \n -> a REAL newline
```

It returned **0 matches, no error, exit code 0.** Nothing threw, nothing warned, and "0 results" reads exactly like "there is nothing there". Case 1 cost a minute; case 2 is the one that ships a wrong conclusion into a durable record. Correct version:

```
pat = "[" + chr(92) + "]n- (.*)"     # literal backslash, then 'n'
hits = re.findall(pat, seg)
```

**The generalisation:** a backslash bug that RAISES is self-correcting and not worth much fear. A backslash bug that changes what a pattern MEANS produces a plausible empty result. Any command in this shape — a count, a `findall`, a `sed` substitution, a grep — must have its match count asserted, or must not go through Bash at all.

## `grep -i` with MULTIPLE `-e` patterns ABORTS — and returns a silent zero

Measured on the GNU grep 3.0 bundled with one Git for Windows install (`grep --version` to see yours; newer builds may not have this). Combining `-i` with **more than one `-e`** crashed the process (SIGABRT, `rc=134`, no output):

| form | result |
|---|---|
| `grep -ci -e A -e B` | **rc=134, aborts** |
| `grep -ci -e A -e B -e C` | **rc=134, aborts** |
| `grep -cil -e A -e B` | **rc=134, aborts** |
| `grep -ci -e A` (one pattern) | rc=0, works |
| `grep -c -e A -e B` (no `-i`) | rc=0, works |
| `grep -ciE "A|B"` | rc=0, works |

Pattern length and count do not matter; `-i` plus two or more `-e` is the whole trigger.

**Why this is a silent-wrong-answer bug, not a loud one.** The habitual form is `grep -ril -e foo -e bar . 2>/dev/null` — and `2>/dev/null` swallows the `Aborted` message. What you see is a command that exits with no output and no error, which reads *exactly* like an honest "no matches found". In one session this made a scan report "clean" and made a check of *this file* report a rule absent that was present in seven places — both caught only by reading the file directly.

**The fix: use `-E` with an alternation.** `grep -riE "foo|bar" .` is equivalent, `-i`-safe, and works on every grep.

**Do not redirect stderr on a multi-pattern grep.** If you must keep `-e`, drop `2>/dev/null` so the abort is visible, and check the exit code — `rc=134` means the search never ran. General rule: "0 results with no error" is not proof that nothing exists.

## Quoting and capture traps

These are the same class of problem as the backslash bug — text corrupted on its way through a shell or a tool argument — and they fire on ordinary work, not just exotic commands.

### Backticks and `$` inside a double-quoted bash string EXECUTE

A backtick is command substitution and `$VAR` is expansion, so this is not literal text:

```
git commit -m "fix the `--force` flag handling in $BUILD_DIR"     # WRONG
```

Bash tries to run `--force` as a command and expand `$BUILD_DIR`, and you get a confusing `unexpected EOF while looking for matching backquote` or a silently empty substitution. This recurs constantly because prose *about code* naturally carries backticks and dollar signs — commit messages most of all.

**Never build multi-line or code-mentioning text with `-m "..."`.** Two safe routes:

- **`git commit -F <file>`** — write the message with the Write tool first, then point at it. This is the default for anything longer than a single plain sentence.
- **A QUOTED heredoc** — `<<'EOF'`, with the quotes mandatory. A bare `<<EOF` still substitutes and puts you right back in the trap.

The same trap lives in any `bash -c "…"` wrapper, so the rule is about the double quotes, not about git.

**The inverse bite: a Windows path ending in `\$var` does NOT expand.** In double quotes `\$` is an escaped literal dollar, so a loop written as

```
for d in a b; do prog "C:\Users\<you>\logs\$d"; done     # WRONG — every iteration gets a path ending in the literal "$d"
```

runs twice against the same nonexistent path. Both iterations fail instantly, **and the loop still exits 0** — a `for` loop reports the status of its LAST command (a trailing `echo`), so a background-task notification says success. Silent no-op, reported as done. Use forward slashes and a variable for the base (`base="C:/Users/<you>/logs"; prog "$base/$d"`), and when a background loop's result matters, `|| rc=1` per iteration plus `exit $rc`, then READ the output file rather than the exit code.

### Literal control characters in tool-call arguments

A control character, a literal newline, a literal tab, or a raw backslash escape inside ANY tool-call string argument is fragile — it may be normalized, halved (see the backslash bug above), or silently dropped before the tool sees it. Write them as escapes instead (`\n`, `\t`, `\uXXXX`), and verify the result after writing rather than assuming it landed.

### Capturing gh/git output: the cp1252 mojibake trap

When Python or any other tool **captures** the output of `gh` or `git` on Windows, never let it decode as the Windows default cp1252 — it silently mojibakes UTF-8 (an em dash becomes `â€"`). `subprocess.run(..., text=True)` with no `encoding=` is exactly this trap and is the common way in.

Capture **bytes** and `.decode('utf-8')`, or set `encoding='utf-8'` / `PYTHONUTF8=1` explicitly.

**Never round-trip fetched content through a misdecode before writing it back to an outward-facing place.** Fetch → misdecode → post has shipped corruption to live upstream GitHub content. For that specific case use the `gh-safe-comment-edit` skill (in this pack), which handles both the mojibake and the CRLF-doubling corruption and does a round-trip verify.

### `nohup cmd &` backgrounds NOTHING — and reports success

The Bash tool's wrapper shell exits as soon as the command returns, and the
detached job's process group goes with it. A `nohup long_job ... & echo started`
therefore dies partway through **and the tool reports exit code 0**, so a
half-finished job and a clean one are identical from the status alone
(measured: a 67-item render died at item 6, exit 0).

Use the tool's own `run_in_background` parameter, which the harness actually
tracks and notifies on. And whatever you use, **verify a long job by its OUTPUT
— the log, the artifact, a count — never by its exit status.** This is the
mirror of the `-u` trap (a healthy hidden job that looks dead because its log
is empty): here a dead job looks healthy.

## Git Bash interop friction

Even setting the backslash bug aside, Git Bash is an MSYS layer over Windows, so:

- **Paths are `/c/Users/...` mounts**, not native `C:\` paths — native Windows paths don't work as arguments without translation.
- **...and the reverse bites SILENTLY: a `/c/Users/...` path handed to a native Windows `.exe` does not resolve.** `python script.py /c/Users/...` sees a path that `os.path.exists()` calls False, so a well-written program takes its "file missing" branch and exits 0 with no output — which reads exactly like the program being broken. **When a bash command passes a path to python/node/any `.exe`, write it `C:/Users/...` (forward slashes, drive letter).** That form works in Git Bash builtins, MSYS coreutils, and native Windows programs alike, so it is the safe default everywhere.
- **Windows-native queries** (CIM/WMI, the registry, services, .NET) aren't reachable directly — you shell out to `reg.exe`, `wmic.exe`, etc. and parse text.

The PowerShell tool (or `pwsh`) does all of that in-process with native paths and objects (`Get-CimInstance`, `HKLM:\...`), and has no backslash-halving issue. So for anything Windows-native, prefer PowerShell, and keep Bash for the POSIX-shaped tasks where its tooling is the natural fit.

## Guard hooks for this bug (none ship with this pack)

Nothing in this pack repairs or blocks a mangled command. The defense is the rules above: forward-slash `C:/…` paths, the Write-tool route, `chr(92)`, and asserted match counts. If you want a hook (see `hook-engineering`, in this pack), these designs were tried:

- **A WARNER (worked well).** A `PreToolUse` hook on `Bash` that fires only when the command contains a run of two or more adjacent backslashes — the exact and only condition under which the transform bites — and emits the `ceil(N/2)` rule, the `chr(92)` recipe and the write-a-file route via `additionalContext`. It never blocks (no `permissionDecision`), stays silent on lone backslashes (`find … \;`, `grep '\.py'`), and gives the full recipe once per session with a one-line reminder after, because `additionalContext` is re-billed on every later turn.
- **A BLOCKER (retired).** Denying any backslash-before-alphanumeric just traded a silent mangle for a hard stop on legitimate work. Don't rebuild it.
- **An AUTO-REPAIR for drive-letter paths (worked, later removed).** Rewrote `\` → `/` inside `C:\…` tokens via `hookSpecificOutput.updatedInput`. It never fixed the regex/escape/sed cases. **Config gotcha if you rebuild one** (observed on Claude Code 2.1.159; a later version may fix it): emit `updatedInput` with **NO `permissionDecision` field**. Emitting `permissionDecision: "defer"` alongside `updatedInput` made the harness throw `"[Tool result missing due to internal error]"` and abort the whole turn. Omitting the field lets the rewritten command go through normal permissions. **Never** use `"allow"` — it bypasses permission checks.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
