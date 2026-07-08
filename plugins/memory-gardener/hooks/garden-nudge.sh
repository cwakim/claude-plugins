#!/bin/bash
# memory-gardener SessionStart nudge.
# Prints at most one line (injected into session context) and ALWAYS exits 0.
# Two modes, in priority order:
#   1. Evidence nudge: a scheduled/manual dry-run left a docket newer than the
#      last real run -> report its item count.
#   2. Heuristic nudge: enough memory files changed since the last real run
#      -> suggest a run. Rate-limited to once per 7 days.
set -u

input=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$cwd" ] && cwd="$PWD"

slug=$(printf '%s' "$cwd" | sed 's/[^a-zA-Z0-9]/-/g')
proj="$HOME/.claude/projects/$slug"
mem="$proj/memory"
state="$proj/garden"

# No memory store, nothing to nudge about.
[ -d "$mem" ] || exit 0
ls "$mem"/*.md >/dev/null 2>&1 || exit 0

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

now=$(date +%s)
last_run=0
[ -f "$state/last-real-run" ] && last_run=$(cat "$state/last-real-run" 2>/dev/null || echo 0)
case "$last_run" in ''|*[!0-9]*) last_run=0 ;; esac

# --- 1. Evidence nudge: pending docket from a dry-run ---
if [ -f "$state/needs-real-run" ] && [ -f "$state/docket.md" ]; then
  if [ "$(mtime "$state/docket.md")" -gt "$last_run" ]; then
    items=$(cat "$state/needs-real-run" 2>/dev/null | tr -cd '0-9')
    [ -z "$items" ] && items="several"
    echo "memory-gardener: the last dry-run audit of this project's memory found $items open docket item(s) (docket: $state/docket.md). Suggest offering the user a real /memory-gardener:garden run."
    exit 0
  fi
fi

# --- 2. Heuristic nudge: memory churn since the last real run ---
last_nudge=0
[ -f "$state/last-nudge" ] && last_nudge=$(cat "$state/last-nudge" 2>/dev/null || echo 0)
case "$last_nudge" in ''|*[!0-9]*) last_nudge=0 ;; esac
[ $((now - last_nudge)) -lt 604800 ] && exit 0   # max one heuristic nudge / 7 days

changed=0
total=0
for f in "$mem"/*.md; do
  [ "$(basename "$f")" = "MEMORY.md" ] && continue   # the index churns on every write
  total=$((total + 1))
  [ "$(mtime "$f")" -gt "$last_run" ] && changed=$((changed + 1))
done

if [ "$last_run" -eq 0 ]; then
  # Never gardened: only worth mentioning once the store has real mass.
  if [ "$total" -ge 10 ]; then
    mkdir -p "$state" && echo "$now" > "$state/last-nudge"
    echo "memory-gardener: this project's memory store ($total memories) has never been gardened. Suggest offering the user /memory-gardener:garden --dry-run."
  fi
  exit 0
fi

days=$(( (now - last_run) / 86400 ))
if { [ "$changed" -ge 5 ] && [ "$days" -ge 14 ]; } || { [ "$changed" -ge 1 ] && [ "$days" -ge 30 ]; }; then
  mkdir -p "$state" && echo "$now" > "$state/last-nudge"
  echo "memory-gardener: $changed of $total memories changed since the last garden run $days days ago. Suggest offering the user /memory-gardener:garden."
fi

exit 0
