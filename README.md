# claude-plugins

A personal marketplace of [Claude Code](https://claude.com/claude-code) plugins by [Charbel Wakim](https://charbelwakim.com), built around one idea: work that outlives the session. Handoffs that survive context loss, memory that stays healthy and backed up, repos that stay clean.

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install <plugin-name>@cwakim-plugins
```

## Plugins

| Plugin | Commands | What it does |
|--------|----------|--------------|
| [session-continuity](plugins/session-continuity) | `/handoff`<br>`/pickup` (+ `list`) | Distills a conversation into a portable, human-readable snapshot: one living note, revised in place, closed with a ground-truth footer (branch, commit, session id). Pickup reads it back, verifies it against reality before acting, and finds threads by name across repos; a PreCompact hook nudges a handoff before context goes lossy. A baton pass, not a context restore. |
| [branch-cleanup](plugins/branch-cleanup) | `/cleanup` | Deletes branches already merged into a base branch, local and remote. Protects long-lived branches, never force-deletes, always confirms. |
| [memory-gardener](plugins/memory-gardener) | `/garden`<br>`/garden schedule` | Audits Claude Code's persistent memory for rot: verifies stale claims against the repo itself, asks only what a human must answer, applies fixes through one confirmed docket. Nudges at session start when the store needs attention; scheduling automates the audit via local cron or launchd. |
| [memory-backup](plugins/memory-backup) | `/backup` (+ `setup`, `status`, `schedule`)<br>`/backup restore`<br>`/backup merge`<br>`/backup zip <path>` | Mirrors every memory store, handoff note, plan, and hand-written global config to a private GitHub repo, one squash-merged PR per run; visibility verified and every file secret-scanned before each push, so credentials never leave the machine. Restore fills what's missing and asks on conflicts; merge converges any number of machines; zip exports a portable dated archive, no GitHub needed. Scheduling optional (cron or launchd), weekly default. |

---

Built and maintained with Claude Code. I write about this kind of thing at [Life in Production](https://lifeinproduction.com).
