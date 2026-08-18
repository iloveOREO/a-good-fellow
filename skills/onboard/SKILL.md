---
name: onboard
description: One-time interactive setup for the good-fellow GitHub automation. Checks gh login (guides device-code login on a remote machine), finds or creates the user's personal good-fellow-instruction.md gist, verifies headless agent auth (claude or codex), and installs a 30-minute cron job that runs the sweep skills. Use when the user says onboard, /onboard, set up good-fellow, or initialize the GitHub agent.
---

# Onboard

Interactive bootstrap for good-fellow. Run each step in order, report progress as you
go, and finish with a summary of what was configured. This skill is the only
good-fellow skill allowed to prompt the user and to edit the crontab.

Read `docs/conventions.md` in this repo first (resolve the repo root from this file's
location; the symlinked skill lives inside the repo).

## Step 0 — State directory

```bash
mkdir -p ~/.good-fellow/logs ~/.good-fellow/worktrees
```

## Step 1 — GitHub CLI login

Run `gh auth status`. If logged in, report the account and continue.

If not logged in, this is a remote machine with no browser. Start the device-code
flow in the background so you can stream its output:

```bash
gh auth login --hostname github.com --git-protocol https --web
```

The command prints a one-time code (like `XXXX-XXXX`) and the URL
`https://github.com/login/device`, then waits. Relay both to the user verbatim and
tell them to open the URL on their own computer/phone and enter the code. Wait for
the command to complete (poll the background task), then re-run `gh auth status` to
confirm. If the code expires, restart the login command and relay the fresh code.

## Step 2 — Personal instruction gist

Look for the gist:

```bash
gh api /gists --paginate --jq '.[] | select(.files["good-fellow-instruction.md"]) | .id' | head -1
```

- **Found**: download it to the cache and show the user a short summary of what it says:

  ```bash
  gh gist view <GIST_ID> --filename good-fellow-instruction.md > ~/.good-fellow/instruction.md
  ```

- **Not found**: explain that this file holds their standing instructions (reply
  language, review taste, repos to prioritize/skip, tone) applied to every GitHub
  task. Ask them to dictate the content now. Write it to
  `~/.good-fellow/instruction.md`, show it back for confirmation, then upload it as a
  secret gist so future machines can reuse it:

  ```bash
  gh gist create ~/.good-fellow/instruction.md --desc "good-fellow personal instructions"
  ```

  (The filename inside the gist must be `good-fellow-instruction.md`; rename the local
  file to that name in a temp copy before `gh gist create` if needed.)

## Step 3 — Headless agent auth

The cron job needs an agent CLI that runs without a human. Check, in order:

1. `claude`: usable if `~/.good-fellow/env` defines `CLAUDE_CODE_OAUTH_TOKEN`, or
   `~/.claude/.credentials.json` exists.
2. `codex`: usable if `~/.codex/auth.json` exists.

If neither is usable, tell the user to either run `claude setup-token` and put the
output in `~/.good-fellow/env` as `CLAUDE_CODE_OAUTH_TOKEN=...` (chmod 600), or log
in to codex — and pause until one of them is done. Do not install a cron job that can
never run.

## Step 4 — Cron job (every 30 minutes)

The runner is `scripts/run-good-fellow.sh` in this repo. Install it idempotently:
check `crontab -l` for `run-good-fellow.sh` first; if present, report and skip.

Otherwise append (preserving existing entries and any existing SHELL/PATH/HOME lines):

```
7,37 * * * * <REPO_ROOT>/scripts/run-good-fellow.sh >> /root/.good-fellow/logs/cron-$(date +\%Y\%m\%d-\%H\%M).log 2>&1
```

Use minutes 7 and 37 (off the hour) to avoid cron rush and other jobs on the machine.
If the crontab lacks `SHELL`/`PATH`/`HOME` headers entirely, add:

```
SHELL=/bin/bash
PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/root
```

Verify with `crontab -l` after writing.

## Step 5 — Smoke test and summary

Run the runner once by hand in dry-run mode to prove auth + locking + logging work:

```bash
GOOD_FELLOW_DRY_RUN=1 <REPO_ROOT>/scripts/run-good-fellow.sh
```

Then report: gh account, gist status (found/created + id), which agent CLI the runner
will use, the cron schedule, and where logs land (`~/.good-fellow/logs/`).
