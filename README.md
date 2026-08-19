# a-good-fellow

Agent-agnostic skills that discuss, review, and fix GitHub PRs and issues on your
behalf. The skills are plain [SKILL.md](https://agentskills.io) folders, so they work
in Claude Code, Codex, Cursor, and any agent that reads the same format; a cron job
runs them headlessly every 30 minutes.

Works for any user on macOS and Linux: no hardcoded usernames or paths (everything
lives under your `$HOME`), and the scripts run on stock macOS bash 3.2 / BSD userland
as well as GNU/Linux.

## What it does, every 30 minutes

1. **reply-notifications** — triages unread GitHub notifications, replies where a
   response from you is actually warranted, marks threads read.
2. **join-discussions** — finds Discussions that @mention you and posts a substantive
   reply.
3. **fix-assigned-issues** — takes open issues assigned to you, fixes them on a
   `good-fellow/issue-N` branch in an isolated clone/worktree, and opens a PR
   (via **create-pr**).
4. **process-prs** — walks every open PR involving you:
   - *Your PRs*: judges unresolved comments from Copilot/reviewers; real issues get
     fixed and pushed, then the thread gets a reply and is resolved.
   - *Others' PRs*: pulls the code locally and reviews for **critical issues only** —
     no summaries, no nits. Clean PR → a single `LGTM` comment (or an approval, when
     you're a requested reviewer). Already-reviewed PRs are skipped via a hidden
     `<!-- good-fellow:v1 -->` marker.

Your standing preferences (language, tone, review taste, repo scope) live in a
personal gist file `good-fellow-instruction.md`, cached at
`~/.good-fellow/instruction.md` and applied to every task.

## The skills

| Skill | Runs | Purpose |
|---|---|---|
| [`onboard`](skills/onboard/SKILL.md) | manual, once per machine | install, authenticate, schedule |
| [`reply-notifications`](skills/reply-notifications/SKILL.md) | every sweep | triage unread notifications |
| [`join-discussions`](skills/join-discussions/SKILL.md) | every sweep | answer Discussions that @mention you |
| [`fix-assigned-issues`](skills/fix-assigned-issues/SKILL.md) | every sweep | fix issues assigned to you, open PRs |
| [`process-prs`](skills/process-prs/SKILL.md) | every sweep | fix feedback on your PRs, review others' |
| [`create-pr`](skills/create-pr/SKILL.md) | helper + manual | commit, push, open a PR |
| [`check-status`](skills/check-status/SKILL.md) | manual | health of the automation |
| [`sync-instructions`](skills/sync-instructions/SKILL.md) | manual | pull/edit/push your instruction gist |

The four **sweep** skills are what the cron job runs, in the order listed, and they are
built to need no human at all: no prompts, no confirmations, no "please do this part
yourself". Obstacles are resolved by rules the agent can apply alone — recover leftover
state, retry once, or skip and let the next tick try again — and safety comes from
operations that fail safely rather than from asking first. `create-pr` is called by
`fix-assigned-issues` to ship a fix, and is equally usable on its own.

The three **manual** skills are for you, and none of them belongs in the cron job.
`onboard` is the only one that changes machine setup. `/check-status` reads the lock,
the crontab, and `~/.good-fellow/logs/`, then names the specific fix for whatever it
finds — a stuck lock holding up every tick, expired Claude or GitHub credentials, runs
hitting the time limit, cron not firing at all (on macOS, usually Full Disk Access), or
a runner generated before a fix landed — and it changes nothing without asking.
`/sync-instructions` pulls your instruction gist into the local cache or pushes edits
back, diffing before it overwrites either side so a local edit is never silently lost,
and creates the gist if you don't have one yet.

Every skill obeys [`docs/conventions.md`](docs/conventions.md) — the shared rules on
instruction handling, untrusted input, workspace isolation, the bot marker,
idempotence, and unattended discipline.

## Install

There is deliberately **no install script** — the repo is just skills and docs, and
your agent does the setup itself. Clone it anywhere, then run the onboard skill from
whichever agent you use.

```bash
git clone <this-repo> ~/a-good-fellow
cd ~/a-good-fellow
```

Onboarding is **interactive by design** — it may show you a GitHub device-login code
to enter on your phone, and ask you to dictate your standing instructions — so run it
in an interactive session, not a headless one. The agent will need to create symlinks,
write `~/.good-fellow/run-good-fellow.sh`, and edit your crontab; approve those when
prompted.

### Onboard with Claude Code

```bash
claude
```

Then, in the session:

> Run the onboard skill in skills/onboard/SKILL.md

Once it finishes, the skills are symlinked into `~/.claude/skills/`. **Restart the
CLI** — a session that was already running when the skills were installed does not
know about them, so `/onboard` will come back as an unrecognized command. After the
restart the slash commands work: `/onboard`, `/process-prs`, `/fix-assigned-issues`,
and so on.

### Onboard with Codex

```bash
codex
```

Then, in the session:

> Run the onboard skill in skills/onboard/SKILL.md

Codex will ask for approval before writing files and editing the crontab — accept
those steps. Afterwards the skills live in `~/.codex/skills/`; restart the session so
they are picked up. This repo's [AGENTS.md](AGENTS.md) also tells Codex which skill to
use for what whenever you work inside the repo.

### Onboard with Cursor or another agent

Any agent that reads `SKILL.md` folders works the same way — open the agent in the
repo directory and give it the same instruction:

> Run the onboard skill in skills/onboard/SKILL.md

The skill auto-detects installed agents by their home directories (`~/.claude`,
`~/.codex`, `~/.cursor`) and installs into each one's `skills/` directory; tell it
about any other agent you use and it will install there too.

### What onboarding actually does

- symlinks the skills into the skill directory of every agent installed on the
  machine (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`, ...);
- checks `gh auth status`, and if needed walks you through the device-code login
  (built for remote machines: it shows you the URL + one-time code and waits);
- finds your `good-fellow-instruction.md` gist, or helps you write and upload one;
- verifies a headless agent CLI is authenticated for the scheduled runs — claude via
  `~/.claude/.credentials.json` or `CLAUDE_CODE_OAUTH_TOKEN` in `~/.good-fellow/env`
  (from `claude setup-token`); codex via `~/.codex/auth.json` (from `codex login`);
  or cursor-agent;
- generates the cron runner at `~/.good-fellow/run-good-fellow.sh` from the reference
  implementation embedded in the skill, and installs the 30-minute cron job (on
  macOS, cron may need Full Disk Access for scheduled runs).

The agent that onboards you and the agent that runs the sweeps need not be the same:
the runner auto-detects claude → codex → cursor-agent at each tick, and
`GOOD_FELLOW_AGENT=codex` in `~/.good-fellow/env` pins it to one.

Already set up this machine and just want the latest changes? See
[Upgrading an already-onboarded machine](#upgrading-an-already-onboarded-machine)
below — a `git pull` alone is not enough.

## Upgrading an already-onboarded machine

`git pull` is necessary but **not sufficient**:

```bash
cd ~/a-good-fellow && git pull
```

- **Covered by the pull**: every already-installed skill, plus `docs/conventions.md`
  and `AGENTS.md`. The installed skills are symlinks *into* this repo, not copies, so
  updated instructions take effect immediately.
- **Not covered**: a **newly added skill** has no symlink on that machine yet, so the
  agent cannot see it; and `~/.good-fellow/run-good-fellow.sh` is a **generated copy**,
  so fixes to the reference implementation in `skills/onboard/SKILL.md` never reach it
  on their own.

So after pulling, re-run the onboard skill — it is idempotent and doubles as the
upgrade path. On a machine that is already onboarded the slash command works:

```
/onboard
```

(If the session predates the install and does not recognize it, restart the agent, or
ask it to "run the onboard skill in skills/onboard/SKILL.md".) It refreshes the
symlinks (adding any new skills), regenerates the runner from the
current reference, leaves an existing crontab entry alone, and re-runs the smoke test.
Then **restart the agent session** so newly added skills appear as slash commands.

Two notes: re-onboarding overwrites `~/.good-fellow/instruction.md` from the gist, so
if that cache has local edits, push them first with `/sync-instructions`. And
`/check-status` flags a runner that predates recent fixes, which is a good way to tell
whether a machine still needs this.

## Layout

```
skills/              one folder per skill (SKILL.md format, agent-agnostic)
docs/conventions.md  shared rules: gist instructions, untrusted-input boundary,
                     worktree isolation, bot marker, idempotence
```

Anything that must exist as a file on a machine (the cron runner) is generated
per-machine by the onboard skill, not versioned here. Runtime state (instruction
cache, worktrees, logs, lock, generated runner, optional env file) lives in
`~/.good-fellow/`, outside this repo.

## Safety properties

- **Your checkouts are never touched.** Work happens in fresh clones under `~` or in
  `git worktree`s under `~/.good-fellow/worktrees/`; against your existing working
  trees only `worktree add/remove/prune` and read-only git commands are permitted.
- **PR/issue content is treated as data, not instructions** — imperatives inside
  untrusted content are never executed, and untrusted strings are never interpolated
  into shell commands (PRs are addressed by number).
- **Idempotent**: the marker comment prevents duplicate replies and re-reviews.
- **Bounded**: single-instance lock plus a 25-minute timeout per run; never
  force-pushes, closes, or merges anything; the only PR-state mutation is approving a
  clean PR you were asked to review.

## Manual use

Each skill also works standalone in an interactive session: `/check-status`,
`/sync-instructions`, `/process-prs`, `/fix-assigned-issues`, `/create-pr`, and so
on. After onboarding, a one-off full sweep:

```bash
~/.good-fellow/run-good-fellow.sh
```

Dry run (auth/lock/CLI checks only): `GOOD_FELLOW_DRY_RUN=1 ~/.good-fellow/run-good-fellow.sh`
