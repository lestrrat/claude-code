# Remote Data Handling

## Core Rule

ALWAYS write command output to `$PROJECT_DIR/.tmp/` first, then process the file. This applies to ALL commands that produce output you need to inspect or process — not just remote calls. NEVER pipe output directly into processing commands.

Especially important for:
- `gh` (GitHub CLI — API calls, PR views, issue lists, release assets, etc.)
- `curl` / `wget`
- `gcloud`, `aws`, `az` (cloud CLI tools)
- `docker` (pulling logs, inspect output, etc.)
- `kubectl` / `helm` (cluster queries)
- `ssh` remote commands
- `git log`, `git diff` (especially against remote refs)
- Build/test output, linter results, any command producing multi-line output

## Pattern

```bash
# CORRECT — store then process
gh api /repos/owner/repo/issues > $PROJECT_DIR/.tmp/gh-issues.json
# then use Read tool, or grep $PROJECT_DIR/.tmp/gh-issues.json, jq, etc.

curl -sL https://example.com/data.json > $PROJECT_DIR/.tmp/data.json
# then process $PROJECT_DIR/.tmp/data.json

kubectl get pods -o json > $PROJECT_DIR/.tmp/pods.json
# then jq '.items[] | ...' $PROJECT_DIR/.tmp/pods.json
```

```bash
# WRONG — piping remote output directly
gh api /repos/owner/repo/issues | jq '.[].title'
curl -sL https://example.com/data.json | grep foo
kubectl get pods -o json | jq ...
```

## File Naming

Use `$PROJECT_DIR/.tmp/<tool>-<descriptive-slug>.<ext>` for temporary files.

Examples:
- `$PROJECT_DIR/.tmp/gh-pr-123.json`
- `$PROJECT_DIR/.tmp/curl-api-response.json`
- `$PROJECT_DIR/.tmp/kubectl-pods.json`

## Why

- Large remote responses can exceed pipe buffer / tool output limits and get silently truncated.
- A local file can be re-read multiple times without redundant network calls.
- Easier to inspect, debug, and retry processing steps independently.
