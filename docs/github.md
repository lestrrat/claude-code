# GitHub

## Tool

- ALWAYS use the `gh` CLI for GitHub interactions (issues, PRs, releases, checks, etc.).
- NEVER scrape GitHub web pages or construct API URLs manually.

## Caching

- When the same GitHub data (PR details, issue comments, check results, etc.) is needed more than once, fetch it ONCE into a local file, then read from that file for all subsequent operations.
- Store cached data in `$PROJECT_DIR/.tmp/gh-<resource>-<id>.json`.

```bash
gh pr view 123 --json title,body,comments > $PROJECT_DIR/.tmp/gh-pr-123.json
# All subsequent reads use $PROJECT_DIR/.tmp/gh-pr-123.json via the Read tool
```
