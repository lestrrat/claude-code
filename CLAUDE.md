# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo

Claude Code configuration dotfiles. No application code — nothing to build, test, or lint.

`setup.sh [dir]` symlinks repo contents into `dir` (default `~/.claude/`). Edits here take effect immediately.

## Structure

| Path | Purpose |
|------|---------|
| `CLAUDE.md.global` | Global instructions → symlinked as `~/.claude/CLAUDE.md` (name changes) |
| `docs/` | Reference docs loaded on-demand per pre-read rules table in `CLAUDE.md.global` |
| `scripts/` | Reusable shell scripts → symlinked as `~/.claude/scripts/` |
| `skills/` | User-invocable skills with YAML front matter (`name`, `description`) + steps |
| `settings.json` | Permission config: `bypassPermissions` default |
| `setup.sh` | Symlink installer, target dir as optional first arg. All items keep original name except `CLAUDE.md.global` → `CLAUDE.md` |

## Editing Rules

- `CLAUDE.md.global` loads into every conversation context. Keep terse, token-efficient. Detail belongs in `docs/` via pre-read rules table.
- `settings.json` uses `defaultMode: bypassPermissions` — `allow` entries are inert there. Do NOT re-add an allowlist. Safety gates live in skill/doc-level confirmation rules, not the permission system.
