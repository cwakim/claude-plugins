---
description: Converge this machine's live memory stores, handoff notes, and plans with another machine's mirror (from the GitHub backup repo or a zip). Restore-style plan and conflict prompts plus keep-both, cross-machine path reconciliation, index files rebuilt as a union. Interactive-only.
---

# Merge (`merge [--dry-run] [path]`)

Converges **this machine's live state** with **the other machines'
mirrors**. Merge reads one, several, or all of the other
`machines/<host>/` subtrees from a backup source and applies their content
into the live stores here, with restore's temperament throughout: plan
first, conflicts asked, nothing local ever deleted, nothing applied before
the plan is confirmed. It never writes into *any* `machines/` subtree; the
every-machine-writes-only-its-own invariant from `docs/layout.md` stands.
It works for any number of machines. Full convergence is one cycle: each
machine in turn merges from all the others and backs up, in any order;
after the last machine's turn every subtree agrees, and resolutions made
early in the cycle propagate through the mirror, so later machines mostly
just confirm them.

Merge covers **memories, handoffs, and plans**. Config is excluded by
design: `settings.json`, keybindings, commands, and agents legitimately
differ per machine, and merging them invites subtle breakage. Config moves
between machines only through an explicit `restore`, where the user has
deliberately chosen a source machine to copy from.

The mirror tree and name-to-target derivation rules live in
`${CLAUDE_PLUGIN_ROOT}/docs/layout.md`; read it before building the plan.
If the source machine picked below turns out to be *this* machine's own
subtree, refuse and point at `restore`: merging a mirror into the machine
it came from is what restore is for.

## Resolve the source

Identical to restore's source resolution:

- **`<path>` given**: a zip made by `zip <path>`, or its already-extracted
  folder. A `.zip` file is extracted into a fresh temp directory
  (`mktemp -d`); a directory is used directly. Verify the source root
  contains at least one `machines/<hostname>/` subtree; if not, say so and
  stop. No GitHub, no `gh`, no network.
- **No `<path>`**: the configured GitHub mirror; `git pull --ff-only` first
  so it is current. If `~/.claude/memory-backup/` is not configured, say so
  and stop: merge presumes an established mirror (for disaster recovery
  onto a fresh machine, use `restore`).

Clean up any temp extraction directory when the run ends, including early
stops (an invalid source, or the user aborting).

## Steps

1. **Pick the source machines.** List the `machines/*` subtrees in the
   source root, excluding this host's own (`hostname -s`). Exactly one
   candidate: use it, but still name it in the plan header, so merging from
   the wrong laptop's mirror is visible before anything happens. Several:
   ask which via a multi-select that includes an **all of them** choice; a
   fleet of three or four machines converges fastest by merging them all in
   one run. None: say so and stop; there is nothing to merge.
2. **Reconcile paths.** Home-relative names transfer between machines by
   construction (the derivation rules in `docs/layout.md` rebuild them
   against *this* home). Three cases need care:
   - **A store whose derived local target does not exist** (the other
     machine has a project this one never had): plan it as a wholesale
     addition to the derived slug anyway. A memory store is just a
     directory under `~/.claude/projects/`; it waits dormant until the
     project is cloned here, and the plan names it, so nothing lands
     invisibly.
   - **Likely same project at a different path** (for example
     `memories/code-personal/` incoming vs a local store at
     `~/.claude/projects/...-sites-personal/`): detect candidate pairs by
     matching the trailing path segment, or by strong overlap in the
     stores' file names. Ask per pair: **merge into the local store's
     path**, **keep separate** (restore to the derived slug as its own
     store), or **skip**. Never silently guess that two stores are the
     same project.
   - **A full-slug store (project outside the home directory)**: the slug
     cannot be re-derived against a different home. Ask: restore the slug
     as-is, remap it to a local path the user names, or skip.
   Handoff notes get the same treatment: a note whose home-relative parent
   directory exists here maps directly; a note targeting a directory that
   does not exist locally is asked about (bring it, creating the
   directories, or skip), batched, and the same trailing-segment pairing
   applies when the same repo lives at different paths on different
   machines. With several sources, reconcile all of them to a single local
   target: each pair question is asked once per project, not once per
   source.
3. **Build the plan**, per target file, over the reconciled targets, with
   the same comparison restore uses: identical files skip silently (never
   asked); files only in a source are additions; files only local are kept
   untouched (merge never deletes); differing content is a conflict. With
   several sources, compare each target across all of them at once,
   deduplicating candidates by content: sources that agree collapse into
   one candidate version, so a file is only a multi-way conflict when the
   sources *actually* differ among themselves (one distinct incoming
   version is the ordinary two-sided case, however many machines carry
   it). Present the plan in one compact summary: stores added wholesale,
   files added, identical skipped (count only), pair decisions from step
   2, and each conflict with a short diff description, labeling every
   candidate version with its host(s) and using the manifests' timestamps
   to say which is newest. **With `--dry-run`,
   this plan is the result: report it and stop.** Ask nothing (the step-2
   questions are reported as open calls the real run would ask, not asked),
   apply nothing, and clean up any temp extraction directory.
4. **Resolve conflicts**, batched via `AskUserQuestion`, one choice set per
   file, built from the deduplicated candidates:
   - **ours**: keep the local version;
   - **theirs (`<host>`)**: take that host's version; one such option per
     distinct incoming version, labeled with its host (or all the hosts
     that carry it, when several agree);
   - **keep all**: keep the local file as-is and write each distinct
     incoming version beside it as `<name>-from-<host>.md` (suffix before
     the extension), so no fact is lost. For a memory file, also adjust
     each copy's frontmatter `name:` slug with the same suffix so
     `[[links]]` stay unambiguous, and let the index union in step 5 list
     them. The duplicates are deliberate debt: merging the texts down to
     one is curation work, the memory-gardener's job, not merge's.
   With two machines this is exactly theirs / ours / keep both.
   A file that was redacted at backup time carries its
   `[REDACTED:<reason>]` markers; if it wins a conflict (or lands via keep
   both), say so in the report: the real value never left its home
   machine, so recover it from there, not from the mirror.
5. **Rebuild the index files as a union.** `MEMORY.md` (per store) and
   `~/.claude/handoff-index.md` are line-per-entry indexes; picking one
   side wholesale would orphan the other side's entries, so they are never
   offered as plain conflicts. After the per-file outcomes settle, rebuild
   each index to list exactly what exists at its targets after apply: keep
   the local lines and their order, append entries for files that landed
   (additions and keep-boths), and drop nothing that is local-only. An
   incoming index line whose file was skipped in step 2 or lost its
   conflict is not appended.
6. **Confirm once, then apply.** The plan plus the conflict resolutions are
   a checkpoint, not a receipt: nothing is written before the single
   confirmation. A plan with no changes at all (everything identical) is
   just reported; there is nothing to confirm.
7. **Report**: stores and files added, conflicts resolved each way (theirs
   / ours / both), pair decisions, index entries appended, identical files
   skipped, local-only files left alone, redacted files that landed, and,
   if the source was a zip whose `manifest.json` records `"scanned":
   false`, a plain warning that those files were never scanned. Remove
   the temp extraction directory if this run created one.
8. **Offer a backup, never auto-run it.** The merge has put this machine's
   live state ahead of its own mirror; end the report with one question:
   run `/backup` now to push the converged state? On yes, follow
   `${CLAUDE_PLUGIN_ROOT}/commands/backup.md`'s backup run. On no, remind
   that convergence completes only when a backup lands (and each other
   machine has merged in turn). Pushing stays a deliberate act; merge
   itself never touches the network beyond reading its source.

## Interactive-only, by design

Merge exists to resolve divergence, and divergence is inherently a
judgment call: which of two edited memories is right, whether two stores
are the same project, whether a fact should live twice. There are no safe
unattended answers to those questions, so there is no cron mode, no
headless path, and no default-resolution flag. If merge is ever invoked
with nobody to ask (for example from a non-interactive script), log the
problem and exit cleanly rather than guessing, the same as `zip`.

## Notes

- **Merge never deletes**, on either side: not a local file, not a source
  file, not a `machines/` subtree. Retiring content is the backup's job
  (tip mirrors the machine) after the owner deletes it locally.
- **Merge never writes to the source.** It reads the other machine's
  subtree and writes only to live local paths; this machine's own subtree
  is updated by the follow-up backup, nothing else.
- **Cycle convergence is the model, not a hidden sync.** However many
  machines share the repo, each one merges deliberately, sees its own
  plan, and answers its own conflicts; nothing converges behind anyone's
  back.
