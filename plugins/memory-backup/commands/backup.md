---
description: Back up every per-project memory store and live handoff note to a private GitHub repo, landing each run as a PR that is squash-merged immediately. Or export a portable zip archive with no GitHub required.
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
- **`restore [path]`** copies stores and handoff notes back onto this
  machine: wholesale where the target is empty, diff-and-ask where it is
  not. With no `<path>`, the source is the configured GitHub mirror; given a
  `<path>` (a zip from `zip <path>`, or its already-extracted folder), the
  source is that archive instead, no GitHub involved. See Restore mode.
- **`schedule`** installs a local cron job that runs the backup on a cadence;
  **`unschedule`** removes it. See Schedule mode.
- **`zip <path>`** writes a dated zip archive of everything a backup would
  mirror to `<path>`, no GitHub, no `gh`, no network. See Zip mode.

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
  .redact-allow               # sha256 hashes of scan findings approved as-is
  memories/<project>/...      # mirror of each non-empty memory store
  handoffs/...                # home-relative tree: index + live notes + archives
  plans/...                   # mirror of ~/.claude/plans/, if non-empty
  config/...                  # selected hand-written files from ~/.claude/
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
- `config/` mirrors selected entries of `~/.claude/` directly:
  `config/CLAUDE.md` is `~/.claude/CLAUDE.md`, `config/settings.json` is
  `~/.claude/settings.json`, and so on. Every file restores to `~/.claude/`
  plus its relative path.

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
     index does not exist, skip the handoff half entirely and silently;
   - **archived handoffs**, which the index no longer lists by design:
     `~/.claude/handoff-archive/` when present, and any `handoff-archive/`
     folder sitting beside a note copied above, each at its home-relative
     place in the `handoffs/` tree;
   - **config**: from `~/.claude/`, into `config/`, when present:
     `CLAUDE.md` plus any file it `@`-references beside it (for example
     `RTK.md`), `settings.json`, `keybindings.json`, and the `commands/`,
     `skills/`, and `agents/` directories if non-empty. `settings.json` gets
     no special credential handling here: like every other mirrored file, it
     goes through the secret scan in the next step. **Never** copy
     `~/.claude.json` (it holds OAuth tokens), transcripts, history, caches,
     or the `plugins/` directory (reinstallable, and `settings.json` records
     which plugins were enabled);
   - **deletions propagate in every tree.** The `handoffs/` and `config/`
     trees are file-by-file copies, so after copying, remove any mirrored
     file whose source no longer exists (the memory and plan trees already
     get this from `rsync --delete`). The invariant: **the repo tip always
     mirrors the machine.** A file deleted locally disappears from the tip
     on the next run, visibly in the PR diff, and git history remains the
     archive it can be recovered from. Without this, restore would resurrect
     deliberately deleted handoffs and config files.
4. **Scan every mirrored text file for secrets** before anything is
   committed: memories, handoffs, plans, and config alike. Flag anything
   credential-shaped, on the tiniest suspicion: values assigned to names
   like token, key, secret, or password; known prefixes (`ghp_`,
   `github_pat_`, `sk-`, `AKIA`, `xox`, `-----BEGIN ... PRIVATE KEY-----`);
   long high-entropy opaque strings. Skip any match whose sha256 hash is
   listed in `machines/<hostname>/.redact-allow` (approved false positives,
   see below).
   **Enumerate the files with `os.walk` (or an explicitly hidden-aware
   walk), never a bare `glob('**/*')`:** python's glob skips dot-directories
   by default, and most handoff notes live under `.claude/` folders, so a
   bare glob silently exempts exactly the files this scan most needs to
   cover. The manifest counts in the next step have the same trap.
   - **Interactive run:** present all findings in one batched
     `AskUserQuestion` (file, the flagged snippet, why it was flagged),
     three choices per finding:
     - **include** as-is: this declares the value **is not a secret**, and
       the declaration is permanent and value-global: its sha256 goes into
       `.redact-allow`, so every future run, interactive or headless,
       pushes that value as-is wherever it appears, with no second look.
       The prompt must say this plainly; never label include as merely
       "skip this once". To revoke, delete the hash's line from
       `.redact-allow` and the next run flags the value again. Only an
       interactive include can write to the allowlist; headless runs never
       do;
     - **omit** the file from this run: the previously mirrored version, if
       any, stays at the tip (report the staleness; do not delete it);
     - **redact** the value in the mirrored copy.
   - **Headless run (cron):** never ask, never omit, never leak: **redact
     automatically and commit the file**, then warn loudly, in the run
     report, the PR body, and the cron log, naming each file and the reason,
     so the next interactive look can clean the source or allowlist a false
     positive.
   - Redaction replaces only the matched value, and only in the mirrored
     copy (sources stay read-only, as ever), with the fixed marker
     `[REDACTED:<reason>]`, for example `[REDACTED:github-token]`. The
     marker is deliberately deterministic: an unchanged source mirrors
     identically on the next run, so redactions never defeat the "no changes
     since last backup" check and never churn PR diffs. Never substitute
     random look-alike values; a redaction must read as a redaction.
   - `.redact-allow` holds one sha256 hash per approved string and is
     committed with the mirror: hashes of non-secrets are safe to track, and
     the decisions survive a fresh clone.
5. Write `manifest.json` (hostname, ISO timestamp, the source paths mirrored,
   store, handoff, plan, and config counts, plus counts of redactions and
   omitted files from the scan). If `git status --porcelain` then shows no
   changes beyond the manifest's timestamp, report "no changes since last
   backup" and reset the tree; do not open an empty PR.
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

## Restore mode (`restore [path]`)

Copies from a backup source back onto this machine. Interactive and
conservative: it adds and (only with consent) overwrites, and it **never
deletes** anything that exists only locally. Whichever source resolves
below, restore only ever reads from it: it never writes back to the
source, and never pushes anywhere.

### Resolve the source

- **`<path>` given**: a zip made by `zip <path>`, or its already-extracted
  folder. If `<path>` is a file (a `.zip`), extract it into a fresh temp
  directory (`mktemp -d`) and use that as the source root; if it is
  already a directory, use it directly. Verify the source root contains at
  least one `machines/<hostname>/` subtree; if not, say so and stop. No
  GitHub involved at all: no clone, no `gh`, no network, and no need for
  `/backup setup` to have ever run.
- **No `<path>`**: the configured GitHub mirror. If
  `~/.claude/memory-backup/` is not configured, this is probably the
  disaster-recovery path: ask for the backup repo (`owner/name`), verify it
  exists, and clone it into place first. Otherwise `git pull --ff-only` so
  the mirror is current.

Every step below treats "the source root" as whichever of these resolved,
identically — the plan, conflict handling, and report do not care whether
it came from git or a zip.

1. Pick the source machine: `machines/<hostname>/` for this host. If that
   directory does not exist (a replacement machine with a new hostname, or
   a zip made on a different laptop), list the machines present in the
   source root and ask which one to restore from.
2. Build a restore plan by comparing the mirror against the live targets,
   per file:
   - **Target store missing or empty** (no `~/.claude/projects/<slug>/memory/`
     or no files in it): restore the whole store wholesale, no questions.
   - **Identical files** (same content): skip silently; never ask about a
     file that would not change.
   - **File only in the backup**: restore it (it cannot clobber anything).
     With tip-mirrors-machine semantics this only happens for files deleted
     locally since the last backup run, or on a machine that never had them;
     either way they appear in the plan summary as additions, so a
     deliberately deleted file coming back is visible before it happens.
   - **File only local**: keep it untouched; restore never deletes.
   - **File in both, content differs**: a **conflict**; goes to the user.
   Handoffs, plans, and config get the same treatment: every file under
   `handoffs/` maps to `~/` plus its relative path (per the layout section),
   `plans/` maps to `~/.claude/plans/`, `config/` maps to `~/.claude/`,
   wholesale where the target is absent, conflict where it exists and
   differs. Store targets are rebuilt as
   `~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/`.
3. Present the plan in one compact summary: stores restored wholesale, files
   added, identical files skipped (count only), and the conflicts with a
   short per-file diff description (which side is newer, what changed). Then
   resolve the conflicts via `AskUserQuestion`, batched (multi-select "take
   the backup version for these", keep local for the rest), never one prompt
   per file. If there are no conflicts, apply without asking.
4. Apply, then report: stores restored, files added, conflicts resolved each
   way, files skipped as identical, local-only files left alone. A file that
   was redacted at backup time restores with its `[REDACTED:<reason>]`
   markers in place: the secret itself never reached the repo, so recover
   the real value from the live source or the credential's issuer, not from
   the backup. If the source root's `manifest.json` records `"scanned":
   false` (a zip made with scanning skipped), say so plainly in the report:
   these files were never checked, backup or not. If `<path>` was a `.zip`
   file, remove the temp extraction directory now that the restore is
   done, and equally on an early stop (an invalid source, or the user
   aborting); a `<path>` that was already a directory is left untouched,
   since this run did not create it.

**Manual fallback** (a machine without this plugin at all, so no
`/backup restore` to run; also seeded into the backup repo's own README at
setup):

```bash
git clone git@github.com:<owner>/<name>.git
rsync -a <name>/machines/<hostname>/memories/<project>/ ~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/
```

Repeat per store; every file under `machines/<hostname>/handoffs/` goes back
to `~/` plus its relative path (the index included), `plans/` goes back to
`~/.claude/plans/`, and `config/` goes back to `~/.claude/`.

## Zip mode (`zip <path>`)

A portable, dated archive of everything a backup would mirror, without
GitHub: no repo, no `gh`, no network. Useful for a USB copy, an air-gapped
machine, or a one-off snapshot before wiping this laptop. Does not require
`/backup setup` to have run.

1. `<path>` is required and must be an existing directory (expand a leading
   `~`); if it is missing or not a directory, say so and stop. There is no
   default destination: writing an archive is a deliberate act.
2. Ask via `AskUserQuestion`, every run, before touching anything: **scan
   the mirrored files for secrets before writing the archive, or skip the
   scan?**
   - **Scan (recommended)**: same secret-scan behavior as a GitHub backup.
   - **Skip**: copy everything as-is, no scanning, no redaction. Warn
     plainly, once, before proceeding: the archive may then contain
     credentials verbatim, and it is only as safe as `<path>` itself (a
     bare USB stick or an unencrypted folder is not a private GitHub repo).
   This choice is per-run and is never remembered; a zip made for quick,
   local carrying is a different threat model than the one it makes
   for someone who's about to hand `<path>` to another machine or drive.
3. Build the same tree a backup run would, in a fresh temp directory
   (`mktemp -d`), under `machines/<hostname>/` for parity with the GitHub
   layout and the manual restore fallback: every non-empty
   `~/.claude/projects/*/memory/` store into `memories/<project>/`;
   `~/.claude/plans/`, if non-empty, into `plans/`; the handoff index and
   every live path it references, plus archived handoffs, into `handoffs/`
   (identical rules to Backup run step 3); the same selected `config/` files
   from `~/.claude/`. Same exclusions as a backup: no `~/.claude.json`,
   transcripts, history, caches, or `plugins/`.
4. **If scanning was chosen**, scan every file for secrets, identical to
   Backup run step 4. If
   `~/.claude/memory-backup/machines/<hostname>/.redact-allow` exists (this
   machine already runs GitHub backups), read it and skip re-asking about
   already-approved hashes; zip never writes to that file, since an
   `include` there is a permanent declaration for the GitHub mirror and a
   zip is a separate, one-off artifact. For any new findings, ask
   interactively (batched, same three choices) and write includes to a
   `.redact-allow` bundled inside the archive itself, not the shared one, so
   the archive documents its own decisions; omit or redact as usual. **If
   scanning was skipped**, do nothing here — every file goes in as found.
5. Write `manifest.json` at the archive root: hostname, ISO timestamp,
   source paths, the same counts as a backup manifest, and `"scanned":
   true`/`false` recording which choice step 2 made.
6. Zip the temp directory into
   `<path>/memory-backup-<hostname>-<YYYY-MM-DD-HHMM>.zip`, then remove the
   temp directory.
7. Report: the archive's full path and size, counts mirrored per store, and
   whether the scan ran. If scanning ran: every redaction or omission
   (loudly, same as a backup). If it was skipped: repeat the warning from
   step 2 once more here, so it isn't just a prompt someone clicked past.

Zip is a snapshot, not configuration: it never touches
`~/.claude/memory-backup/` or the GitHub remote. Restore it with
`/backup restore <path>`, pointed at the zip or its extracted folder — see
Restore mode, which treats a zip source and the GitHub mirror identically.

**Zip is interactive-only; there is no headless or cron mode for it, by
design.** `/backup`'s headless path exists because a recurring GitHub
backup has nobody around to ask each week, so it has to have an unattended
answer (redact-and-flag). Zip has no such case: it only runs because a
person is sitting at this machine, deciding on a destination `<path>` right
now — a USB drive that's plugged in, a folder they're about to hand off, a
laptop they're about to wipe. There is no scheduled version of "pick a path
and hand it to someone" to automate, so there is no `--no-scan` flag or
cron-safe default for the scan question either: it is always asked, every
run. If `zip` is ever invoked with nobody to ask (for example from a
non-interactive script), log the problem and exit cleanly rather than
guessing an answer to the scan question — same as `/backup`'s unconfigured
headless behavior.

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
- **Backup runs never write to sources.** Outside of Restore mode, a backup
  run writes only to `~/.claude/memory-backup/`; a zip run writes only to
  the `<path>` it was given (plus its own temp directory, cleaned up after).
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
  diff-aware with conflicts asked like restore (v2); object storage targets
  such as S3, GCS, and Alibaba OSS (v3); Google Drive via rclone (v4).
