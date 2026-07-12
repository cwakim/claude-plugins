# The mirror layout

Shared reference for every memory-backup command. A backup run builds this
tree, `zip` archives the same tree, and `restore` and `merge` map it back
onto a machine. Read this before building a mirror or deriving a target
path; the rules here are the single source of truth for both directions.

## The staging repo

State lives in `~/.claude/memory-backup/`, a clone of the backup repo. The
clone existing with an `origin` remote *is* the configuration; there is no
separate config file. The layout is namespaced by hostname: every machine
writes only inside its own `machines/<hostname>/` subtree and pushes
branches carrying its hostname, so any number of laptops can back up into
the same repo without ever colliding. No command, ever, writes into another
machine's subtree; `restore` and `merge` read from other subtrees but write
only to live local paths.

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

`<hostname>` is `hostname -s`. A zip archive contains the same
`machines/<hostname>/` tree at its root, so every rule below applies
identically to a zip source.

## Naming and derivation rules

Both trees strip the home prefix so names stay short and every target
derives from the name alone, with no lookup table:

- **`memories/<project>/`**: `<project>` is the store's slug minus the home
  prefix. The slug for `~/sites/personal` is
  `-Users-charbelwakim-sites-personal`, mirrored as
  `memories/sites-personal/`. The live target is rebuilt on the current
  machine as `~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/`,
  which also makes mirrors portable to a machine with a different username.
  A store whose project lives outside the home directory keeps its full
  slug (leading `-` and all); such a slug cannot be re-derived against a
  different home and needs the user's call when mapped onto another machine.
- **`handoffs/`** mirrors home-relative paths as real folders:
  `~/sites/personal/.claude/handoff.md` is stored at
  `handoffs/sites/personal/.claude/handoff.md`, and the index at
  `handoffs/.claude/handoff-index.md`. Every file maps to `~/` plus its
  relative path. A note outside the home directory keeps its full path
  under `handoffs/`.
- **`plans/`** mirrors `~/.claude/plans/` directly.
- **`config/`** mirrors selected entries of `~/.claude/` directly:
  `config/CLAUDE.md` is `~/.claude/CLAUDE.md`, `config/settings.json` is
  `~/.claude/settings.json`, and so on. Every file maps to `~/.claude/`
  plus its relative path.

## What goes in, what stays out

The mirror covers: every `~/.claude/projects/*/memory/` directory that
contains at least one file; `~/.claude/plans/` if non-empty; the handoff
index (`~/.claude/handoff-index.md`) plus every live path it references and
every archived handoff (`~/.claude/handoff-archive/`, and any
`handoff-archive/` folder beside a live note); and from `~/.claude/`:
`CLAUDE.md` plus any file it `@`-references beside it, `settings.json`,
`keybindings.json`, and the `commands/`, `skills/`, and `agents/`
directories if non-empty.

**Never** mirrored: `~/.claude.json` (it holds OAuth tokens), transcripts,
history, caches, or the `plugins/` directory (reinstallable, and
`settings.json` records which plugins were enabled).

## The manifest

`manifest.json` at the subtree root records: hostname, ISO timestamp, the
source paths mirrored, store, handoff, plan, and config counts, counts of
redactions and omitted files from the secret scan, and `"scanned":
true`/`false` (a GitHub backup always scans; a zip records the per-run
choice).

## Invariants

- **The repo tip always mirrors the machine.** Deletions propagate in every
  tree: a file deleted locally disappears from the tip on the next backup,
  visibly in the PR diff, and git history remains the archive it can be
  recovered from.
- **Sources are read-only.** A backup or zip run never writes to a memory
  store, handoff note, plan, or config file. Only `restore` and `merge`
  write to live paths, and only interactively, plan-confirmed.
- **Hidden-aware walks, always.** Enumerate files with `os.walk` (or an
  explicitly hidden-aware walk), never a bare `glob('**/*')`: python's glob
  skips dot-directories by default, and most handoff notes live under
  `.claude/` folders. This applies to mirroring, scanning, and manifest
  counts alike.
- **Never force-push.** Commands touch only `main` and their own `backup/*`
  branches, and resolve nothing with force.
