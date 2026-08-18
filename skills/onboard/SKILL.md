---
name: onboard
description: One-time interactive setup for the good-fellow GitHub automation. Installs the skills for every agent on the machine, checks gh login (guides device-code login on a remote machine), finds or creates the user's personal good-fellow-instruction.md gist, verifies headless agent auth (claude, codex, or cursor), generates the runner script, and installs a 30-minute cron job that runs the sweep skills. Use when the user says onboard, /onboard, set up good-fellow, or initialize the GitHub agent.
---

# Onboard

Interactive bootstrap for good-fellow. Run each step in order, report progress as you
go, and finish with a summary of what was configured. This skill is the only
good-fellow skill allowed to prompt the user and to change machine state (symlinks,
generated scripts, crontab).

Read `docs/conventions.md` in this repo first. Resolve `<REPO_ROOT>` from this file's
real location (`SKILL.md` may be reached through a symlink — follow it). Everything
below must work for **any user on macOS or Linux**: derive paths from `$HOME`, never
assume a username, and prefer commands available in both GNU and BSD userlands.

## Step 0 — Tell the user what will be touched, then create the state directory

Onboarding writes **outside the repository**, and most agents restrict that: the
`Write`/`Edit` tools typically refuse absolute paths outside the working directory,
which mid-flow shows up as a blocked write and a permission dialog. Two rules avoid
that entirely:

- **Never use the `Write`/`Edit` tools for anything outside `<REPO_ROOT>`.** Create
  out-of-tree files with a single `Bash` heredoc instead (`cat > file <<'EOF'`).
  Bash is governed by command permissions rather than the workspace path check, so
  one approval covers the whole write.
- **Ask once, up front.** Before touching anything, list every out-of-tree path this
  skill will create or modify, so the user grants access knowingly instead of being
  interrupted later:

  | Path | Why |
  |---|---|
  | `~/.good-fellow/` | state: instruction cache, logs, worktrees, generated runner |
  | `~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/` | skill symlinks (only for agents that exist) |
  | the user's crontab | the 30-minute schedule |

  Mention that they can pre-authorize instead of approving each step — in Claude
  Code, starting the session with `claude --add-dir ~/.good-fellow` (after Step 0
  creates it) or approving the first Bash write covers the rest.

If a write is denied anyway, **do not stop and do not leave setup half-finished**:
print the exact command block for the user to paste into their own shell, ask them to
confirm when done, then verify the result yourself (`test -x`, `crontab -l`) and carry
on with the remaining steps.

Create the state directory now — this is also the first approval prompt, so say what
it is for:

```bash
mkdir -p ~/.good-fellow/logs ~/.good-fellow/worktrees
```

## Step 1 — Install the skills for every agent on this machine

Detect installed agents by their home directories: `~/.claude`, `~/.codex`,
`~/.cursor` (ask the user about any other agent they use that reads SKILL.md
folders). For each detected agent, symlink every skill folder from this repo into its
skills directory. Rules:

- Create the `skills` directory if missing.
- If the target name is already a symlink, refresh it (`ln -sfn`; BSD `-n` behaves
  like `-h`, so this works on macOS too).
- If the target exists and is **not** a symlink, leave it alone and warn — never
  overwrite someone's real skill.

Example (adapt as needed):

```bash
for base in "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
  [ -d "$base" ] || continue
  mkdir -p "$base/skills"
  for skill in <REPO_ROOT>/skills/*/; do
    name=$(basename "$skill")
    if [ -e "$base/skills/$name" ] && [ ! -L "$base/skills/$name" ]; then
      echo "SKIP: $base/skills/$name exists and is not a symlink"
    else
      ln -sfn "${skill%/}" "$base/skills/$name"
    fi
  done
done
```

## Step 2 — GitHub CLI login

Run `gh auth status`. If logged in, report the account and continue.

If not logged in, assume a remote/headless machine with no browser. Start the
device-code flow in the background so you can stream its output:

```bash
gh auth login --hostname github.com --git-protocol https --web
```

The command prints a one-time code (like `XXXX-XXXX`) and the URL
`https://github.com/login/device`, then waits. Relay both to the user verbatim and
tell them to open the URL on their own computer/phone and enter the code. Wait for
the command to complete, then re-run `gh auth status` to confirm. If the code
expires, restart the login and relay the fresh code.

## Step 3 — Personal instruction gist

Look for the gist:

```bash
gh api /gists --paginate --jq '.[] | select(.files["good-fellow-instruction.md"]) | .id' | head -1
```

- **Found**: download it to the cache and show the user a short summary of what it
  says:

  ```bash
  gh gist view <GIST_ID> --filename good-fellow-instruction.md > ~/.good-fellow/instruction.md
  ```

- **Not found**: explain that this file holds their standing instructions (reply
  language, review taste, repos to prioritize/skip, tone) applied to every GitHub
  task. Ask them to dictate the content now, then save it with a heredoc — **not the
  `Write` tool**, which would be blocked outside the repo (Step 0):

  ```bash
  cat > ~/.good-fellow/instruction.md <<'EOF'
  <the user's instructions>
  EOF
  ```

  Show it back for confirmation, then upload it as a secret gist so future machines
  can reuse it. The filename inside the gist must be exactly
  `good-fellow-instruction.md` (gist filenames come from the local file name, so
  create it from a copy with that name):

  ```bash
  cp ~/.good-fellow/instruction.md /tmp/good-fellow-instruction.md
  gh gist create /tmp/good-fellow-instruction.md --desc "good-fellow personal instructions"
  ```

## Step 4 — Headless agent auth

The scheduled job needs an agent CLI that runs without a human. Check, in order
(matching the runner's auto-detect):

1. `claude`: usable if `~/.good-fellow/env` defines `CLAUDE_CODE_OAUTH_TOKEN`, or
   `~/.claude/.credentials.json` exists.
2. `codex`: usable if `~/.codex/auth.json` exists.
3. `cursor-agent`: usable if installed and `cursor-agent status` shows a login.

If none is usable, ask the user to fix it and pause until they have. Have them run
these **themselves** rather than pasting the token to you — it is a long-lived
credential, and this keeps it out of the transcript:

```bash
claude setup-token
umask 077 && printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' '<token>' >> ~/.good-fellow/env
```

Alternatively they can log in with codex or cursor-agent. Verify afterwards without
printing the secret (`test -s ~/.good-fellow/env`, `grep -c CLAUDE_CODE_OAUTH_TOKEN
~/.good-fellow/env`). Do not install a scheduled job that can never run.

## Step 5 — Generate the runner script

Cron needs a file to invoke, so generate one at `~/.good-fellow/run-good-fellow.sh`.
Do not copy it from anywhere — write it from the reference below, adjusting for what
you learned in Steps 1–4 (e.g. hardcode the detected `<REPO_ROOT>`).

**Write it with a single Bash heredoc, never the `Write` tool** (Step 0): the target
is outside the repo, so `Write` gets blocked and interrupts onboarding. Use a
**quoted** delimiter so the runner's own `$HOME`, `$STATUS`, `$PROMPT` etc. are
written literally instead of being expanded now, and combine the write with `chmod`
so one approval finishes the step:

```bash
cat > ~/.good-fellow/run-good-fellow.sh <<'GOOD_FELLOW_RUNNER_EOF'
<the full runner script>
GOOD_FELLOW_RUNNER_EOF
chmod +x ~/.good-fellow/run-good-fellow.sh
```

Then verify it before relying on it: `bash -n ~/.good-fellow/run-good-fellow.sh`
(syntax) and `test -x ~/.good-fellow/run-good-fellow.sh` (executable).

Requirements the generated script must satisfy:

- **Portability**: runs on macOS's default bash 3.2 and BSD userland as well as
  Linux. No `flock` on macOS → fall back to an atomic `mkdir` lock. No GNU `timeout`
  on macOS → use `gtimeout` if present, else run without a hard limit.
- **Single instance, orphan-proof**: skip the tick if the previous run still holds
  the lock — but the lock design must make "stuck forever" impossible:
  - The runner **process itself** holds the lock. Never spawn a sentinel/background
    process to hold it: if that child leaks, every later tick sees "concurrent run"
    and silently skips for days (this happened in production).
  - Launch the agent child with the lock fd **closed** (`9>&-`) so no leaked
    subprocess can inherit it and keep the lock alive after the runner exits.
  - Record the holder PID and acquisition time. A contender that finds a lock older
    than ~2×MAX_RUNTIME (healthy runs are hard-capped at MAX_RUNTIME) must treat it
    as stuck: log loudly, kill the recorded holder, and reclaim — never skip.
  - Open the flock file with append (`9>>`), not truncate (`9>`): a truncating open
    happens even when the contender then fails to get the lock, which would reset
    the staleness clock on every tick.
  - Every skip logs the holder PID and lock age so repeated skips are diagnosable.
- **PATH**: cron strips the environment — rebuild a PATH covering `$HOME/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, and the system dirs.
- **Auth checks**: `gh auth status` must pass; agent CLI auto-detect in the order
  claude → codex → cursor-agent (overridable via `GOOD_FELLOW_AGENT`).
- **Workspace access**: the sweeps clone into `~/<repo>` and use
  `~/.good-fellow/worktrees/`, both outside the runner's working directory. Grant
  access explicitly (`claude --add-dir "$HOME"`), otherwise those writes are blocked
  with nobody present to approve them and the run fails silently.
- **Claude invocation**: do NOT use `--dangerously-skip-permissions` (claude refuses
  it when running as root); pre-authorize tools with `--allowedTools` instead.
- **Timeout**: default 1500s so a run always ends before the next 30-minute tick.
- **Log rotation**: delete logs in `~/.good-fellow/logs` older than 14 days.

Reference implementation:

```bash
#!/usr/bin/env bash
# good-fellow runner — generated by the onboard skill. Sweep logic lives in the
# skills at <REPO_ROOT>/skills/*/SKILL.md; this script only decides when/how to run.
set -Eeuo pipefail

REPO_DIR="<REPO_ROOT>"
STATE_DIR="$HOME/.good-fellow"
MAX_RUNTIME="${GOOD_FELLOW_MAX_RUNTIME:-1500}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
mkdir -p "$STATE_DIR/logs" "$STATE_DIR/worktrees"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# --- single-instance lock, orphan-proof ---------------------------------------
# The runner PROCESS holds the lock (flock on Linux, atomic mkdir on macOS); the
# agent child is started with the lock fd closed (9>&-) so a leaked subprocess can
# never keep the lock. A lock older than STALE_AFTER cannot belong to a healthy run
# (runs are capped at MAX_RUNTIME): kill the holder and reclaim, never skip forever.
LOCK="$STATE_DIR/.lock"; PIDFILE="$STATE_DIR/.lock.pid"
STALE_AFTER=$((MAX_RUNTIME * 2 + 300))
age_of() { m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0); echo $(( $(date +%s) - m )); }

if command -v flock >/dev/null 2>&1; then
  exec 9>>"$LOCK"   # >> not >: opening must not reset the staleness clock
  if ! flock -n 9; then
    holder=$(cat "$PIDFILE" 2>/dev/null || echo unknown); age=$(age_of "$PIDFILE")
    if [ "$age" -le "$STALE_AFTER" ]; then
      log "previous run still going (holder $holder, ${age}s); skipping this tick"; exit 0
    fi
    log "ERROR: lock stuck for ${age}s (holder $holder); killing holder and reclaiming"
    kill "$holder" 2>/dev/null || true; sleep 5; kill -9 "$holder" 2>/dev/null || true
    flock -w 30 9 || { log "FATAL: lock still held after killing $holder; manual cleanup needed"; exit 75; }
  fi
  echo $$ > "$PIDFILE"
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    holder=$(cat "$LOCK.d/pid" 2>/dev/null || echo unknown); age=$(age_of "$LOCK.d")
    if kill -0 "$holder" 2>/dev/null && [ "$age" -le "$STALE_AFTER" ]; then
      log "previous run still going (holder $holder, ${age}s); skipping this tick"; exit 0
    fi
    log "reclaiming stale lock (holder $holder no longer valid, age ${age}s)"
    kill "$holder" 2>/dev/null || true
    rm -rf "$LOCK.d"; mkdir "$LOCK.d" || { log "FATAL: cannot reclaim lock"; exit 75; }
  fi
  echo $$ > "$LOCK.d/pid"
  trap 'rm -rf "$LOCK.d" 2>/dev/null || true' EXIT
fi

[ -f "$STATE_DIR/env" ] && { set -a; . "$STATE_DIR/env"; set +a; }
gh auth status >/dev/null 2>&1 || { log "FATAL: gh not logged in; run onboard"; exit 78; }

AGENT="${GOOD_FELLOW_AGENT:-}"
if [ -z "$AGENT" ]; then
  if command -v claude >/dev/null 2>&1 && { [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ -s "$HOME/.claude/.credentials.json" ]; }; then
    AGENT=claude
  elif command -v codex >/dev/null 2>&1 && [ -s "$HOME/.codex/auth.json" ]; then
    AGENT=codex
  elif command -v cursor-agent >/dev/null 2>&1; then
    AGENT=cursor
  else
    log "FATAL: no authenticated agent CLI (claude/codex/cursor-agent); run onboard"; exit 78
  fi
fi
log "agent CLI: $AGENT"

PROMPT="You are running an unattended good-fellow sweep on behalf of the user.

First read $REPO_DIR/docs/conventions.md and ~/.good-fellow/instruction.md and obey
both throughout. Then execute these four skills in order, each per its SKILL.md:

1. reply-notifications ($REPO_DIR/skills/reply-notifications/SKILL.md)
2. join-discussions    ($REPO_DIR/skills/join-discussions/SKILL.md)
3. fix-assigned-issues ($REPO_DIR/skills/fix-assigned-issues/SKILL.md)
4. process-prs         ($REPO_DIR/skills/process-prs/SKILL.md)

No user is present: never wait for input, prefer skipping over guessing, and finish
with one consolidated report of everything done and skipped."
[ "${GOOD_FELLOW_DRY_RUN:-0}" = "1" ] && PROMPT='Reply with exactly: good-fellow dry run ok. Do nothing else.'

TIMEOUT_CMD=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_CMD="timeout --kill-after=30 $MAX_RUNTIME"
command -v gtimeout >/dev/null 2>&1 && [ -z "$TIMEOUT_CMD" ] && TIMEOUT_CMD="gtimeout --kill-after=30 $MAX_RUNTIME"

# 9>&- everywhere: the agent (and anything it leaks) must never inherit the lock fd.
# --add-dir "$HOME": sweeps clone into ~/<repo> and work in ~/.good-fellow/worktrees,
# both outside REPO_DIR; without it those writes are blocked and nobody is present to
# approve them, so the run would fail silently.
cd "$REPO_DIR"; STATUS=0
case "$AGENT" in
  claude) $TIMEOUT_CMD claude -p "$PROMPT" --add-dir "$HOME" \
            --allowedTools Bash Read Grep Glob Write Edit MultiEdit Skill TodoWrite 9>&- || STATUS=$? ;;
  codex)  $TIMEOUT_CMD codex exec --dangerously-bypass-approvals-and-sandbox "$PROMPT" 9>&- || STATUS=$? ;;
  cursor) $TIMEOUT_CMD cursor-agent --print --force "$PROMPT" 9>&- || STATUS=$? ;;
esac

if [ "$STATUS" = 124 ] || [ "$STATUS" = 137 ]; then
  log "hit the ${MAX_RUNTIME}s timeout; rest rolls to next tick"
fi
find "$STATE_DIR/logs" -name '*.log' -mtime +14 -delete 2>/dev/null || true
log "done (status $STATUS)"; exit "$STATUS"
```

## Step 6 — Scheduled job (every 30 minutes)

Use cron — it works on both Linux and macOS. Install idempotently: check
`crontab -l` for `run-good-fellow.sh` first; if present, report and skip.

Otherwise append, preserving existing entries and headers, with all paths under the
**current user's home** (run `echo $HOME` — never assume a username):

```
7,37 * * * * $HOME/.good-fellow/run-good-fellow.sh >> $HOME/.good-fellow/logs/cron-$(date +\%Y\%m\%d-\%H\%M).log 2>&1
```

(Write `$HOME` out as its literal value — cron does not reliably expand variables in
the command field on all systems.) Use minutes 7 and 37, off the hour, to avoid the
top-of-hour cron rush and other jobs on the machine. If the crontab lacks
`SHELL`/`PATH`/`HOME` headers entirely, add them using this machine's actual values
(`echo $PATH`, `echo $HOME`) so `gh` and the agent CLI resolve — on macOS that must
include the Homebrew bin dir (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin`
on Intel).

Install it in one command so it is a single approval and never leaves the crontab
half-written (`crontab -` replaces the whole table, so always start from the current
one):

```bash
{ crontab -l 2>/dev/null; echo '7,37 * * * * <expanded command line>'; } | crontab -
```

Verify with `crontab -l` after writing.

macOS note: the first cron run may be blocked until the user grants `cron` Full Disk
Access (System Settings → Privacy & Security). If the smoke test below works but
scheduled runs produce no logs, tell the user to check that setting.

## Step 7 — Smoke test and summary

Run the generated runner once by hand in dry-run mode to prove auth + locking +
logging work end to end:

```bash
GOOD_FELLOW_DRY_RUN=1 ~/.good-fellow/run-good-fellow.sh
```

Then report: agents the skills were installed for, gh account, gist status
(found/created + id), which agent CLI the runner will use, the cron schedule, and
where logs land (`~/.good-fellow/logs/`).

Finally, tell the user to **restart their agent session**: agents build their skill
list at startup, so the session that just ran onboarding (and any other session that
was already open) will not recognize `/onboard`, `/process-prs`, or the other slash
commands until it is restarted.
