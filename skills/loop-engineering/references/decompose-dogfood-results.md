# decompose-to-anchor -- dogfood validation (2026-06-17)

The skill was verified by **applying it to itself**: "is this skill good?" is subjective, so
it was decomposed to a mechanical anchor -- *a weak model (Haiku), given ONLY the skill on a
fresh subjective task it has never seen, must land on a genuinely mechanical leaf.* That is the
`skill-execution-hardening` weak-model loop, which is itself an instance of this skill's principle.

## Method

- **Writer != grader.** Writer = Haiku (via the Agent tool, `model: "haiku"`), blind (given only the
  SKILL.md path + the scenario, no answer key). Grader = Opus (this session).
- **Cheap ground truth, derived BEFORE running** -- four checkable properties per run:
  - **P1** -- recognizes there is no usable *top-level* mechanical anchor (doesn't fake one or punt to "use judgment").
  - **P2** -- decomposes the goal into sub-properties.
  - **P3** -- lands on at least one *genuinely mechanical* leaf (count / threshold / boundary / structural match / diff-vs-reference), not another vague proxy.
  - **P4** -- derives a stop condition from that leaf.
  - **P5** (bonus) -- reaches for the ground-truth-diff accelerant.
- **Non-forgeable honesty signal:** `tool_uses` from each Agent result. `tool_uses: 1` on every
  with-skill run = it actually opened and read the skill (one Read). Baseline = `tool_uses: 0` (no skill to read).
- Scenarios were chosen to be subjective-at-top and **NOT** the skill's worked example (video editing),
  to test transfer, not memorization. Effort: Haiku subagents inherited the session effort (session model Opus 4.8).

## Round 1 (baseline + 3 with-skill)

| Run | Scenario | tool_uses | P1 | P2 | P3 | P4 | P5 | Verdict |
|---|---|---|---|---|---|---|---|---|
| A | blog-post prose quality | 1 | Y | Y | assertion-evidence window, ending-structure, paragraph concreteness | Y | Y | PASS 5/5 |
| B | SaaS landing-page "professional" | 1 | Y | Y | WCAG contrast, padding scale, viewport fit, color count | Y | Y | PASS 5/5 |
| C | EN->DE doc translation | 1 | Y | Y | terminology cardinality, glossary exact-match, format diff | Y | Y | PASS 5/5 |
| baseline | blog-post prose (NO skill) | 0 | partial | Y | leaned on a model-judge rubric; **never reached ground-truth-diff** | Y | N | -- |

**Skill is load-bearing:** Haiku alone gives competent generic loop advice (rubric + model-judge + human
final call) but never reaches the ground-truth-diff accelerant and leans on a model-as-judge rubric rather
than scriptable leaves. The skill moves the weak model from "use a rubric" -> "decompose to scriptable
leaves + diff against a ground-truth library." Delta is real, not night-and-day (Haiku is a strong base).

## Round 2 -- confirming (fresh agents; consistency + harder generalization + a trap)

| Run | Scenario | tool_uses | P1 | P2 | P3 | P4 | P5 | Verdict |
|---|---|---|---|---|---|---|---|---|
| A' | blog-post prose (re-run) | 1 | Y | Y | 12-pt mechanical checklist + structural diff | Y | Y | PASS -- consistent with A |
| D | podcast audio "professional" | 1 | Y | Y | LUFS variance <2 dB, true-peak -3 dB, FFT hum @50/60 Hz, noise floor -60 dB | Y | Y | PASS -- clean new-domain transfer |
| E | mission statement "inspiring" (**TRAP**) | 1 | Y | Y | found only the *few* real ones (<=20 words, jargon-free, active-verb) | Y | Y | **PASS -- did NOT fake an anchor** |

**The trap (E)** is the load-bearing test: the scenario is mostly taste, and the skill's real risk is
pushing a weak model to *over-mechanize* (invent a fake "inspiration score"). Instead Haiku wrote:
*"What you CANNOT anchor without human taste: whether it's actually inspiring ... the final pick is
irreducibly taste; you can't automate it"* and gave a 3-mode answer (mechanical checks narrow the field
-> humans pick the winner). That is recipe step 6 + the "faking an anchor" anti-pattern holding under pressure.

## Outcome

- **6/6 with-skill runs pass across 5 domains** (prose x2, design, translation, audio, mission-statement),
  including the over-mechanization trap.
- **Converged at iteration 1 -- the draft needed no fix.** Per `skill-execution-hardening` step 8
  (stop deliberately; >=2 consecutive clean conditions across multiple trials), the loop was stopped here.
  No edit was applied, to avoid over-fitting (skill-creator: "don't put in fiddly overfitty changes").
- Cost: 7 Haiku runs ~= 31-38k subagent tokens each (~258k total) + Opus grading. Well under the
  ~1M-token ceiling the skill-execution-hardening worked example hit.

## Caveats (honest residual)

- A clean weak-model run shows the instructions survive a weak reader; it does not prove every real
  session is safe. A fix that stops *Haiku* over-mechanizing may not transfer to a different weak path.
- The prose runs trended slightly over-eager (long semi-mechanical checklists). The skill's
  "Anchoring everything or nothing" anti-pattern + the trap result cover this, so no edit was made --
  but if future runs fake anchors on taste-heavy tasks, tighten that anti-pattern first.
