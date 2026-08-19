---
description: Back up every per-project memory store, handoff note, plan, and the hand-written global config to a private GitHub repo, landing each run as a PR that is squash-merged immediately. Also setup, status, and scheduling (cron or launchd); restore, zip, and merge are sibling commands this one dispatches to.
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
- **`setup`** is the single command for all target configuration: **add** a
  target (GitHub repo or object-storage bucket), **reconfigure** (re-point) an
  existing one, or **remove** one. Run it again anytime to change anything;
  there is no separate reconfigure command.
- **`status`** reports the configuration, the remote repo and its visibility,
  and when the last backup landed. No changes.
- **`schedule`** installs a local scheduled job (cron, or launchd on macOS)
  that runs the backup on a cadence; **`unschedule`** removes it. See
  Schedule mode.
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

## Object-storage target (v3)

The default target is a private GitHub repo (everything below). A backup can
instead mirror the **same tree** to an S3-compatible object store (AWS S3, GCS
via its S3-interop endpoint, Alibaba OSS, or a self-hosted MinIO). The mirror
layout, naming, manifest, and mandatory secret scan are identical; only the
destination and the history mechanism differ. When
`~/.claude/memory-backup/obstore.json` exists, this command builds and
secret-scans the tree into `~/.claude/memory-backup/staging/` exactly as for
git, then hands it to `${CLAUDE_PLUGIN_ROOT}/scripts/obstore-sync.sh`, which
verifies the bucket is private and mirrors it with delete-propagation. On a
public bucket the script refuses by default (exit 4); an **interactive** run
warns and, only on the user's explicit yes, re-invokes with `--allow-public`,
while a **headless** run stays refused (nobody to consent). Both targets may be
configured at once — they write disjoint destinations — and `restore` reads a
bucket via `${CLAUDE_PLUGIN_ROOT}/scripts/obstore-pull.sh`. Read
`${CLAUDE_PLUGIN_ROOT}/docs/object-storage.md` for the destination model, the
privacy gate, versioning-as-history, and the remaining follow-ups. The sync and
pull cores are covered by an end-to-end localhost test (`tests/obstore/`, run
against MinIO in Docker).

## Setup (`setup`, or first run when unconfigured)

`setup` is the one command for **all** target configuration: add a target,
reconfigure (re-point) an existing one, or remove one. There is no separate
reconfigure command; running `setup` again is how you change anything.

**Run this as one continuous flow, not a narrated plan.** The only pauses are
the `AskUserQuestion` prompts themselves and the final confirmation: ask a
question, act on the answer, move straight to the next step. Do **not** emit
"checkpoint", "remaining work", or step-by-step progress summaries between the
questions, and do not stop to describe what you are about to do. Produce exactly
one short report at the very end (what changed, what is now configured). A brief
one-line state summary before the first question is fine; running commentary
between stages is not.

"Configured" means at least one target exists: the GitHub staging clone
(`~/.claude/memory-backup/` with an origin remote) or an object-storage config
(`~/.claude/memory-backup/obstore.json`). A first run with neither triggers
setup; on an already-configured machine, `setup` can add the second target
(both may coexist, writing disjoint destinations), re-point either one, or drop
one.

**Ask in two stages, never as one flat action×target list.** A combined list
("re-point object storage / remove object storage / re-point GitHub / remove
GitHub") is confusing; ask the *action* first, then the *target*, and skip
either question when there is only one sensible answer:

1. **Stage one — the action.** Ask via `AskUserQuestion`, offering only the
   actions that are actually possible given what is configured:
   - **Add a target** — offered only when a target is not yet configured.
   - **Reconfigure a target** — offered only when at least one is configured.
   - **Remove a target** — offered only when at least one is configured.
   If only one action is possible (e.g. nothing configured yet → only *add*),
   skip this question and take it.
2. **Stage two — which target.** Ask only when the chosen action has more than
   one candidate; otherwise proceed with the single one, naming it:
   - **Add** → the unconfigured target (if both are unconfigured, ask which).
   - **Reconfigure** / **Remove** → ask which only when both are configured;
     with one configured, it is the target, no question.

Then follow the matching branch: **Reconfigure** re-points an existing target
(GitHub rewires the staging clone to a different repo; object storage rewrites
`obstore.json` to a different bucket) and uses the same branch as **Add**;
**Remove** is the **Remove a target** section below.

Then follow the matching branch. Reconfiguring never deletes the remote repo or
the bucket; it only changes this machine's wiring.

### GitHub target

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
4. Clone into `~/.claude/memory-backup/`. Immediately run
   `git config --local commit.gpgsign false` in the clone: this repo holds
   only backup commits from this plugin, never hand-authored work, so
   signing adds nothing, and a headless run (`claude -p`, no TTY) cannot
   satisfy a GPG passphrase prompt — the scoping is local to this one clone,
   never the user's global git config, so signing elsewhere on the machine
   is untouched. Seed `README.md` (what the repo contains, a warning that it
   must stay private, `/backup restore` as the recovery path plus the manual
   fallback from restore.md) and `.gitignore` (containing `.cron.log`).
   Commit and push this seed **directly to main**: branch protection does not
   exist yet, and the classic protection API needs the branch to exist first.
   If `~/.claude/memory-backup/` already existed from before this fix, apply
   the same `git config --local commit.gpgsign false` to it once, same
   reasoning, no need to re-clone.
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

### Object-storage target

Configures an S3-compatible bucket (AWS S3, GCS via its S3-interop endpoint,
Alibaba OSS, or MinIO). No `gh`; credentials come from the standard `aws` CLI
resolution and never enter the mirror. See `docs/object-storage.md`.

1. **Provider** — ask via `AskUserQuestion`: AWS S3, GCS, Alibaba OSS, or
   MinIO/other. This fixes the endpoint: none for AWS; `--endpoint`
   `https://storage.googleapis.com` for GCS; `https://oss-<region>.aliyuncs.com`
   for OSS; a user-supplied URL (e.g. `http://localhost:9000`) for MinIO. Ask
   for the `aws` profile if the default credentials are not the right ones, and
   the region (default `us-east-1`; MinIO ignores it).
2. **Bucket and prefix** — ask for the bucket name and an optional key prefix
   (empty puts `machines/` at the bucket root). Ask whether to **create** a new
   bucket or use an **existing** one.
3. **Create, harden, and certify private** — run
   `${CLAUDE_PLUGIN_ROOT}/scripts/obstore-setup.sh --bucket <name>
   [--create] [--prefix <k>] [--endpoint <url>] [--region <r>]
   [--profile <p>] --report <tmp>`. It creates the bucket if `--create`,
   enables versioning (the history analog of git) and Public Access Block where
   the provider supports them (best-effort, warned otherwise), and then runs
   the anonymous-access probe. **If the bucket is still public it exits 4 and
   setup stops** — surface the message; do not write any config. Exit 3 means
   the bucket is unreachable or could not be created; stop and show why.
   Relay the report's `versioning`/`publicAccessBlock` state so the user knows
   whether history retention is actually on.
4. **Persist the config** — only on exit 0, write
   `~/.claude/memory-backup/obstore.json` with the bucket, prefix, endpoint,
   region, and profile (create the directory if this is the machine's first
   target). That file existing *is* the object-storage configuration, the way
   the clone-with-an-origin is the GitHub one.
5. Before the first upload, confirm loudly, once, exactly as the GitHub branch
   does: list what will be uploaded and state plainly it leaves the machine for
   the bucket. Proceed only on an explicit yes, then run the backup flow below,
   which builds and secret-scans the tree and calls `obstore-sync.sh`.

### Remove a target

Removing a target stops this machine from backing up to it. It is deliberately
conservative: it only ever deletes **local wiring**, never the remote repo, the
bucket, or their contents (both keep every version already pushed). Offered only
for a target that is actually configured, and never removes the last remaining
one without a clear warning that the machine would then back up nowhere.

- **Remove the object-storage target:** confirm, then delete
  `~/.claude/memory-backup/obstore.json` (and any leftover
  `~/.claude/memory-backup/staging/`). The bucket and every object in it are
  left untouched; re-add later by running `setup` again. State plainly that
  scheduled runs will no longer push to the bucket.
- **Remove the GitHub target:** this is heavier, because the staging clone
  *is* the configuration and also holds the local copy of the mirror. Warn
  clearly, then (on an explicit yes) delete `~/.claude/memory-backup/`. The
  GitHub repo and its full history are **not** touched — only this machine's
  clone. Re-add later with `setup`, which re-clones. If object storage is
  configured via `obstore.json` inside that directory, note that removing the
  clone also drops the object-storage config; offer to keep a copy of
  `obstore.json` first.

After removing, report what remains configured (or that the machine now backs
up nowhere), and remind that a scheduled job, if any, still runs until
`unschedule` — a job with no targets left just exits cleanly.

## Backup run

Runs unattended once configured: no questions, so it works headlessly from a
scheduled job. If unconfigured and running headlessly (no user to ask), log the problem
and exit cleanly instead of starting setup.

**Run every configured target.** Both a GitHub clone and an
`obstore.json` may exist; run each that does (order does not matter, they write
disjoint destinations), and report per target. The GitHub run is steps 1-7
below; the object-storage run follows in its own subsection.

### GitHub target

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

### Object-storage target

Runs when `~/.claude/memory-backup/obstore.json` exists. It reuses the exact
same tree build and secret scan as the GitHub run; only the destination
differs.

1. Read the bucket, prefix, endpoint, region, and profile from `obstore.json`.
2. Build the mirror into `~/.claude/memory-backup/staging/machines/<hostname>/`
   exactly as GitHub-run step 3 does (same sources, naming, inclusion list, and
   in-tree deletion propagation from `docs/layout.md`). The staging dir is this
   target's working area, the way the clone is GitHub's.
3. **Secret-scan every mirrored file** exactly as GitHub-run step 4 (and
   `docs/secret-scan.md`): interactive asks, headless redacts and flags. The
   scan runs on the staging tree *before* a byte is uploaded. Write
   `manifest.json` (`"scanned": true`).
4. Push with `${CLAUDE_PLUGIN_ROOT}/scripts/obstore-sync.sh --source
   ~/.claude/memory-backup/staging --bucket <b> [--prefix <p>] [--endpoint
   <url>] [--region <r>] [--profile <p>] --report <tmp>`. It verifies the
   bucket is private and mirrors with delete-propagation.
   - **Exit 0**: report objects uploaded/deleted from the JSON report; an
     all-zero run is the "no changes since last backup" no-op.
   - **Exit 4 (public bucket)**: **interactive** — warn and offer proceed /
     fix / abort (see `docs/object-storage.md`); on "proceed" re-run with
     `--allow-public`, on "fix" make the bucket private and re-run.
     **Headless** — do not retry; report the refusal loudly and leave the
     bucket untouched. A scheduled run never passes `--allow-public`.
   - **Exit 3/5**: report the failure (unreachable/credentials, or sync error);
     an incomplete push is not a completed backup.
5. Report as the GitHub run does: the bucket, objects changed, every redaction
   and omission from the scan (loudly), and how long it took.

## Status (`status`)

Read-only. Report which target(s) are configured and, for each:

- **GitHub**: whether `~/.claude/memory-backup/` is a clone with an origin, the
  origin remote and its current visibility, the timestamp of the last landed
  backup (last commit on main), and how many stores and handoff notes the last
  manifest recorded.
- **Object storage**: if `~/.claude/memory-backup/obstore.json` exists, the
  bucket, prefix, and endpoint, and a live privacy check on the bucket (the
  same anonymous-access probe the sync uses) so a bucket silently flipped
  public is caught here, not just at push time.

Then whether a scheduled job exists: check both the crontab marker
(`crontab -l 2>/dev/null | grep "# memory-backup"`) and the launchd agent
(`launchctl print gui/$(id -u)/local.memory-backup`).

## Schedule mode (`schedule` / `unschedule`)

Installs (or removes) a **local scheduled job** that runs the backup on a
cadence. Local, not a cloud routine: the stores live on this machine. Two
schedulers are supported: **cron** (everywhere) and **launchd** (macOS
only). The functional difference that matters: cron silently skips a run if
the machine is asleep or off at the scheduled time; launchd runs a missed
job as soon as the machine wakes (though not if it was fully powered off).

**`unschedule`:** remove whichever exists (check both) and confirm:

```bash
# cron entry, if present
crontab -l 2>/dev/null | grep -v "# memory-backup" | crontab -
# launchd agent, if present
launchctl bootout gui/$(id -u)/local.memory-backup 2>/dev/null
rm -f ~/Library/LaunchAgents/local.memory-backup.plist
```

**`schedule`:**

1. Check for an existing job under **both** schedulers (the crontab marker
   and the launchd agent, as in Status). If one exists, show it and ask
   whether to replace or keep it; replacing may also mean switching
   scheduler, in which case remove the old job as in `unschedule`. If no
   backup has ever run interactively (no `machines/<hostname>/` in the
   staging repo, or no `.redact-allow` decisions yet), recommend one
   interactive `/backup` first: a headless run resolves secret scan findings
   on its own (redact and flag, it cannot ask), so the first pass over the
   stores should get the user's include/omit/redact calls, not the
   scheduler's defaults.
2. On macOS (`uname` is `Darwin`), ask which scheduler via
   `AskUserQuestion`, recommending launchd: a laptop asleep at the
   scheduled time misses cron runs entirely, while launchd catches up on
   wake. Offer cron for users who prefer keeping everything in one crontab.
   On other platforms, use cron without asking.
3. Ask the cadence via `AskUserQuestion` (weekly is the sensible default for
   a backup; offer daily and monthly too).
4. Resolve the absolute `claude` binary path (`command -v claude`): neither
   scheduler loads the user's shell profile, so a bare `claude` will not be
   found.
5. Install the job. The command is identical under both schedulers; only
   the wrapper differs.

   **cron**: append the entry (never overwrite other lines):
   ```bash
   (crontab -l 2>/dev/null; echo '<min> <hour> <dom> * <dow> cd ~ && <abs-claude> -p "/memory-backup:backup" --allowedTools "Read,Glob,Grep,Write,Bash" >> ~/.claude/memory-backup/.cron.log 2>&1 # memory-backup') | crontab -
   ```

   **launchd**: write `~/Library/LaunchAgents/local.memory-backup.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key>
     <string>local.memory-backup</string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/zsh</string>
       <string>-lc</string>
       <string>cd ~ &amp;&amp; <abs-claude> -p "/memory-backup:backup" --allowedTools "Read,Glob,Grep,Write,Bash" &gt;&gt; ~/.claude/memory-backup/.cron.log 2&gt;&amp;1</string>
     </array>
     <key>StartCalendarInterval</key>
     <dict>
       <!-- weekly: Weekday (0=Sun) + Hour + Minute; daily: Hour + Minute;
            monthly: Day + Hour + Minute -->
     </dict>
   </dict>
   </plist>
   ```
   then validate and load it:
   ```bash
   plutil -lint ~/Library/LaunchAgents/local.memory-backup.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.memory-backup.plist
   ```

   Either way the `--allowedTools` list is what lets the headless run work
   unattended: reads for collecting the stores, Bash for rsync, git, and gh,
   Write for the manifest. Warn the user this grants those tools unattended
   for that run, and that each run is a real headless session consuming
   plan/API usage. Both schedulers log to the same
   `~/.claude/memory-backup/.cron.log`.
6. Offer a smoke test: run the exact command once in the foreground and
   confirm it lands a backup (or reports "no changes") cleanly. (For
   launchd, `launchctl kickstart gui/$(id -u)/local.memory-backup` fires
   the real job on demand.)
7. Report what was installed (the crontab line, or the plist path and
   label) and how to remove it (`unschedule`). Uninstalling the plugin does
   **not** remove the scheduled job; unschedule first.

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
- Roadmap: object-storage targets (S3, GCS, Alibaba OSS, MinIO) are **v3** —
  setup (add/reconfigure/remove), backup, restore, and merge are all wired, and
  the cores (`scripts/obstore-{setup,sync,pull}.sh`) are tested end-to-end
  against a localhost MinIO (`tests/obstore/`, 15 tests) and dogfooded live.
  Google Drive via rclone is v4, not started.
