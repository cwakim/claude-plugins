#!/usr/bin/env bash
#
# obstore-setup.sh: create (optional) and harden an S3-compatible bucket so it
# is a safe memory-backup destination, then certify it is private. The
# mechanical core of the object-storage `setup` flow: the Claude-driven command
# asks the questions and writes `obstore.json`; this script does the
# deterministic, security-critical part and refuses to certify a bucket that is
# still public.
#
# What "harden" means, mirroring the git target's "private repo + branch
# protection":
#   * versioning ON        : the history analog of git (overwritten/deleted
#                            objects keep prior versions). Best-effort: warned,
#                            not fatal, where a provider lacks it.
#   * Public Access Block  : all four flags, on providers that support it.
#                            Best-effort: MinIO and some S3-compatibles lack the
#                            API; that is warned, not fatal.
#   * privacy probe        : the FATAL gate. After hardening, an anonymous,
#                            unsigned request must be denied. If the bucket is
#                            still public (e.g. a pre-existing public policy on
#                            an existing bucket), setup is REFUSED (exit 4): we
#                            never certify a public bucket, exactly as the git
#                            target refuses a non-private repo.
#
# Usage:
#   obstore-setup.sh --bucket NAME [--create] [--prefix KEY] [--endpoint URL]
#                    [--region R] [--profile P] [--report FILE]
#
# Exit codes:
#   0  bucket exists, is hardened as far as the provider allows, and is private
#   2  usage error (bad/missing arguments, missing aws CLI)
#   3  bucket could not be created, or is unreachable with our credentials
#   4  REFUSED: bucket is public after hardening

set -euo pipefail

die()  { printf 'obstore-setup: %s\n' "$1" >&2; exit "${2:-2}"; }
warn() { printf 'obstore-setup: %s\n' "$1" >&2; }

BUCKET="" PREFIX="" ENDPOINT="" REGION="us-east-1" PROFILE="" REPORT="" CREATE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bucket)   BUCKET="${2:-}"; shift 2 ;;
    --prefix)   PREFIX="${2:-}"; shift 2 ;;
    --endpoint) ENDPOINT="${2:-}"; shift 2 ;;
    --region)   REGION="${2:-}"; shift 2 ;;
    --profile)  PROFILE="${2:-}"; shift 2 ;;
    --create)   CREATE=1; shift ;;
    --report)   REPORT="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown argument: $1" ;;
  esac
done

command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH" 2
[ -n "$BUCKET" ] || die "--bucket is required"
PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"

AWS_COMMON=(--region "$REGION")
[ -n "$ENDPOINT" ] && AWS_COMMON+=(--endpoint-url "$ENDPOINT")
[ -n "$PROFILE" ]  && AWS_COMMON+=(--profile "$PROFILE")
ANON=(--no-sign-request --region "$REGION")
[ -n "$ENDPOINT" ] && ANON+=(--endpoint-url "$ENDPOINT")

# --- 1. Create (optional), then require the bucket be reachable & ours -------
if [ "$CREATE" -eq 1 ]; then
  if ! mb_err="$(aws "${AWS_COMMON[@]}" s3 mb "s3://${BUCKET}" 2>&1)"; then
    # Tolerate "already owned by you"; anything else (name taken by another
    # account, bad creds) is confirmed by the head-bucket check just below.
    printf '%s' "$mb_err" | grep -qiE 'AlreadyOwnedByYou|BucketAlreadyOwnedByYou' \
      || warn "create: $mb_err"
  fi
fi
if ! head_err="$(aws "${AWS_COMMON[@]}" s3api head-bucket --bucket "$BUCKET" 2>&1)"; then
  die "bucket '$BUCKET' is not reachable/owned with the configured credentials: ${head_err}" 3
fi

# --- 2. Versioning (best-effort; the history analog of git) ------------------
versioning="unsupported"
if aws "${AWS_COMMON[@]}" s3api put-bucket-versioning --bucket "$BUCKET" \
      --versioning-configuration Status=Enabled >/dev/null 2>&1; then
  status="$(aws "${AWS_COMMON[@]}" s3api get-bucket-versioning --bucket "$BUCKET" \
            --query 'Status' --output text 2>/dev/null || true)"
  [ "$status" = "Enabled" ] && versioning="enabled"
fi
[ "$versioning" = "enabled" ] || warn "versioning could not be enabled on this provider; prior versions will not be retained."

# --- 3. Public Access Block (best-effort; AWS and compatibles) ---------------
pab="unsupported"
if aws "${AWS_COMMON[@]}" s3api put-public-access-block --bucket "$BUCKET" \
      --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
      >/dev/null 2>&1; then
  pab="set"
fi
[ "$pab" = "set" ] || warn "Public Access Block is unavailable on this provider; relying on the anonymous-access probe below."

# --- 4. Privacy probe: the FATAL gate ----------------------------------------
is_public=0
if aws "${ANON[@]}" s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 >/dev/null 2>&1; then
  is_public=1
else
  first_key="$(aws "${AWS_COMMON[@]}" s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 \
                --query 'Contents[0].Key' --output text 2>/dev/null || true)"
  if [ -n "$first_key" ] && [ "$first_key" != "None" ]; then
    aws "${ANON[@]}" s3api head-object --bucket "$BUCKET" --key "$first_key" >/dev/null 2>&1 && is_public=1
  fi
fi
[ "$is_public" -eq 0 ] || die "REFUSED: bucket '$BUCKET' still answers anonymous requests (it is public). Make it private and re-run setup." 4

# --- 5. Report ---------------------------------------------------------------
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
report="$(cat <<JSON
{
  "bucket": "$(esc "$BUCKET")",
  "prefix": "$(esc "$PREFIX")",
  "endpoint": "$(esc "$ENDPOINT")",
  "region": "$(esc "$REGION")",
  "versioning": "${versioning}",
  "publicAccessBlock": "${pab}",
  "private": true
}
JSON
)"
if [ -n "$REPORT" ]; then printf '%s\n' "$report" > "$REPORT"; else printf '%s\n' "$report"; fi
exit 0
