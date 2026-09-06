#!/usr/bin/env bash
# Event-driven watcher for a GitHub issue/PR thread.
#
# Emits ONE stdout line per NEW item from anyone other than the authenticated
# account, across THREE channels for a PR:
#   - conversation comments   (issues/{n}/comments)   seen-key: <id>     (bare)
#   - inline review comments  (pulls/{n}/comments)     seen-key: rc:<id>
#   - review submissions      (pulls/{n}/reviews)      seen-key: rv:<id>
# plus issue/PR state changes. For a plain ISSUE only the conversation channel
# and state are polled (the pulls/* endpoints don't exist; detected once up front
# so we don't 404 every cycle).
#
# When launched under the `Monitor` tool, each emitted line becomes a chat
# notification that re-invokes the agent to analyze and (per the gh-comment-watch
# autonomy) auto-post an in-scope reply.
#
# Loop-safety: the authenticated account's OWN items are excluded, so an
# auto-posted reply never re-triggers the watch. Dedup is by (channel,id) via a
# persistent seen-file, so an edited/old item never re-fires and a RESTARTED
# monitor auto-catches anything posted while it was down. Conversation-comment
# keys stay BARE for backward-compat with pre-existing seen-files; the two PR
# channels are prefixed so their separate id-spaces can never collide.
#
# Required env:
#   GCW_REPO     owner/repo  -- for a FORK PR this is the UPSTREAM repo, because
#                the PR object lives upstream (e.g. OWNER/REPO), NOT the fork
#   GCW_NUMBER   issue or PR number    (e.g. 4939)
# Optional env:
#   GCW_ME       account to exclude    (default = gh authenticated login)
#   GCW_DIR      state dir for seen/alive files (default = $TMPDIR or /tmp)
#   GCW_INTERVAL poll seconds          (default 60; keep >=30 for remote APIs)
set -u
: "${GCW_REPO:?set GCW_REPO=owner/repo}"
: "${GCW_NUMBER:?set GCW_NUMBER=issue-or-pr-number}"
ME="${GCW_ME:-$(gh api user --jq .login 2>/dev/null)}"
export ME
DIR="${GCW_DIR:-${TMPDIR:-/tmp}}"
INT="${GCW_INTERVAL:-60}"
mkdir -p "$DIR"
slug="${GCW_REPO//\//_}-${GCW_NUMBER}"
SEEN="$DIR/gcw-$slug.seen"
ALIVE="$DIR/gcw-$slug.alive"
touch "$SEEN"

# Detect once whether this number is a PR, so we skip pulls/* (404 on an issue).
is_pr=0
if gh api "repos/$GCW_REPO/pulls/$GCW_NUMBER" --jq .number >/dev/null 2>&1; then
  is_pr=1
fi

get_state(){ gh api "repos/$GCW_REPO/issues/$GCW_NUMBER" --jq .state 2>/dev/null | tr -d '\r\n '; }
state="$(get_state)"; [ -z "$state" ] && state=open

# Dedup a stream of "id<TAB>author<TAB>body" lines and emit the new ones.
#   $1 = seen-key prefix ("" = bare), $2 = human label
emit_new(){
  local pfx="$1" label="$2" id author body key
  while IFS=$'\t' read -r id author body; do
    id="$(printf '%s' "$id" | tr -d '\r\n ')"
    [ -z "$id" ] && continue
    key="$pfx$id"
    if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
      printf '%s\n' "$key" >> "$SEEN"
      printf 'NEW %s on %s#%s by %s (id %s): %s\n' "$label" "$GCW_REPO" "$GCW_NUMBER" "$author" "$id" "$body"
    fi
  done
}

while true; do
  : > "$ALIVE"   # liveness heartbeat (mtime checked by the ScheduleWakeup backstop)

  # 1) Conversation comments (issue + PR conversation tab). Keys stay bare.
  gh api "repos/$GCW_REPO/issues/$GCW_NUMBER/comments?per_page=100" \
    --jq '.[] | select(.user.login != env.ME) | "\(.id)\t\(.user.login)\t\(.body | gsub("[\n\r]+"; " ") | .[0:300])"' 2>/dev/null \
  | emit_new "" "COMMENT"

  if [ "$is_pr" = 1 ]; then
    # 2) Inline review comments (line notes in the "Files changed" tab). Prefix rc:
    gh api "repos/$GCW_REPO/pulls/$GCW_NUMBER/comments?per_page=100" \
      --jq '.[] | select(.user.login != env.ME) | "\(.id)\t\(.user.login)\t\(.path // "?"):\(.line // .original_line // 0) \(.body | gsub("[\n\r]+"; " ") | .[0:300])"' 2>/dev/null \
    | emit_new "rc:" "REVIEW COMMENT"

    # 3) Review submissions (APPROVED / CHANGES_REQUESTED / a review summary body).
    #    Skip the empty "COMMENTED" wrapper GitHub auto-creates to hold inline notes.
    gh api "repos/$GCW_REPO/pulls/$GCW_NUMBER/reviews?per_page=100" \
      --jq '.[] | select(.user.login != env.ME) | select((.body | length > 0) or (.state == "APPROVED") or (.state == "CHANGES_REQUESTED") or (.state == "DISMISSED")) | "\(.id)\t\(.user.login)\t[\(.state)] \(.body | gsub("[\n\r]+"; " ") | .[0:300])"' 2>/dev/null \
    | emit_new "rv:" "REVIEW"
  fi

  # 4) State flip (closed / merged / reopened).
  cur="$(get_state)"; [ -z "$cur" ] && cur="$state"
  if [ "$cur" != "$state" ]; then
    printf 'STATE changed on %s#%s: %s -> %s\n' "$GCW_REPO" "$GCW_NUMBER" "$state" "$cur"
    state="$cur"
  fi

  sleep "$INT"
done
