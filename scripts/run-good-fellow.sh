#!/usr/bin/env bash
# good-fellow cron runner: every 30 minutes, run the sweep skills headlessly.
#
# The sweep logic lives in the skills (skills/*/SKILL.md), versioned in this repo.
# This script only decides when to run, which agent CLI to use, and how to fail.
#
# Auth (either works):
#   claude: CLAUDE_CODE_OAUTH_TOKEN in ~/.good-fellow/env (chmod 600), or a login in
#           ~/.claude/.credentials.json
#   codex:  a login in ~/.codex/auth.json
#
# Env:
#   GOOD_FELLOW_DRY_RUN=1  -> verify auth/lock/CLI selection, run a trivial prompt.

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${GOOD_FELLOW_STATE_DIR:-$HOME/.good-fellow}"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/.lock"
ENV_FILE="$STATE_DIR/env"
# One run must finish before the next 30-minute tick; 25 min leaves a safety margin.
MAX_RUNTIME="${GOOD_FELLOW_MAX_RUNTIME:-1500}"

export HOME="${HOME:-/root}"
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

mkdir -p "$LOG_DIR" "$STATE_DIR/worktrees"

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

# --- single-instance lock: skip this tick if a run is still going -------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "previous run still holds $LOCK_FILE; skipping this tick"
  exit 0
fi

# --- optional env file (claude oauth token etc.) ------------------------------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

# --- gh must be authenticated -------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  log "FATAL: gh is not logged in; run the onboard skill first"
  exit 78 # EX_CONFIG
fi

# --- pick the agent CLI: prefer claude, fall back to codex --------------------
AGENT=""
if command -v claude >/dev/null 2>&1 \
   && { [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || [[ -s "$HOME/.claude/.credentials.json" ]]; }; then
  AGENT=claude
elif command -v codex >/dev/null 2>&1 && [[ -s "$HOME/.codex/auth.json" ]]; then
  AGENT=codex
else
  log "FATAL: no authenticated agent CLI found. Either:"
  log "  1) claude setup-token -> put CLAUDE_CODE_OAUTH_TOKEN=... in $ENV_FILE (chmod 600), or"
  log "  2) log in with 'claude login' or codex on this machine"
  exit 78
fi
log "agent CLI: $AGENT"

# --- build the sweep prompt ---------------------------------------------------
if [[ "${GOOD_FELLOW_DRY_RUN:-0}" == "1" ]]; then
  PROMPT='Reply with exactly: good-fellow dry run ok. Do nothing else.'
  log "dry run mode"
else
  PROMPT="You are running an unattended good-fellow sweep on behalf of the user.

First read $REPO_DIR/docs/conventions.md and ~/.good-fellow/instruction.md and obey
both throughout. Then execute these four skills in order, each per its SKILL.md:

1. reply-notifications ($REPO_DIR/skills/reply-notifications/SKILL.md)
2. join-discussions    ($REPO_DIR/skills/join-discussions/SKILL.md)
3. fix-assigned-issues ($REPO_DIR/skills/fix-assigned-issues/SKILL.md)
4. process-prs         ($REPO_DIR/skills/process-prs/SKILL.md)

No user is present: never wait for input, prefer skipping over guessing, and finish
with one consolidated report of everything done and skipped."
fi

# --- run ----------------------------------------------------------------------
cd "$REPO_DIR"
STATUS=0
case "$AGENT" in
  claude)
    # Not --dangerously-skip-permissions: claude refuses that as root. Pre-authorizing
    # the tool set covers the sweep (gh/git run through Bash) and works for any user.
    timeout --kill-after=30 "$MAX_RUNTIME" \
      claude -p "$PROMPT" \
        --allowedTools Bash Read Grep Glob Write Edit MultiEdit Skill TodoWrite || STATUS=$?
    ;;
  codex)
    timeout --kill-after=30 "$MAX_RUNTIME" \
      codex exec --dangerously-bypass-approvals-and-sandbox "$PROMPT" || STATUS=$?
    ;;
esac

if [[ $STATUS -eq 124 || $STATUS -eq 137 ]]; then
  log "run hit the ${MAX_RUNTIME}s timeout; remaining work rolls over to the next tick"
elif [[ $STATUS -ne 0 ]]; then
  log "agent exited with status $STATUS"
fi

# --- log rotation -------------------------------------------------------------
find "$LOG_DIR" -name '*.log' -mtime +14 -delete 2>/dev/null || true

log "done (status $STATUS)"
exit "$STATUS"
