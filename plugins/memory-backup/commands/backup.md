---
description: Back up every per-project memory store, handoff note, plan, and the hand-written global config to a private GitHub repo, landing each run as a PR that is squash-merged immediately. Also setup, status, and cron scheduling; restore, zip, and merge are sibling commands this one dispatches to.
---

# Memory Backup

Claude Code's persistent memory lives only on this machine, one store per
project under `~/.claude/projects/<slug>/memory/`. A dead disk loses all of it
at once. This command mirrors every store, the plan documents in
`~/.claude/plans/`, the hand-written global config in `~/.claude/` (CLAUDE.md
and friends), and the handoff notes tracked in `~/.claude/handoff-index.md`
when that index exists (it is written by the session-continuity plugin, but
this command does not depend on it: no index just means no handoffs to back
up), plus archived handoffs, into a staging git repo and pushes each run to a
**private** GitHub repo. Every run lands through a pull request that
is squash-merged on the spot: main stays protected, the PR history doubles as
a change log of memory churn, and the backup is complete only when the merge
is.

This is a backup, not a sync. Backup runs copy outward only and never write
to a memory store, a handoff note, or the index. Restoring and merging are
their own explicit commands (see Arguments).

The mirror tree, naming rules, and invariants live in
`${CLAUDE_PLUGIN_ROOT}/docs/layout.md`; the secret-scan behavior in
`${CLAUDE_PLUGIN_ROOT}/docs/secret-scan.md`. Read both before a backup run.

## Arguments

`$ARGUMENTS` is optional:

- *(none)* runs a backup. If nothing is configured yet, run **Setup** first,
  then continue into the backup.
- **`setup`** (re)configures: choose or create the GitHub repo, apply its
  protections, clone the staging copy.
- **`status`** reports the configuration, the remote repo and its visibility,
  and when the last backup landed. No changes.
- **`schedule`** installs a local cron job that runs the backup on a cadence;
  **`unschedule`** removes it. See Schedule mode.
- **`restore ...`**, **`zip ...`**, **`merge ...`** are sibling commands,
  split out so each invocation loads only what it needs. Read
  `${CLAUDE_PLUGIN_ROOT}/commands/restore.md`, `zip.md`, or `merge.md` and
  follow it, passing the remaining arguments through unchanged:
  `/backup restore --dry-run` behaves exactly like
  `/memory-backup:restore --dry-run`.

## The staging repo

State lives in `~/.claude/memory-backup/`, a clone of the backup repo. The
clone existing with an `origin` remote *is* the configuration; there is no
separate config file. Every machine writes only inside its own
`machines/<hostname>/` subtree (`hostname -s`), so any number of laptops can
back up into the same repo without ever colliding (backup per machine; use
`merge` to converge two machines deliberately). The full tree and the
name-derivation rules are in `docs/layout.md`.

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
   recovery path plus the manual fallback from restore.md) and
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
3. Mirror the sources into `machines/<hostname>/` with `rsync -a --delete`,
   following the tree, naming rules, and inclusion list in `docs/layout.md`:
   - every non-empty memory store into `memories/<project>/`; remove
     mirrored stores whose source directory no longer exists or is empty
     (the mirror tracks reality; git history keeps the old contents);
   - `~/.claude/plans/` into `plans/`, if it exists and is non-empty;
   - if `~/.claude/handoff-index.md` exists: copy it and every live path it
     references into the home-relative tree under `handoffs/`. Extract those
     paths deterministically (a `python3` one-liner over the index), **not**
     via shell `grep` inside command substitution: some environments hook or
     proxy grep and return empty output there, which silently skips every
     note. Skip paths that no longer exist; never edit the user's index,
     sources are read-only. If the index does not exist, skip the handoff
     half entirely and silently;
   - **archived handoffs**, which the index no longer lists by design:
     `~/.claude/handoff-archive/` when present, and any `handoff-archive/`
     folder sitting beside a note copied above, each at its home-relative
     place in the `handoffs/` tree;
   - **config**: the selected `~/.claude/` files from `docs/layout.md` into
     `config/`. `settings.json` gets no special credential handling here:
     like every other mirrored file, it goes through the secret scan in the
     next step. The exclusions in `docs/layout.md` (`~/.claude.json`,
     transcripts, history, caches, `plugins/`) are absolute;
   - **deletions propagate in every tree.** The `handoffs/` and `config/`
     trees are file-by-file copies, so after copying, remove any mirrored
     file whose source no longer exists (the memory and plan trees already
     get this from `rsync --delete`). The invariant: **the repo tip always
     mirrors the machine.** Without this, restore would resurrect
     deliberately deleted handoffs and config files.
4. **Scan every mirrored text file for secrets** before anything is
   committed, exactly as specified in `docs/secret-scan.md`: interactive
   runs ask per finding (include / omit / redact, batched), headless runs
   redact automatically and warn loudly; either way the file is backed up
   and the credential never leaves the machine.
5. Write `manifest.json` per `docs/layout.md` (with `"scanned": true`).
   If `git status --porcelain` then shows no changes beyond the manifest's
   timestamp, report "no changes since last backup" and reset the tree; do
   not open an empty PR.
6. Land it:
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
7. Report: the repo, the merged PR link, files added/changed/deleted per
   store, every redaction and omission from the secret scan (loudly, never
   buried), and how long it took.

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
   keep it. If no backup has ever run interactively (no
   `machines/<hostname>/` in the staging repo, or no `.redact-allow`
   decisions yet), recommend one interactive `/backup` first: cron resolves
   secret scan findings on its own (redact and flag, it cannot ask), so the
   first pass over the stores should get the user's include/omit/redact
   calls, not cron's defaults.
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

## Notes

- **Private, verified on every push.** The visibility check runs before each
  push, not just at setup, and there is no override in v1.
- **Secrets stay home; never silently incomplete.** The private repo is the
  boundary for personal prose, not a safe place for credentials: a secret
  pushed to any remote repo should be treated as compromised. The scan keeps
  secrets from leaving at all; when it fires headlessly the file is still
  backed up, redacted and loudly flagged, never silently dropped. If a real
  secret does reach the repo anyway, **rotate it**: deleting it from the
  source removes it from the tip on the next run, but git history keeps
  every pushed version, and purging history is against this command's own
  invariants (history is the archive; never force-push).
- **Backup runs never write to sources.** A backup run writes only to
  `~/.claude/memory-backup/`.
- **Backup, not sync.** Live local state is only ever written by an explicit
  `restore` or `merge`, both interactive and plan-confirmed; nothing flows
  back in the background.
- **Never force-push.** The command touches only `main` and its own
  `backup/*` branches, and resolves nothing with force.
- Roadmap (planned, not built): object storage targets such as S3, GCS, and
  Alibaba OSS (v3); Google Drive via rclone (v4).
