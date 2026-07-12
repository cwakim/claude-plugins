---
description: Export a portable, dated zip archive of everything a backup would mirror - memory stores, handoff notes, plans, and global config - with no GitHub, no gh, no network. Asks each run whether to secret-scan first. Interactive-only by design.
---

# Zip (`zip <path>`)

A portable, dated archive of everything a backup would mirror, without
GitHub: no repo, no `gh`, no network. Useful for a USB copy, an air-gapped
machine, or a one-off snapshot before wiping this laptop. Does not require
`/backup setup` to have run.

The mirror tree and naming rules live in
`${CLAUDE_PLUGIN_ROOT}/docs/layout.md`; the scan behavior in
`${CLAUDE_PLUGIN_ROOT}/docs/secret-scan.md`. Read both before building the
archive.

## Steps

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
   layout and the manual restore fallback: the full inclusion list, naming
   rules, and exclusions are in `docs/layout.md`, and the handoff-copying
   rules (index parsed with python, archived handoffs collected separately)
   are identical to a backup run's.
4. **If scanning was chosen**, scan every file for secrets per
   `docs/secret-scan.md`. Reuse this machine's shared `.redact-allow`
   read-only if it exists; new findings are asked interactively (batched,
   same three choices) and includes go to a `.redact-allow` bundled inside
   the archive itself, never the shared one, per the allowlist section of
   `docs/secret-scan.md`. **If scanning was skipped**, do nothing here:
   every file goes in as found.
5. Write `manifest.json` at the archive root per `docs/layout.md`, with
   `"scanned": true`/`false` recording which choice step 2 made.
6. Zip the temp directory into
   `<path>/memory-backup-<hostname>-<YYYY-MM-DD-HHMM>.zip`, then remove the
   temp directory.
7. Report: the archive's full path and size, counts mirrored per store, and
   whether the scan ran. If scanning ran: every redaction or omission
   (loudly, same as a backup). If it was skipped: repeat the warning from
   step 2 once more here, so it isn't just a prompt someone clicked past.

## Notes

Zip is a snapshot, not configuration: it never touches
`~/.claude/memory-backup/` or the GitHub remote. Restore it with
`/backup restore <path>`, pointed at the zip or its extracted folder; see
`commands/restore.md`, which treats a zip source and the GitHub mirror
identically. A zip can also feed `merge` on another machine, the same way.

**Zip is interactive-only; there is no headless or cron mode for it, by
design.** `/backup`'s headless path exists because a recurring GitHub
backup has nobody around to ask each week, so it has to have an unattended
answer (redact-and-flag). Zip has no such case: it only runs because a
person is sitting at this machine, deciding on a destination `<path>` right
now: a USB drive that's plugged in, a folder they're about to hand off, a
laptop they're about to wipe. There is no scheduled version of "pick a path
and hand it to someone" to automate, so there is no `--no-scan` flag or
cron-safe default for the scan question either: it is always asked, every
run. If `zip` is ever invoked with nobody to ask (for example from a
non-interactive script), log the problem and exit cleanly rather than
guessing an answer to the scan question, the same as `/backup`'s unconfigured
headless behavior.
