# Object-storage target tests

End-to-end tests for `scripts/obstore-sync.sh` (backup) and
`scripts/obstore-pull.sh` (restore), the mechanical core of the v3
object-storage target. They run against a **real** S3-compatible server
(MinIO) started in Docker on `localhost` — no AWS account, no credentials, no
bytes leave the machine.

## Run

```bash
plugins/memory-backup/tests/obstore/run.sh
```

Requires `docker` (daemon running) and the `aws` CLI. If either is missing the
script prints why and exits **3 (SKIP)** rather than a false pass. The first
run pulls `minio/minio` (~230 MB); later runs reuse it. `KEEP=1 ...` leaves the
container and workdir up for inspection; `PORT=NNNN ...` changes the host port
(default 9010).

## What it proves

Each case is one behavior of the core, asserted against the live server:

1. **Privacy gate** — a bucket made publicly listable is **REFUSED** (exit 4)
   and nothing is uploaded. This is the object-storage analog of the git
   target's "refuse a non-private repo".
2. **Initial upload** — every file in the built tree lands as an object.
3. **No-change run** — a second run with an unchanged tree uploads and deletes
   nothing (the "no changes since last backup" no-op).
4. **Change + add** — a modified file and a new file both upload; untouched
   files do not.
5. **Delete propagation** — a file removed locally is removed from the bucket
   (`--delete`), upholding "the prefix always mirrors the machine".
6. **Round-trip** — syncing the bucket back to a fresh directory reproduces the
   source byte-for-byte (restore correctness).
7. **Dry-run** — `--dry-run` reports the pending change but the stored object is
   untouched (ETag unchanged).
8. **Fail-closed** — an unreachable endpoint aborts (exit 3) without uploading,
   never assuming privacy it could not verify.
9. **`--allow-public` override** — the explicit interactive override turns the
   public-bucket refusal into a loud warning and proceeds (exit 0,
   `allowPublic:true`). Headless never passes it, so headless stays refused.
10. **Restore pull** — `obstore-pull.sh` materializes the bucket into a local
    directory that reproduces the mirror byte-for-byte: the whole
    object-storage-specific part of restore, after which the existing
    plan/apply logic takes over.
11. **Pull fails closed** — pulling a prefix with nothing under it aborts
    (exit 3), so an empty download never masquerades as a valid source root.

A green run is `11 passed, 0 failed`, exit 0.
