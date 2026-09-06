---
name: llm-legible-project-docs
description: >-
  Reference for structuring code projects and writing project docs - and any instruction or warning surface - so fast, cheap inference reads them correctly and ACTS on them. Use when scaffolding a project, writing or extending a CLAUDE.md, deciding where a new file belongs, debugging why a Haiku session misread the structure, or authoring any SKILL.md.
---

# LLM-legible project structure and CLAUDE.md as a validated index

Two complementary patterns: (1) structure code projects to match training-data priors so fast inference's default guesses are correct, and (2) write project docs as a validated index that doesn't claim what hasn't been verified. Both are needed — the structure rule prevents one class of hallucination, the index rule prevents another.

## Project layouts for LLM legibility — match the training-data prior

Smaller / faster models (Haiku, fast inference paths) pattern-match against training-data conventions far more than they reason from documentation. A convention-following project gets *correct default guesses*; a deviating one gets *plausible-but-wrong* guesses that only careful verification recovers — and fast sessions often skip it. **The cheapest way to reduce hallucination is to make the model's default guess correct, not to add more warnings against guessing.** Structural complement to "don't guess beyond the validated summary": that rule prevents guessing when verification is feasible; this makes guesses correct when guessing happens anyway.

**Practical implications when designing or scaffolding any code project:**

- **File layout follows framework conventions.** Flask: `static/`, `templates/`, `routes/`. Python packages: `src/`, `tests/`, `pyproject.toml`. React: `src/components/`, `src/hooks/`, `public/`. Node: `package.json`, `node_modules/`, `dist/`. Putting things where the model expects them eliminates an entire class of "where does X live" failure.
- **Disambiguate overloaded vocabulary.** If your domain reuses words with strong training-data priors — "projects" (Claude Code projects vs game-world projects), "agents" (AI agents vs sales agents), "tasks" (Python tasks vs Jira tasks), "products" (SaaS vs CPG) — write a one-line glossary near the top of the project's CLAUDE.md disambiguating each. Fast sessions otherwise collapse to the training-dominant meaning regardless of context.
- **Module docstrings as the discoverability surface.** Models expect `"""..."""` at the top of any Python file to summarize the module. Use that slot; don't bury the summary lower or in a sibling README.
- **README and CLAUDE.md at the project root.** Both have strong training-data priors. Putting setup notes in `docs/intro.md` is a small but real friction.
- **Script names verb-first lowercase-underscore.** `scanner_arb_v2.py`, not `ScannerArbV2.py` or `arb.scan.v2.py`. That's the Python ecosystem default.

**The escape hatch when you must deviate.** Sometimes the right design lives off-convention (a JS file served from a Python string template, a config in a non-standard path, a script that belongs in `bin/` not `scripts/`). For each deviation, **leave a stub at the conventional location** pointing at the real one. Example: `webapp/static/bridge.js` containing only `// SEE: webapp/bridge.py BRIDGE_JS_TEMPLATE`. A fast session that globs the conventional path lands on the truth instead of "not found → confident guess."

**The fix-layer hierarchy.** Empirically validated 2026-05-21 against fast-Haiku sessions in the Arc Raiders trading-harness audit. Ordered by **resistance to the model skipping the relevant investigation step**, not by reliability of the fix when consulted:

1. **Conventional path resolves to truth** (rename file, place stub, mirror layout). Glob hits the right thing whether or not the model reads docs. *Survives even when the model investigates nothing.*
2. **Source files self-describe** (top-of-file docstring states what the file is). Surfaces on any Read of the file, no chapter detour required.
3. **CLAUDE.md is exhaustive at the top** (tool routing, hard rules, glossary). Surfaces when CLAUDE.md is consulted — which is the default for fresh-session auto-load, though fast/casual queries sometimes bypass docs entirely.
4. **Chapter files carry the detail** (EXTENDING.md, BROWSER_FLOW.md, etc.). Surfaces when the chapter is opened.

All four work when their action (Glob / Read / consult / open) happens; the ranking is by **what happens if the action is skipped** — layer 1 still surfaces the truth, layers 2-4 don't. Pick the lowest-numbered feasible layer, but don't dismiss higher ones — they work fine when consulted (the common case for fresh sessions).

**Critical methodological note for cold-start audits of doc changes.** Subagent CLAUDE.md is **auto-loaded from parent-session start and not refreshed when the parent edits CLAUDE.md mid-session.** If you edit CLAUDE.md and then spawn subagents to verify the edit, those subagents see the pre-edit CLAUDE.md — any apparent "documentary fix failed" finding is suspect until re-tested with fresh context. To re-test properly: (a) tell the subagent explicitly to Read CLAUDE.md before answering — this puts current content in its context the way auto-load would — or (b) drive a real fresh Claude Code chat in the project's cwd. Without this discipline, layer-3/4 fix effectiveness is systematically underestimated. The 2026-05-21 audit ran into this exact trap before correcting: the glossary disambiguation for "projects" and the EXTENDING.md routing row both appeared to "fail" against stale-cache subagents, then both worked when the cache was refreshed.

**Meta-failure mode orthogonal to caching.** Fast Haiku sometimes claims "I'm reading X" or "Based on what I see" while doing 0 tool uses — falsifying its own investigation status. Don't trust an agent's narrative about what it consulted; verify by tool-use count. This is real and independent of the stale-cache issue; structural fixes still matter because they don't require any investigation to be triggered.

## Project CLAUDE.md as a validated index — don't claim what hasn't been verified

Every CLAUDE.md you write — at the project root or in chapter files — is read by future fast/cheap-inference sessions with shorter attention spans than the session that wrote it. Treat each section title and one-line bullet as a **validated claim**: it must accurately describe what's in the chapter or file it points at, no more and no less. Nothing about a chapter is validated by mere mention; the validation is the act of reading the chapter and writing the summary truthfully.

**The cardinal rule for project documentation: don't guess beyond the validated summary.** State this rule explicitly near the top of every project CLAUDE.md. When a fresh session asks "where does X live", "what's in Y", "how does Z work", the model has two paths: (a) tool-call to the chapter or source, or (b) extrapolate from the summary in its context. Extrapolation is the hallucination path. The cardinal rule names extrapolation as a failure mode so the model selects path (a). This single rule replaces a long list of "don't hallucinate X" warnings — one rule, infinitely many specific failures prevented.

**Progressive disclosure via index → chapter → source.** Structure project docs like a book:
- **Index** = project-root CLAUDE.md: always auto-loaded, tight, validated. Holds (i) tool routing for high-traffic actions, (ii) standing style and hard rules, (iii) glossary disambiguation for overloaded vocabulary, (iv) a chapter index — one line per chapter file with a validated summary.
- **Chapter files** alongside the code (e.g. `EXTENDING.md`, `BROWSER_FLOW.md`, `INSTRUCTIONS.md`): operational detail for one specific area. Loaded only when the owner or the model navigates there.
- **Source code**: ground truth, made self-describing by top-of-file docstrings.

The anti-pattern to avoid: dumping all operational detail into CLAUDE.md so it auto-loads every session. Bloats context, buries the genuinely-always-needed bits (hard rules, response style), and trains future sessions to skim. Extract chapter-shaped content to chapter files; replace the inline content with a validated one-line summary plus a pointer.

**Self-protecting discipline.** When you add, rename, or significantly change a chapter file, re-walk the CLAUDE.md summary that points at it: does the summary still accurately describe the chapter's content? Index entries rot the moment the underlying file changes. Bake this as a checklist item into the project's contribution / extension rules. Without it, the index drifts from reality and the validated-summary rule's foundation crumbles. (Concrete example from the Arc Raiders project: `EXTENDING.md`'s discoverability checklist has an item #6 that explicitly says "if you added/renamed a chapter file referenced from CLAUDE.md, re-check that the one-line summary in CLAUDE.md is a validated description of the chapter's actual content.")

Established 2026-05-21 (Arc Raiders restructure). Pre: 1/3 cold-start Haiku sessions fabricated paths/structure on casual queries (invented `webapp/static/bridge.js`, a non-existent `metaforge-cache/`). Post (cardinal rule + index/chapter pattern): 5/5 stress tests passed — each Haiku identified the underlying ask, navigated the chapter index, opened the source, cited real lines. Adopt for any project whose CLAUDE.md is auto-loaded by fast inference.

## Behavior-changing warnings must be imperative directives, not advisories

A gotcha written in advisory voice — "X may happen," "be aware of Y," "note Z" — gets read, acknowledged ("yeah, that's a known thing"), and then **worked around as usual.** That defeats its whole purpose: the warning exists to PREVENT the habitual workaround, but passive phrasing reads as background trivia to rationalize past. (Seen repeatedly: PowerShell→bash gotchas in CLAUDE.md ignored *while the session admits they were mentioned*; the subagent-stale-CLAUDE.md caching note forgotten though it lives in four separate docs.)

When a warning must change behavior, write it so it can't be skimmed:

1. **Imperative, not descriptive.** "ALWAYS do X / NEVER do Y / STOP and verify Z before W" — an action the reader must take, not a fact they may note.
2. **Name the failure cost — loudest for silent ones.** The worst gotcha makes a session believe something worked when it didn't. Spell it out: "skip this and you get a SILENT false pass, not an error." Silent-failure gotchas get the strongest treatment; naming the stakes is what makes the directive register instead of sliding past.
3. **Place it at the decision point** — immediately before the tool call / command it governs, not in a distant "warnings" section. (This is voice *within* fix-layers 2–4 above: a directive at the action fires; the same text in an appendix gets skimmed.)
4. **Forbid the workaround by name.** If a tempting wrong default is the reason the warning exists, say "do NOT just work around this by <the usual move>" — name the reflex it counters, or the model takes that reflex and notes the warning as a curiosity.
5. **Reserve the force for genuine gotchas.** If every line shouts, none do. Loud imperative directives are for silent/expensive errors; ordinary context stays ordinary prose.

This is the corollary to "make the default guess correct rather than add warnings" (the layouts section above): the structural fix is always first choice because it needs no compliance. But when you *can't* make the right behavior the default and must rely on written words, those words only work as a **binding directive**, not an advisory. Applies to every instruction surface you author — project CLAUDE.md, `~/.claude/CLAUDE.md`, SKILL.md files, snippets, chapter docs.

Established 2026-06-01 (the owner): passive warnings get rationalized away; the canonical motivating case is a silent "it worked when it hadn't" failure that a passively-worded gotcha failed to prevent.

## SKILL.md frontmatter must survive a strict YAML parser

A skill's `description` reads as prose but lives in YAML frontmatter, and YAML *plain scalars* have silent hazards that make a parser **truncate or drop the description** — which silently kills the skill's triggering. The two that bite in practice: a colon-space (`: `, read as a nested key) and a space-then-hash (` #`, which starts a comment and discards everything after it). Claude Code's own parser tolerates some of these, but stricter tooling does not — and a lenient truncation is **silent**: the skill still loads, just with half its trigger text gone.

When a description contains any such hazard, make the frontmatter strict-valid with a **folded block scalar** — write `description: >-` and put the text on the indented line below. A block scalar treats *all* punctuation as literal (colons, `#`, quotes, brackets), so the description needs no escaping or rewording and is preserved byte-for-byte. Then **verify by parsing**: load the frontmatter with a real YAML parser (PyYAML `safe_load`) and confirm `name` and the *full* `description` come back intact — don't trust that it looks fine on disk. (2026-06-14: a global em-dash cleanup of descriptions silently truncated `windows-elevation-uac` at a `#Requires` token; converting the affected descriptions to block scalars fixed the whole class.)

## Convention-matching duty — the full 5-point detail

The principle is stated inline in `~/.claude/CLAUDE.md` (default to convention, surface deviations). The **elaborated 5-point duty + worked examples** — the "forks belong in the kitchen drawer" framing, and the default-on-scaffold / surface-when-proposing / surface-when-noticed / naming-prior / no-cuteness rules — live in **[`references/convention-matching-detail.md`](references/convention-matching-detail.md)**. Read it when scaffolding or naming and you need the detail beyond the one-line CLAUDE.md rule.
