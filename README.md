# claude-plugins

A small personal marketplace of [Claude Code](https://claude.com/claude-code) plugins, by [Charbel Wakim](https://charbelwakim.com).

## Install

```text
/plugin marketplace add cwakim/claude-plugins
/plugin install <plugin-name>@cwakim-plugins
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| [session-continuity](plugins/session-continuity) | `/handoff` distills a conversation into a portable, human-readable snapshot, revising one living note in place instead of stacking dated entries, and closing with a ground-truth footer (branch, commit, session id). `/pickup` reads it back, verifies it against reality before acting, and finds threads by name across repos; `/pickup list` shows everything in flight. A PreCompact hook nudges a handoff before context goes lossy. A baton pass, not a context restore. |
| [branch-cleanup](plugins/branch-cleanup) | `/cleanup` deletes branches already merged into a base branch, local and remote. Protects long-lived branches, never force-deletes, always confirms. |
| [memory-gardener](plugins/memory-gardener) | `/garden` audits Claude Code's persistent memory for rot. Verifies stale claims against the repo itself, asks only what a human must answer, applies fixes through one confirmed docket. Nudges at session start when the store needs attention; `/garden schedule` automates the audit via local cron. |
| [memory-backup](plugins/memory-backup) | `/backup` mirrors every memory store, handoff note (live and archived), plan document, and the hand-written global config on the machine to a private GitHub repo, one squash-merged PR per run. Privacy verified on every push; every file secret-scanned before commit (interactive runs ask, cron redacts and flags loudly, credentials never leave the machine). `/backup restore` fills empty targets wholesale and asks per conflicting file, from GitHub or from a zip, never deleting local content and never applying an unconfirmed plan (`--dry-run` previews only). `/backup zip <path>` exports the same mirror as a portable dated archive, no GitHub required, asking each run whether to secret-scan first. Cron optional, cadence is your call (weekly default). |

---

Built and maintained with Claude Code. I write about this kind of thing at [Life in Production](https://lifeinproduction.com).
