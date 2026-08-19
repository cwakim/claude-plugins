#!/usr/bin/env bash
#
# run.sh — end-to-end test for obstore-sync.sh against a real S3-compatible
# server (MinIO) running on localhost in Docker. No AWS account, no network
# egress, nothing leaves the machine. Proves the v3 object-storage core does
# what it claims: verifies privacy, mirrors, propagates deletes, round-trips,
# and fails closed.
#
# Requirements: docker (daemon running), aws CLI. If either is missing the
# script prints why and exits 3 (SKIP), never a false pass.
#
# Usage: tests/obstore/run.sh          # start MinIO, run, tear down
#        KEEP=1 tests/obstore/run.sh   # leave the container up for inspection

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SYNC="$HERE/../../scripts/obstore-sync.sh"
PULL="$HERE/../../scripts/obstore-pull.sh"
SETUP="$HERE/../../scripts/obstore-setup.sh"
PORT="${PORT:-9010}"
ENDPOINT="http://127.0.0.1:${PORT}"
BUCKET="mb-test-$$"
CONTAINER="mb-obstore-test-$$"
WORK="$(mktemp -d)"
PASS=0 FAIL=0

# MinIO root creds; also what the aws CLI authenticates with below.
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1
AWSM=(aws --endpoint-url "$ENDPOINT")

skip() { printf '\n\033[33mSKIP:\033[0m %s\n' "$1" >&2; cleanup; exit 3; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

# Robust object count. `length(Contents || `[]`)` yields 0 on an empty bucket,
# where a bare `Contents[].Key` prints the literal "None" and `length(Contents)`
# errors on the absent key.
count_objects() {
  "${AWSM[@]}" s3api list-objects-v2 --bucket "$BUCKET" \
    --query 'length(Contents || `[]`)' --output text 2>/dev/null
}

cleanup() {
  if [ "${KEEP:-0}" != "1" ]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  else
    printf '\nKEEP=1: container %s and workdir %s left up.\n' "$CONTAINER" "$WORK"
  fi
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || skip "docker not found"
docker info >/dev/null 2>&1        || skip "docker daemon not running (start Docker Desktop)"
command -v aws >/dev/null 2>&1     || skip "aws CLI not found"
[ -x "$SYNC" ] || chmod +x "$SYNC"
[ -x "$PULL" ] || chmod +x "$PULL"
[ -x "$SETUP" ] || chmod +x "$SETUP"

echo "==> Starting MinIO on ${ENDPOINT} (container ${CONTAINER})"
docker run -d --name "$CONTAINER" -p "${PORT}:9000" \
  -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data >/dev/null 2>&1 \
  || skip "could not start MinIO (image pull needs network on first run)"

echo "==> Waiting for MinIO to become ready"
ready=0
for _ in $(seq 1 40); do
  if curl -fsS "${ENDPOINT}/minio/health/ready" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.5
done
[ "$ready" = 1 ] || skip "MinIO did not become ready in time"

echo "==> Creating private bucket ${BUCKET}"
"${AWSM[@]}" s3 mb "s3://${BUCKET}" >/dev/null || skip "could not create bucket"

# Build a realistic mirror tree: machines/<host>/{memories,handoffs,plans,config}
HOST="testhost"
build_tree() {
  local root="$1"; rm -rf "$root"; mkdir -p "$root/machines/$HOST"
  local m="$root/machines/$HOST"
  mkdir -p "$m/memories/sites-personal" "$m/handoffs/.claude" "$m/plans" "$m/config"
  printf 'MEMORY index\n- one\n'            > "$m/memories/sites-personal/MEMORY.md"
  printf 'a fact about the project\n'       > "$m/memories/sites-personal/fact.md"
  printf '# handoff index\n- thread A\n'    > "$m/handoffs/.claude/handoff-index.md"
  printf 'plan body\n'                      > "$m/plans/roadmap.md"
  printf '# global CLAUDE.md\n'             > "$m/config/CLAUDE.md"
  printf '{"host":"%s","scanned":true}\n' "$HOST" > "$m/manifest.json"
}
build_tree "$WORK/src"

echo
echo "==> Tests"

# --- Test 1: privacy gate refuses a PUBLIC bucket -------------------------
# Grant anonymous list+read via a bucket policy, then expect REFUSED (exit 4).
cat > "$WORK/public.json" <<POLICY
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*",
"Action":["s3:GetObject","s3:ListBucket"],
"Resource":["arn:aws:s3:::${BUCKET}","arn:aws:s3:::${BUCKET}/*"]}]}
POLICY
"${AWSM[@]}" s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$WORK/public.json" >/dev/null 2>&1
out="$("$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" 2>&1)"; rc=$?
if [ $rc -eq 4 ] && printf '%s' "$out" | grep -q REFUSED; then
  n="$(count_objects)"                      # must still be empty: nothing uploaded
  if [ "$n" = 0 ]; then ok "public bucket refused, nothing uploaded (exit 4)"
  else bad "public bucket refused but $n objects present"; fi
else
  bad "expected refusal (exit 4) on public bucket, got rc=$rc: $out"
fi
"${AWSM[@]}" s3api delete-bucket-policy --bucket "$BUCKET" >/dev/null 2>&1   # back to private

# --- Test 2: initial upload mirrors every file ----------------------------
rep="$WORK/rep.json"
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" --report "$rep" >/dev/null 2>&1; rc=$?
want=6   # files in build_tree
got="$(count_objects)"
up="$(grep -o '"uploaded": [0-9]*' "$rep" | grep -o '[0-9]*')"
{ [ $rc -eq 0 ] && [ "$got" = "$want" ] && [ "$up" = "$want" ]; } \
  && ok "initial upload put $want objects (report uploaded=$up)" \
  || bad "initial upload: rc=$rc objects=$got report_uploaded=$up (want $want)"

# --- Test 3: re-run with no changes uploads nothing -----------------------
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" --report "$rep" >/dev/null 2>&1
up="$(grep -o '"uploaded": [0-9]*' "$rep" | grep -o '[0-9]*')"
del="$(grep -o '"deleted": [0-9]*' "$rep" | grep -o '[0-9]*')"
{ [ "$up" = 0 ] && [ "$del" = 0 ]; } \
  && ok "no-change run is a no-op (uploaded=0 deleted=0)" \
  || bad "no-change run reported uploaded=$up deleted=$del"

# --- Test 4: a changed file and a new file both upload --------------------
printf 'a fact, revised\n'  > "$WORK/src/machines/$HOST/memories/sites-personal/fact.md"
printf 'brand new memory\n' > "$WORK/src/machines/$HOST/memories/sites-personal/new.md"
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" --report "$rep" >/dev/null 2>&1
up="$(grep -o '"uploaded": [0-9]*' "$rep" | grep -o '[0-9]*')"
[ "$up" = 2 ] \
  && ok "changed+added files upload (uploaded=2)" \
  || bad "expected uploaded=2 after change+add, got $up"

# --- Test 5: a locally-deleted file is deleted from the bucket ------------
rm "$WORK/src/machines/$HOST/memories/sites-personal/new.md"
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" --report "$rep" >/dev/null 2>&1
del="$(grep -o '"deleted": [0-9]*' "$rep" | grep -o '[0-9]*')"
gone=1; "${AWSM[@]}" s3api head-object --bucket "$BUCKET" \
  --key "machines/$HOST/memories/sites-personal/new.md" >/dev/null 2>&1 && gone=0
{ [ "$del" = 1 ] && [ "$gone" = 1 ]; } \
  && ok "local deletion propagates (deleted=1, object gone)" \
  || bad "delete-propagation: report deleted=$del object_gone=$gone"

# --- Test 6: round-trip (restore) reproduces the tree byte-for-byte --------
mkdir -p "$WORK/restore"
"${AWSM[@]}" s3 sync "s3://${BUCKET}/" "$WORK/restore" --quiet >/dev/null 2>&1
if diff -r "$WORK/src" "$WORK/restore" >/dev/null 2>&1; then
  ok "round-trip download matches source exactly"
else
  bad "round-trip mismatch:$(diff -rq "$WORK/src" "$WORK/restore" 2>&1 | head -5)"
fi

# --- Test 7: --dry-run reports the change but does not apply it ------------
printf 'changed again, dry\n' > "$WORK/src/machines/$HOST/memories/sites-personal/fact.md"
before="$("${AWSM[@]}" s3api head-object --bucket "$BUCKET" \
          --key "machines/$HOST/memories/sites-personal/fact.md" --query ETag --output text 2>/dev/null)"
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" --dry-run --report "$rep" >/dev/null 2>&1
after="$("${AWSM[@]}" s3api head-object --bucket "$BUCKET" \
          --key "machines/$HOST/memories/sites-personal/fact.md" --query ETag --output text 2>/dev/null)"
up="$(grep -o '"uploaded": [0-9]*' "$rep" | grep -o '[0-9]*')"
dry="$(grep -o '"dryRun": [a-z]*' "$rep" | grep -o '[a-z]*$')"
{ [ "$up" = 1 ] && [ "$dry" = true ] && [ "$before" = "$after" ]; } \
  && ok "dry-run plans the change (uploaded=1) but object is untouched" \
  || bad "dry-run: uploaded=$up dryRun=$dry etag_changed=$([ "$before" = "$after" ] && echo no || echo yes)"

# --- Test 8: fail-closed when the endpoint is unreachable ------------------
out="$("$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "http://127.0.0.1:1" --prefix "" 2>&1)"; rc=$?
{ [ $rc -eq 3 ]; } \
  && ok "unreachable endpoint fails closed (exit 3, no upload)" \
  || bad "expected exit 3 on dead endpoint, got rc=$rc: $out"

# --- Test 9: --allow-public warns and proceeds on a public bucket ----------
# Same public policy as Test 1, but the explicit override turns refusal into a
# warning. The interactive layer passes this only after the user consents;
# headless never does.
"${AWSM[@]}" s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$WORK/public.json" >/dev/null 2>&1
out="$("$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" \
        --allow-public --report "$rep" 2>&1)"; rc=$?
ap="$(grep -o '"allowPublic": [a-z]*' "$rep" 2>/dev/null | grep -o '[a-z]*$')"
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q WARNING && [ "$ap" = true ]; } \
  && ok "--allow-public warns and proceeds on a public bucket (exit 0)" \
  || bad "--allow-public: rc=$rc warned=$(printf '%s' "$out" | grep -qc WARNING) allowPublic=$ap"
"${AWSM[@]}" s3api delete-bucket-policy --bucket "$BUCKET" >/dev/null 2>&1   # back to private

# --- Test 10: obstore-pull materializes a restore source root --------------
# The whole object-storage-specific part of restore: pull the bucket to a dir,
# then it is byte-for-byte the tree that restore treats like an extracted zip.
mkdir -p "$WORK/pull"
"$PULL" --dest "$WORK/pull" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" >/dev/null 2>&1; rc=$?
if [ $rc -eq 0 ] && [ -d "$WORK/pull/machines/$HOST" ] \
   && diff -r "$WORK/src/machines/$HOST" "$WORK/pull/machines/$HOST" >/dev/null 2>&1; then
  ok "obstore-pull reproduces the mirror as a restore source root"
else
  bad "obstore-pull: rc=$rc diff=$(diff -rq "$WORK/src/machines/$HOST" "$WORK/pull/machines/$HOST" 2>&1 | head -3)"
fi

# --- Test 11: obstore-pull fails closed on an empty prefix -----------------
# An empty pull must not masquerade as a valid (empty) source root.
out="$("$PULL" --dest "$WORK/pull2" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "nonexistent" 2>&1)"; rc=$?
{ [ $rc -eq 3 ]; } \
  && ok "obstore-pull fails closed when there is nothing to pull (exit 3)" \
  || bad "expected exit 3 on empty prefix, got rc=$rc: $out"

# --- Test 12: setup creates, enables versioning, and certifies private -----
NEWB="${BUCKET}-setup"
"$SETUP" --bucket "$NEWB" --create --endpoint "$ENDPOINT" --report "$rep" >/dev/null 2>&1; rc=$?
priv="$(grep -o '"private": [a-z]*' "$rep" 2>/dev/null | grep -o '[a-z]*$')"
ver="$(grep -o '"versioning": "[a-z]*"' "$rep" 2>/dev/null | grep -o '[a-z]*"$' | tr -d '"')"
live_ver="$("${AWSM[@]}" s3api get-bucket-versioning --bucket "$NEWB" --query Status --output text 2>/dev/null)"
{ [ $rc -eq 0 ] && [ "$priv" = true ] && [ "$ver" = enabled ] && [ "$live_ver" = Enabled ]; } \
  && ok "setup --create makes a private, versioned bucket (exit 0)" \
  || bad "setup --create: rc=$rc private=$priv versioning=$ver live=$live_ver"

# --- Test 13: setup refuses to certify a public bucket ---------------------
# A policy targeting $NEWB (public.json names $BUCKET, so rebuild for $NEWB).
cat > "$WORK/pub-new.json" <<POLICY
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*",
"Action":["s3:GetObject","s3:ListBucket"],
"Resource":["arn:aws:s3:::${NEWB}","arn:aws:s3:::${NEWB}/*"]}]}
POLICY
"${AWSM[@]}" s3api put-bucket-policy --bucket "$NEWB" --policy "file://$WORK/pub-new.json" >/dev/null 2>&1
out="$("$SETUP" --bucket "$NEWB" --endpoint "$ENDPOINT" 2>&1)"; rc=$?
{ [ $rc -eq 4 ] && printf '%s' "$out" | grep -q REFUSED; } \
  && ok "setup refuses to certify a public bucket (exit 4)" \
  || bad "expected exit 4 REFUSED on public bucket, got rc=$rc: $out"

# --- Test 14: public -> refuse -> make private -> succeed (the fix lifecycle)
# Mirrors the interactive "fix it" path: a bucket that starts public is refused
# by both setup and sync; after it is made private, both proceed.
LB="${BUCKET}-life"
"${AWSM[@]}" s3 mb "s3://$LB" >/dev/null 2>&1
cat > "$WORK/pub-life.json" <<POLICY
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*",
"Action":["s3:GetObject","s3:ListBucket"],
"Resource":["arn:aws:s3:::${LB}","arn:aws:s3:::${LB}/*"]}]}
POLICY
"${AWSM[@]}" s3api put-bucket-policy --bucket "$LB" --policy "file://$WORK/pub-life.json" >/dev/null 2>&1
"$SETUP" --bucket "$LB" --endpoint "$ENDPOINT" >/dev/null 2>&1; s_rc=$?
"$SYNC" --source "$WORK/src" --bucket "$LB" --endpoint "$ENDPOINT" --prefix "" >/dev/null 2>&1; y_rc=$?
n_public="$("${AWSM[@]}" s3api list-objects-v2 --bucket "$LB" --query 'length(Contents || `[]`)' --output text 2>/dev/null)"
# The fix: make it private.
"${AWSM[@]}" s3api delete-bucket-policy --bucket "$LB" >/dev/null 2>&1
"$SETUP" --bucket "$LB" --endpoint "$ENDPOINT" >/dev/null 2>&1; s_rc2=$?
"$SYNC" --source "$WORK/src" --bucket "$LB" --endpoint "$ENDPOINT" --prefix "" >/dev/null 2>&1; y_rc2=$?
n_private="$("${AWSM[@]}" s3api list-objects-v2 --bucket "$LB" --query 'length(Contents || `[]`)' --output text 2>/dev/null)"
{ [ "$s_rc" = 4 ] && [ "$y_rc" = 4 ] && [ "$n_public" = 0 ] \
  && [ "$s_rc2" = 0 ] && [ "$y_rc2" = 0 ] && [ "$n_private" -gt 0 ]; } \
  && ok "public->refuse (nothing up) -> made private -> setup+sync succeed" \
  || bad "lifecycle: public(setup=$s_rc sync=$y_rc objs=$n_public) private(setup=$s_rc2 sync=$y_rc2 objs=$n_private)"

# --- Test 15: pull with no --host brings down every machine (merge's need) --
# merge reads across all machines' subtrees, so a full pull must materialize
# them all, not just this host's.
mkdir -p "$WORK/src/machines/otherhost/memories/sites-work"
printf 'a memory from the other laptop\n' > "$WORK/src/machines/otherhost/memories/sites-work/note.md"
"$SYNC" --source "$WORK/src" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" >/dev/null 2>&1
rm -rf "$WORK/pullall"; mkdir -p "$WORK/pullall"
"$PULL" --dest "$WORK/pullall" --bucket "$BUCKET" --endpoint "$ENDPOINT" --prefix "" >/dev/null 2>&1
{ [ -d "$WORK/pullall/machines/$HOST" ] && [ -d "$WORK/pullall/machines/otherhost" ]; } \
  && ok "full pull materializes every machine's subtree (merge source)" \
  || bad "full pull missing a host: $(ls "$WORK/pullall/machines" 2>&1)"

echo
printf '==> %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
