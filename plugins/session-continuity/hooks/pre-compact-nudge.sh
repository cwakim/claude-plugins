#!/bin/bash
# PreCompact nudge: compaction is about to make the conversation lossy, which
# is exactly when a handoff note is most valuable and most often forgotten.
# Emits a systemMessage reminding the user to /handoff first. Always exits 0:
# a nudge must never block compaction.

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
note="$dir/.claude/handoff.md"

if [ -f "$note" ]; then
  mtime=$(stat -f %m "$note" 2>/dev/null || stat -c %Y "$note" 2>/dev/null)
  if [ -n "$mtime" ]; then
    days=$(( ($(date +%s) - mtime) / 86400 ))
    if [ "$days" -eq 0 ]; then
      msg="Context is about to be compacted. .claude/handoff.md was updated today; run /handoff if the state has moved since."
    else
      msg="Context is about to be compacted. .claude/handoff.md is $days day(s) old; consider /handoff to refresh it while the details are still in context."
    fi
  else
    msg="Context is about to be compacted; consider /handoff to refresh .claude/handoff.md while the details are still in context."
  fi
else
  msg="Context is about to be compacted and this project has no handoff note; consider /handoff to save the thread state while it is still in context."
fi

printf '{"systemMessage":"%s"}\n' "$msg"
exit 0
