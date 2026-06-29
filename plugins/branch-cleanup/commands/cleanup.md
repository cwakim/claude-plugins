---
description: Safely delete branches already merged into a base branch (local and remote), protecting long-lived branches and never force-deleting unmerged work.
---

# Branch Cleanup

Delete the branches that are fully merged into a **base branch**, both locally and
on the remote, then report what was removed and what was kept. Long-lived branches
are protected, the branch you are currently on is never touched, and unmerged work
is left strictly alone (only safe `git branch -d`, never force-delete `-D`).

This is housekeeping after merges land: it removes the stale `feat/*`, `fix/*`, and
similar branches whose commits already live in the base, so `git branch` stops being
a junkyard. It does **not** decide what to merge and it never deletes anything that
is not already merged.

## Arguments

`$ARGUMENTS` is optional and freeform:

- **A branch name** (e.g. `develop`, `main`) sets the **base** to compare against.
  If omitted, use the repository's default branch (see step 1).
- **`--dry-run`** lists what would be deleted and stops, without deleting or asking.
- **`--local-only`** skips remote deletion entirely (never touches `origin`).

Examples: `/cleanup`, `/cleanup develop`, `/cleanup main --dry-run`,
`/cleanup --local-only`.

## Protected branches

Never delete, regardless of merge status:

- The **base branch** itself.
- The **current branch** (the one `HEAD` points at).
- A default keep-list of common long-lived branches: `main`, `master`, `develop`,
  `development`, `preview`, `staging`, `production`, `release`.

If the user has named other long-lived branches in this repo's `CLAUDE.md` or in the
conversation, treat those as protected too.

## Steps

1. **Determine the base branch.** If `$ARGUMENTS` names one, use it. Otherwise detect
   the repo default:
   ```bash
   git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p'
   ```
   If that yields nothing (no remote), fall back to `main` if it exists, else `master`.
   Confirm the chosen base out loud before deleting anything.

2. **Refresh the branch list** so merged-state and remote-tracking refs are current:
   ```bash
   git fetch --prune origin
   ```
   (Skip the fetch if there is no `origin` remote.)

3. **Find local branches merged into the base**, excluding protected ones and the
   current branch (the leading `*` marks current):
   ```bash
   git branch --merged <base> | grep -vE '^\*|^[ +]*(main|master|develop|development|preview|staging|production|release)$' | sed 's/^[ +]*//'
   ```
   Drop the base branch from the result if it is not already in the pattern.

4. **Find remote branches merged into the base** (skip this step under `--local-only`):
   ```bash
   git branch -r --merged <base> | grep -vE 'origin/HEAD|origin/(main|master|develop|development|preview|staging|production|release)$' | sed 's# *origin/##'
   ```

5. **Show the full list** of branches to be deleted, split into **local** and **remote**,
   and the base they were measured against. Under `--dry-run`, stop here.

6. **Ask for confirmation** before deleting anything. Proceed only on an explicit yes.

7. **On confirmation, delete:**
   - Local: `git branch -d <branch>` for each. `-d` refuses to delete an unmerged
     branch, which is the safety net — if one errors as "not fully merged," skip it and
     report it rather than forcing.
   - Remote (unless `--local-only`): `git push origin --delete <branch>` for each.

8. **Report** what was deleted (local + remote) and what was kept, noting anything that
   `-d` refused as a surprise (it means the branch was not actually merged).

## Notes

- **Never use `git branch -D`** here. The whole guarantee of this command is that it
  only removes already-merged branches; force-delete would break that.
- A branch can be merged locally but not on the remote, or vice versa. The two lists are
  computed independently, so a branch may appear in one and not the other. That is fine.
- A branch whose commits were **squash- or rebase-merged** will not show as merged to
  `git branch --merged` (the SHAs differ), so it is correctly left alone here. Cleaning
  those up is a separate, riskier judgment call this command intentionally does not make.
- Always show the list and get a yes before deleting. Never delete on a bare invocation
  without confirmation.
