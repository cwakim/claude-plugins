# memory-backup

Off-machine durability for Claude Code's machine-local state. `/backup`
mirrors every per-project memory store, every handoff note (live and
archived), the plans directory, and the hand-written global config
(`~/.claude/CLAUDE.md` and friends) into a staging clone and pushes it to a
**private** GitHub repo, landing each run as a pull request that is
squash-merged immediately. Set it up once, then run it by hand or from a
weekly cron. Restore, zip export, and cross-machine merge are sibling
commands: `/backup restore ...`, `/backup zip ...`, and `/backup merge ...`
all still work, dispatching to `/memory-backup:restore`, `:zip`, and
`:merge` respectively.

## Why

Claude Code's persistent memory lives in exactly one place: this machine, one
directory per project under `~/.claude/projects/<slug>/memory/`. Handoff notes
are scattered across project repos and are often gitignored; the handoff index,
the plan documents in `~/.claude/plans/`, and the hand-written global config
(`~/.claude/CLAUDE.md`, `settings.json`, custom commands and agents) live
outside any repo. None of it is reproducible: it is distilled judgment,
decisions, and context accumulated across sessions. A dead disk loses all of
it at once, and nothing else backs it up.

This plugin exists for that single failure and stays deliberately narrow:

- **Backup, not sync.** Sources are read-only during a backup: nothing ever
  flows from the repo back onto live stores in the background. Restoring
  and merging are explicit, interactive, plan-confirmed commands you run on
  purpose. The mirror is namespaced by hostname (`machines/<hostname>/...`)
  and backup branches carry the hostname too, so any number of laptops can
  back up into the same repo, each in its own subtree, without ever
  colliding; `/backup merge` is how two of them converge deliberately (see
  Merge below).
- **Private, verified on every push.** Memories hold personal and
  work-sensitive content. The run checks the repo is still private before
  every push and refuses a public repo with no override.
- **Secrets stay home.** Every mirrored file is secret-scanned before it is
  committed. Interactive runs ask you per finding; unattended runs redact
  the value in the mirrored copy and flag it loudly, so the file is still
  backed up but the credential never leaves the machine. See Sensitive
  content below.
- **Restore never clobbers.** `/backup restore` fills empty targets wholesale,
  but where local content already exists it diffs file by file: identical
  files are skipped without a question, local-only files are never deleted,
  and every conflicting file is your call, asked in one batched prompt.

## How a run lands

Every backup is a pull request that is squash-merged on the spot: main stays
protected (PRs required, zero approvals), merged branches auto-delete, and the
PR history reads as a change log of your memory churn. If the merge fails the
run says so and leaves the PR link: an unmerged PR is not a completed backup.
A run with no changes opens no PR at all.

## Workflows

### Setup, once

```text
/backup setup
```

Choose a repo name (default `memory-backup`) or point at an existing repo.
Creating goes through `gh`: private repo, branch protection on main, auto
delete of merged branches. Pointing at an existing repo verifies it is
private first. Before the first push you get one loud confirmation listing
exactly what leaves the machine.

### The routine

```text
/backup               # mirror, commit, PR, squash-merge; "no changes" is a no-op
/backup status        # config, repo visibility, when the last backup landed
/backup restore       # copy back from the repo: fill what is empty, ask on conflicts
/backup restore <path> # same, but from a zip (or its extracted folder) instead of GitHub
/backup merge         # converge with another machine's mirror (see Merge below)
```

### Automated (opt-in)

```text
/backup schedule      # pick a scheduler and cadence (weekly default)
/backup unschedule    # remove it
```

On macOS the schedule step asks whether to install the job as a classic
**cron** entry or a **launchd** agent, and recommends launchd: cron silently
skips a run if the machine is asleep at the scheduled time, launchd runs the
missed job when it wakes. On other platforms it installs cron without asking.

Four things to know before scheduling:

- **Run `/backup` interactively at least once first.** A headless run
  resolves secret scan findings on its own (it redacts and flags; it cannot
  ask), so let an interactive run surface what the scan finds in *your*
  stores and make the include/omit/redact calls yourself. Once the false
  positives are allowlisted, scheduled runs are quiet.
- It is a **local job, not a cloud routine**, on purpose: the stores live on
  your machine and a scheduled cloud agent cannot read them.
- Each scheduled run is a real headless Claude Code session and **consumes
  plan/API usage**. Weekly is a sensible default.
- The headless run needs tools pre-approved (`--allowedTools "Read,Glob,Grep,
  Write,Bash"` in the job's command), because nobody is there to click
  through permission prompts. The schedule step shows you the exact command
  and offers a foreground smoke test before trusting it to the scheduler.

### Portable archive (no GitHub required)

```text
/backup zip <path>      # dated zip of everything a backup would mirror
```

For a USB copy, an air-gapped machine, or a one-off snapshot before wiping
a laptop. No repo, no `gh`, no network, and no prior `/backup setup`
needed. Every run asks first whether to secret-scan before writing the
archive: **scan** runs the same check a GitHub backup does (reusing this
machine's `.redact-allow` if one already exists, without writing back to
it), **skip** copies everything as-is with one loud warning that the
archive may then hold credentials verbatim and is only as safe as `<path>`
itself. The result lands at
`memory-backup-<hostname>-<YYYY-MM-DD-HHMM>.zip`. Restore it with
`/backup restore <path>` (see Restore below), pointed at the zip or its
extracted folder: the same diff-aware, conflict-batched restore as the
GitHub mirror, not the raw manual fallback.

Zip is **interactive-only, deliberately**: no cron, no headless mode.
Unlike a recurring GitHub backup, which needs an unattended answer because
nobody is around to ask it weekly, zip only ever runs because someone is at
this machine right now, choosing a destination path. There's nothing to
schedule about that, so the scan question above is always asked, every run.

You can also run the same headless backup yourself at any time, without
cron, from any terminal; this is exactly what the cron job executes (cron
uses the absolute `claude` path, which `command -v claude` resolves here):

```bash
cd ~ && "$(command -v claude)" -p "/memory-backup:backup" --allowedTools "Read,Glob,Grep,Write,Bash"
```

With no `--model` flag (as above, and as the cron line runs it), the backup
uses your global default model (`model` in `~/.claude/settings.json`, or
Claude Code's built-in default if that key is unset). Pass `--model` to pin
it explicitly instead:

```bash
cd ~ && "$(command -v claude)" -p "/memory-backup:backup" --allowedTools "Read,Glob,Grep,Write,Bash" --model sonnet
```

Useful as a manual push after a heavy session, or to debug a failing cron
run in the foreground (scheduled runs log to
`~/.claude/memory-backup/.cron.log`).

## What gets backed up

```text
machines/<hostname>/
  manifest.json                          # hostname, timestamp, source paths, counts
  .redact-allow                          # hashes of scan findings you approved as-is
  memories/
    sites-personal/...                   # every non-empty memory store, named by
    sites-claude-plugins/...             # its project slug minus the home prefix
  handoffs/
    .claude/handoff-index.md             # the handoff index, if one exists
    .claude/handoff-archive/...          # archived threads (the index drops these)
    sites/personal/.claude/handoff.md    # each live note, at its home-relative path
  plans/...                              # mirror of ~/.claude/plans/
  config/                                # selected hand-written ~/.claude/ files:
    CLAUDE.md                            # global instructions + @-referenced files
    settings.json                        # hooks, plugins, marketplaces
    ...                                  # keybindings.json, commands/, skills/, agents/
```

Both trees strip the home prefix, so names stay short, the repo is browsable
by project, and every restore target derives from the name alone (`~/` plus
the relative path for handoffs; the store slug is rebuilt from the current
machine's home, which also makes mirrors portable across usernames).

Handoff notes are produced by the session-continuity plugin, but there is no
dependency: `/backup` reads `~/.claude/handoff-index.md` as a plain file if it
exists and silently skips the handoff half if it does not. Archived handoffs
are collected separately on purpose: archiving removes a note from the index,
so an index-driven copy alone would silently miss them.

Deliberately excluded: `~/.claude.json` (holds OAuth tokens; never pushed,
even to a private repo), transcripts, history, caches, and installed plugins
(reinstallable; `settings.json` records which were enabled).

The staging clone lives at `~/.claude/memory-backup/`; that clone existing
with an origin remote *is* the configuration. Deleting it deconfigures the
plugin without touching the GitHub repo.

## Sensitive content

The private repo is the boundary for personal and work-sensitive prose. It
is **not** a safe place for credentials: a private repo is only as secure as
your GitHub account, every token with repo scope on every machine, and every
third-party app you have granted access, so a secret that reaches any remote
repo should be treated as compromised. `/backup` therefore keeps secrets
from leaving the machine at all:

- Every mirrored text file is **secret-scanned before it is committed**:
  memories, handoffs, plans, and config alike. Anything credential-shaped is
  flagged on the tiniest suspicion: token/key/secret/password assignments,
  known prefixes such as `ghp_`, `sk-`, or `AKIA`, private key blocks, long
  opaque strings.
- **Interactive runs ask**, in one batched prompt, per finding: **include**
  it, **omit** the file from the run, or **redact** the value.
- **Include is a permanent declaration, so treat it with respect.** Choosing
  include means "this is not a secret": the value's hash goes into a
  committed allowlist (`.redact-allow`), and every future run, interactive
  or cron, pushes that value as-is wherever it appears, with no second
  look. Include a real credential and cron will keep pushing it every week.
  Only an interactive include can write to the allowlist; cron never does.
  To revoke one, delete its line from `machines/<hostname>/.redact-allow`
  and the next run flags the value again.
- **Unattended runs never ask and never leak**: the value is replaced with a
  fixed `[REDACTED:<reason>]` marker in the mirrored copy, the file is
  committed, and the run warns loudly in the report, the PR body, and the
  cron log. The file is backed up; the secret stays home. The marker is
  deterministic on purpose, so an unchanged source never shows up as a new
  diff.
- Redaction touches **only the mirrored copy**. Your memories, handoffs, and
  config files are never edited. A redacted file restores with its markers
  in place; recover the real value from the credential's issuer, not the
  backup.
- `~/.claude.json` never goes through any of this: it is excluded outright,
  always.

This all applies to the GitHub mirror, where scanning is mandatory. A zip
export (see Portable archive above) asks each run whether to scan at all,
since it never leaves the machine on its own the way a push does.

If a real secret does reach the repo anyway, **rotate it**. Deleting it from
the source removes it from the repo tip on the next run, but git history
keeps every pushed version, and purging history is against this plugin's own
invariants (history is the archive; never force-push).

## Restore

```text
/backup restore                    # from the configured GitHub mirror
/backup restore <path>             # from a zip made by `zip <path>`, or its extracted folder
/backup restore --dry-run [path]   # plan only: show what a restore would do, touch nothing
```

With no `<path>`, on a fresh machine it clones the backup repo (asking for
`owner/name`); with a `<path>`, it reads that zip or folder directly, no
GitHub, no `gh`, no network. Either way, if the hostname is new (a
replacement machine, or a zip made on a different laptop) it asks which
machine's mirror to restore from, then compares mirror and live targets and
builds one plan, identically regardless of source:

- A store or handoff target that is **missing or empty** is restored
  wholesale, with no per-file questions.
- **Identical files are skipped silently**; you are never asked about a file
  that would not change.
- A file that exists **only in the backup** is restored; a file that exists
  **only locally** is left untouched. Restore never deletes.
- A file that **exists on both sides with different content** is a conflict:
  you see a short per-file diff summary and pick which files take the backup
  version, in one batched prompt, keeping the local version for the rest.

The plan is a checkpoint, not a receipt: nothing is written until you accept
it. After the conflict prompt (or straight away, if there are none), restore
asks once to apply the plan; a plan with no changes at all is just reported.
With `--dry-run` it stops at the plan entirely: what would be restored
wholesale, added, or conflict, and nothing else, so you can inspect a mirror
(especially the GitHub one, which may be weeks ahead of or behind this
machine) before committing to anything. The report lists
what was restored, added, resolved each way, and skipped as identical, and
if the source was a zip made with scanning skipped (`manifest.json`'s
`"scanned": false`), says so plainly: those files were never checked.

For a machine without this plugin at all (so no `/backup restore` to run),
the manual fallback is a plain `git clone` plus `rsync` of
`machines/<hostname>/memories/<project>/` back into
`~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/`, handoff files
back to `~/` plus their relative path, `plans/` back to `~/.claude/plans/`,
and `config/` back to `~/.claude/`; the backup repo's own README carries
these steps, so they survive even if this machine does not.

## Merge

```text
/backup merge                    # converge with another machine's mirror, from GitHub
/backup merge <path>             # same, from a zip made on the other machine
/backup merge --dry-run [path]   # plan only: report what a merge would do, ask nothing
```

Restore maps a mirror back onto the machine it came from; **merge converges
this machine with the other machines' mirrors**, however many there are. It
reads one, several, or all of the other `machines/<host>/` subtrees from
the backup repo (or a zip carried over) and applies memories, handoff
notes, and plans into the live state here, with
restore's temperament: identical files skip silently, additions land
visibly, conflicts are yours, nothing local is ever deleted, and nothing is
applied before you confirm the plan. Config is deliberately excluded:
settings, keybindings, and commands legitimately differ per machine and only
move via an explicit restore.

What merge adds beyond restore:

- **Cross-machine path reconciliation.** Home-relative names transfer
  between machines by construction (even across usernames). A store for a
  project this machine never had lands dormant at its derived path, named
  in the plan. When the same project likely lives at *different* paths on
  the two machines, merge detects the pair and asks: merge into the local
  path, keep separate, or skip; it never silently guesses. Stores from
  outside the home directory are asked about too (as-is, remap, or skip).
- **Keep both (or all).** Conflicts offer more than theirs/ours: keep the
  local file and land each distinct incoming version beside it as
  `<name>-from-<host>.md`, indexed, so no fact is lost. Sources that agree
  are deduplicated into one candidate first, so a three-laptop fleet only
  ever asks about versions that actually differ. Gardening the duplicates
  down to one file later is the memory-gardener's job.
- **Indexes rebuilt as a union.** `MEMORY.md` and the handoff index are
  never offered as pick-one conflicts (that would orphan the losing side's
  entries); after per-file outcomes settle, each index is rebuilt to list
  exactly what exists, keeping local order and appending what landed.
- **A backup offer at the end.** A merge leaves this machine ahead of its
  own mirror, so it ends by asking whether to run `/backup` now. It never
  pushes on its own. Any number of machines converge in one cycle: each
  merges from the others and backs up, in any order, and resolutions made
  early in the cycle propagate so later machines mostly just confirm.

Merge is **interactive-only**, like zip: divergence is a judgment call, so
there is no cron mode and no default-resolution flag. Invoked with nobody
to ask, it logs the problem and exits cleanly.

## Safety guarantees

- The repo's visibility is verified before **every** push, not just at setup;
  anything other than private aborts the run.
- **The repo tip always mirrors the machine.** A memory, handoff, plan, or
  config file you delete locally disappears from the tip on the next run,
  visibly in that backup's PR diff; git history keeps every version for
  recovery. Deleted means deleted at the tip, so restore does not resurrect
  what you removed on purpose.
- A backup run writes only to `~/.claude/memory-backup/`; a zip run writes
  only to the `<path>` you give it. Live stores are only ever written by an
  explicit `/backup restore` or `/backup merge`.
- Restore and merge never delete a local-only file and never overwrite a
  differing file without you choosing it; identical files are never even
  asked about. Nothing is applied before the plan is confirmed, and
  `--dry-run` never gets that far: it reports the plan and stops. Neither
  ever writes back to its source, and merge never writes into any
  `machines/` subtree; each machine's own subtree is updated only by its
  own backup runs.
- Every file mirrored to GitHub is secret-scanned before commit; a headless
  run redacts and flags rather than leaking a credential or silently
  dropping a file, so the backup is never silently incomplete. A zip asks
  each run whether to scan at all, and says so loudly (in the archive and
  the report) whenever scanning was skipped.
- Never force-pushes; touches only `main` and its own `backup/*` branches.
- Unconfigured headless runs log and exit cleanly instead of prompting.

## Roadmap

Planned, not built:

- **v3 object storage**: S3, GCS, Alibaba OSS.
- **v4 Google Drive**: likely via rclone.

`merge` (the planned v2) shipped in 1.0.0; see Merge above.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install memory-backup@cwakim-plugins
```

Requires the GitHub CLI (`gh`), authenticated.

## Notes

- Pairs naturally with the memory-gardener plugin (gardening keeps memory
  healthy, backup keeps it existing), but neither depends on the other.
- Uninstalling the plugin does **not** remove a scheduled cron job (plugins
  have no uninstall hook). Run `/backup unschedule` first.
