# branch-cleanup

One command for the housekeeping after merges land: delete the branches that are
already merged into a base branch, locally and on the remote, without touching
anything still in flight.

- **`/cleanup`** — list the branches fully merged into the base, show them, confirm,
  then delete them local + remote and report what was kept.

## Why

After a few PRs merge, `git branch` fills with dead `feat/*` and `fix/*` branches whose
commits already live in `main`. Deleting them by hand is fiddly and easy to get wrong in
the dangerous direction (a stray `-D` on something that was not actually merged). This
command does only the safe version:

- **Merged-only** — uses `git branch -d`, which refuses to delete an unmerged branch. It
  physically cannot drop work that has not landed.
- **Protected branches** — the base, the branch you are on, and a keep-list of long-lived
  branches (`main`, `master`, `develop`, `development`, `preview`, `staging`,
  `production`, `release`) are never touched.
- **Confirmed** — it always shows the full local + remote list and waits for a yes before
  deleting anything.

## Usage

```text
/cleanup                     # base = repo default branch; clean local + remote
/cleanup develop             # measure "merged" against develop instead
/cleanup main --dry-run      # show what would go, delete nothing, don't ask
/cleanup --local-only        # never touch origin, prune local branches only
```

The base branch defaults to the repository's default branch (from `origin/HEAD`,
falling back to `main` then `master`). Pass a branch name to override it.

## Notes

- Squash- and rebase-merged branches do **not** look merged to git (the commit SHAs
  differ), so they are deliberately left alone — cleaning those is a riskier judgment
  call this command does not make.
- Local and remote merged-state are computed independently, so a branch can be removed
  from one and kept in the other.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install branch-cleanup@cwakim-plugins
```
