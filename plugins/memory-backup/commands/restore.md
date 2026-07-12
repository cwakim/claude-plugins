---
description: Copy memory stores, handoff notes, plans, and config from a backup (the GitHub mirror or a zip) back onto this machine. Diff-aware and conservative - empty targets restore wholesale, conflicts are asked, nothing local is ever deleted. --dry-run reports the plan and stops.
---

# Restore (`restore [--dry-run] [path]`)

Copies from a backup source back onto this machine. Interactive and
conservative: it adds and (only with consent) overwrites, and it **never
deletes** anything that exists only locally. Whichever source resolves
below, restore only ever reads from it: it never writes back to the
source, and never pushes anywhere. With `--dry-run` it goes exactly as far
as the plan (step 3) and stops: nothing is applied, no question is asked,
and any temp extraction directory is cleaned up. Useful for checking what a
restore would do, especially against the GitHub mirror, which may be weeks
ahead of or behind this machine.

The mirror tree and the name-to-target derivation rules live in
`${CLAUDE_PLUGIN_ROOT}/docs/layout.md`; read it before building the plan.
To converge this machine with a *different* machine's mirror, use `merge`
(`${CLAUDE_PLUGIN_ROOT}/commands/merge.md`) instead: restore maps a mirror
back onto the machine it came from (or a replacement for it), merge
reconciles two machines' divergent state.

## Resolve the source

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
identically: the plan, conflict handling, and report do not care whether
it came from git or a zip.

## Steps

1. Pick the source machine: `machines/<hostname>/` for this host. If that
   directory does not exist (a replacement machine with a new hostname, or
   a zip made on a different laptop), list the machines present in the
   source root and ask which one to restore from.
2. Build a restore plan by comparing the mirror against the live targets,
   per file:
   - **Target store missing or empty** (no `~/.claude/projects/<slug>/memory/`
     or no files in it): restore the whole store wholesale, no per-file
     questions (the single plan confirmation in step 3 still covers it).
   - **Identical files** (same content): skip silently; never ask about a
     file that would not change.
   - **File only in the backup**: restore it (it cannot clobber anything).
     With tip-mirrors-machine semantics this only happens for files deleted
     locally since the last backup run, or on a machine that never had them;
     either way they appear in the plan summary as additions, so a
     deliberately deleted file coming back is visible before it happens.
   - **File only local**: keep it untouched; restore never deletes.
   - **File in both, content differs**: a **conflict**; goes to the user.
   Handoffs, plans, and config get the same treatment: every file maps to
   its live target per the derivation rules in `docs/layout.md`, wholesale
   where the target is absent, conflict where it exists and differs.
3. Present the plan in one compact summary: stores restored wholesale, files
   added, identical files skipped (count only), and the conflicts with a
   short per-file diff description (which side is newer, what changed).
   **With `--dry-run`, this plan is the result: report it and stop.**
   Apply nothing, ask nothing, and clean up the temp extraction directory
   if `<path>` was a zip. Otherwise resolve the conflicts via
   `AskUserQuestion`, batched (multi-select "take the backup version for
   these", keep local for the rest), never one prompt per file, then
   confirm once before applying; when there are no conflicts, that single
   confirmation is the only question. The plan is a checkpoint, not a
   receipt: nothing is written before it is accepted. A plan with no
   changes at all (everything identical) is just reported; there is
   nothing to confirm.
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

## Manual fallback

For a machine without this plugin at all (so no `/backup restore` to run;
also seeded into the backup repo's own README at setup):

```bash
git clone git@github.com:<owner>/<name>.git
rsync -a <name>/machines/<hostname>/memories/<project>/ ~/.claude/projects/$(echo ~ | tr '/' '-')-<project>/memory/
```

Repeat per store; every file under `machines/<hostname>/handoffs/` goes back
to `~/` plus its relative path (the index included), `plans/` goes back to
`~/.claude/plans/`, and `config/` goes back to `~/.claude/`.
