---
name: check-status
description: Report the health of the good-fellow automation - whether a sweep is running right now, whether the 30-minute cron job is installed and firing, what the recent runs did, and why they failed or were skipped. Diagnoses stuck locks, expired credentials, timeouts, and blocked writes. Use when the user asks about cron job status, whether the bot is running, why nothing happened, or to check on the automation.
---

# Check Status

Read-only health check of the good-fellow automation. Read `docs/conventions.md`
(repo root of this skill) first.

**Do not change anything without asking.** Every remediation below is a suggestion to
put in front of the user; only act after they say so. The one exception is reading
logs and process state, which is always safe.

Lead the report with a one-line verdict — healthy / running now / degraded / not
running at all — then the supporting detail.

## 1. Is a sweep running right now?

```bash
cat ~/.good-fellow/.lock.pid 2>/dev/null
ps -o pid,lstart,etime,cmd -p "$(cat ~/.good-fellow/.lock.pid 2>/dev/null)" 2>/dev/null
```

- Holder alive → a sweep is in flight; report its elapsed time and which log file it
  is writing (`ls -t ~/.good-fellow/logs/*.log | head -1`).
- Pidfile present but the process is gone → a crashed run left the pidfile. Harmless
  on the flock path (the lock died with the process); note it and move on.
- On macOS the lock is a directory: check `~/.good-fellow/.lock.d/pid` instead.

Compare the elapsed time against `MAX_RUNTIME` (1500s default). A run older than that
should have been killed by `timeout`; if it wasn't, `timeout`/`gtimeout` is missing on
this machine and the runner is unbounded — worth flagging.

## 2. Is the schedule installed and firing?

```bash
crontab -l 2>/dev/null | grep -n 'run-good-fellow'
ls -lt ~/.good-fellow/logs/ | head -10
```

Every tick writes a log, so the newest log timestamp tells you when cron last fired.
Judge against the schedule (`7,37 * * * *` → at most ~30 minutes old):

- No crontab entry → onboarding never finished the schedule step. Suggest `/onboard`.
- Entry present but no logs at all → cron is not executing the job. Usual causes: on
  macOS, `cron` lacks Full Disk Access (System Settings → Privacy & Security); on any
  OS, the crontab `PATH` does not contain `gh` or the agent CLI, or the runner is not
  executable (`test -x ~/.good-fellow/run-good-fellow.sh`).
- Newest log much older than one tick → cron stopped firing; check the system cron
  service and whether the crontab was rewritten by another tool.

## 3. What did recent runs do?

```bash
for f in $(ls -t ~/.good-fellow/logs/*.log | head -12); do echo "== $f"; tail -5 "$f"; done
```

Classify each run by its final line:

| Log line | Meaning |
|---|---|
| `done (status 0)` | clean run |
| `previous run still going (holder N, Ns); skipping this tick` | normal only if a real run was in flight |
| `ERROR: lock stuck for Ns ... reclaiming` | a leaked holder was cleaned up; the run then proceeded |
| `hit the Ns timeout` | the sweep ran out of time; work rolls to the next tick |
| `FATAL: gh not logged in` | GitHub credentials gone |
| `FATAL: no authenticated agent CLI` | agent credentials gone |
| `done (status N)` with N≠0 | the agent itself errored — read the body of that log |

## 4. Red flags worth calling out

- **Consecutive skips.** Several ticks in a row ending in `skipping this tick` with the
  same holder PID means a leaked process is holding the lock and nothing is running.
  The runner self-heals after `2×MAX_RUNTIME+300s`, so if you see this *and* the age
  is below that threshold, it is genuinely still working; above it, the reclaim logic
  should have fired — if it didn't, the runner predates that fix. Verify with
  `grep -c STALE_AFTER ~/.good-fellow/run-good-fellow.sh` and suggest re-running
  `/onboard` to regenerate it.
- **Missing `--add-dir`.** `grep -c 'add-dir' ~/.good-fellow/run-good-fellow.sh` → 0
  means unattended sweeps cannot write to `~/<repo>` or `~/.good-fellow/worktrees/`,
  so runs fail silently with nobody to approve the prompt. Suggest regenerating the
  runner.
- **Repeated timeouts.** Consistently hitting the limit means the workload no longer
  fits in one tick. Suggest raising `GOOD_FELLOW_MAX_RUNTIME` in `~/.good-fellow/env`
  (keeping it under the 30-minute cadence) or narrowing scope in the instruction gist.
- **Credential expiry.** Claude OAuth refresh tokens expire roughly monthly; a run of
  `FATAL` lines starting on one date usually means a re-login is due
  (`claude setup-token`, then update `~/.good-fellow/env`).
- **Stale worktrees.** `ls ~/.good-fellow/worktrees/` piling up means runs are dying
  before cleanup. Left in place deliberately after failures, but a large backlog is a
  signal — offer to prune with `git worktree prune` per repo.

## 5. What the automation actually accomplished

Logs say whether runs succeeded; GitHub says whether they were useful. Sample the
recent output by searching for the marker:

```bash
gh search prs --state=open --involves=@me --json repository,number,url --limit 20
```

Then for a few of those, check whether a `<!-- good-fellow:v1 -->` comment exists and
when. Report a short tally (PRs reviewed, threads resolved, issues picked up) rather
than dumping raw JSON.

## 6. Report

One-line verdict, then: current run (if any), schedule and last fire time, the last
few runs with outcomes, red flags with the specific suggested fix, and recent GitHub
activity. Keep it short enough to read at a glance; no raw log dumps unless something
failed, in which case include the relevant excerpt.
