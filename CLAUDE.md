# claude-plugins

A personal Claude Code plugin marketplace. The repo is `cwakim/claude-plugins`;
the marketplace and each plugin live under it.

## Layout

```
.claude-plugin/marketplace.json        # marketplace manifest (lists every plugin)
plugins/<name>/.claude-plugin/plugin.json   # per-plugin manifest
plugins/<name>/commands/*.md           # the plugin's slash commands
plugins/<name>/README.md               # per-plugin docs
README.md                              # root: install + plugin table
```

## Gotchas (read before editing manifests)

- **The marketplace `name` must not contain "claude".** The loader rejects any
  name containing "claude" as impersonating an official marketplace. That is why
  `marketplace.json` is named `cwakim-plugins` even though the repo and install
  path are `cwakim/claude-plugins`. Do not "fix" this mismatch.
- **Bump versions in two places, in sync.** A plugin's version lives in both
  `plugins/<name>/.claude-plugin/plugin.json` and its entry in
  `.claude-plugin/marketplace.json`. They must match.
- **Install/update uses the marketplace suffix:**
  `/plugin install <name>@cwakim-plugins` (a bare `<name>` is ambiguous).

## Adding a plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json` (name, description,
   version, author) and `plugins/<name>/commands/*.md`.
2. Register it in the `plugins` array of `.claude-plugin/marketplace.json`.
3. Add a row to the table in the root `README.md`.

## Workflow

- **PR-based**: branch, open a PR, self-merge. Branches auto-delete on merge.
  Do not commit directly to `main`.
- Never push without asking.
- **Prose**: no em-dashes or en-dashes.
- After merging a plugin change, refresh the dogfooded install with
  `/plugin marketplace update cwakim-plugins` then `/plugin update <name>@cwakim-plugins`.
