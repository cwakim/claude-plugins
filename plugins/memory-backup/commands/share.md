---
description: Build a curated, sanitized handoff bundle for one thread of work and hand it to someone without repo access - the anchor handoff note, the memory stores it touches (project and reference memories only, personal ones held back and offered), the plans you pick, and a generated ONBOARDING.md. Secret-scanned every run. Delivered as a secret gist or a zip. Interactive-only.
---

# Share (`share <thread>`)

Packages one thread of work so a colleague, or you on a machine with no
access to the backup repo, can pick it up. Unlike `zip`, which mirrors
*everything* for your own disaster recovery, `share` is **curated and
sanitized**: it carries only what someone else needs to continue a single
thread, with your personal memories held back by default and every file
secret-scanned before it leaves the machine. It does not require `/backup
setup` to have run.

The bundle uses the same `machines/<hostname>/` layout as every other
command (see `${CLAUDE_PLUGIN_ROOT}/docs/layout.md`), so the recipient
ingests it with the `restore` or `merge` they already have, no new command
on their side. The scan behavior is in
`${CLAUDE_PLUGIN_ROOT}/docs/secret-scan.md`. Read both before building a
bundle.

`share` is **interactive-only, by design.** Every step is a judgment call:
which thread, which repos, which plans, whether a held-back memory should
go, where the bundle lands. There is no cron or headless mode. If `share`
is ever invoked with nobody to ask (for example from a non-interactive
script), log the problem and exit cleanly rather than guessing, the same
as `zip` and `merge`.

## Step 1 - Resolve the thread and its scope

`<thread>` is required.

1. **Match it against `~/.claude/handoff-index.md`**, case-insensitively
   and allowing partial matches, against the titles and one-line goals in
   the index (the same matching `/pickup` uses). This file is written by
   the session-continuity plugin; `share` reads it as a plain file and
   there is no hard dependency.
   - **One live match** (its path still exists): that handoff note is the
     **anchor**.
   - **Several**: list them and ask which via `AskUserQuestion`.
   - **No match, but `<thread>` looks like a path** (contains `/` or ends
     `.md`, expand a leading `~`): use that file as the anchor if it
     exists.
   - **No match and no index**: say so and stop. Suggest running
     `/handoff` on the thread first, since `share` is built around a
     handoff note.
2. **Derive the in-scope set from the anchor note:**
   - **The anchor handoff note itself**, plus a one-line index entry for
     it (see Step 3).
   - **The repo the note lives in**: from the note's home-relative path
     (`~/sites/foo/.claude/handoff.md` -> repo `~/sites/foo`), derive its
     memory store slug per `docs/layout.md` (`sites-foo` ->
     `~/.claude/projects/$(echo ~ | tr '/' '-')-sites-foo/memory/`). If
     that store exists and is non-empty, it is in scope.
   - **Other repos named in the note body**: scan the note text for other
     absolute or `~`-relative repo paths. For each whose memory store
     exists, ask via `AskUserQuestion` whether to include that store too.
     Never pull in a store the note only mentions in passing without
     asking.
   - **Plans**: if `~/.claude/plans/` exists and is non-empty, list every
     plan file and ask via `AskUserQuestion` (multi-select) which belong
     to this thread. Handoff notes do not reliably link plan files, so
     this is never automatic; default the selection to none.
3. If the derived scope is empty (no memory store, no plans, just the
   handoff note), say so and confirm the user still wants a
   handoff-note-only bundle before continuing.

## Step 2 - Curate the memory stores

For each in-scope store, walk it with a hidden-aware traversal (`os.walk`,
per the invariants in `docs/layout.md`) and classify every file:

- **`MEMORY.md`**: always included; it is rebuilt in step 4, not copied
  verbatim.
- **A memory file with frontmatter** (`---` block with `metadata:` /
  `type:`): read the `type`.
  - `project` or `reference` -> **include**. These are the context and
    the pointers a colleague needs.
  - `user` or `feedback` -> **hold back**. These describe you and how you
    work, not the thread.
- **Any other file** (no frontmatter, unparseable frontmatter, an
  unrecognized `type`): **include**, and note it in the report as
  included-by-default so the user can see what fell through.

After the automatic pass, if anything was held back, present **one**
`AskUserQuestion` (multi-select): list each held-back memory by its
`name:` and `description:`, and let the user add any back into the bundle.
A `feedback` note about a project convention, for instance, is often worth
sharing. Nothing held back is included unless the user picks it here.

Global config is **never** part of a share bundle: no `~/.claude/CLAUDE.md`,
no `settings.json`, no `commands/`, `skills/`, or `agents/`. Do not offer
it. State plainly in the final report that config was excluded by design.

## Step 3 - Build the bundle tree

In a fresh temp directory (`mktemp -d`), build the standard
`machines/<hostname>/` tree from `docs/layout.md`, containing only the
in-scope, curated subset:

```text
machines/<hostname>/
  manifest.json        # standard fields, plus the share fields below
  .redact-allow        # new includes from this run's scan (bundle-local)
  memories/<project>/  # each in-scope store, curated per step 2
  handoffs/            # the anchor note at its home-relative path, plus
                       #   .claude/handoff-index.md holding just its one line
  plans/               # only the plans picked in step 1
  ONBOARDING.md        # generated, see step 5
```

- **Handoffs**: only the anchor note, mapped to its home-relative path the
  same way a backup maps it. The bundled `handoffs/.claude/handoff-index.md`
  is a **one-line index**: just the anchor note's entry, kept verbatim. The
  path it resolves to on the recipient's machine is not knowable here, so
  leave the entry text as-is and let their `restore`/`merge` reconcile the
  path. Do not copy this machine's whole index.
- **No `config/` directory**, ever.
- **`manifest.json`** carries the standard fields from `docs/layout.md`
  plus: `"share": true`, `"thread": "<anchor thread name>"`,
  `"scope"` (the stores, plan files, and handoff note included), and
  `"excluded"` (counts of `user`/`feedback` memories held back, and the
  note that config is always excluded). `"scanned"` is always `true`.

## Step 4 - Rebuild each MEMORY.md, then secret-scan

1. **Rebuild `MEMORY.md`** for each in-scope store so it indexes exactly
   the memory files that made it into the bundle: keep the surviving
   lines in their original order, drop the line for any file that was
   held back, and change nothing else. This is the same union-rebuild
   discipline `merge` uses for index files: a stale index pointing at a
   file that is not in the bundle is worse than a shorter one.
2. **Secret-scan every file in the bundle**, mandatory, per
   `docs/secret-scan.md`: memories, the handoff note, plans, and the
   generated `ONBOARDING.md` alike. A share bundle is built specifically
   to leave the machine and reach another person, so it always gets the
   full interactive scan, never `zip`'s skip option.
   - Reuse this machine's shared
     `~/.claude/memory-backup/machines/<hostname>/.redact-allow` read-only
     if it exists, to skip re-asking about already-approved values.
   - Present new findings in one batched `AskUserQuestion` with the same
     three choices (include / omit / redact). Includes are written to the
     **bundle-local** `.redact-allow` only, never the shared one, exactly
     as `zip` does: a share bundle documents its own scan decisions and
     must not silently change what the GitHub mirror will push.

## Step 5 - Generate ONBOARDING.md

Write `machines/<hostname>/ONBOARDING.md`: a short, human-first page the
recipient reads before touching anything. Distill it from the anchor
handoff note, do not just copy the note in. Include:

- **The goal** and **where the thread stands right now**, two or three
  sentences each, from the note's Goal and Status sections.
- **The immediate next step**, from the note's Next / blocked section.
- **Repos to clone** to work on this, with their paths.
- **What is in this bundle**: which memory stores (and that personal
  memories were held back), which plans, the handoff note. Note that
  global config was not included.
- **How to ingest it**: the recipient runs `/backup merge <source>` (or
  `/backup restore <source>` on a machine with no memory of their own),
  where `<source>` is the gist URL or the zip path they received. `merge`
  is the better default: it keeps their own state and resolves conflicts
  keep-both.
- **If a file shows `[REDACTED:<reason>]` markers**: the real value was
  scrubbed before the bundle left the machine; get it from the thread
  owner or the credential's issuer.

Keep it to roughly one screen. A contributor with zero context should be
able to read it and know what the thread is and what to do next.

## Step 6 - Deliver

Ask via `AskUserQuestion`: **secret gist** or **zip**?

### Secret gist

1. Zip the bundle temp directory into a temp file
   `memory-backup-share-<thread-slug>-<YYYY-MM-DD-HHMM>.zip`.
2. Base64-encode that zip into a text file `bundle.zip.base64`.
3. `gh gist create --secret --desc "memory-backup share: <thread> (<date>)" ONBOARDING.md bundle.zip.base64`,
   where `ONBOARDING.md` is a copy of the generated page (plaintext, so
   the recipient can read it directly in the gist web view before
   downloading anything).
4. Report the gist URL. Tell the user plainly:
   - A **secret gist is not access-controlled**: anyone with the link can
     view it. It is unlisted and not searchable, but the link is the only
     gate.
   - **Revoke it when the recipient is done**: `gh gist delete <id>`.
   - The recipient runs `/backup merge <gist-url>` (restore also accepts
     the URL); `restore`/`merge` fetch the gist, decode `bundle.zip.base64`,
     and treat it as a zip source.
5. Remove the temp zip, the base64 file, and the bundle temp directory.

### Zip

1. Ask for a destination directory (`<path>`, expand a leading `~`); it
   must exist and be a directory. There is no default: writing an archive
   is deliberate.
2. Zip the bundle temp directory into
   `<path>/memory-backup-share-<thread-slug>-<YYYY-MM-DD-HHMM>.zip`.
3. Report the archive's full path and size. The recipient runs
   `/backup merge <path>` (or `restore`).
4. Remove the bundle temp directory.

## Step 7 - Report

One summary:

- The thread, and the anchor handoff note's path.
- Memory stores included, and per store: files shared, `user`/`feedback`
  memories held back (count, and which were added back), files
  included-by-default because they had no recognizable `type`.
- Plans included.
- Every redaction or omission from the scan, loudly, naming each file and
  the reason, the same as a backup run.
- That global config was excluded by design.
- The delivery: the gist URL plus the `gh gist delete <id>` reminder, or
  the zip's path and size.
- The one-line ingest instruction for the recipient.

## Notes

- **Share never writes to a source.** Memory stores, the handoff note,
  plans: all read-only, as with every command except `restore` and
  `merge`. The only writes are into the temp bundle directory and, for a
  zip, the `<path>` you name.
- **Share never touches `~/.claude/memory-backup/`** or the GitHub remote
  or an object-storage bucket. It is not a backup; it does not change what
  any target holds. The one exception is reading the shared `.redact-allow`
  to avoid re-asking about known-good values.
- **The recipient needs the plugin and `gh`.** They ingest with their own
  `restore` or `merge`; `share` adds nothing to install on their side
  beyond what `restore` already documents for a gist source.
- **This is a point-in-time bundle.** If the thread moves on, run `share`
  again for a fresh one; there is no update-in-place for an already
  delivered gist (delete it and share again).
