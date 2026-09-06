---
name: sonnet-fabrication-calibration
description: >-
  How to calibrate TRUST in Sonnet's (and any cheap model's) output - it confidently fabricates authoritative-looking specifics, a failure more effort does NOT fix. Use before relying on a Sonnet or Haiku answer when a load-bearing specific is at stake - a number, name, date, citation, API signature, config key. Also - can I trust this Sonnet answer.
---

# Calibrating trust in Sonnet (confident fabrication)

**The one rule: fluency is not reliability. A load-bearing SPECIFIC from Sonnet is a suspicion until an independent check confirms it — never trusted on Sonnet's confidence, and never on a single run.** Route work to Sonnet freely — it is a great workhorse and saves real tokens — then gate the specifics it cannot be trusted to get right. The danger is not that Sonnet looks wrong; it is that a fabricated specific arrives *polished, confident, and authoritative*, so a non-expert (and a trusting orchestrator that consumes its output) can't see it.

## The validated finding (receipt: `Claude Eval Sandbox/sonnet-intelligence-eval/`, 2026-06-13)

Measured over 8 everyday paste-and-ask tasks, blind Opus judge, Sonnet ×3 trials per task:
- **Sonnet is genuinely useful most of the time** — saves time ~75% (18/24), accuracy 2.42/3, calibration 2.17/3 (high-effort figures; the low-effort free-faithful run scored on par, nominally higher on aggregate, with the same fabrication failure mode). The point of this skill is NOT to distrust Sonnet broadly; it is to gate one specific failure mode.
- **The failure mode that matters: confident fabrication of authoritative-looking specifics, inconsistent run-to-run.** Concrete instances from the run: invented a tax dollar-figure the source notice never gave (all 3 trials; one a *major* hallucination that also misframed the document); flipped between a correct $4,225 and a wrong $3,900 on the *same* bi-weekly→monthly conversion across identical trials; wrote a fabricated surname into a form; a low-effort run invented specific router IPs and default admin/admin credentials, while asserting the cause was "100% DNS … 95% of the time."
- **Effort is NOT the lever.** A same-day low-effort re-run performed on par with high-effort; the tax-figure fabrication reproduced as a MAJOR hallucination at *both* efforts. This is the model's baseline behavior, not a thinking-budget shortfall — so **"bump Sonnet's effort to make a fabrication-prone task safe" does not work.** Either anchor/verify the specific, or escalate the *model*.
- **Haiku is worse** (accuracy 2.13, 4/8 saves-time; its worst answer confidently misdiagnosed a brake rattle as engine knock). **Opus removed all of it** (flawless: 8/8 saves-time, 3.00/3.00/3.00, 0 major hallucinations).
- **The safety floor held across ALL tiers.** Every model — Sonnet and Haiku included — rejected the dangerous "pour hot water on a frozen windshield" premise and flagged the phishing email. So this is a *factual-specifics* failure, **not** a *judgment or safety* failure. Do not over-rotate into distrusting Sonnet's reasoning, its refusals, or its calibration on uncertainty — those were fine.
- **Caveats:** n=8, single judge, no adversarial second-judge; "net time saved" is the judge's modeled estimate, not a user study. Treat the *rates* as directional; treat the *failure mode* as the durable, load-bearing signal.

## Trust vs. gate

**Trust Sonnet — route freely, no special gate:**
- Reasoning, code reading/understanding, applying a defined change, routine per-file analysis/review.
- Drafts, ideation, summaries, rewrites — anything a human or an Opus pass reviews before it becomes load-bearing.
- Mechanical transforms with a clear-correct answer (format, extract, collate).
- Anything **anchored** — the output is checked against a ground truth you supply: a source doc, a spec, a test, a reference output, a diff.
- Anything **verified downstream** — an Opus pass, a tool, a test, or a human gate sits under it (the "net under it" from `workflow-cost-discipline`).
- **Safety and judgment calls** — refusing a dangerous premise, flagging phishing, framing an uncertain diagnosis honestly. The floor held; Sonnet is fine here.

**Gate behind an independent check — do NOT trust on confidence:**
- A **number / figure / amount** that will be acted on: a total, a unit conversion, a threshold, a date-math result.
- A **name / surname / entity** written into a form, a draft, or a record.
- A **date / deadline / consequence** extracted from a document.
- A **citation / source / quote / URL** — Sonnet invents plausible-looking ones.
- An **API signature / function name / config key / CLI flag / version** — "does this exist / does it take these args."
- A **legal / medical / tax / financial / safety fact** stated as definite.
- A bare factual **"does X exist / is X true"** claim with no anchor.
- **Words put in someone's mouth** — a draft that asserts the user's facts or preferences that Sonnet was never given.

## How to gate a specific (cheapest sufficient first)

1. **Anchor it.** Give the producer or the checker a ground truth to compare against — the source document, a spec, a test, a reference output. The fabrication surface closes when there is something concrete to check against, so an *anchored* check is itself a Sonnet-safe job (per `workflow-cost-discipline`'s "anchored grading → Sonnet").
2. **Tool-verify it.** Run the code, hit the API, grep the file, do the date math in a script. Deterministic, zero hallucination risk, ~free. Prefer this for anything mechanically checkable (boring-over-clever applied to verification).
3. **Sample ≥2 / cross-check.** For a specific with no clean anchor, a single answer's confidence is worthless because it flips run-to-run. Run it ≥2× (or derive it a second, independent way): agreement is weak evidence; *disagreement is proof of fabrication*. This turns the run-to-run-inconsistency half of the finding into a cheap probe.
4. **Escalate the MODEL, not the effort.** If a specific is load-bearing and cannot be anchored or tool-checked, send *that piece* to Opus (flawless here) — not "Sonnet at higher effort," which does not help (effort is not the lever). Keep Sonnet for the surrounding cheap work; spend Opus narrow, on the specific.

## Boundaries and related skills

This skill owns the **trust-calibration principle** — when a cheap-model output is safe to rely on — and its **maintenance**. It is the canonical "why" the routing skills point to; it does not duplicate them.
- **Cost / mechanism** (which model is cheapest, workflow vs. subagent, per-stage routing) → `workflow-cost-discipline` (workflows) and `phase-gated-model-routing` (session phases). They decide *what to route*; this decides *what to trust*.
- **Bug-hunt application** → `efficient-bug-hunt` (not included in this pack) already bakes this in as the anti-fabrication finder contract + the adversarial-verifier firewall. Use it there; don't re-derive.
- **Picking the verifier's model** for a gate → `phase-gated-model-routing (absorbed cheapest-sufficient-model-eval, 2026-09-05)`. **Running a self-verifying loop** (writer ≠ grader is the same principle) → `loop-engineering`.

## Maintenance — own this loop (the owner, 2026-06-19)

the owner's standing ask: be the one who maintains, tests, and improves Sonnet's calibration. That means:
- **The finding is dated to Sonnet 4.6 (2026-06-13) and is model-baseline behavior, not a config artifact** — so it holds until the model changes. **Recheck trigger: when the default Sonnet version bumps (4.7 / 5 / …), re-run the eval before trusting this calibration** — fabrication rate and shape can shift with a new model. Update this skill + the `FINDINGS.md` entry to the new receipts; never carry a stale rate.
- **Re-validate** via the existing harness: `Claude Eval Sandbox/sonnet-intelligence-eval/` (8 paste-and-ask tasks, blind Opus judge, Sonnet ×3 for consistency). It **defaults to a no-cost dry run** — pass `args.execute=true`, and a cheap `taskIds` subset for a smoke test. Re-confirm the two load-bearing claims: (a) the specifics-fabrication still reproduces, (b) effort is still not the lever.
- **Harden this skill's execution** with the weak-model loop (`skill-execution-hardening`): does a cold Haiku session, handed a specific-bearing task plus this skill, actually insert the gate? Test triggering with `skill-execution-hardening (absorbed skill-trigger-test-windows, 2026-09-05)`. Writer ≠ grader — a fresh subagent grades, never the author.
- **Failures become durable checks.** When a real Sonnet fabrication slips through in live work, file it the same session as a named test case (the symptom + the specific it invented + the gate that would have caught it) and fold the class into the gate list above — don't let the fix live only in chat memory.
