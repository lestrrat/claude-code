# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo

Claude Code configuration dotfiles. No application code — nothing to build, test, or lint.

`setup.sh` symlinks repo contents into `~/.claude/`. Edits here take effect immediately.

## Structure

| Path | Purpose |
|------|---------|
| `CLAUDE.md.global` | Global instructions → symlinked as `~/.claude/CLAUDE.md` (name changes) |
| `docs/` | Reference docs loaded on-demand per pre-read rules table in `CLAUDE.md.global` |
| `skills/` | User-invocable skills with YAML front matter (`name`, `description`) + steps |
| `settings.json` | Bash command permission allowlists, format: `Bash(<prefix>:*)` |
| `setup.sh` | Symlink installer. All items keep original name except `CLAUDE.md.global` → `CLAUDE.md` |

## Editing Rules

- `CLAUDE.md.global` loads into every conversation context. Keep terse, token-efficient. Detail belongs in `docs/` via pre-read rules table.
- New auto-approved commands → add `Bash(<command-prefix>:*)` entry to `settings.json`.
