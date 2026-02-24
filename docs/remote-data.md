# Remote Data Handling

## Core Rule

When running any command that fetches data from a remote source, ALWAYS write the output to a local file first, then process the file — NEVER pipe remote output directly into processing commands.

This applies to (but is not limited to):
- `gh` (GitHub CLI — API calls, PR views, issue lists, release assets, etc.)
- `curl` / `wget`
- `gcloud`, `aws`, `az` (cloud CLI tools)
- `docker` (pulling logs, inspect output, etc.)
- `kubectl` / `helm` (cluster queries)
- `ssh` remote commands
- `git log`, `git diff` against remote refs that trigger fetches
- Any other CLI that hits a network endpoint and produces output

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
