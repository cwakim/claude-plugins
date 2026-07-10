# memory-backup

Off-machine durability for Claude Code's machine-local state. One command,
`/backup`, mirrors every per-project memory store, every handoff note (live
and archived), the plans directory, and the hand-written global config
(`~/.claude/CLAUDE.md` and friends) into a staging clone and pushes it to a
**private** GitHub repo, landing each run as a pull request that is
squash-merged immediately. Set it up once, then
run it by hand or from a weekly cron.

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

- **Backup, not sync.** Sources are read-only. Nothing ever flows from the
  repo back onto live stores, and merging stores across machines is out of
  scope for v1 (planned as the v2 `merge` command; see Roadmap). The mirror
  is namespaced by hostname (`machines/<hostname>/...`) and
  backup branches carry the hostname too, so any number of laptops can back
  up into the same repo, each in its own subtree, without ever colliding.
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
```

### Automated (opt-in)

```text
/backup schedule      # pick a cadence; installs a local cron job (weekly default)
/backup unschedule    # remove it
```

Three things to know before scheduling:

- It is **local cron, not a cloud routine**, on purpose: the stores live on
  your machine and a scheduled cloud agent cannot read them.
- Each scheduled run is a real headless Claude Code session and **consumes
  plan/API usage**. Weekly is a sensible default.
- The headless run needs tools pre-approved (`--allowedTools "Read,Glob,Grep,
  Write,Bash"` in the cron line), because nobody is there to click through
  permission prompts. The schedule step shows you the exact line and offers a
  foreground smoke test before trusting it to cron.

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
  it (a false positive; its hash is remembered in a committed allowlist so
  you are never asked about it again), **omit** the file from the run, or
  **redact** the value.
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

If a real secret does reach the repo anyway, **rotate it**. Deleting it from
the source removes it from the repo tip on the next run, but git history
keeps every pushed version, and purging history is against this plugin's own
invariants (history is the archive; never force-push).

## Restore

```text
/backup restore
```

On a fresh machine it clones the backup repo (asking for `owner/name`) and,
if the hostname is new, asks which machine's mirror to restore from. Then it
compares mirror and live targets and builds one plan:

- A store or handoff target that is **missing or empty** is restored
  wholesale, no questions asked.
- **Identical files are skipped silently**; you are never asked about a file
  that would not change.
- A file that exists **only in the backup** is restored; a file that exists
  **only locally** is left untouched. Restore never deletes.
- A file that **exists on both sides with different content** is a conflict:
  you see a short per-file diff summary and pick which files take the backup
  version, in one batched prompt, keeping the local version for the rest.

If there are no conflicts the plan applies without asking. The report lists
what was restored, added, resolved each way, and skipped as identical.

For a machine without this plugin, the manual fallback is a plain
`git clone` plus `rsync` of `machines/<hostname>/memories/<project>/` back
into `~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/`, handoff
files back to `~/` plus their relative path, `plans/` back to
`~/.claude/plans/`, and `config/` back to `~/.claude/`; the backup repo's own
README carries these steps, so they survive even if this machine does not.

## Safety guarantees

- The repo's visibility is verified before **every** push, not just at setup;
  anything other than private aborts the run.
- **The repo tip always mirrors the machine.** A memory, handoff, plan, or
  config file you delete locally disappears from the tip on the next run,
  visibly in that backup's PR diff; git history keeps every version for
  recovery. Deleted means deleted at the tip, so restore does not resurrect
  what you removed on purpose.
- Backup runs write only to `~/.claude/memory-backup/`; live stores are only
  ever written by an explicit `/backup restore`.
- Restore never deletes a local-only file and never overwrites a differing
  file without you choosing it; identical files are never even asked about.
- Every mirrored file is secret-scanned before commit; a headless run
  redacts and flags rather than leaking a credential or silently dropping a
  file, so the backup is never silently incomplete.
- Never force-pushes; touches only `main` and its own `backup/*` branches.
- Unconfigured headless runs log and exit cleanly instead of prompting.

## Roadmap

Planned, not built:

- **v2 `merge`**: combine two machines' mirrors so memories and handoff notes
  from two laptops converge. Per store, diff-aware, the same temperament as
  restore: identical files merge silently, conflicts are yours to resolve,
  nothing is deleted. Handoff notes are keyed to absolute paths, which can
  differ between machines; merge will have to reconcile that mapping, which
  is part of why it is its own version.
- **v3 `--zip <path>`**: a dated archive you can carry.
- **v4 object storage**: S3, GCS, Alibaba OSS.
- **v5 Google Drive**: likely via rclone.

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
