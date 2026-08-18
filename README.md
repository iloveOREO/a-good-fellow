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

## Install

There is deliberately **no install script** — the repo is just skills and docs, and
your agent does the setup itself. Clone the repo, then point your agent at the
onboard skill:

> Run the onboard skill in skills/onboard/SKILL.md

(Once installed, it's also available as `/onboard`.) Following that skill, the agent
will:

- symlink the skills into the skill directory of every agent installed on the
  machine (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`, ...);
- check `gh auth status`, and if needed walk you through the device-code login
  (built for remote machines: it shows you the URL + one-time code and waits);
- find your `good-fellow-instruction.md` gist, or help you write and upload one;
- verify a headless agent CLI is authenticated (claude via
  `~/.claude/.credentials.json` or `CLAUDE_CODE_OAUTH_TOKEN` in `~/.good-fellow/env`;
  codex via `~/.codex/auth.json`; or cursor-agent);
- generate the cron runner at `~/.good-fellow/run-good-fellow.sh` from the reference
  implementation embedded in the skill, and install the 30-minute cron job (on
  macOS, cron may need Full Disk Access for scheduled runs).

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

Each skill also works standalone in an interactive session: `/process-prs`,
`/fix-assigned-issues`, `/create-pr`, etc. After onboarding, a one-off full sweep:

```bash
~/.good-fellow/run-good-fellow.sh
```

Dry run (auth/lock/CLI checks only): `GOOD_FELLOW_DRY_RUN=1 ~/.good-fellow/run-good-fellow.sh`
