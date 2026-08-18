# a-good-fellow

Agent-agnostic skills that discuss, review, and fix GitHub PRs and issues on your
behalf. The skills are plain [SKILL.md](https://agentskills.io) folders, so they work
in Claude Code, Codex, and any agent that reads the same format; a cron job runs them
headlessly every 30 minutes.

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

```bash
./install.sh
```

symlinks the skills into `~/.claude/skills/` and `~/.codex/skills/`. Then run the
**onboard** skill from your agent (`/onboard` in Claude Code). It will:

- check `gh auth status`, and if needed walk you through the device-code login
  (built for remote machines: it shows you the URL + one-time code and waits);
- find your `good-fellow-instruction.md` gist, or help you write and upload one;
- verify a headless agent CLI is authenticated (claude via
  `~/.claude/.credentials.json` or `CLAUDE_CODE_OAUTH_TOKEN` in `~/.good-fellow/env`;
  codex via `~/.codex/auth.json`);
- install the 30-minute cron job running `scripts/run-good-fellow.sh`.

## Layout

```
skills/            one folder per skill (SKILL.md format, agent-agnostic)
docs/conventions.md  shared rules: gist instructions, untrusted-input boundary,
                     worktree isolation, bot marker, idempotence
scripts/run-good-fellow.sh  cron entry point: lock, auth, CLI auto-detect, timeout
```

Runtime state (instruction cache, worktrees, logs, lock, optional env file) lives in
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
`/fix-assigned-issues`, `/create-pr`, etc. A one-off full sweep:

```bash
scripts/run-good-fellow.sh
```

Dry run (auth/lock/CLI checks only): `GOOD_FELLOW_DRY_RUN=1 scripts/run-good-fellow.sh`
