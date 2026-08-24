# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo

Claude Code configuration dotfiles. No application code and no build step. A few scripts carry enough logic to be worth testing; those tests live in `tests/` and are run by hand.

`setup.sh [dir]` symlinks repo contents into `dir` (default `~/.claude/`). Edits here take effect immediately.

## Structure

| Path | Purpose |
|------|---------|
| `CLAUDE.md.global` | Global instructions → symlinked as `~/.claude/CLAUDE.md` (name changes) |
| `docs/` | Reference docs loaded on-demand per pre-read rules table in `CLAUDE.md.global` |
| `scripts/` | Reusable shell scripts → symlinked as `~/.claude/scripts/` |
| `skills/` | User-invocable skills with YAML front matter (`name`, `description`) + steps |
| `settings.json` | Permission config (`bypassPermissions` default) + hook registrations |
| `setup.sh` | Symlink installer, target dir as optional first arg. All items keep original name except `CLAUDE.md.global` → `CLAUDE.md`. Also links `githooks/pre-commit` into the repo's git hooks dir |
| `githooks/` | This repo's own git hooks + their helpers. NOT symlinked into `~/.claude/` — repo tooling, not agent tooling |
| `tests/` | Scenario tests for the scripts that have real logic. Run one directly: `tests/git-is-squash-merged.sh`. Pass a path to test another copy, e.g. the installed `~/.claude/scripts/git-is-squash-merged`. NOT symlinked into `~/.claude/` |

## Editing Rules

- `CLAUDE.md.global` loads into every conversation context. Keep terse, token-efficient. Detail belongs in `docs/` via pre-read rules table.
- `settings.json` uses `defaultMode: bypassPermissions` — `allow` entries are inert there. Do NOT re-add an allowlist. Safety gates live in skill/doc-level confirmation rules, not the permission system.
- Hook entries in `settings.json` MUST use the nested form — `"<Event>": [ { "hooks": [ { "type": "command", "command": "…" } ] } ]` — for EVERY event, including matcher-less ones like `UserPromptSubmit`. The flat form the published docs show for matcher-less events (`[ { "type": "command", … } ]`) parses without error and silently never fires. Verified 2026-07-29; re-test with a marker-file probe hook before trusting any doc example.

## Reporting-Rules Reminder

`scripts/hook-reporting-rules` prints `scripts/reporting-rules-condensed.md` on every prompt, countering attention decay: `CLAUDE.md` is in context from turn one, but by turn 30 it sits thousands of tokens back.

- The hook does ONE file read — no extraction, hashing, or comparison. It runs every turn, so per-turn work stays at zero.
- `scripts/reporting-rules-condensed.md` is a hand-written condensed copy. `CLAUDE.md.global`'s `# Reporting` sections marked `(ALL user-facing text)` are authoritative.
- Sync is enforced at commit time by `githooks/pre-commit`, NOT by an instruction to keep the two aligned. The copy carries an `owner-sha256` of the authoritative sections; the hook rejects a commit that changes them without regenerating the copy. Failure message states the resync steps.
- Editing `CLAUDE.md.global`'s tagged sections → rewrite the condensed bullets, then update `owner-sha256`. Marker-based selection means tagging a new section pulls it into the check automatically.
