---
name: upstream-submission-walkthrough
description: >-
  Step-by-step EXECUTION walkthrough for pushing staged fix branches to your fork and opening upstream PRs, after the bodies are drafted. Gates every step on your typed go, with a separate pause before the irreversible PR-open. Triggers - push the PRs, ship these fixes upstream, open the pull requests, send these to the maintainer.
---

# Upstream submission walkthrough (user-gated execution)

This skill is the **execution** half of an upstream contribution: the bodies are
drafted and the branches are staged — now the user wants to push to their fork and open
the PRs **with themselves in the loop, one step at a time, reviewing everything.**

It exists because the push/open phase is where the **irreversible, outward-facing,
reputation-bearing** actions live (a public PR notifies the maintainer and cannot
be deleted), and the user is deliberately hands-on here. The whole point is to make every
step legible to a non-coder and to never let anything reach the maintainer without
their explicit word.

It is the companion to two things, and must not duplicate them:
- **`ai-authorship-disclosure` (not included in this pack)** owns the disclosure paragraph, the disclosure
  *tier* (incl. the **lazybones tier** = "…chose to submit based on Claude's
  analysis"), and the pre-submission checklist. Bodies arrive here already drafted
  and disclosed; do not re-draft them.
- **The project's mechanical gate** — in the author's setup, `UPSTREAM_STANDARDS.md`
  + `tools/verify_upstream.py` + a pre-push hook (fresh base, no submodule pollution,
  LF blobs, lint clean, AI trailer, leak scan). These are the author's own files, not
  shipped with this pack. Use whatever your clone has; if it has no gate, the
  minimum is the upstream repo's own lint/tests plus `git diff <base>..<branch> --stat`
  showing only the intended files. This skill *runs* the gate at the right moments;
  it does not replace it.

---

## 0. HARD PRECONDITION — strongest model at high effort, main thread (check FIRST)

**Before doing anything else, confirm the main thread is running the strongest
model available to the user (an Opus-tier model) at high or higher effort — NOT
low/medium. If you cannot confirm both, STOP and ask the user to switch before any
push/open step.**

- **Why this is a real gate, not ceremony.** This drives public, near-irreversible actions against a real maintainer's repo (a botched PR can't be deleted, only closed; the notification already fired) — spend intelligence in proportion to blast surface. The **model is the load-bearing part**; **high effort suffices for the execution tail** (careful gated git/gh work) — reserve the highest effort for a session still doing live verification or disclosure-drafting.
- **Model check.** Your system prompt names the session model. If it is not an Opus-tier model, halt: "this walkthrough is gated to the strongest model at high effort — you're on `<model>`; switch and re-run."
- **Effort check.** Session effort is a harness control you **cannot self-set or always self-observe**. Get the user's confirmation before the first push/open step: *"Confirm you're on <model> at high effort (or higher) and I'll start."* If they're on low/medium or a weaker model, ask them to bump it.
- **Subagents are exempt and encouraged.** Sonnet/Haiku subagents for verify/lint/finder/diff-reading are fine; only the **orchestrating main thread that pulls the trigger** must meet the gate.

Once both are confirmed, proceed.

---

## 1. The gating discipline (how every step is run)

The user is deliberately hands-on. For **each** step below:

1. **Explain it in plain English first** — what the step does, and any technical
   term defined inline (assume they are not a coder; "rebase", "head/base", "the gate",
   "the hook" all get a one-clause gloss). Say what is reversible vs not.
2. **Wait for their TYPED go.** They type "go" / a question / a redirect. **Do NOT use
   AskUserQuestion or any multiple-choice button here** — this flow is built around the
   user typing each go, not clicking a pre-offered choice. (This overrides
   any usual "offer discrete choices as buttons" preference.)
3. **Run only that step, then report** what happened before moving on.
4. **Nothing is pushed or opened without their explicit go** — and the public PR-open
   gets its own separate PAUSE (step 6 below). Silence is not consent.

Keep each explanation scannable (front-loaded, tight). If they've been away a while,
open with a one-line recap of where the sequence is.

---

## 2. Reversibility map (state this honestly; it's what calms the anxiety)

The user's biggest worry is usually the irreversible step. Be precise about which is which —
don't blur them to move faster, and don't overstate the escape hatch.

| Step | Reversible? | What it touches |
|---|---|---|
| Fetch / rebase / re-gate | Yes — local only | nothing leaves the machine |
| Generate PR body files | Yes — local scratch | nothing leaves the machine |
| Push branches to **the fork** | Yes — branches delete cleanly off the fork; maintainer never notified | the user's own fork |
| **Open a PR** | **NO** — a PR can be **closed** but **not deleted**; it stays a visible closed record and the notification already fired. Deleting the fork is messy and not a clean undo — never sell it as one. | the maintainer's repo (public) |

Reframe the worst case truthfully: the worst outcome of an opened PR is **a closed
PR** — the most ordinary thing on the platform, not damage. And when the maintainer
has a track record of welcoming these (e.g. merged earlier PRs and asked for more), the
reputational risk is low. Give the user the honest picture, then let them decide; never
pressure.

---

## 3. The canonical step sequence

Steps map to a typical wave (one real upstream project is the worked example;
generalize the mechanics for other repos). Gate each per §1.

- **Step 1 — Freshness re-check (fetch).** `git -C <clone> fetch origin`. Read-only.
  Report whether the upstream default branch (e.g. `origin/dev`) moved.
- **Step 2 — Rebase + re-gate.** Rebase every candidate branch onto the *current*
  upstream branch in a **temp worktree** (never switch the testbed checkout), then
  run the project's gate on each (author's setup: `verify_upstream.py <branch>
  --expect-files <exact list>`) until all pass. Rebase first: re-plant on the newest
  base *before* any review or push, so each PR shows only its own change.
  Halt on any conflict or gate failure and report that branch.
- **Step 3 — Generate body files.** Write each PR's body **verbatim** from the
  drafted source into a scratch dir (`.cache/pr-bodies/<N>-<branch>.md`): the
  `*Disclosure:*` paragraph + `### Issue` + `### Fix` (+ `### Testing` where it
  exists), NOT the `## PR N` / `**Title:**` lines (the title is a separate field).
  Use `--body-file` (a disclosure-checking hook, if you run one, can't read an
  inline shell body). **Do not re-draft** — the disclosure wording is locked to the prior accepted
  form; re-drafting risks exactly the drift the disclosure skill guards against.
  Confirm each file opens with the `*Disclosure:` line.
- **Step 4 — Preview every PR to the user.** Show each PR's **title + body** (verbatim) and
  the base→head mapping (`<upstream>:<default-branch>` ← `<fork-owner>:<branch>`).
  Let them read all of them and request edits *before* anything is pushed. (See §4.)
- **Step 5 — Push branches to the fork.** `git -C <clone> push <fork-remote>
  <branch>` per branch (NOT the upstream remote). If the clone has a pre-push hook it
  fires per branch; halt and report if any trips. Reversible; maintainer
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
  commit the notes.

**Stop conditions (halt and report, never push through):** a gate or hook failure;
a branch that won't cleanly rebase; PR #1 rendering wrong; or any uncertainty about
the model/effort precondition.

**Operational (learned the hard way): open each PR with a CLEAN, standalone `gh pr create`
and an ABSOLUTE `--body-file` path.** The author's disclosure-checking `PreToolUse` hook reads the
`--body-file` to confirm the `*Disclosure:` line; it **fails closed (blocks the create)** if it can't resolve the path — which
happens when the path is RELATIVE (the hook's cwd differs) or the `gh pr create` is buried inside a
loop / `$()` / a multi-command script it can't parse. So: one PR per Bash call, literal absolute body
path, no wrapping. PR #1 alone first (verify render), then fire the remaining N in PARALLEL (separate
Bash calls in one message) — each is independently validated and they create concurrently.

---

## 4. Previewing PRs (what the user reviews before pushing)

Show, per PR: **title**, then the **body** as it will render. The repeated disclosure
sentence may be abbreviated in the *display* for readability across many PRs, but the
**file on disk must carry it in full** — and say so, so the user knows the abbreviation is
display-only. Make clear which branch each maps to and that the base is the upstream
default branch, head is their fork. This is their last look before branches leave the
machine; invite edits explicitly.

---

## 5. Worked reference

The author's canonical run: 9 gate-clean fix branches against one real upstream
project, bodies drafted in a `notes/<wave>-pr-bodies.md` file, the push sequence walked
one step at a time with the user typing each go — and the reversibility conversation
(§2) led them to hold before the push. Keep the same shape in your own project: one
notes file holding the drafted bodies plus a "Push sequence" section recording each
step's outcome and the final PR URLs.

## Validation

The trigger description was validated with `skill-execution-hardening`'s (in this pack)
`scripts/trigger_probe.py` (in the author's testing, the skill-creator's own `run_eval.py`
read 0 triggers for everything on Windows). Result: **precision 10/10** — all ten
tricky near-misses (draft-a-body, maintainer reply, bug hunt, commit+push-master, rebase,
internal-repo PR, gate-by-itself, bridge push to a second install, summarize-notes, fork-master push) correctly
stayed silent. Recall under-read to ~0 on headless Opus — the documented **act-first** artifact, not
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
