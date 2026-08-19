# The object-storage target (v3)

Shared reference for backing up to an S3-compatible object store instead of a
private GitHub repo. The **mirror tree is identical** to the git target
(`machines/<hostname>/...`, same naming, same manifest, same secret scan) as
defined in `layout.md` and `secret-scan.md`; only the *destination* and the
*history mechanism* change. Read `layout.md` first; this doc only covers what
differs.

## Why object storage, and when

The git target lands each backup as a squash-merged PR and leans on GitHub for
history, privacy, and the change log. Object storage trades that PR ergonomics
for reach: the same tree can live in AWS S3, Google Cloud Storage (via its
S3-interoperability endpoint), Alibaba OSS, or a self-hosted MinIO, behind an
IAM policy and a lifecycle rule instead of a GitHub account. Pick it when the
mirror should sit in infrastructure you already run, when the data is larger
than a git repo should carry, or when there is no GitHub in the picture at all.

Both targets can coexist: they write disjoint destinations and share nothing
mutable. A machine may back up to git, to object storage, or to both.

## The destination model

There is no staging clone for this target, so the clone-with-an-origin-remote
convention that *is* the git config does not apply. Instead a small JSON config
records the destination:

```text
~/.claude/memory-backup/obstore.json
  { "bucket": "...", "prefix": "...", "endpoint": "...", "region": "...",
    "profile": "..." }
```

- **bucket** / **prefix**: the tree is mirrored to
  `s3://<bucket>/<prefix>/machines/<hostname>/...`. An empty prefix puts
  `machines/` at the bucket root. The per-hostname namespacing is unchanged, so
  any number of machines share one bucket without colliding, exactly as they
  share one repo.
- **endpoint**: omitted for real AWS S3. Set for everything else:
  - MinIO: `http://host:9000`
  - GCS (S3-interop): `https://storage.googleapis.com`
  - Alibaba OSS: `https://oss-<region>.aliyuncs.com`
- **region** / **profile**: passed to the `aws` CLI; the profile selects which
  credentials authenticate the upload.

Credentials come from the standard `aws` CLI resolution (env, profile, instance
role). They are read by the CLI at call time and, like the git target's GitHub
token, **never enter the mirror**.

## How a run lands

1. Build the mirror tree into a staging dir (`~/.claude/memory-backup/staging/`)
   exactly as the git flow builds `machines/<hostname>/`: same sources, same
   naming, same deletion propagation within the tree.
2. **Secret-scan every mirrored file** per `secret-scan.md`. This is unchanged
   and mandatory: interactive runs ask per finding, headless runs redact and
   flag. The scan happens on the staging tree *before* a single byte is
   uploaded. The `.redact-allow` allowlist lives in the tree and round-trips
   through the bucket like any other file.
3. Write `manifest.json` (`"scanned": true`).
4. Hand the staging dir to `scripts/obstore-sync.sh`, which verifies the bucket
   is private and mirrors it (see below). Nothing is uploaded until the privacy
   gate passes.
5. Report: bucket and prefix, objects uploaded and deleted, every redaction and
   omission from the scan (loudly), and how long it took. A run with nothing to
   change uploads nothing and says so.

`scripts/obstore-sync.sh` is the mechanical core, kept as a real script (not
inline bash) precisely so it can be tested end-to-end against a local server;
see `tests/obstore/`. Its contract: the source dir is already built and already
scanned; it only verifies privacy and mirrors. It never reads live stores and
never scans.

## Privacy: verified before every upload

The git target refuses any repo that is not `PRIVATE`. The object-storage
target upholds the same boundary with two checks:

1. **Reachable with our credentials.** `head-bucket` must succeed. A missing
   bucket or bad credentials aborts the run (exit 3) before any privacy claim
   is even considered. This is not overridable.
2. **Closed to the public.** An *anonymous, unsigned* request must be denied.
   The script probes `list-objects-v2 --no-sign-request` (and an anonymous
   `head-object` on an existing key); if either succeeds, the bucket is public.
   This probe is empirical and endpoint-agnostic, so it behaves identically on
   AWS and MinIO and does not depend on any one provider's ACL/policy API.

**What a public finding does depends on who is running**, mirroring how the
secret scan splits interactive from headless:

- **Interactive:** the command warns loudly and asks: **proceed anyway**,
  **fix it** (make the bucket private: remove the public policy / enable Public
  Access Block, then re-verify), or **abort**. A public bucket is sometimes a
  mistake and sometimes a deliberate call; the person at the keyboard makes it.
  "Proceed anyway" re-invokes the sync with `--allow-public`, an explicit,
  per-run, auditable override (it shows up as `"allowPublic": true` in the
  report).
- **Headless (cron/launchd):** there is nobody to warn, so the run **fails
  closed**: REFUSED (exit 4), nothing uploaded. A scheduled job never passes
  `--allow-public`; it will not push your memories to a public bucket
  unattended just because an interactive run might have chosen to.

So `obstore-sync.sh` defaults to refusing a public bucket (exit 4) and only
proceeds when the interactive layer passes `--allow-public` after your yes.

On real AWS the **setup** step additionally turns on the bucket's Public Access
Block (all four flags) and enables **versioning**; the anonymous probe above is
the universal backstop that also guards providers whose Public Access Block
semantics differ.

## History, deletion, and the mirror invariant

- **The prefix always mirrors the machine.** The sync runs with `--delete`, so
  a file removed locally is removed from the bucket on the next run, the same
  invariant the git tip upholds. Restore therefore never resurrects a
  deliberately deleted file.
- **Versioning is the history analog of git.** With bucket versioning on, every
  overwritten or deleted object keeps its prior versions, so the "history is the
  archive, never destroy it" rule survives the move off git. Setup enables
  versioning where the provider supports it and warns where it does not.
- **Never destructive beyond its subtree.** The script only ever syncs into
  `<prefix>/machines/<hostname>/`; it never deletes a bucket, never touches
  another machine's subtree, and never disables versioning.

## Restore from a bucket

`restore` reads an object-storage bucket as a source: when
`obstore.json` exists (and no zip `<path>` is given), it materializes the
mirror into a temp directory with `scripts/obstore-pull.sh` and then runs the
**existing** diff-aware plan/conflict/apply logic unchanged: the temp
directory is just another "source root", handled exactly like an extracted zip
(read-only, cleaned up at the end). `obstore-pull.sh` is read-only against the
bucket and fails closed if there is nothing to pull, so an empty download can
never masquerade as a valid empty source root. If **both** a git mirror and a
bucket are configured, restore asks which to read from; the round-trip is
covered by `tests/obstore/` (pull reproduces the tree byte-for-byte). See
`commands/restore.md`.

## Two targets at once

The git and object-storage targets are independent and may both be configured:
they write disjoint destinations (a git repo vs. a bucket) and share no mutable
state, so a machine can back up to either or both. `restore` asks which source
to read when both exist; a backup run pushes to whichever targets are
configured.

## Setup

`/backup setup` asks which target to configure (GitHub or object storage). The
object-storage branch (see `commands/backup.md`) asks provider, bucket, and
prefix, then runs `scripts/obstore-setup.sh`, the mechanical core:

- **create** the bucket (with `--create`), tolerating "already owned by you";
- **enable versioning**: the history analog of git. Best-effort: warned, not
  fatal, where a provider lacks it. (MinIO supports it; the tests confirm the
  bucket comes back `Status=Enabled`.)
- **enable Public Access Block** (all four flags) where supported. Best-effort:
  MinIO and some S3-compatibles lack the API; warned, not fatal.
- **certify private**: the *fatal* gate. After hardening, the anonymous-access
  probe must be denied; a bucket that is still public exits 4 and setup stops,
  writing no config. This is why PAB being unsupported is not fatal: the
  empirical probe, not any one provider's API, is the real guarantee.

Only on exit 0 does the command write `~/.claude/memory-backup/obstore.json`.
Setup is covered by `tests/obstore/` (create+harden+certify, and refusal of a
public bucket).

## Merge from a bucket

`merge` reads an object-storage bucket the same way `restore` does, materializing
it with `obstore-pull.sh` into a temp source root, but with **no** `--host`, so
the whole `machines/` tree comes down and merge can read across every machine's
subtree. Both-targets-configured asks which to merge from. The multi-host pull
merge depends on is covered by `tests/obstore/`. See `commands/merge.md`.

With that, setup, backup, restore, and merge all support object storage, and a
scheduled headless run backs up every configured target and stays fail-closed on
a public bucket (it never passes `--allow-public`).

## Reconfigure, add, or remove a target

There is no separate reconfigure command: **`setup` does it all.** Run `setup`
again to add the other target, re-point an existing one (a different repo or
bucket), or remove one. `status` lists what is configured. Removing a target
deletes only local wiring (`obstore.json`, or the staging clone) and never the
remote repo, the bucket, or their contents. See `commands/backup.md` (Setup, and
Remove a target).

One coupling to know: `obstore.json` lives inside the staging-clone directory
(`~/.claude/memory-backup/`), so removing the GitHub target (deleting that
directory) also drops the object-storage config; the remove flow warns and
offers to keep a copy first.
