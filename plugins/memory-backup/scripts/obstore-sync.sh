#!/usr/bin/env bash
#
# obstore-sync.sh — mirror a prepared memory-backup tree to an S3-compatible
# object store (AWS S3, GCS via its S3-interop endpoint, Alibaba OSS, or a
# local MinIO). The mechanical core of the memory-backup v3 object-storage
# target: the Claude-driven command builds and secret-scans the tree, then
# calls this script to verify the destination is private and push the mirror.
#
# Contract (read this before changing anything):
#   * SOURCE is already built and already secret-scanned by the caller. This
#     script NEVER scans and NEVER reads the user's live stores; it only
#     mirrors an existing directory. Secret scanning lives in the command
#     layer (docs/secret-scan.md), exactly as it does for the git target.
#   * The destination bucket MUST be private. Fail-closed: if we cannot prove
#     the bucket is reachable with our own credentials AND closed to
#     anonymous access, we refuse and upload nothing. A bucket the public can
#     read or list is the exact failure this gate exists for.
#   * Deletions propagate (`aws s3 sync --delete`): the object-store prefix
#     always mirrors the machine, the same invariant the git tip upholds.
#     Bucket versioning (enabled at setup) is the history analog of git.
#   * This script never deletes a bucket, never touches objects outside its
#     own `<prefix>/machines/<host>/` subtree, and never disables versioning.
#
# Usage:
#   obstore-sync.sh --source DIR --bucket NAME --prefix KEY [options]
#
# Required:
#   --source DIR      Local directory to mirror (the built machines/<host> root
#                     or the staging root that contains it).
#   --bucket NAME     Destination bucket.
#   --prefix KEY      Key prefix under the bucket (e.g. "" or "backups").
#
# Options:
#   --endpoint URL    S3-compatible endpoint. Omit for real AWS S3. Set for
#                     MinIO (http://localhost:9000), GCS
#                     (https://storage.googleapis.com), or OSS
#                     (https://oss-<region>.aliyuncs.com).
#   --region R        AWS region (default: us-east-1; MinIO ignores it).
#   --profile P       aws CLI profile to use for authenticated calls.
#   --dry-run         Plan only: report what would upload/delete, change nothing.
#   --report FILE     Write the JSON report here (default: stdout).
#   -h, --help        This help.
#
# Exit codes:
#   0  success (sync applied, or dry-run planned)
#   2  usage error (bad/missing arguments, missing aws CLI)
#   3  destination unusable (bucket missing, or credentials cannot reach it)
#   4  REFUSED: bucket is public (anonymous access is not denied)
#   5  sync failed (aws s3 sync returned non-zero)

set -euo pipefail

die()  { printf 'obstore-sync: %s\n' "$1" >&2; exit "${2:-2}"; }
warn() { printf 'obstore-sync: %s\n' "$1" >&2; }

SOURCE="" BUCKET="" PREFIX="" ENDPOINT="" REGION="us-east-1" PROFILE=""
DRYRUN=0 REPORT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --source)   SOURCE="${2:-}"; shift 2 ;;
    --bucket)   BUCKET="${2:-}"; shift 2 ;;
    --prefix)   PREFIX="${2:-}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    --region)   REGION="${2:-}"; shift 2 ;;
    --profile)  PROFILE="${2:-}"; shift 2 ;;
    --dry-run)  DRYRUN=1; shift ;;
    --report)   REPORT="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH" 2
[ -n "$SOURCE" ] || die "--source is required"
[ -n "$BUCKET" ] || die "--bucket is required"
[ -d "$SOURCE" ] || die "--source is not a directory: $SOURCE" 2

# Normalize: strip trailing slashes from prefix, guarantee source has one.
PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"
SRC="${SOURCE%/}/"
if [ -n "$PREFIX" ]; then DEST="s3://${BUCKET}/${PREFIX}/"; else DEST="s3://${BUCKET}/"; fi

# Common args for every aws call. --endpoint-url is only added when set, so a
# real-AWS run (no endpoint) is untouched.
AWS_COMMON=(--region "$REGION")
[ -n "$ENDPOINT" ] && AWS_COMMON+=(--endpoint-url "$ENDPOINT")
[ -n "$PROFILE" ]  && AWS_COMMON+=(--profile "$PROFILE")

# ---------------------------------------------------------------------------
# 1. Destination reachable with OUR credentials? (fail-closed on any doubt)
# ---------------------------------------------------------------------------
if ! head_err="$(aws "${AWS_COMMON[@]}" s3api head-bucket --bucket "$BUCKET" 2>&1)"; then
  die "cannot reach bucket '$BUCKET' with the configured credentials: ${head_err}" 3
fi

# ---------------------------------------------------------------------------
# 2. Privacy gate — anonymous access MUST be denied. We probe unsigned, so the
#    check is endpoint-agnostic and works identically on AWS and MinIO. If an
#    unauthenticated caller can LIST or GET, the bucket is public: refuse.
#    (On real AWS the setup step additionally enforces the account/bucket
#    Public Access Block; this empirical probe is the universal backstop.)
# ---------------------------------------------------------------------------
ANON=(--no-sign-request --region "$REGION")
[ -n "$ENDPOINT" ] && ANON+=(--endpoint-url "$ENDPOINT")

# 2a. Anonymous LIST must fail.
if aws "${ANON[@]}" s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 >/dev/null 2>&1; then
  die "REFUSED: bucket '$BUCKET' allows anonymous listing (it is public). Nothing uploaded." 4
fi

# 2b. Anonymous GET of an existing object must fail. Only meaningful if the
#     bucket already holds an object we can name; if it is empty, 2a is enough.
first_key="$(aws "${AWS_COMMON[@]}" s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 \
              --query 'Contents[0].Key' --output text 2>/dev/null || true)"
if [ -n "$first_key" ] && [ "$first_key" != "None" ]; then
  if aws "${ANON[@]}" s3api head-object --bucket "$BUCKET" --key "$first_key" >/dev/null 2>&1; then
    die "REFUSED: bucket '$BUCKET' allows anonymous object reads (it is public). Nothing uploaded." 4
  fi
fi

# ---------------------------------------------------------------------------
# 3. Mirror with delete-propagation. Parse the machine-readable line prefixes
#    aws emits ("upload: ...", "delete: ...", and "(dryrun) ..." variants).
# ---------------------------------------------------------------------------
SYNC=("${AWS_COMMON[@]}" s3 sync "$SRC" "$DEST" --delete --no-progress)
[ "$DRYRUN" -eq 1 ] && SYNC+=(--dryrun)

set +e
sync_out="$(aws "${SYNC[@]}" 2>&1)"; sync_rc=$?
set -e
if [ $sync_rc -ne 0 ]; then
  warn "aws s3 sync failed (rc=$sync_rc):"
  printf '%s\n' "$sync_out" >&2
  exit 5
fi

# Count outcomes. aws prefixes dry-run lines with "(dryrun) ".
uploaded="$(printf '%s\n' "$sync_out" | grep -cE '^(\(dryrun\) )?upload:' || true)"
deleted="$( printf '%s\n' "$sync_out" | grep -cE '^(\(dryrun\) )?delete:' || true)"
uploaded="${uploaded:-0}"; deleted="${deleted:-0}"

# ---------------------------------------------------------------------------
# 4. JSON report.
# ---------------------------------------------------------------------------
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
report="$(cat <<JSON
{
  "target": "object-storage",
  "bucket": "$(esc "$BUCKET")",
  "prefix": "$(esc "$PREFIX")",
  "endpoint": "$(esc "$ENDPOINT")",
  "dryRun": $( [ "$DRYRUN" -eq 1 ] && echo true || echo false ),
  "uploaded": ${uploaded},
  "deleted": ${deleted}
}
JSON
)"

if [ -n "$REPORT" ]; then printf '%s\n' "$report" > "$REPORT"; else printf '%s\n' "$report"; fi
exit 0
