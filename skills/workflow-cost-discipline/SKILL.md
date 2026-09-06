---
name: workflow-cost-discipline
description: "Model-routing, cost, and mechanism judgment for Claude Code workflows - fan-out triggered by the workflow keyword, /deep-research, ultracode, or any fan out, audit, migrate or deep research ask. Use BEFORE launching one, when picking the spawn mechanism (workflow vs background subagent vs chip vs scheduled task), and when choosing a stage's model or effort. Trap - every agent inherits the session model AND effort. Not for one-off subagents."
---

# Workflow cost discipline (the owner)

**Prime directive: never let a fan-out silently inherit the session model/effort.** Every `agent()` that doesn't set `model` inherits the **session model**; every agent that doesn't set `effort` inherits the **session effort**. So an Opus/high session spawns an all-Opus, all-high-effort fleet unless the script routes per stage. Per-call `opts.effort` ('low'|'medium'|'high'|'xhigh'|'max') exists in the Workflow API (verified live 2026-07-01; recheck if the Workflow tool schema drops it) — **set `effort` explicitly on EVERY `agent()` call** (mechanical stages low, deep verify/judge stages high), exactly as you already route `model`. A pure-Opus run is allowed only as a deliberate, justified choice, never the silent default.

**Efficiency is part of quality.** The usage limit gates how long you can iterate; an Opus blowout that benches you until reset yields lower total quality than an efficient run that leaves headroom. Ferrari rule: capable models are fine, but don't send the premier model to do work a cheaper one does just as well.

## First gate: is a workflow warranted at all?
Not launching an unnecessary workflow saves the whole run. ~99% of a low-output agent's cost is the context it carries, so agent-count × per-agent floor (~20k Sonnet / ~67k Haiku) dominates — decide the **mechanism** before the model.

Reach for a workflow only when ≥1 holds:
- More agents than one conversation can coordinate (dozens–hundreds).
- Work too big for one context window (intermediates would blow the context).
- A repeatable quality pattern IS the point (adversarial cross-check, multi-angle drafting), codified to run the same way each time.
- The orchestration itself must be rerunnable (saved as a command).

Otherwise **do it directly** — a few files, a single coherent edit, a sequential no-fan-out job. The docs: a workflow "can use meaningfully more tokens than working through the same task in conversation." Never use one to raise quality on a *single coherent artifact* (one strong agent in one context wins). (Under standing **ultracode**, the skip-bar rises to *trivial or already-verified* — see Spend modes.)

## Mechanism cascade (cheapest that suffices wins)
1. Fits one context, one coherent line of work → **single agent** (inline).
2. Parallel/isolated exploration you'll read & synthesize yourself, width × per-agent return ≲ ~10–15% of the window, one stage, no repeat → **subagents** (Agent tool).
3. Only if ≥1 holds → **workflow**: width × return would crowd the main context; results must pipe agent→agent without round-tripping through you; scale beyond ~10 agents; a codified verify/panel pattern is the point; orchestration must be deterministic/rerunnable.

Parallelism and fresh contexts do NOT distinguish workflows from subagents — both have those. The only difference: a workflow moves orchestration into a script and keeps intermediates **out** of your context. "N parallel research agents I'll synthesize myself" = **subagents**, not a workflow. If no tier-3 trigger fires, a workflow is net-new spend (identical fan-out cost + a re-bought synthesis step). *(Receipt, 2026-05-31, n=1: same 3-agent task — fan-out $0.57 vs workflow $0.60 + a $1.96 Opus synthesis the fan-out did inline for ~free; quality tied. The workflow's flat-context property earns its premium only past a ~10–15% window deposit.)*

### Spawn-mechanism map (the five spin-off types, and what each costs you)
The cascade above picks between the two you launch yourself; this is the full set, including the ones a chat cannot spawn.

- **Dynamic WORKFLOW** (`Workflow` tool) — fans out subagents and returns synthesized results here automatically. **Non-blocking:** returns a task id at once, runs in the background, fires a `<task-notification>` on completion, so you stay available to the owner. Use only when the first gate clears.
- **Background subagent** (`Agent`, `run_in_background: true`) — same async auto-notify for one delegated job, or a small parallel fan-out you read and synthesize yourself. Works in auto mode; **its final text IS the result**, so no shared file is needed for anything you can spawn this way. Default workhorse — use it instead of asking the owner to open a chat tab himself.
- **`spawn_task` CHIP** (`mcp__ccd_session__spawn_task`) — a SEPARATE session behind a chip the owner clicks, with **no memory of this chat**: the prompt must be fully self-contained. Reports back only via a shared file.
- **Scheduled task** (`notifyOnCompletion: true`) — recurring or deferred work; every run is fresh and self-contained, and notifies this session on completion.
- **A genuinely separate project chat** the owner runs himself — reports back only via a shared file.

**Never hold a live turn open on a blocking wait** for any of these (`TaskOutput block:true`, long polls): the owner's messages queue unseen until it returns. End the turn; the completion notification re-wakes you.

**Not cross-session channels — don't mistake these for one.** The native `Task*` list (`TaskCreate`/`TaskList`) is **per-session** working memory, shared only inside an active experimental *Agent Team*; it is not a free cross-chat bus, so durable cross-chat or cross-device state still belongs in Notion or a file. **Agent Teams** (shared task list + inter-agent mailbox) is experimental and off by default — its split-pane mode needs tmux/iTerm, unavailable on the Windows desktop app; in-process works anywhere but is still experimental. Neither is stable enough to build on; the background-subagent + Notion model is the stable equivalent. Revisit when it leaves experimental.

**Byproduct-first — the cheapest delegation is no new work.** Before commissioning recon, ask whether a planned or in-flight execution chat already opens those same files, inboxes, or pages; if so, fold a one-line instruction into THAT chat's scoped pointer ("while you have these open, also log per-episode state to <the shared md>") and consume the result. Gate that per-workstream — never bake it into a dual-use tool, which would fire wrongly on the tool's other uses.

## Right-size every agent's model (the main job)
Set the **session model to Sonnet**, then *inherit* for most stages and override **up** to Opus only where thinking matters (or **down** to Haiku for rare high-volume mechanical work). This honors Anthropic's "omit `model`, inherit" default while fitting a metered budget.

| Model | Use for |
|---|---|
| **Haiku** | Genuinely mechanical, well-bounded, clear-correct-answer work: function mapping, file discovery, grep/extraction, format transforms, collation. **Caveat: ~3.4× more context/agent than Sonnet (measured) — largely cancels its price edge at small sizes; reserve for high-volume mechanical work.** |
| **Sonnet** | **Default workhorse:** code reading/understanding, applying a defined change, routine per-file analysis/review. When torn between Haiku and Opus, pick Sonnet. |
| **Opus** | Real reasoning / quality-critical: final synthesis, adversarial verification of findings, hard architectural judgment — where a mistake propagates or quality is the whole point. |

**Route by failure DETECTABILITY and correction cost, not by tier** (Notion routing audit 2026-08-26; re-stated by the owner 2026-08-29 — *"i feel as though we underutilize the cheaper agents"* and *"surely opus would have smarter feedback for you than sonnet"*, in the same breath, because they are the same error). The question is not how hard the work looks, it is **what happens if the agent is wrong and nobody notices.** Work behind a real verifier — a passing gate, a selftest, a measured dB, a diff that must match — routes DOWN safely, because a wrong answer surfaces. Work with no mechanical verifier — taste, register, prose, "does this feel like the thing it depicts", anything only the owner can settle — does NOT route down, at any effort. Receipt, 2026-08-29: every mechanical gate passed a generated artifact; one Opus reviewer asked the unanchored question and found four defects those gates had all passed.

**A gnarly issue is a targeted subagent, not more inline turns** (owner, 2026-08-29: *"for gnarly issues, better to use a targeted subagent than to wrestle with it for too long"*). Grinding inline also goes dark on him while he may be waiting.

**Minimize Opus's footprint:**
- **Anchored grading is NOT an Opus job.** When the verifier has an objective anchor (ground-truth answer, reference fix, spec, test result), the comparison is bounded → Sonnet (sometimes Haiku). "Spend Opus on verification" applies only to *unanchored* judgment ("is this finding real?" with no answer key).
- **One Opus stage, not Opus-by-default.** Most workflows need Opus in at most one place. If more than one stage is Opus, justify each.
- **Don't carpet with Haiku either** — too-dumb agents produce garbage that needs cleanup (a false economy). Target: dramatic cost cut with no change to output quality.

**Free Haiku down-route for discovery:** pass `agentType:'Explore'` — a built-in, restricted-tool agent that runs on **Haiku regardless of session model** and sidesteps the Haiku MCP eager-load (composes with `schema`). Prefer Anthropic's built-in agent types over hand-rolled custom ones (calibration risk).

**Routing down assumes a net under it** — a downstream Opus pass that double-checks the cheaper agents. If a stage's output is final and won't be Opus-verified, use the stronger model there; prefer Opus where an early wrong turn is expensive to *unwind* rather than a cheap after-the-fact tweak.

**Blast-surface override (hard rule) — self-mod gets the Ferrari.** For security-relevant changes, edits to global rules/config/systems, or any self-modification (`~/.claude/CLAUDE.md`, skills, hooks, `settings.json`, the deny list): route **UP** — strongest model, deeper review, an independent adversarial pass (never a self-review). This is THE exception to the Ferrari rule. (Mirrors `~/.claude/CLAUDE.md` § "Spend intelligence in proportion to blast surface".)

## Spend modes (read the room)
**Cycle-timing is the signal:** early in the weekly cycle → **conserve** (burning early breeds an all-week token-pinching dread the owner dislikes); late with surplus still unspent → **burn** (use-it-or-lose-it; the unused % evaporates at reset). E.g. ~16 h left + ~66% unspent = a clear burn window.
- **Conserve** (default when unstated): aggressive-but-sensible routing, smaller fan-out, set a `+Nk` budget, Sonnet session model.
- **Burn:** "more" means more *verification / independent perspectives / deeper Opus synthesis* — NOT the same mechanical work done expensively. Never fire ~100 Opus agents at trivial tasks.
- **Ultracode = standing burn signal** (overrides the conserve default): at the First gate, raise the skip-bar to *trivial or already-verified*; still right-size mechanical stages down.
- **Ultracode is ALSO the standing APPROVAL to launch** (the owner, 2026-08-10: "if i enable ultracode that should be assumed fine for workflows"). With it on, do not stop to ask whether to run a workflow — **launch it**. Turning ultracode on is the deliberate act; re-asking each time taxes a decision he already made, which is the exact friction it exists to remove. Global CLAUDE.md carries the matching carve-out to "propose, don't launch". Everything below still binds: right-size the models, set `opts.effort` per call, and say what you launched.

If a run is non-trivial (many agents / lots of Opus / broad scope) **and ultracode is OFF**, state the rough plan first (agent count + model mix + whether to budget) and let the owner bump it to burn. With ultracode ON, state the plan in one line and go — that line is a courtesy, not a gate.

## Hard guardrails
- **Never silently launch a large all-Opus fan-out.** Route down or surface it first.
- **Several agents on ONE structured file: state the write MECHANISM, not just the key list (2026-08-29).** A semantic boundary ("you own `lines`, they own `control`") does NOT compose with a whole-file write — `json.load` + `json.dump` rewrites every byte, changing formatting and key order that another agent is string-matching against. Every agent can honour its boundary and they still clobber each other. Measured: a reformat silently turned another agent's exact-string edit into a no-op; it failed safely only because that replace verified before writing. So — (1) tell each agent either *edit in place, preserve the rest byte-for-byte* or *you may rewrite the whole file, and say so in your return*; (2) **a whole-file rewrite is a reportable event** — downstream string edits will fail against it, and the owner's own note on this was that the subagent should have given a heads-up; (3) never string-match a shared file without counting occurrences first — require exactly one, refuse on 0 or >1; (4) re-read the file immediately before editing if anyone has touched it since your last read; (5) **prefer serialising edits to one shared file over parallelising them** — concurrency pays across *different* files; on one file the coordination cost exceeded the gain, twice in one night.
- **Effort inherits the session on every `agent()` that omits it — the lever that dominated the 6.6M incident (the owner, 2026-06-14).** A high/xhigh/ultracode session fans the WHOLE tree out at that depth (finders, mappers, every cheap stage), and thinking is **output-billed**. Primary control: **per-call `opts.effort`** ('low'…'max'; in the live Workflow schema, verified 2026-07-01) — set it explicitly on EVERY `agent()` call, never run a broad finder/mapper fan-out at xhigh. Backstop when any call omits it (or if the schema ever drops the param): **DROP the session effort to the cheapest stage's level (≤ medium) before a wide fan-out.** (The documented `agentType`→`effort:`-frontmatter pin resolves only for agent defs present at *session start*; a def created mid-session is reported "not found", and wiring an unresolved `agentType` in **breaks** the call.) Receipt: `efficient-bug-hunt` (not included in this pack) launched from an Opus-**high** session fanned 82 agents at high effort → **~6.6M tokens** before it was killed.
- **Right-size TOOLS, not just models (the owner, 2026-06-19).** A workflow's default subagent carries the FULL kit (Write/Edit/Bash/WebFetch/WebSearch/all MCP). Pin any stage whose only real need is reading local files (read / synthesize / verify / critique) to a minimal-tools `agentType`, so a **prompt-injection from the untrusted input it reads** can't write, shell out, or hit the network. Built-in `Explore` blocks Write/Edit but KEEPS Bash/WebFetch/WebSearch and forces Haiku; for a hard write+network lockdown that still honors per-stage `opts.model`/`opts.effort`, use a custom minimal-tools type — **`~/.claude/agents/readonly-worker.md`** (`tools: Read, Grep, Glob`, no model/effort pinned) is the reusable default. Resolves only if the def existed at session start (see the effort-pin note above) → author + commit, live next session. Receipt: `slack-distill` mined external Slack-Connect messages with the full kit exposed; hardened to `readonly-worker` 2026-06-19.
- **`+Nk` budget = a real throw-stop (spawns throw once hit), but counts OUTPUT tokens only** — binds tightly on thinking/xhigh/ultracode runs, loosely on low-output mechanical fan-outs (input-dominated cost sails past the cap). Pair it with agent-count × per-agent-context × model-price; don't lean on `+Nk` alone for mechanical fan-outs.
- **Present 2-3 costed options before spending; bound cost structurally.** `args` can silently fail to reach the script (observed 2026-06-13: a background `scriptPath` launch ignored `args` and ran the full ~1.5M-token pilot instead of the intended ~8-call subset). Default the script to a no-cost dry run requiring an explicit `args.execute === true` (or hardcode a cheap default), so a dropped arg yields a harmless dry run, not a surprise bill.
- **Bake in verification** for anything that generates findings (an independent cross-check / vote stage) — workflows surface hallucinated "findings" without it.
- **Scope first on big targets** — calibrate on one subdirectory before pointing at a whole codebase.
- **Staged/escalation workflows: checkpoint after the cheap wave; don't auto-run all tiers.** Launch the first/cheapest wave alone and *look* — it often answers the headline outright (e.g. "Haiku 3/3 on 7/8" settles "is Haiku enough?"); an auto-cascade can't tell real signal from an eval/judge artifact, but you can. (the owner, 2026-06-12: an auto-escalation spent ~12 extra agents surfacing only a judge-strictness artifact that changed no recommendation.)
- **Caps:** 16 concurrent (`min(16, logical-cores − 2)`; 16 on this 32-core machine), 1000 total per run, ≤4096 items per single `parallel()`/`pipeline()` call. Runs are background batch jobs that stop when the script finishes (or is stopped) — not daemons.

## Environment (this machine)
- Claude Code via the **Desktop app**, not the CLI. Approvals appear as a card (Once / Always / Deny + a token-usage caution); progress in the **Background tasks** pane. Prefer **Once** for expensive runs.
- `settings.json` `skipWorkflowUsageWarning` was `true` (the pre-run cost caution was silenced); **re-set to `false` 2026-05-30.** If warnings ever vanish again, check this key first.
- `CLAUDE_CODE_SUBAGENT_MODEL` env var pins **all** subagents to one model (top of the resolution order; overrides per-call `model` + frontmatter; `inherit` restores). CLI-only (awkward in the Desktop app); useful only for uniform mechanical runs. There is no setting that caps agents-per-workflow.
- **Ultracode is session-runtime state that doesn't persist** — new sessions reset to the app default (`unpinOpus48LaunchEffort: true` + the "we recommend medium effort" nudge), so it silently lapses on its own (not a Claude toggle — the model can't set `/effort`). If usage/behavior suggests it's off when the owner expected it on, *say so* rather than assume he dropped it.
- **Background runner can die silently mid-run (observed 2026-06-10, Desktop).** Every agent freezes at once — the tool ran (artifacts on disk) but the result never returns; `/workflows` shows yellow "running" while `TaskOutput` says "No task found". Diagnose from the run's transcript dir (`journal.jsonl` started-with-no-completion, stalled agent `.jsonl` + artifact timestamps). Recover with `Workflow({scriptPath, resumeFromRunId})` — completed `agent()` calls return cached; unfinished ones re-run, so write finder prompts re-runnable / overwrite-safe.
- **1M context on Max:** included for Opus (no premium above 200K; metered by tokens actually in context, so *enabling* it costs nothing, only *filling* it does), but a recurring billing regression ([CC #40223](https://github.com/anthropics/claude-code/issues/40223)) can mistag it as "Billed as extra usage" (real pay-as-you-go). For orchestration (stays lean), **plain 200K Opus is the zero-risk default**; pick `[1m]` only after confirming the picker shows "included", or with Settings → Usage → "Extra usage" toggled OFF. **Sonnet 1M is NOT included** (needs paid credits even on Max).

### Empirical findings (receipts)
Detailed token accounting — per-agent context sizes, same-model cache-sharing across the concurrency cap, the Haiku MCP eager-load, `budget.spent()` unreliability, `pipeline()` cache reuse, the `args`-not-array gotcha, the cheap measurement recipe — lives in **[`references/empirical-findings.md`](references/empirical-findings.md)**; read it before any new cost probe or to justify a routing number. Actionable one-liners (already used inline above): Haiku carries **~3.4× Sonnet's** per-agent context (MCP eager-load; current Claude Code behavior — recheck as it updates); **~99%** of a low-output agent's cost is context; same-model agents share cache only *past* the ~16-agent concurrency wave (agents beyond the first wave read the prefix at **~0.1×**); `+Nk` counts **output** tokens only.

## After the run: persist the result
The harness writes a workflow's synthesized output only to an **ephemeral** temp file (`…\Temp\claude\…\tasks\<id>.output`) that gets reaped, and scripts have no filesystem access — so a workflow cannot save its own result. **Saving it is a main-loop duty: when a workflow completes, save its meaningful output to a durable home before the turn ends** (the owner, 2026-06-06). Choose the home by what the result IS — a version-controlled project doc (indexed in that project's CLAUDE.md) for reference material; a memory file for a concise decision/pointer; a handoff artifact if it feeds another chat. In a worktree, a repo doc is branch-only until fast-forwarded.

## Quick pre-flight
0. **Workflow at all?** (First gate) — if it fits one context and one conversation can coordinate it, do it directly and skip the rest. (Ultracode inverts this.)
1. **Mode?** Conserve (default) or burn — ask in one line if unclear and the run is non-trivial.
2. **Right-size models** per stage; Sonnet session model unless Opus is warranted.
3. **Estimate** agent count + model mix; add a `+Nk` budget for big/conserve runs.
4. **Verify** — include a cross-check stage if the workflow produces findings.
5. **Present 2-3 costed options and WAIT for the owner's pick** (lean / standard / thorough, each with agent count + model mix + rough token cost, as a clickable `AskUserQuestion`, recommended first). He wants to choose the structure *and* know the cost before any spend, every time.
6. **Plan the result's home** (see *After the run*).

## Related
- Empirical receipts: `references/empirical-findings.md`. Mechanism eval (subagent vs workflow): `subagent-eval/mechanism/` in the Claude Eval Sandbox (`findings.md` verdict, `measure.py` to re-run).
- Canonical docs: https://code.claude.com/docs/en/workflows and https://code.claude.com/docs/en/costs

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
