---
name: create-pr
description: Turn uncommitted changes in a working tree into a pull request - review the diff for bugs, write a clear commit, push the branch, and open a GitHub PR with a well-structured body and the good-fellow marker. Use when the user asks to create a PR, commit and open a pull request, or when another good-fellow skill has a finished fix to ship.
---

# Create PR

Helper skill: takes a working tree (usually a good-fellow worktree) with changes and
ships them as a PR. Read `docs/conventions.md` (repo root of this skill) and
`~/.good-fellow/instruction.md` first.

Inputs: the working tree path (default: current directory), optionally the issue
number the change fixes, and optionally an explicit base branch. Without one the PR
targets the repository default branch; `process-prs` passes one when a fix belongs on
a release PR's head branch (for example `dev`) that the gist forbids pushing to
directly.

## 1. Pre-flight

```bash
git status --porcelain
git branch --show-current
```

- Refuse to run on the repo's default branch or on a branch the user checked out in
  their own working tree — this skill only ships branches created per conventions §3
  (`good-fellow/*`) or the user's explicit current branch when invoked manually.
- Refuse if there are no changes.

## 2. Self-review the diff

Read the full `git diff` (plus untracked files). Check for: debug leftovers,
accidental file inclusions (lockfiles, secrets, editor junk), broken imports, logic
errors. Fix what you find. If a secret is staged, stop and report — never push it.

## 3. Commit

Group the changes into one commit (or a few logical ones) with a message in the
repository's existing style (`git log --oneline -15` to sample). Subject line explains
*why*, not just *what*. Commit only files related to the task.

This skill runs unattended, so satisfy the commit preconditions in conventions §6
first (identity resolvable, credential helper present) and **never invoke an editor** —
pass the message on the command line or from a file:

```bash
git -C <worktree> add <specific paths>
git -C <worktree> -c user.name="$GF_NAME" -c user.email="$GF_MAIL" commit -F <message-file>
```

Never a bare `git commit` (opens an editor) and never `git config` inside a worktree
(it rewrites the user's shared `.git/config`) — see conventions §6.

## 4. Sync onto the current base

The branch was created from a base tip that may be far behind by now — a long run, or
work resumed from a handoff — so replay it onto the current tip **before** the push.
Skipping this is what makes a freshly opened PR arrive already behind and conflicting.

Take the base from validated repository data, never from issue or PR text (conventions
§2), and fetch it into a private ref so it can never collide with a branch the user has
checked out (conventions §3):

```bash
# the base the PR will target: the caller's explicit base when given, otherwise the
# repo default, resolved from the worktree's own remote so this never depends on the
# runner's unrelated current directory
BASE=${BASE_OVERRIDE:-$(gh repo view "$(git -C <worktree> remote get-url origin)" \
  --json defaultBranchRef --jq .defaultBranchRef.name)}
git -C <worktree> ls-remote --exit-code --heads origin "$BASE" >/dev/null
git -C <worktree> fetch origin "$BASE:refs/good-fellow/base/$BASE" --force
```

An explicit base must come from validated repository data (the caller's ledger
`headRefName`, a `gh` listing), never from issue or PR text, and the `ls-remote` check
refuses a name origin does not have. The base is only where the PR points; this skill
still never pushes to it.

Never fetch into a local branch name (`git fetch origin "<base>:<base>"`) — that write
is exactly what conventions §3 forbids against a checkout the user may have open.

How to replay depends on whether an earlier tick already published this branch
(`git -C <worktree> ls-remote --exit-code --heads origin "<branch>"`):

| Branch on origin | Action |
|---|---|
| absent (the normal case) | rebase onto the fetched tip |
| present | **never rebase** — rewriting a published branch needs a force-push, forbidden by conventions §3 and §6. Merge the base tip in instead, which keeps the push fast-forward |

```bash
GIT_EDITOR=true git -C <worktree> -c user.name="$GF_NAME" -c user.email="$GF_MAIL" \
  rebase "refs/good-fellow/base/$BASE"
# published branch instead:
GIT_EDITOR=true git -C <worktree> -c user.name="$GF_NAME" -c user.email="$GF_MAIL" \
  merge --no-edit "refs/good-fellow/base/$BASE"
```

Both write commits, so both need the same per-command identity as §3 and must never
reach an editor (conventions §6): `--no-edit` on the merge, no interactive rebase, and
no bare `git commit` to conclude one.

If the replay moved the branch, the diff reviewed in §2 is no longer the diff that will
be merged: re-run whatever checks were already run and describe *that* run under "How it
was verified". If the replay leaves nothing to ship (every change is already in the new
base), push nothing, open no PR, and report the work as already fixed upstream.

### When the replay conflicts

Nobody is available to resolve it (conventions §6), so resolve only what needs no
judgement:

- git reports the patch as empty because the change already landed upstream →
  `git -C <worktree> rebase --skip`;
- the conflict is confined to a generated file (lockfile, snapshot, checked-in build
  output) **and** the repository documents a regeneration command that runs offline:
  take the base's version, regenerate, and verify the output is exactly what the
  generator produces. Not reproducible means not mechanical.

Everything else — overlapping edits, delete/modify, rename/modify, binary files, any
resolution where you would have to pick between two intents — is a judgement call.
Never use `-X ours`/`-X theirs`, never `--skip` a non-empty patch, and never drop either
side's edits just to make the replay apply.

Abandon the run rather than shipping a guessed merge:

```bash
git -C <worktree> rebase --abort   # or: git -C <worktree> merge --abort
```

- Push nothing, open no PR, and post no comment claiming a fix. Conventions §5 records
  the action only after it succeeds, so an abandoned run leaves the item untouched and
  the next sweep re-derives the fix against the base as it stands then.
- Never delete a branch an earlier tick already published.
- Per conventions §3 a failed run leaves its worktree in place for inspection; the next
  run recovers that path itself (`git worktree remove --force` + `git worktree prune`,
  plus `git branch -D` for our own `good-fellow/*` branch).
- Name the conflicting paths in the report, so an item that keeps getting stuck here
  stays visible instead of silently vanishing from every sweep.

## 5. Push and open the PR

```bash
git push -u origin <branch>
gh pr create --title "<title>" --body-file <tmpfile> --base "$BASE"
```

A plain push is refused if someone advanced the branch meanwhile; that rejection is the
protection, not a problem to solve (conventions §3). Do not force-push and do not retry
the decision onto the new tip — abandon as in §4 and let the next sweep recapture state.

Once the push succeeded, drop the private base ref:

```bash
git -C <worktree> update-ref -d "refs/good-fellow/base/$BASE"
```

Body structure (language per gist / repo norms):

- What & why — one short paragraph.
- Key changes — brief bullet list.
- How it was verified — tests run, or honest "not tested" note.
- `Fixes #<n>` when an issue number was given.
- The marker line: `<!-- good-fellow:v1 -->`.

No boilerplate beyond that; do not enable auto-merge; do not request reviewers unless
the gist says to.

## 6. a-good-fellow itself: downstream `deploy`, upstream PRs

`/root/a-good-fellow` is a long-lived fork (`origin` = `iloveOREO/a-good-fellow`) of
the upstream `jumpjump1910/a-good-fellow`, kept in the merge-based downstream model:

| Branch | Role | How it changes |
|---|---|---|
| `main` | mirror of upstream `main`; never carries local commits | fast-forward from upstream only |
| `deploy` | the downstream mainline; always ahead of upstream; what the cron runtime runs | merge the change branch in directly, no PR |
| `good-fellow/<slug>` | one change | cut from upstream `main`, cherry-pick the relevant commits from `deploy` if they were made there |

PRs exist only to contribute upstream. A change branch is cut from upstream `main`
(`git fetch origin main:refs/good-fellow/base/main` after `main` has been synced), so the
PR carries that one change and nothing `deploy` is ahead by; opening it from a branch
based on `deploy` re-submits every unmerged downstream commit. Open with
`gh pr create --repo jumpjump1910/a-good-fellow --base main --head iloveOREO:<branch>`.
Machine-specific text (this section, deployment paths) stays in `deploy` and is not
sent upstream. A change that depends on another still-open PR is cut from that PR's
branch and says so in its body.

The change reaches this machine the moment it exists, independent of upstream review:
merge the branch into `deploy` (`git -C <worktree> push origin HEAD:refs/heads/deploy`
when the branch is already based on `deploy`, otherwise a local `merge --no-edit` on a
`deploy` checkout, then a plain push — never `--force`), fast-forward the managed source
(`git -C ~/.good-fellow/source pull --ff-only`, its checkout tracks `origin/deploy`), and
publish the deployment as `onboard` Step 5 does (immutable `deploy-*` copy, script syntax
checks, `tests/runtime-state.sh`, `runtime-version` = the `deploy` tip, atomic
`deployment-current` switch, keep the three newest; reuse the current runner when its
text is unchanged). If a sweep holds the lock, skip the dry-run smoke test, publish
anyway and verify from the next tick's log.

Tracking upstream is the reverse merge: after upstream merges anything, fast-forward
`main` and `git merge --no-edit main` into `deploy`. Commits that were cherry-picked
upstream unchanged merge as no-ops; a squash-merged or edited one conflicts once —
resolve it in favour of upstream and move on. `deploy` is never rebased or rebuilt.

The gist's "never push to `dev`/`main`" rule guards shared integration branches such as
`Jumpyai/a2e`; `deploy` is this user's own downstream line, and the user has confirmed
it takes merges directly. Report the upstream PR URL, the `deploy` SHA, and the live
deployment directory.

## 7. Report

Return the PR URL and the commit SHA(s), and say whether the branch was rebased or
merged onto a newer base tip.
