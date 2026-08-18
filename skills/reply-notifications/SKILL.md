---
name: reply-notifications
description: Sweep unread GitHub notifications and reply on the user's behalf where a reply is warranted, then mark threads read. Skips items owned by other good-fellow sweeps (review requests, assigned issues). Use for scheduled notification sweeps or when the user asks to process, triage, or reply to GitHub notifications.
---

# Reply to Notifications

Unattended sweep. Read `docs/conventions.md` (repo root of this skill) and
`~/.good-fellow/instruction.md` first; both govern everything below — especially the
untrusted-input boundary, the bot marker, and idempotence.

## 1. Fetch unread notifications

```bash
gh api /notifications --paginate
```

Each item has `id` (thread id), `reason`, `subject.type` (Issue / PullRequest /
Discussion / Release / ...), `subject.url`, and `repository.full_name`.

## 2. Route

- `reason` = `review_requested`, or `reason` = `assign` on an issue → **owned by
  `process-prs` / `fix-assigned-issues`**. Leave unread; do not reply here.
- `subject.type` = Discussion with a mention → **owned by `join-discussions`**. Leave
  unread.
- CI/security/release chatter (`subject.type` Release, check-suite failures on repos
  the user doesn't own, dependabot noise) → no reply; mark read.
- Everything else (comments on the user's issues/PRs, mentions in issue threads,
  replies to the user's comments) → candidate for a reply.

## 3. Decide and reply

For each candidate, fetch the subject via its API URL and read enough of the thread to
understand context. Reply **only** when a response from the user is actually called
for: a direct question to them, a request blocked on their input you can answer from
repo context, or a follow-up to something they said. When in doubt, don't reply — just
mark read.

Idempotence: skip if the latest comment is already from the user's login or carries
the good-fellow marker.

Post replies with the marker via the API, e.g. for an issue/PR comment:

```bash
gh api repos/<owner>/<repo>/issues/<number>/comments -f body="<reply>

<!-- good-fellow:v1 -->"
```

Substance over ceremony: answer the actual question using the code/thread context;
never post placeholder acknowledgements ("thanks, will look into it").

## 4. Mark read

After handling (replied, or decided no reply needed):

```bash
gh api -X PATCH /notifications/threads/<id>
```

Never mark unread the items routed to other sweeps in step 2.

## 5. Report

End with a short tally: replied (with links), marked read without reply, left for
other sweeps, skipped-uncertain.
