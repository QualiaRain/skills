# Convention-matching duty — the full 5-point detail

(The principle is stated inline in `~/.claude/CLAUDE.md`: default to convention, surface deviations. This file carries the elaborated examples, referenced from [`../SKILL.md`](../SKILL.md).)

the owner's framing: **forks belong in the kitchen drawer.** If a kitchen has the forks in the bathroom, you have to explain it to every guest forever. The code is the kitchen; every future inference session (and every other Claude that lands in the project) is the guest. The bigger the project, the more guests come through, the more it pays to keep forks where they're expected.

**This is a standing duty, applied continuously:**

1. **Default to convention when scaffolding or naming.** Without explicit reason to deviate, your default proposal should match the dominant training-data convention for the ecosystem in question. Flask → `static/`, `templates/`, `routes/`. Python package → `src/`, `tests/`, `pyproject.toml`. Node → `package.json`, `dist/`, `node_modules/`. Python scripts → verb-named, lowercase, underscores. Config → standard locations (`config/`, `.env`, `pyproject.toml [tool.X]`). API URL paths → REST conventions. Don't reach for novel layouts unless there's a reason.

2. **Surface deviation when you propose it.** If a deviation is genuinely justified (better fit for the use case, an existing project decision, performance), say so explicitly to the owner: *"This deviates from the conventional X. The conventional path would be Y; doing Z because [reason]. Note: this costs fast-inference legibility unless we add a stub at the conventional path."* Let the owner decide. Without this surfacing, the owner can't catch the divergence and the cost accumulates silently across the project's lifetime.

3. **Surface deviation you notice in existing code.** When reading or extending code that already deviates from convention, flag it rather than silently working around it. Offer two paths: (a) align to convention (rename / move), (b) add a stub at the conventional path pointing at the real location. Either resolves the future-inference tax. Doing nothing perpetuates it.

4. **Naming carries a convention prior too.** "Trade harness" matches expectation; "Trade orchestrator-thingy" doesn't. "ledger" carries a clear schema prior; "deals-log" doesn't. When picking a name for a new module, file, function, or directory, pick from the ecosystem's standard vocabulary unless there's a reason. Novel names are debt.

5. **Don't smuggle deviation through cuteness.** Punny names, project-internal jargon, or one-off compound names (`scanner_arb_v2`, `bridge_thing`, `mf_helper`) all hide the actual structure from future inference. Plain conventional names beat clever ones — they pattern-match in the right way and grep predictably.

The cumulative effect of this duty is invisible per-decision but compounds across the project's lifetime. Future sessions land on a layout that matches their priors, find files where they expect them, and spend less context recovering from "where does X live" confusion. Established 2026-05-21 alongside the Arc Raiders restructure principles — the local fix that mattered most (a stub `webapp/static/bridge.js` at the Flask-conventional path) was a direct application of this rule, and applies the same way to any future Flask / Python / Node / etc. project.
