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
| [session-continuity](plugins/session-continuity) | `/handoff` saves a portable snapshot of a conversation; `/pickup` picks it back up. A baton pass, not a context restore. |
| [branch-cleanup](plugins/branch-cleanup) | `/cleanup` deletes branches already merged into a base branch, local and remote. Protects long-lived branches, never force-deletes, always confirms. |

---

Built and maintained with Claude Code. I write about this kind of thing at [Life in Production](https://lifeinproduction.com).
