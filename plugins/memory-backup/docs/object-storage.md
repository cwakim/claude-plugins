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

- **bucket** / **prefix** — the tree is mirrored to
  `s3://<bucket>/<prefix>/machines/<hostname>/...`. An empty prefix puts
  `machines/` at the bucket root. The per-hostname namespacing is unchanged, so
  any number of machines share one bucket without colliding, exactly as they
  share one repo.
- **endpoint** — omitted for real AWS S3. Set for everything else:
  - MinIO: `http://host:9000`
  - GCS (S3-interop): `https://storage.googleapis.com`
  - Alibaba OSS: `https://oss-<region>.aliyuncs.com`
- **region** / **profile** — passed to the `aws` CLI; the profile selects which
  credentials authenticate the upload.

Credentials come from the standard `aws` CLI resolution (env, profile, instance
role). They are read by the CLI at call time and, like the git target's GitHub
token, **never enter the mirror**.

## How a run lands

1. Build the mirror tree into a staging dir (`~/.claude/memory-backup/staging/`)
   exactly as the git flow builds `machines/<hostname>/` — same sources, same
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

## Privacy: verified before every upload, fail-closed

The git target refuses any repo that is not `PRIVATE`. The object-storage
target upholds the same boundary with two checks, and **fails closed** — if it
cannot prove the bucket is both reachable and private, it uploads nothing:

1. **Reachable with our credentials.** `head-bucket` must succeed. A missing
   bucket or bad credentials aborts the run (exit 3) before any privacy claim
   is even considered.
2. **Closed to the public.** An *anonymous, unsigned* request must be denied.
   The script probes `list-objects-v2 --no-sign-request` (and an anonymous
   `head-object` on an existing key); if either succeeds, the bucket is public
   and the run is **REFUSED** (exit 4), nothing uploaded. This probe is
   empirical and endpoint-agnostic, so it behaves identically on AWS and MinIO
   and does not depend on any one provider's ACL/policy API.

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

## Out of scope for this cut (follow-ups)

- **Restore/merge from object storage.** The round-trip is proven in the tests
  (a plain `aws s3 sync` in reverse reproduces the tree byte-for-byte), so
  wiring `restore`/`merge` to read a bucket is mechanical, but the interactive
  plan/diff UX is not yet built here.
- **Setup UX** (the `AskUserQuestion` target picker, bucket creation, Public
  Access Block + versioning enablement) is specified above and in `backup.md`
  but not yet a turnkey command flow.
- **Scheduling** reuses the existing headless machinery unchanged once setup
  lands; nothing target-specific is needed.
