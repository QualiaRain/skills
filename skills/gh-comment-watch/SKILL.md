---
name: gh-comment-watch
description: "After posting a Claude-authored comment to an external or upstream GitHub issue or PR, arm an event-driven watch that fires on a reply or state change, then analyze, re-test and auto-post follow-ups until resolved. Standard, not opt-in. Also for watching a thread you did NOT comment on - monitor this PR for replies, ping me when the maintainer responds, notify me when #NNNN changes. Not for comments in the owner's own voice."
---

# Post-comment watch: arm an event-driven monitor, auto-resolve until done

When you post a Claude-authored comment to an upstream GitHub issue/PR, **posting is only half the
job** — a maintainer or reporter will often reply, and an AI being slow to answer follow-ups on its
own comment is the failure this skill prevents. So immediately after posting, **arm an event-driven
watch** that wakes you the moment there's a reply, and resolve the thread autonomously.

Established as standing process by the account owner 2026-06-17 (born from OWNER/REPO#123).

## When this fires

- **TRIGGERS:** any comment you (Claude) post to a GitHub issue/PR the account owner does **not**
  own — the disclosed, Claude-authored kind that can draw a follow-up.
- **SKIPS:** a comment drafted in the account owner's own voice that he reviews and sends; a terminal
  sign-off that expects no reply ("thanks, confirmed fixed"); non-GitHub messages (Slack/email);
  PR branch-push/open mechanics (that's `upstream-submission-walkthrough`).

## The standing autonomy boundary (account owner, 2026-06-17)

Each reply itself opens with the Claude disclosure line, so honesty is carried per-reply — no human
review is claimed and none is needed for routine answers. On a watched-thread event:

- **On-topic follow-up to my comment** (the bug, the workaround, the fix, a clarifying question I can
  answer) → analyze, re-test locally if it needs evidence, draft per `ai-authorship-disclosure` (not included in this pack), and
  **AUTO-POST it** via `gh-safe-comment-edit`. No go needed.
- **A new outward ACTION beyond replying** — the maintainer wants a PR opened (especially in a
  *different* repo, e.g. huggingface/diffusers), or wants a code change on the upstream project's side → post a brief
  courteous ack if natural, then **SURFACE the bigger action to the account owner** with a ready
  plan. Do not auto-open.
- **Contentious / a disagreement with the maintainer / anything reputational** → **SURFACE, do not
  auto-post.**
- **No activity** → stay silent; the monitor keeps watching.

## Procedure

### 1. Post the comment
Use `gh-safe-comment-edit` (`ghsafe.py post`) — never hand-roll a `gh api` write (mojibake/CRLF
risk). Run `ai-authorship-disclosure` on the CONTENT first. Capture the numeric comment id and the
issue/PR number.

### 2. Arm the event-driven monitor
The watcher script is `scripts/watch_issue.sh` (in this skill). It polls every 60s and emits one
line per NEW comment (anyone but the authenticated account) or state change, dedup'd by comment id.
Smoke-test the core pipeline once (it should emit nothing right after you post — only your own
comment exists, which is excluded), then launch it **persistent** under the `Monitor` tool:

```
# Smoke-test (expect no output = correct):
GCW_REPO=OWNER/REPO GCW_NUMBER=123 \
  bash -c 'gh api "repos/$GCW_REPO/issues/$GCW_NUMBER/comments?per_page=100" \
    --jq ".[] | select(.user.login != \"$(gh api user --jq .login)\") | .id"'

# Launch under Monitor (persistent=true, timeout_ms=3600000), description e.g.
#   "new comments / state changes on OWNER/REPO#123":
GCW_REPO=OWNER/REPO GCW_NUMBER=123 GCW_DIR=<project>/tmp \
  bash "<this-skill>/scripts/watch_issue.sh"
```

Set `GCW_DIR` to a writable, gitignored scratch dir (so the `.seen`/`.alive` state persists across a
restart but never gets committed). On Windows/Git-Bash use forward-slash absolute paths.

### 3. Arm a liveness backstop (optional but recommended)
A long `ScheduleWakeup` (~30 min) whose ONLY job is to relaunch the monitor if it died — it checks
the heartbeat file `GCW_DIR/gcw-<repo>-<number>.alive` (touched every ~60s):
`find "<GCW_DIR>/gcw-<slug>.alive" -mmin -5` → prints path = alive (re-arm, silent); prints nothing
= dead → relaunch the Monitor and re-arm. The backstop **never polls or posts** — replies are driven
only by the monitor's emitted events (prevents double-posting). The persistent seen-file means a
relaunched monitor re-emits anything missed during downtime.

### 4. Handle each emitted event
When a `NEW COMMENT …` or `STATE changed …` event lands, act per the autonomy boundary above. Record
what you posted in the project's notes/handoff. Then the monitor keeps running (no re-arm needed —
it's persistent).

### 5. Stop when resolved
"Resolved" = the issue/PR is **closed or merged**, OR the maintainer/reporter **confirms and nothing
is pending**, OR the thread has been **quiet for ~7 days** after the last exchange, OR the account
owner says stop. Then `TaskStop` the monitor and omit the backstop re-arm. Until then, keep watching.

## Loop-safety invariants (do not break)

- **Exclude the authenticated account** (`GCW_ME`, default `gh api user --jq .login`) — an auto-posted
  reply must never re-trigger the watch.
- **Dedup by comment id** via the persistent seen-file — an edit or a re-fetch must not re-handle a
  comment (which would double-reply).
- **Backstop never posts** — only the monitor's events drive replies.
- **Session-bound** — Monitor and ScheduleWakeup both die when the session ends. To keep watching
  across sessions, the project's `next.md`/handoff must say how to re-arm (relaunch the Monitor with
  the same env + command); leave a watch entry there.
- **Disclosure + posting mechanics are delegated** — content goes through `ai-authorship-disclosure`,
  posting through `gh-safe-comment-edit`. This skill owns only the watch + the autonomy routing.

## Watching a thread you did NOT just comment on

You want a Claude Code session to notice when an external PR/issue gets new activity (a maintainer
reply, a review, a label, a merge/close) and **wake itself to act** — without you babysitting it and
without a usage-burning timer that re-reads cold context every half hour for nothing.

The pattern generalizes to **any external resource you can poll** (a CI run, a release feed, a status
page). GitHub is the worked example.

### Lead with the negative result (so nobody re-investigates it)

**A local Claude Code session CANNOT receive a true push event from GitHub.** The session runs behind
NAT with no inbound port; a GitHub "push" means a **webhook**, which needs a publicly reachable HTTP
receiver. The only real-push path is `webhook + a public tunnel (ngrok/cloudflared) + a local
listener` — **not worth it for a few threads**, and it opens an inbound attack surface. Do not build
it for routine PR-watching.

Verified empirically (don't re-run these — the answers are stable):

- **No GraphQL subscriptions.** `gh api graphql -f query='{__schema{subscriptionType{name}}}'` →
  `subscriptionType: null`. GitHub's GraphQL API has no streaming/subscription type.
- **Notifications REST API is poll-only**, with a server-enforced `X-Poll-Interval` **floor of 60s**.
- **`gh` has no `--watch` / event-stream subcommand.**
- **No GitHub MCP server is connected by default** on this machine.

So every real option is **polling**. The skill below is the cheapest correct way to poll.

### The right answer: a hybrid (primary signal + long backstop)

This is the `ScheduleWakeup` spec's own prescribed shape — a **primary background signal** plus a
**long fallback** — instantiated for GitHub.

#### 1. Primary signal — a `run_in_background` long-poll task

The load-bearing mechanism: a `run_in_background` Bash task **re-invokes the session when it exits**
(confirmed in the Bash tool spec). So write a script that:

- records each watched thread's baseline `updatedAt|state`,
- sleeps 60s in a loop and re-reads,
- `exit 0`s **the instant any thread differs** from its baseline.

That wakes the session ~1 minute after real activity, at **zero idle-wake cost** (a background sleep
costs nothing; only the exit-on-change wakes you).

Watch `updatedAt` + `state` **directly** — both bump on a comment, review, label, merge, or close. Do
NOT route this through the Notifications API: its per-thread subscription/read state is fiddly and
easy to get wrong, and `updatedAt|state` is a clean, total signal.

#### 2. Backstop — a long `ScheduleWakeup`

Arm one `ScheduleWakeup`, clamped to `[60, 3600]` seconds (max 1h). Its **only** job is to catch a
silently-dead watcher: on fire, re-check the threads once and **relaunch** the background task if it
died. The backstop never drives the action — the background task's exit does — so the two can't
double-act.

### Why this matters: the win is COST, not latency

A naive 30-minute timer wakes the session **~48×/day**, each time a full **cold context re-read**,
even when nothing happened. The background watcher wakes it **only on real activity**. On a metered
plan that is the entire benefit. (Latency improving from 30 min to ~1 min is real but usually
irrelevant for watching a maintainer reply — don't sell the latency; sell the avoided idle wakes.)

### The hard limit — state it plainly so nobody chases a fix

**This only runs while the Claude Code app/session is open.** App open → hands-off, it wakes on
change. App closed → the watch **pauses**, and resumes when you reopen. No mechanism fixes that
without cloud infrastructure.

And a cloud cron **cannot** substitute: the follow-on work — run a verifier, push a fix from a
**local** clone, run local reproducers — needs **this machine's local files**. A cloud routine could
detect the change but couldn't do the thing you actually wake up to do. Don't propose one as the fix.

### Copy-paste watcher template

Drop this in a gitignored scratch dir (e.g. `<project>/tmp/watch_threads.sh`), fill the PLACEHOLDERs,
strip CR, and launch it with `run_in_background: true`. It is deliberately rote so the cheapest model
can replay it with no reasoning.

```bash
#!/usr/bin/env bash
# Background long-poll watcher. Exits 0 the instant any watched thread changes
# (new comment/review/label/state), which re-invokes the Claude Code session via
# run_in_background's exit notification. Zero idle-wake cost; a long ScheduleWakeup backstops it.
set -u
REPO="OWNER/REPO"          # e.g. OWNER/REPO

# One getter per watched thread. PR -> `gh pr view`, issue -> `gh issue view`.
# Add/remove getters to match the threads you're watching.
get_a() { gh pr    view PR_NUMBER    --repo "$REPO" --json updatedAt,state -q '.updatedAt+"|"+.state' 2>/dev/null; }
get_b() { gh issue view ISSUE_NUMBER --repo "$REPO" --json updatedAt,state -q '.updatedAt+"|"+.state' 2>/dev/null; }

base_a="$(get_a)"; base_b="$(get_b)"
echo "baseline  a=$base_a  b=$base_b"

# 2880 cycles * 60s = 48h safety bound; on timeout it exits and the session re-checks + relaunches.
max_cycles=2880
for ((i=0; i<max_cycles; i++)); do
  sleep 60
  cur_a="$(get_a)"; cur_b="$(get_b)"
  # Tolerate a transient empty result (network/auth blip) WITHOUT a false trigger.
  [ -z "$cur_a" ] && continue
  [ -z "$cur_b" ] && continue
  if [ "$cur_a" != "$base_a" ] || [ "$cur_b" != "$base_b" ]; then
    echo "CHANGE DETECTED at cycle $i"
    echo "a: $base_a  ->  $cur_a"
    echo "b: $base_b  ->  $cur_b"
    exit 0
  fi
done
echo "max cycles reached (48h), no change detected"
exit 0
```

**Launch sequence:**

1. **Strip CR first** (Windows/Git-Bash — a stray `\r` breaks the shebang and the loop):
   `sed -i 's/\r$//' <project>/tmp/watch_threads.sh`
2. **Run it** with the Bash tool, `run_in_background: true`. On exit you're re-invoked; read its
   stdout to see which thread changed, then act.
3. **Arm the backstop** — a `ScheduleWakeup` of ~3600s whose only job, on fire, is to confirm the
   background task is alive and relaunch it if not.

#### Gotchas baked into the template (don't re-derive these)

- **Windows CR.** Strip `\r` before running, every time — silent breakage otherwise.
- **gh JSON read.** `gh pr view <N> --repo <owner/repo> --json updatedAt,state -q '.updatedAt+"|"+.state'`
  (and `gh issue view` identically). `updatedAt|state` is the total change signal.
- **Tolerate empty results.** A network/auth blip returns an empty string; `continue` past it so it
  never counts as a "change" and fires a false wake.
- **Max-cycle safety bound.** The loop self-exits after ~48h (`exit 0`) so a forgotten watcher
  becomes a re-check, not an immortal process; the backstop relaunches if the threads still matter.

### Relationship to sibling skills

- **`gh-comment-watch`** — the narrower companion: *you just posted a disclosed, Claude-authored
  comment to an upstream issue/PR and want to auto-resolve the reply thread* (its own monitor +
  auto-post-the-reply autonomy boundary). If that's the situation, use it; it owns the reply policy.
  This skill owns the **general** "watch any external thread/resource and wake on change" mechanism
  and the push-impossibility result.
- **`loop-engineering`** — iterate-until-green / writer≠grader, watching **your own** work toward a
  measurable finish. This skill is its outward-facing sibling: watching an **external** resource you
  don't control and waking on its change. Cross-link, don't duplicate.

## Notes / limits

- **All three PR feedback channels are watched** (verified 2026-06-28 against cli/cli#13723):
  conversation comments (`issues/{n}/comments`), inline review comments in the Files-changed tab
  (`pulls/{n}/comments`, emitted with `file:line`), and review submissions
  (`pulls/{n}/reviews`, emitted with `[APPROVED]`/`[CHANGES_REQUESTED]`/etc.). The empty `COMMENTED`
  review wrapper GitHub auto-creates to hold inline notes is filtered out so it isn't double-counted.
  For a plain issue the pulls/* channels are detected-absent once and skipped (no per-cycle 404).
- **`GCW_REPO` is the UPSTREAM repo for a fork PR.** A fork→upstream PR object lives on the upstream
  repo, so point the watch at e.g. `OWNER/REPO`, never `yourfork/REPO`, or it watches nothing.
- Authenticated GitHub rate limit is 5000/hr; 60s polling (~4 calls/cycle for a PR) is well under it.
- Hard Rules / project constraints still bind every action the watch takes (e.g. never touch a second install,
  never open generated images; local re-tests only).

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
