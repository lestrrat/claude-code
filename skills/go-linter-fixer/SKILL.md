---
name: go-linter-fixer
description: Run golangci-lint on Go code and fix any issues found. Use after writing or modifying Go code, or when the user explicitly requests linting.
---

Run `golangci-lint run` on the target path (default `./...`). Respect existing `.golangci.yml`.

## Fix order (safest first)

1. Formatting/style — unused imports/variables, comments, gofmt
2. Error handling — unchecked errors, wrapping with `%w`
3. Code quality — unnecessary conversions, dead code

Rules:
- Minimal, targeted changes. Preserve original logic.
- NEVER commit or run git commands.
- Do NOT auto-fix if it might change behavior or involves security/architecture. Report those and ask user.

## Verify

Re-run `golangci-lint run` after fixes. If new issues appear from your changes, fix them.

## Report

```
Linting: X found, Y fixed, Z need manual review
Files modified: [list]
Remaining: [unfixed issues with recommendations]
```
