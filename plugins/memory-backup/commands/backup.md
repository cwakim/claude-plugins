---
description: Back up every per-project memory store and live handoff note to a private GitHub repo, landing each run as a PR that is squash-merged immediately.
---

# Memory Backup

Claude Code's persistent memory lives only on this machine, one store per
project under `~/.claude/projects/<slug>/memory/`. A dead disk loses all of it
at once. This command mirrors every store, the plan documents in
`~/.claude/plans/`, and the handoff notes tracked in
`~/.claude/handoff-index.md` when that index exists (it is written by the
session-continuity plugin, but this command does not depend on it: no index
just means no handoffs to back up), into a staging git repo and pushes each
run to a **private** GitHub repo. Every run lands through a pull request that
is squash-merged on the spot: main stays protected, the PR history doubles as
a change log of memory churn, and the backup is complete only when the merge
is.

This is a backup, not a sync. Backup runs copy outward only and never write
to a memory store, a handoff note, or the index. Restoring is its own
explicit mode: empty targets are restored wholesale, existing content is
diffed file by file and nothing that differs is overwritten without you
choosing it. Identical files are never asked about.

## Arguments

`$ARGUMENTS` is optional:

- *(none)* runs a backup. If nothing is configured yet, run **Setup** first,
  then continue into the backup.
- **`setup`** (re)configures: choose or create the GitHub repo, apply its
  protections, clone the staging copy.
- **`status`** reports the configuration, the remote repo and its visibility,
  and when the last backup landed. No changes.
- **`restore`** copies stores and handoff notes from the backup repo back onto
  this machine: wholesale where the target is empty, diff-and-ask where it is
  not. See Restore mode.
- **`schedule`** installs a local cron job that runs the backup on a cadence;
  **`unschedule`** removes it. See Schedule mode.

## The staging repo

State lives in `~/.claude/memory-backup/`, a clone of the backup repo. The
clone existing with an `origin` remote *is* the configuration; there is no
separate config file. The layout is namespaced by hostname: every machine
writes only inside its own `machines/<hostname>/` subtree and pushes branches
carrying its hostname, so any number of laptops can back up into the same
repo without ever colliding (backup per machine; true multi-machine sync is
out of scope):

```text
machines/<hostname>/
  manifest.json               # hostname, ISO timestamp, source paths, counts
  memories/<project>/...      # mirror of each non-empty memory store
  handoffs/...                # home-relative tree: index + each live note
  plans/...                   # mirror of ~/.claude/plans/, if non-empty
README.md                     # what this repo is + restore instructions
.gitignore                    # ignores .cron.log
.cron.log                     # output of scheduled runs (untracked)
```

`<hostname>` is `hostname -s`. Both trees strip the home prefix so names stay
short and restore derives every target from the name alone, with no lookup
table:

- `<project>` is the store's slug minus the home prefix: the slug for
  `~/sites/personal` is `-Users-charbelwakim-sites-personal`, mirrored as
  `memories/sites-personal/`. The live slug is rebuilt at restore time as
  `$(echo ~ | tr '/' '-')-<project>`, which also makes mirrors portable to a
  machine with a different username. A store whose project lives outside the
  home directory keeps its full slug.
- `handoffs/` mirrors home-relative paths as real folders:
  `~/sites/personal/.claude/handoff.md` is stored at
  `handoffs/sites/personal/.claude/handoff.md`, and the index at
  `handoffs/.claude/handoff-index.md`. Every file restores to `~/` plus its
  relative path. A note outside the home directory keeps its full path
  under `handoffs/`.

## Setup (`setup`, or first run when unconfigured)

1. Check `gh auth status`. If it fails, stop and tell the user to run
   `gh auth login` (suggest `! gh auth login` so it runs interactively).
2. If `~/.claude/memory-backup/` already exists with an origin remote, show
   the remote and ask whether to keep it or reconfigure; reconfiguring only
   changes the remote wiring, it never deletes the old GitHub repo.
3. Ask via `AskUserQuestion`: create a new private repo (suggest the name
   `memory-backup`) or use an existing one (ask for `owner/name`).
   - **Create:** `gh repo create <name> --private --description "Backup of
     Claude Code memory stores and handoff notes. Private. Managed by the
     memory-backup plugin."`
   - **Existing:** verify it exists and check
     `gh repo view <owner/name> --json visibility`. If it is not `PRIVATE`,
     **refuse and stop**. Memories hold personal and work-sensitive content;
     there is no public override.
4. Clone into `~/.claude/memory-backup/`. Seed `README.md` (what the repo
   contains, a warning that it must stay private, `/backup restore` as the
   recovery path plus the manual fallback from Restore mode below) and
   `.gitignore` (containing `.cron.log`).
   Commit and push this seed **directly to main**: branch protection does not
   exist yet, and the classic protection API needs the branch to exist first.
5. Now apply the repo settings:
   - `gh repo edit <owner/name> --delete-branch-on-merge`
   - Branch protection on `main` requiring a PR with zero approvals. This is
     **best-effort**: GitHub only allows branch protection on private repos
     with a Pro plan, so a free-plan account gets HTTP 403 here. Do not fail
     setup on that; explain that protection is unenforced and that the PR
     flow is upheld by this command's own discipline instead.
     ```bash
     gh api -X PUT repos/<owner>/<name>/branches/main/protection \
       --input - <<'EOF'
     {
       "required_status_checks": null,
       "enforce_admins": false,
       "required_pull_request_reviews": { "required_approving_review_count": 0 },
       "restrictions": null
     }
     EOF
     ```
6. Before the first backup push, confirm loudly, once: list what will be
   uploaded (how many memory stores, how many files, how many handoff notes)
   and state plainly that this content leaves the machine for a private GitHub
   repo. Proceed only on an explicit yes, then run the backup flow below.

## Backup run

Runs unattended once configured: no questions, so it works headlessly from
cron. If unconfigured and running headlessly (no user to ask), log the problem
and exit cleanly instead of starting setup.

1. **Verify visibility first, every time.** `gh repo view --json visibility`
   on the origin repo; if it is not `PRIVATE`, abort loudly and do not push.
   A repo silently flipped public is exactly the failure this check exists for.
2. `git pull --ff-only` the staging repo. If the network is down, warn and
   stop cleanly; never resolve with force.
3. Mirror the sources into `machines/<hostname>/` with `rsync -a --delete`:
   - every `~/.claude/projects/*/memory/` directory that contains at least one
     file, each into `memories/<project>/` (slug minus home prefix, per the
     layout section);
   - remove mirrored stores whose source directory no longer exists or is
     empty (the mirror tracks reality; git history keeps the old contents);
   - `~/.claude/plans/` into `plans/`, if it exists and is non-empty;
   - if `~/.claude/handoff-index.md` exists: copy it and every live path it
     references into the home-relative tree under `handoffs/` (the index
     lands at `handoffs/.claude/handoff-index.md`). Extract those paths
     deterministically (a
     `python3` one-liner over the index), **not** via shell `grep` inside
     command substitution: some environments hook or proxy grep and return
     empty output there, which silently skips every note. Skip paths that no
     longer exist; never edit the user's index, sources are read-only. If the
     index does not exist, skip the handoff half entirely and silently.
4. Write `manifest.json` (hostname, ISO timestamp, the source paths mirrored,
   store, handoff, and plan counts). If `git status --porcelain` then shows no
   changes beyond the manifest's timestamp, report "no changes since last
   backup" and reset the tree; do not open an empty PR.
5. Land it:
   ```bash
   git checkout -b backup/<hostname>-<YYYY-MM-DD-HHMM>
   git add -A && git commit -m "backup(<hostname>): <YYYY-MM-DD HH:MM>, <N> files changed"
   git push -u origin backup/<hostname>-<YYYY-MM-DD-HHMM>
   gh pr create --fill --body "<per-store summary: files added/changed/deleted>"
   gh pr merge --squash --delete-branch
   git checkout main && git pull --ff-only
   ```
   If the merge fails, say so explicitly and leave the PR link: an unmerged
   PR is **not** a completed backup.
6. Report: the repo, the merged PR link, files added/changed/deleted per
   store, and how long it took.

## Status (`status`)

Read-only. Report: whether `~/.claude/memory-backup/` is configured, the
origin remote and its current visibility, the timestamp of the last landed
backup (last commit on main), how many stores and handoff notes the last
manifest recorded, and whether a `# memory-backup` cron entry exists.

## Schedule mode (`schedule` / `unschedule`)

Installs (or removes) a **local cron job** that runs the backup on a cadence.
Local cron, not a cloud routine: the stores live on this machine.

**`unschedule`:** remove the entry and confirm:

```bash
crontab -l 2>/dev/null | grep -v "# memory-backup" | crontab -
```

**`schedule`:**

1. Check for an existing entry (`crontab -l 2>/dev/null | grep
   "# memory-backup"`). If one exists, show it and ask whether to replace or
   keep it.
2. Ask the cadence via `AskUserQuestion` (weekly is the sensible default for
   a backup; offer daily and monthly too).
3. Resolve the absolute `claude` binary path (`command -v claude`): cron's
   PATH is minimal and will not find it otherwise.
4. Append the entry (never overwrite other lines):
   ```bash
   (crontab -l 2>/dev/null; echo '<min> <hour> <dom> * <dow> cd ~ && <abs-claude> -p "/memory-backup:backup" --allowedTools "Read,Glob,Grep,Write,Bash" >> ~/.claude/memory-backup/.cron.log 2>&1 # memory-backup') | crontab -
   ```
   The `--allowedTools` list lets the headless run work unattended: reads for
   collecting the stores, Bash for rsync, git, and gh, Write for the manifest.
   Warn the user this grants those tools unattended for that run, and that
   each run is a real headless session consuming plan/API usage.
5. Offer a smoke test: run the exact command once in the foreground and
   confirm it lands a backup (or reports "no changes") cleanly.
6. Report the installed line and how to remove it (`unschedule`). Uninstalling
   the plugin does **not** remove the cron job; unschedule first.

## Restore mode (`restore`)

Copies from the backup repo back onto this machine. Interactive and
conservative: it adds and (only with consent) overwrites, and it **never
deletes** anything that exists only locally.

1. If `~/.claude/memory-backup/` is not configured, this is probably the
   disaster-recovery path: ask for the backup repo (`owner/name`), verify it
   exists, and clone it into place first. Otherwise `git pull --ff-only` so
   the mirror is current. Restore never pushes.
2. Pick the source machine: `machines/<hostname>/` for this host. If that
   directory does not exist (a replacement machine with a new hostname), list
   the machines present in the repo and ask which one to restore from.
3. Build a restore plan by comparing the mirror against the live targets,
   per file:
   - **Target store missing or empty** (no `~/.claude/projects/<slug>/memory/`
     or no files in it): restore the whole store wholesale, no questions.
   - **Identical files** (same content): skip silently; never ask about a
     file that would not change.
   - **File only in the backup**: restore it (it cannot clobber anything).
   - **File only local**: keep it untouched; restore never deletes.
   - **File in both, content differs**: a **conflict**; goes to the user.
   Handoffs and plans get the same treatment: every file under `handoffs/`
   maps to `~/` plus its relative path (per the layout section), `plans/`
   maps to `~/.claude/plans/`, wholesale where the target is absent, conflict
   where it exists and differs. Store targets are rebuilt as
   `~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/`.
4. Present the plan in one compact summary: stores restored wholesale, files
   added, identical files skipped (count only), and the conflicts with a
   short per-file diff description (which side is newer, what changed). Then
   resolve the conflicts via `AskUserQuestion`, batched (multi-select "take
   the backup version for these", keep local for the rest), never one prompt
   per file. If there are no conflicts, apply without asking.
5. Apply, then report: stores restored, files added, conflicts resolved each
   way, files skipped as identical, local-only files left alone.

**Manual fallback** (a machine without this plugin; also seeded into the
backup repo's own README at setup):

```bash
git clone git@github.com:<owner>/<name>.git
rsync -a <name>/machines/<hostname>/memories/<project>/ ~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/
```

Repeat per store; every file under `machines/<hostname>/handoffs/` goes back
to `~/` plus its relative path (the index included), and `plans/` goes back
to `~/.claude/plans/`.

## Notes

- **Private, verified on every push.** The visibility check runs before each
  push, not just at setup, and there is no override in v1.
- **Backup runs never write to sources.** Outside of Restore mode, the only
  directory this command writes to is `~/.claude/memory-backup/`.
- **Restore never destroys.** It only runs when invoked, never deletes
  local-only files, never overwrites a differing file without the user
  choosing it, and never asks about identical ones.
- **Backup, not sync.** Restore is a deliberate, interactive act, not a
  background merge; multi-machine sync is out of scope in v1 (a merge
  command is on the roadmap as v2).
- **Never force-push.** The command touches only `main` and its own
  `backup/*` branches, and resolves nothing with force.
- Roadmap (planned, not built): a `merge` command that combines two machines'
  mirrors so memories and handoff notes from two laptops can converge,
  diff-aware with conflicts asked like restore (v2); `--zip <path>` for a dated archive you
  can carry (v3); object storage targets such as S3, GCS, and Alibaba OSS
  (v4); Google Drive via rclone (v5).
