#!/usr/bin/env bash
#
# obstore-pull.sh — materialize a memory-backup mirror from an S3-compatible
# object store into a local directory, so `restore` (and `merge`) can treat it
# exactly like an extracted zip. The read-direction counterpart of
# obstore-sync.sh, and the whole object-storage-specific part of restore: once
# the tree is on disk, the existing source-agnostic plan/diff/apply logic takes
# over unchanged.
#
# Contract:
#   * Read-only against the bucket: it downloads, never uploads, never deletes
#     a remote object. (No privacy gate here — that gate guards *writing* your
#     memories to a public place; pulling your own data down is not that risk.)
#   * Fail-closed on reachability: if the bucket or prefix cannot be read with
#     the configured credentials, it aborts rather than producing a partial or
#     empty "source root" that a restore would then treat as authoritative.
#   * Downloads the whole `<prefix>/machines/` subtree (every host) by default,
#     so restore can list machines and pick one, mirroring how a zip carries
#     whichever machines it was made with. Pass --host to fetch just one.
#
# Usage:
#   obstore-pull.sh --dest DIR --bucket NAME [--prefix KEY] [--host HOST]
#                   [--endpoint URL] [--region R] [--profile P]
#
# On success, DEST contains `machines/<host>/...` — a valid restore source root.
#
# Exit codes:
#   0  success (mirror materialized under DEST)
#   2  usage error (bad/missing arguments, missing aws CLI)
#   3  source unusable (bucket/prefix unreachable, or nothing there to pull)

set -euo pipefail

die() { printf 'obstore-pull: %s\n' "$1" >&2; exit "${2:-2}"; }

DEST="" BUCKET="" PREFIX="" HOST="" ENDPOINT="" REGION="us-east-1" PROFILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)     DEST="${2:-}"; shift 2 ;;
    --bucket)   BUCKET="${2:-}"; shift 2 ;;
    --prefix)   PREFIX="${2:-}"; shift 2 ;;
    --host)     HOST="${2:-}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    --region)   REGION="${2:-}"; shift 2 ;;
    --profile)  PROFILE="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH" 2
[ -n "$DEST" ]   || die "--dest is required"
[ -n "$BUCKET" ] || die "--bucket is required"

PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"
# Source subtree: the whole machines/ tree, or a single host under it.
sub="machines"; [ -n "$HOST" ] && sub="machines/${HOST}"
if [ -n "$PREFIX" ]; then SRC="s3://${BUCKET}/${PREFIX}/${sub}/"; else SRC="s3://${BUCKET}/${sub}/"; fi
DEST_SUB="${DEST%/}/${sub}"

AWS_COMMON=(--region "$REGION")
[ -n "$ENDPOINT" ] && AWS_COMMON+=(--endpoint-url "$ENDPOINT")
[ -n "$PROFILE" ]  && AWS_COMMON+=(--profile "$PROFILE")

# Reachable with our credentials?
if ! head_err="$(aws "${AWS_COMMON[@]}" s3api head-bucket --bucket "$BUCKET" 2>&1)"; then
  die "cannot reach bucket '$BUCKET' with the configured credentials: ${head_err}" 3
fi

# Is there anything at the prefix to pull? (Fail-closed: an empty pull must not
# masquerade as a valid, empty source root.)
listing="$(aws "${AWS_COMMON[@]}" s3api list-objects-v2 --bucket "$BUCKET" \
             $( [ -n "$PREFIX" ] && printf -- '--prefix %s/%s/' "$PREFIX" "$sub" || printf -- '--prefix %s/' "$sub" ) \
             --max-items 1 --query 'length(Contents || `[]`)' --output text 2>/dev/null || echo 0)"
[ "${listing:-0}" != 0 ] || die "nothing to restore under '${SRC}' (no objects there)" 3

mkdir -p "$DEST_SUB"
aws "${AWS_COMMON[@]}" s3 sync "$SRC" "$DEST_SUB" --no-progress >/dev/null \
  || die "download from '${SRC}' failed" 3

printf '%s\n' "$DEST"
exit 0
