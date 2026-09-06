---
name: upstream-submission-walkthrough
description: >-
  the owner's step-by-step EXECUTION walkthrough for pushing staged fix branches to his fork and opening upstream PRs, after the bodies are drafted. Gates every step on his typed go, with a separate pause before the irreversible PR-open. Triggers - push the PRs, ship these fixes upstream, open the pull requests, send these to vlad.
---

# Upstream submission walkthrough (the owner-gated execution)

This skill is the **execution** half of an upstream contribution: the bodies are
drafted and the branches are staged — now the owner wants to push to his fork and open
the PRs **with himself in the loop, one step at a time, reviewing everything.**

It exists because the push/open phase is where the **irreversible, outward-facing,
reputation-bearing** actions live (a public PR notifies the maintainer and cannot
be deleted), and the owner is deliberately hands-on here. The whole point is to make every
step legible to a non-coder and to never let anything reach the maintainer without
his explicit word.

It is the companion to two things, and must not duplicate them:
- **`ai-authorship-disclosure` (not included in this pack)** owns the disclosure paragraph, the disclosure
  *tier* (incl. the **lazybones tier** = "…chose to submit based on Claude's
  analysis"), and the pre-submission checklist. Bodies arrive here already drafted
  and disclosed; do not re-draft them.
- **`UPSTREAM_STANDARDS.md` + `tools/verify_upstream.py` + the pre-push hook** are
  the mechanical gate (fresh base, no submodule pollution, LF blobs, lint clean,
  AI trailer, leak scan). This skill *runs* the gate at the right moments; it does
  not replace it.

---

## 0. HARD PRECONDITION — Opus 4.8 at elevated effort (high or xhigh), main thread (check FIRST)

**Before doing anything else, confirm the main thread is Opus 4.8 at elevated effort
(high or xhigh — NOT low/medium). If you cannot confirm both, STOP and ask the owner to switch
before any push/open step.**

- **Why this is a real gate, not ceremony.** This drives public, near-irreversible actions against a real maintainer's repo (a botched PR can't be deleted, only closed; the notification already fired) — the "spend intelligence in proportion to blast surface / outward-facing = max model" rule. Standing requirement (the owner, 2026-06-15): the **model (Opus 4.8) is the load-bearing part**; **high effort suffices for the execution tail** (careful gated git/gh work) — reserve **xhigh** for a session still doing live verification or disclosure-drafting.
- **Model check.** Your system prompt names the session model. If not Opus 4.8 (`claude-opus-4-8…`), halt: "this walkthrough is gated to Opus 4.8 (high/xhigh) — you're on `<model>`; switch and re-run."
- **Effort check.** Session effort is a harness control you **cannot self-set or always self-observe** (like `/compact`). Get the owner's confirmation before the first push/open step: *"Confirm you're on Opus 4.8 + high (or xhigh) and I'll start."* high is the default for an execution-tail resume; xhigh if still verifying/drafting. If he's on low/medium or a weaker model, ask him to bump it.
- **Subagents are exempt and encouraged.** Sonnet/Haiku subagents for verify/lint/finder/diff-reading are fine; only the **orchestrating main thread that pulls the trigger** must be Opus 4.8 at high/xhigh.

Once both are confirmed, proceed.

---

## 1. The gating discipline (how every step is run)

the owner is deliberately hands-on. For **each** step below:

1. **Explain it in plain English first** — what the step does, and any technical
   term defined inline (he is not a coder; "rebase", "head/base", "the gate", "the
   hook" all get a one-clause gloss). Say what is reversible vs not.
2. **Wait for his TYPED go.** He types "go" / a question / a redirect. **Do NOT use
   AskUserQuestion or any multiple-choice button here** — he has explicitly said he
   wants to type his go in this flow, not click. (This is the one place the usual
   "offer discrete choices as buttons" preference is overridden.)
3. **Run only that step, then report** what happened before moving on.
4. **Nothing is pushed or opened without his explicit go** — and the public PR-open
   gets its own separate PAUSE (step 6 below). Silence is not consent.

Keep each explanation scannable (front-loaded, tight). If he's been away a while,
open with a one-line recap of where the sequence is.

---

## 2. Reversibility map (state this honestly; it's what calms the anxiety)

the owner's biggest worry is the irreversible step. Be precise about which is which —
don't blur them to move faster, and don't overstate the escape hatch.

| Step | Reversible? | What it touches |
|---|---|---|
| Fetch / rebase / re-gate | Yes — local only | nothing leaves the machine |
| Generate PR body files | Yes — local scratch | nothing leaves the machine |
| Push branches to **the fork** | Yes — branches delete cleanly off the fork; maintainer never notified | his own fork |
| **Open a PR** | **NO** — a PR can be **closed** but **not deleted**; it stays a visible closed record and the notification already fired. Deleting the fork is messy and not a clean undo — never sell it as one. | the maintainer's repo (public) |

Reframe the worst case truthfully: the worst outcome of an opened PR is **a closed
PR** — the most ordinary thing on the platform, not damage. And when the maintainer
has a track record of welcoming these (e.g. vlad merged the prior waves and asked
for more), the reputational risk is low. Give the owner the honest picture, then let him
decide; never pressure.

---

## 3. The canonical step sequence

Steps map to a typical wave (the SD.Next/vlad instantiation is the worked example;
generalize the mechanics for other repos). Gate each per §1.

- **Step 1 — Freshness re-check (fetch).** `git -C <clone> fetch origin`. Read-only.
  Report whether the upstream default branch (e.g. `origin/dev`) moved.
- **Step 2 — Rebase + re-gate.** Rebase every candidate branch onto the *current*
  upstream branch in a **temp worktree** (never switch the testbed checkout), then
  run `verify_upstream.py <branch> --expect-files <exact list>` on each until all
  pass. This is the **Rebase-first** rule from `UPSTREAM_STANDARDS.md`: re-plant on
  the newest base *before* any review or push, so each PR shows only its own change.
  Halt on any conflict or gate failure and report that branch.
- **Step 3 — Generate body files.** Write each PR's body **verbatim** from the
  drafted source into a scratch dir (`.cache/pr-bodies/<N>-<branch>.md`): the
  `*Disclosure:*` paragraph + `### Issue` + `### Fix` (+ `### Testing` where it
  exists), NOT the `## PR N` / `**Title:**` lines (the title is a separate field).
  Use `--body-file` because the disclosure-gate hook can't read an inline shell
  body. **Do not re-draft** — the disclosure wording is locked to the prior accepted
  form; re-drafting risks exactly the drift the disclosure skill guards against.
  Confirm each file opens with the `*Disclosure:` line (the hook requires it).
- **Step 4 — Preview every PR to the owner.** Show each PR's **title + body** (verbatim) and
  the base→head mapping (`<upstream>:<default-branch>` ← `<fork-owner>:<branch>`).
  Let him read all of them and request edits *before* anything is pushed. (See §4.)
- **Step 5 — Push branches to the fork.** `git -C <clone> push <fork-remote>
  <branch>` per branch (NOT the upstream remote). The pre-push hook fires per branch
  (submodule + leak + lint); halt and report if any trips. Reversible; maintainer
  not notified.
- **Step 6 — PAUSE for an explicit public-push go.** This is the irreversible gate.
  State plainly that the next action opens real PRs the maintainer will see and that
  can't be deleted. Wait for a fresh, explicit go for *this* step — a prior "go" on
  the push does not carry over.
- **Step 7 — Open PR #1 first, then verify, then the rest.** Open the highest-impact
  PR alone: `gh pr create --repo <upstream> --base <default-branch> --head
  <fork-owner>:<branch> --title "<title>" --body-file <file>`. Then `gh pr view
  <url>` to confirm it rendered (disclosure italic, title, body intact). Only after
  it's confirmed good, open the remaining PRs. A wrong render → halt and report.
- **Step 8 — Report + record + clean up.** Report all PR URLs, update the durable
  notes (mark "submitted", record the URLs), delete the scratch body files, and
  checkpoint the docs. Then offer the boundary recommendation (compact/clear/new
  chat) per the wrap discipline.

**Stop conditions (halt and report, never push through):** a gate or hook failure;
a branch that won't cleanly rebase; PR #1 rendering wrong; or any uncertainty about
the model/effort precondition.

**Operational (learned 2026-06-15, Wave-4): open each PR with a CLEAN, standalone `gh pr create`
and an ABSOLUTE `--body-file` path.** The `disclosure-gate` hook reads the `--body-file` to confirm
the `*Disclosure:` line; it **fails closed (blocks the create)** if it can't resolve the path — which
happens when the path is RELATIVE (the hook's cwd differs) or the `gh pr create` is buried inside a
loop / `$()` / a multi-command script it can't parse. So: one PR per Bash call, literal absolute body
path, no wrapping. PR #1 alone first (verify render), then fire the remaining N in PARALLEL (separate
Bash calls in one message) — each is independently validated and they create concurrently.

---

## 4. Previewing PRs (what the owner reviews before pushing)

Show, per PR: **title**, then the **body** as it will render. The repeated disclosure
sentence may be abbreviated in the *display* for readability across many PRs, but the
**file on disk must carry it in full** — and say so, so the owner knows the abbreviation is
display-only. Make clear which branch each maps to and that the base is the upstream
default branch, head is his fork. This is his last look before branches leave the
machine; invite edits explicitly.

---

## 5. Worked reference

The 2026-06-15 SD.Next **Wave-4** run is the canonical instantiation: 9 gate-clean
fix branches, bodies drafted in `notes/wave4-pr-bodies.md` (lazybones-tier
disclosure), the push sequence walked one step at a time with the owner typing each go, the
reversibility conversation that led him to hold before the push, and the durable
checkpoint on `master`. See that repo's `notes/wave4-pr-bodies.md` (the "Push
sequence" section) and `notes/bug-hunt-wave4-staging.md` for the full record of how
this flow ran end to end.

## Validation (2026-06-15)

The trigger description was validated with `skill-execution-hardening (absorbed skill-trigger-test-windows, 2026-09-05)`'s `trigger_probe.py`
(the skill-creator's own `run_eval.py` is broken on Windows — reads 0 triggers for everything;
consult that skill BEFORE running any triggering eval here). Result: **precision 10/10** — all ten
tricky near-misses (draft-a-body, maintainer reply, bug hunt, commit+push-master, rebase,
internal-repo PR, gate-by-itself, bridge push to D:, summarize-notes, fork-master push) correctly
stayed silent. Recall under-reads to ~0 on headless Opus — the documented **act-first** artifact, not
a description gap: a captured positive transcript showed Claude applying the upstream-contribution
discipline (refused to act without context, flagged the disclosure policy) rather than ignoring it.
No description change was warranted. Eval set: `evals/trigger-evals.json`.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
