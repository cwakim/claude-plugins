# The secret scan

Shared reference for the commands that build a mirror: a GitHub backup run
(where scanning is mandatory) and `zip` (where each run chooses). Scan
every mirrored text file **before anything is committed or archived**:
memories, handoffs, plans, and config alike.

## What to flag

Anything credential-shaped, on the tiniest suspicion: values assigned to
names like token, key, secret, or password; known prefixes (`ghp_`,
`github_pat_`, `sk-`, `AKIA`, `xox`, `-----BEGIN ... PRIVATE KEY-----`);
long high-entropy opaque strings. Skip any match whose sha256 hash is
listed in `machines/<hostname>/.redact-allow` (approved false positives,
see below).

Enumerate the files with a hidden-aware walk, per the invariants in
`layout.md`: a bare glob silently exempts exactly the dot-directory files
this scan most needs to cover.

## Interactive runs

Present all findings in one batched `AskUserQuestion` (file, the flagged
snippet, why it was flagged), three choices per finding:

- **include** as-is: this declares the value **is not a secret**, and the
  declaration is permanent and value-global: its sha256 goes into
  `.redact-allow`, so every future run, interactive or headless, pushes
  that value as-is wherever it appears, with no second look. The prompt
  must say this plainly; never label include as merely "skip this once".
  To revoke, delete the hash's line from `.redact-allow` and the next run
  flags the value again. Only an interactive include can write to the
  allowlist; headless runs never do.
- **omit** the file from this run: the previously mirrored version, if
  any, stays at the tip (report the staleness; do not delete it).
- **redact** the value in the mirrored copy.

## Headless runs (cron)

Never ask, never omit, never leak: **redact automatically and commit the
file**, then warn loudly, in the run report, the PR body, and the cron log,
naming each file and the reason, so the next interactive look can clean the
source or allowlist a false positive.

## Redaction

Redaction replaces only the matched value, and only in the mirrored copy
(sources stay read-only, as ever), with the fixed marker
`[REDACTED:<reason>]`, for example `[REDACTED:github-token]`. The marker is
deliberately deterministic: an unchanged source mirrors identically on the
next run, so redactions never defeat the "no changes since last backup"
check and never churn PR diffs. Never substitute random look-alike values;
a redaction must read as a redaction.

## The allowlist

`.redact-allow` holds one sha256 hash per approved string and is committed
with the mirror: hashes of non-secrets are safe to track, and the decisions
survive a fresh clone.

`zip` treats the shared allowlist as read-only: if
`~/.claude/memory-backup/machines/<hostname>/.redact-allow` exists (this
machine already runs GitHub backups), read it and skip re-asking about
already-approved hashes, but never write to it: an include there is a
permanent declaration for the GitHub mirror, and a zip is a separate,
one-off artifact. New includes during a zip scan go to a `.redact-allow`
bundled inside the archive itself, so the archive documents its own
decisions.
