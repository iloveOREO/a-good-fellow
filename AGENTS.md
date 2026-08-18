# Agent guide

This repository is a set of agent-agnostic skills that handle GitHub PRs, issues,
notifications, and discussions on the user's behalf.

Before executing any skill here, read `docs/conventions.md` — it defines the
untrusted-input boundary, workspace isolation rules, the `<!-- good-fellow:v1 -->`
marker, and idempotence requirements. Also read `~/.good-fellow/instruction.md`
(the user's standing instructions, cached from their gist) and apply it to every
GitHub task.

Skills (each in `skills/<name>/SKILL.md`):

- `onboard` — interactive setup: skill installation, gh login, instruction gist,
  headless auth, generated cron runner. Start here on a fresh machine.
- `reply-notifications` — sweep unread notifications, reply where warranted.
- `join-discussions` — reply to Discussions that @mention the user.
- `fix-assigned-issues` — fix assigned issues and open PRs.
- `create-pr` — commit + push + open a PR from a working tree with changes.
- `process-prs` — fix feedback on the user's PRs; review others' PRs (critical
  issues only, `LGTM` otherwise, approve when clean and review was requested).

The scheduled entry point is `~/.good-fellow/run-good-fellow.sh` (cron, every 30
minutes) — generated per-machine by the onboard skill from the reference
implementation embedded in `skills/onboard/SKILL.md`; it is not versioned here.
