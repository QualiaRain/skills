---
name: bash-on-windows
description: >-
  Bash tool (Git Bash/MSYS2) on Windows: quoting and capture traps. It silently halves doubled backslashes, corrupting Windows paths, regex, and sed/grep patterns - read before ANY backslash or heredoc in a Bash command, a commit message with backticks or multiple lines, capturing gh/git output (cp1252 mojibake), or choosing Bash vs PowerShell.
---

# Bash tool on Windows — sharp edges

This machine is Windows 11; the Bash tool here is Git Bash (MSYS2, bash 5.2). The dedicated **PowerShell tool (`pwsh` 7.6.2) is the default** for most work on this machine — reach for Bash only when a task is genuinely POSIX-shaped (a pipeline of Unix text tools, an existing shell script). When you do use Bash, two things bite.

## The backslash-halving bug (the big one)

Claude Code's Bash tool **silently halves `\\X`** (X alphanumeric) anywhere in the `command` field — `\\n`, `\\t`, `\\d`, `\\Users`, `\\Windows`, `\\1`, etc. — to `\X` before the shell ever sees it. This is a Claude Code preprocessor bug (issue #11225, closed not-planned; reconfirmed 2026-05-16 on CC 2.1.128), not shell behavior, so:

- It applies **everywhere** in the command — `python -c` args, `echo`/`grep`/`sed` strings, PowerShell content piped through, all of it. Not just heredoc bodies.
- `bash -c '...'` does **NOT** bypass it.
- Runs of `\\\\` (four consecutive backslashes between non-backslash chars) are preserved — but the rule is shape-dependent, so don't lean on it.

### CORRECTION — the exact rule, measured 2026-08-28

The three bullets above are right that it happens and right that you cannot quote your way out of it. Two of their details are **wrong**, and both wrong details are the kind that make you guess a workaround and get it wrong. The measurement supersedes them; the original text stays above so the correction is auditable.

**Method** (repeatable, and worth repeating if the harness ever changes): submit a command whose body is a **quoted** heredoc `<<'EOF'`, inside which bash performs no processing of any kind, containing runs of 1–8 backslashes, and dump the bytes with `od -c`. Then read that same call's recorded `tool_input.command` back out of the session transcript. Recorded input carried 1,2,3,4,5,6,7,8 backslashes. Bash's stdin received **1,1,2,2,3,3,4,4**.

- **The rule is: every ADJACENT PAIR of backslashes collapses to one. N arrive as `ceil(N/2)`.** `2→1`, `3→2`, `4→2`, `8→4`.
- **`\\\\` is NOT preserved.** Four arrive as two. The "shape-dependent, don't lean on it" bullet was right to distrust it and wrong about the value.
- **It is not keyed to `\\X` with X alphanumeric.** `\\]` halves too. X is irrelevant; only adjacency matters.
- **A LONE backslash is never touched.** `\n` `\t` `\r` `\x41` `\'` `\"` `\$` and a trailing `\` all arrive verbatim. **Nothing is interpreted and no byte is substituted** — the tool does not turn `\n` into a newline, it turns `\\n` into `\n`, and whatever reads it next does the interpreting. That distinction matters when you are debugging: the corruption is always one halving, never a translation.
- **It fires inside `<<'EOF'` and inside single quotes**, where the shell does nothing at all. That is what proves it is a tool-layer transform rather than shell semantics.
- **Anything BEYOND `ceil(N/2)` is ordinary bash escaping, not this bug.** In double quotes or an *unquoted* heredoc, bash then eats a further layer (`\\`→`\`, `\$`→`$`). Measured: `"a\\\\b"` in the command field → tool halves to `a\\b` → double-quote rules → `a\b`. Normal, documented shell behaviour stacked on top of the tool defect. Don't file it as the same thing.
- **The PowerShell tool does NOT do this.** Same 1–8 probe, all eight runs survived intact. If you need literal backslashes through a shell, that is the shell.

### Loud cases self-correct; the silent ones are a directive

When the halving breaks something it *usually* breaks **loudly**: `"\\Users"` becomes `\U`, a SyntaxError in a non-raw Python string, the command fails, you re-orient. Those are self-correcting — don't block over them.

**The directive is for the *silent* bucket — silent wrong data.** A `sed 's/\\n/X/g'` meant to match the two characters backslash-n silently becomes `s/\n/X/g` (matches a newline); a backslash echoed into a file just vanishes. No error, no failed exit code — just plausible-looking wrong output you will take as correct. **So BEFORE running any Bash command where a literal `\X` feeds sed/grep/awk, a non-raw string, or a file write: STOP and use the file route (below) — do NOT just fire it and check the exit code, because a 0 exit here means nothing.** This is the one Bash gotcha that yields a silent false success — the failure you cannot catch after the fact.

### Damage modes at a glance

- **Python (non-raw) — LOUD half:** `"\\Users"` → `\U` SyntaxError; `b"\\n"`, `re.compile("\\d+")` shift meaning or warn.
- **Python (non-raw) — SILENT half, and the one that actually costs time:** when the letter after the halved backslash forms a *valid* Python escape, there is no error at all — just wrong bytes. `'scripts\\auto_resume.py'` becomes `scripts\x07uto_resume.py` (BEL); `\\test` → tab, `\\new` → newline, `\\bin` → backspace. The corrupting letters are `a b f n r t v x u U N` and `0-7`; every other letter is inert and survives, so `'scripts\\hue_guard.py'` works perfectly **in the same command that silently mangles `\\auto_resume.py`**. That letter-dependence is the trap: the technique looks reliable because most paths happen to be fine. A string-match patch built this way does not throw — it just matches nothing, and a naive "0 rows changed" reads as "already done". **Assert the match count on every string patch, and prefer the Write-tool route for anything containing a Windows path.** (Receipt: 2026-08-09, two failed `.ps1` patches in the B project; the Write-tool rewrite of the same edit worked first try.)
- **DATED paths — the same silent half, via the octal branch, and the shape this workspace hits most:** `0-7` are in the corrupting set, so a date folder is a live grenade. `'3z\\call-logs\\2026-08-18-ai-office-hours'` halves to `\2026-...`, Python reads `\202` as an octal escape, and you get `3z\call-logs\x826-08-18-ai-office-hours`. No error. Every `logs\2026-*`, every dated event folder, every `Z:\Work\...\2026-07-30` is this shape, and a doc patched through one ships mangled paths that read fine in the diff. `\3z` does it too (`\3` → `\x03`). **A date or a digit right after a backslash means Write-tool route, no exceptions.** (Receipt: 2026-08-21, a `python - <<'PY'` heredoc patching a client reconciliation doc corrupted all three of its Windows paths; the Write-a-.py-file rewrite fixed them first try.)
- **Windows paths in non-raw strings:** SyntaxError on `\U`, `\W`, etc.
- **sed/grep:** `s/\\n/X/g`, `\\d`, `\\b` quietly change what they match.
- **PowerShell-via-Bash:** literals with `\\Windows\\System32` get mangled.
- **Raw-string Windows paths** `r'C:\\Users\\...'` happen to survive because Windows collapses consecutive backslashes — coincidence, not a guarantee.

### The fix

For any Bash command that needs a literal `\\X` to reach the shell, **write the script to a file with the Write tool, then execute the file.** The Write path preserves backslashes end-to-end; the Bash `command` field does not. For short, escape-free one-offs, `python -c` and `printf` are fine.

**Don't:**

- Wrap with `bash -c` hoping to bypass — it doesn't.
- Double up to `\\\\X` to compensate — the preservation rule is fragile and shape-dependent; you'll guess wrong.
- Assume a Python file passed via `-c` behaves "the same as" running it from disk — the `-c` arg goes through the same mangling; a file on disk doesn't.

- **Patching SOURCE CODE that contains string escapes is the same grenade, and it does not look like a path.** A patch adding `"...\n"` to a Python file halves to a real newline inside the literal, and the file dies with `SyntaxError: unterminated string literal` on a line you did not think you touched. **Any patch whose payload contains a backslash AT ALL — escape sequence, path, regex — goes in a `.py` file written with the Write tool, never a heredoc.** (Receipt: 2026-08-21, third chat running to hit this; a heredoc patch broke a 3,000-line source file, and the Write-a-file rewrite worked first try. The path-shaped rule above was already here and did not fire, because the payload was `\n`, not a folder name.)

- **A long PROSE/markdown document body goes in the Write tool, even with ZERO backslashes.** Every rule above keys on a backslash, so none of them fire on a doc that is all backticks, apostrophes and fenced code blocks — and that payload breaks the heredoc anyway. If you are authoring a file's CONTENT, Write is the tool; Bash is for the file OPERATIONS around it (`ls`, `md5sum`, `git add`). Auto-mode's "prefer Bash for file changes" means edits and moves, not composing a document. (Receipt: 2026-08-21, a `cat > pack.md <<'EOF'` writing a deliverable pack died with "unexpected EOF while looking for matching quote"; the Write-tool rewrite worked first try. Zero backslashes in the payload, so every existing rule here stayed silent.)

### The inline escape hatch: `chr(92)`, and no literal backslash at all

Route 1 is still the Write tool. But when the command genuinely must stay inline, there is a second route that works, and it is not "escape harder" — it is **put no literal backslash in the text at all, and build them at runtime.** The tool only transforms backslash characters; a `chr(92)` call contains none, so there is nothing to halve.

```
BS = chr(92)
needle = "launchers" + BS + BS + "RENDER"     # two literal backslashes
nl     = chr(10)                               # newline, never "\n" in a pattern
```

For regex, the same trick plus character classes: `"[" + BS + "]"` for a literal backslash, `chr(10)` for a newline, `"[0-9]"` instead of `\d`, `"[ " + chr(9) + "]"` instead of `\t`. A pattern with zero backslashes in the command text cannot be corrupted on the way in.

**Both routes are verifiable and the guessing route is not.** After route 2, assert the count — `assert n == expected` — because the whole failure class is a match that silently returns nothing.

### The two 2026-08-28 failures, worked

Both were committed by a session that **had this skill available** and still walked in, ten minutes apart. That is why there is now a hook (below) and not just this paragraph.

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

Past damage from this bug is catalogued at `~/.claude/plans/heredoc-bug-audit.md`.

## `grep -i` with MULTIPLE `-e` patterns ABORTS — and returns a silent zero

`grep` here is GNU grep 3.0 (MSYS2). Combining `-i` with **more than one `-e`** crashes the process (SIGABRT, `rc=134`, no output). Measured 2026-08-25, every combination:

| form | result |
|---|---|
| `grep -ci -e A -e B` | **rc=134, aborts** |
| `grep -ci -e A -e B -e C` | **rc=134, aborts** |
| `grep -cil -e A -e B` | **rc=134, aborts** |
| `grep -ci -e A` (one pattern) | rc=0, works |
| `grep -c -e A -e B` (no `-i`) | rc=0, works |
| `grep -ciE "A|B"` | rc=0, works |

Pattern length and count do not matter; `-i` plus two or more `-e` is the whole trigger.

**Why this is a silent-wrong-answer bug, not a loud one.** The habitual form is `grep -ril -e foo -e bar . 2>/dev/null` — and `2>/dev/null` swallows the `Aborted` message. What you see is a command that exits with no output and no error, which reads *exactly* like an honest "no matches found". Nothing about it looks like a crash, so the false negative propagates straight into a conclusion.

**The fix: use `-E` with an alternation.** `grep -riE "foo|bar" .` is equivalent, `-i`-safe, and one character shorter.

**Do not redirect stderr on a multi-pattern grep.** If you must keep `-e`, drop `2>/dev/null` so the abort is visible, and check the exit code — `rc=134` means the search never ran.

(Receipt: 2026-08-25, one session hit this twice. A `grep -ril -e bambi -e lovense ...` scan of the Notion mirror reported clean, and a `grep -i -e heredoc -e "Write tool"` check of *this file* reported the heredoc rule absent when it was present in seven places — nearly producing a duplicate edit to a skill that already had the rule. Both were caught only by reading the file directly. The generic ISSUE-WATCH line "0 results with no error is not nothing exists" is the class; this is the specific mechanism on this machine.)

## Quoting and capture traps

Moved here from `~/.claude/CLAUDE.md` 2026-08-20. These are the same class of problem as the backslash bug — text corrupted on its way through a shell or a tool argument — and they fire on ordinary work, not just exotic commands.

### Backticks and `$` inside a double-quoted bash string EXECUTE

A backtick is command substitution and `$VAR` is expansion, so this is not literal text:

```
git commit -m "fix the `--force` flag handling in $BUILD_DIR"     # WRONG
```

Bash tries to run `--force` as a command and expand `$BUILD_DIR`, and you get a confusing `unexpected EOF while looking for matching backquote` or a silently empty substitution. This recurs constantly because prose *about code* naturally carries backticks and dollar signs — commit messages most of all. It bit repeatedly through 2026-08-07.

**Never build multi-line or code-mentioning text with `-m "..."`.** Two safe routes:

- **`git commit -F <file>`** — write the message with the Write tool first, then point at it. This is the default for anything longer than a single plain sentence.
- **A QUOTED heredoc** — `<<'EOF'`, with the quotes mandatory. A bare `<<EOF` still substitutes and puts you right back in the trap.

The same trap lives in any `bash -c "…"` wrapper, so the rule is about the double quotes, not about git.

**The inverse bite, 2026-08-29: a Windows path ending in `\$var` does NOT expand.** In double quotes `\$` is an escaped literal dollar, so a loop written as

```
for d in a b; do prog "C:\Users\<you>\Claude\call-logs\$d"; done     # WRONG — every iteration gets a path ending in the literal "$d"
```

runs twice against the same nonexistent path. Both iterations failed instantly, **and the loop still exited 0** — a `for` loop reports the status of its LAST command (a trailing `echo`), so the harness's background-task notification said success. Silent no-op, reported as done. Use forward slashes and a variable for the base (`base="C:/Users/.../call-logs"; prog "$base/$d"`), and when a background loop's result matters, `|| rc=1` per iteration plus `exit $rc`, then READ the output file rather than the exit code.

### Literal control characters in tool-call arguments

A control character, a literal newline, a literal tab, or a raw backslash escape inside ANY tool-call string argument is fragile — it may be normalized, halved (see the backslash bug above), or silently dropped before the tool sees it. Write them as escapes instead (`\n`, `\t`, `\uXXXX`), and verify the result after writing rather than assuming it landed.

### Capturing gh/git output: the cp1252 mojibake trap

When Python or any other tool **captures** the output of `gh` or `git` on this machine, never let it decode as the Windows default cp1252 — it silently mojibakes UTF-8 (an em dash becomes `â€"`). `subprocess.run(..., text=True)` with no `encoding=` is exactly this trap and is the common way in.

Capture **bytes** and `.decode('utf-8')`, or set `encoding='utf-8'` / `PYTHONUTF8=1` explicitly.

**Never round-trip fetched content through a misdecode before writing it back to an outward-facing place.** Fetch → misdecode → post has shipped corruption to live upstream GitHub content twice from this machine. For that specific case use the `gh-safe-comment-edit` skill, which handles both the mojibake and the CRLF-doubling corruption and does a round-trip verify.

### `nohup cmd &` backgrounds NOTHING — and reports success

The Bash tool's wrapper shell exits as soon as the command returns, and the
detached job's process group goes with it. A `nohup long_job ... & echo started`
therefore dies partway through **and the tool reports exit code 0**, so a
half-finished job and a clean one are identical from the status alone.
Measured 2026-08-21: a 67-item render died at item 6, exit 0.

Use the tool's own `run_in_background` parameter, which the harness actually
tracks and notifies on. And whatever you use, **verify a long job by its OUTPUT
— the log, the artifact, a count — never by its exit status.** This is the
mirror of the `-u` trap (a healthy hidden job that looks dead because its log
is empty): here a dead job looks healthy.

## Git Bash interop friction

Even setting the backslash bug aside, Git Bash is an MSYS layer over Windows, so:

- **Paths are `/c/Users/...` mounts**, not native `C:\` paths — native Windows paths don't work as arguments without translation.
- **...and the reverse bites SILENTLY: a `/c/Users/...` path handed to a native Windows `.exe` does not resolve.** `python script.py /c/Users/...` sees a path that `os.path.exists()` calls False, so a well-written program takes its "file missing" branch and exits 0 with no output — which reads exactly like the program being broken. Bit 2026-08-21 while testing a hook: the hook printed nothing and looked defective; it had correctly gone silent on a transcript it could not open. **When a bash command passes a path to python/node/any `.exe`, write it `C:/Users/...` (forward slashes, drive letter).** That form works in Git Bash builtins, MSYS coreutils, and native Windows programs alike, so it is the safe default everywhere.
- **Windows-native queries** (CIM/WMI, the registry, services, .NET) aren't reachable directly — you shell out to `reg.exe`, `wmic.exe`, etc. and parse text.

The dedicated PowerShell tool does all of that in-process with native paths and objects (`Get-CimInstance`, `HKLM:\...`), and has no backslash-halving issue. So for anything Windows-native — which is most work on this machine — prefer PowerShell, and keep Bash for the POSIX-shaped tasks where its tooling is the natural fit.

## Guard hooks for this bug

### LIVE since 2026-08-28 — `bash-backslash-guard.py`, a WARNER. Read the name carefully.

**A hook now fires on this.** `~/.claude/hooks/bash-backslash-guard.py` is wired in the `PreToolUse` chain (between `claude-md-accretion-gate.py` and `context-router.py`). On any **Bash** command containing a run of two or more adjacent backslashes — the exact and only condition under which the transform bites — it emits the `ceil(N/2)` rule, the `chr(92)` recipe and the write-a-file route, on both channels (`additionalContext` so the session sees it, `systemMessage` so the owner does).

- **It WARNS, it never blocks.** No `permissionDecision`, ever. A false positive that stops legitimate work is worse than the bug.
- **Silent on lone backslashes** (`find … \;`, `grep '\.py'`, `sed 's/\./x/'`), which measurably survive intact, and silent on the PowerShell and Write tools, which do not have the defect.
- Full recipe on the first hit of a session, one-line reminder after — `additionalContext` is re-billed on every later call, so a long block firing repeatedly costs more than the prose it replaced.
- Tests: `~/.claude/hooks/test_bash_backslash_guard.py`, 26 cases, driving the real subprocess. Proven firing on a **live** Bash call the day it was written, not just in the test harness.

**NAME COLLISION, and it will mislead you.** A *different* hook with this *same filename* was retired in 2026-06 for blocking — see the last paragraph of this section. If you find a note saying `bash-backslash-guard.py` was retired as a bad idea, it is talking about the blocking one. This is not that hook; the whole design difference is warn-vs-block.

### The path-repair guards — still all retired. Nothing repairs a path today.

The warner above tells you the command is about to be mangled. **It does not fix anything**, and nothing else does either: the halving still happens on the very call it warns about. Everything below stands.

**No hook protects Bash paths on this machine.** Every guard described below is gone from `~/.claude/hooks/` (verified absent 2026-07-28: no `bash-winpath-guard.py`, no `d-drive-guard.py`, no `bash-backslash-guard.py`). `settings.json` wires exactly one `PreToolUse` hook, `privacy-fence.py`, which does not touch paths. *(Two corrections, 2026-08-28: the `PreToolUse` chain is now six hooks, not one — `privacy-fence`, `permission-gate`, `notion-destructive-gate`, `claude-md-accretion-gate`, `bash-backslash-guard`, `context-router`; and a `bash-backslash-guard.py` exists again, as the WARNER described above. Neither changes the sentence that matters: still nothing REPAIRS a path.)* **Write `C:/…` with forward slashes yourself, and prefer PowerShell for Windows-native work** — that is now the whole defense.

**RETIRED — `bash-winpath-guard.py` (auto-repair; wired 2026-06-03, removed from live 2026-06-23, commit `f98cd70`).** A `PreToolUse` hook (matcher `Bash`) that *repaired* a Windows drive-letter path in a Bash command **in place**: inside a `C:\…` token it swapped `\` → `/` (so `cd C:\Users\me` actually ran as `cd C:/Users/me`) via `hookSpecificOutput.updatedInput`, with **no** `permissionDecision` so the normal permission flow still decided (never auto-approved). Forward slashes dodge both corruption layers (the tool's `\\`-halving and bash's `\X`-eating), and Git Bash builtins, MSYS coreutils, and Windows `.exe`s all accept `C:/…`. It only touched drive-letter paths — `\d`/`\n`, sed/grep patterns, escaped spaces were NOT rewritten. Its battery `test_bash-winpath-guard.py` was 23/23 green at the time; **both files are gone, so that result cannot be replayed** — do not cite it as current evidence.

**RETIRED — `d-drive-guard.py` (removed from live 2026-06-23, commit `f98cd70`).** The winpath guard used to hand the off-limits drive to this hook. **No HOOK guards `D:` today, but the deny list still covers part of it:** `settings.json:441-445` denies `Read(D:/**)`, `Edit(D:/**)`, `Bash(cd D:*)` and `Bash(pushd D:*)`. What is NOT covered is the command-string vector, a `D:` path inside any other shell command (`cat D:/x`, `Get-Content D:\x`, an `xperf` target), which is exactly what `f98cd70`'s own commit message flagged as newly unguarded when it removed the hook. So the file-tool and `cd` forms fail mechanically; every other form is enforced **by instruction only**. Treat the hard rule in the global `CLAUDE.md` ("never read or write the `D:` drive") as absolute regardless, and do not assume the deny list will catch the command form. (Corrected 2026-07-28: this paragraph previously claimed no mechanical guard existed at all.)

**CRITICAL config gotcha, kept for whoever rebuilds it (cost a chat to find — 2026-06-03, CC 2.1.159).** Such a hook MUST emit `updatedInput` with **NO `permissionDecision` field**. Emitting `permissionDecision: "defer"` alongside `updatedInput` makes the harness throw `"[Tool result missing due to internal error]"` and **abort the entire turn** on every drive-path Bash call (you must send a fresh message to resume) — far worse than the mangle it fixes. Omitting the field is documented-equivalent to `defer` (the rewritten command still goes through normal permissions). **Never** use `"allow"` (it bypasses permission checks). The `EMIT_PERMISSION_DECISION = ""` constant in the hook spells out all three states. A later CC version may fix the `defer` abort, but a working `""` needs no change.

**There is no safety net now.** Even when the auto-repair hook was live it never fixed the non-path backslash cases above (regex/escape/sed). With it retired, the `C:\…` foot-gun is unguarded too, so **PowerShell is the default for Windows-native work** and forward slashes are mandatory when you do reach for Bash.

**Retired — `bash-backslash-guard.py` (BLOCK variant; unwired 2026-05-27, deleted 2026-06-10). Not the live warner of the same name — see the top of this section.** An older `PreToolUse` hook that *blocked* any backslash-before-alphanumeric — retired because a hard block just trades a silent mangle for a hard stop (the auto-repair hook is the better answer for the path subset). The file is gone from disk; do NOT wire it expecting it to work. If the silent-data (sed/grep) subset ever recurs, recover it via `git -C ~/.claude show 966f609^:hooks/bash-backslash-guard.py`.

