#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fetch-review-items.sh [options] <pr-url>

Fetch GitHub Copilot PR review items, normalize them to JSON, then deduplicate
them via dedup_review_items.py.

Options:
  --tmp-dir PATH              Directory for raw gh output. Default: .tmp
  --pr-view-json PATH         Use existing gh pr view JSON instead of fetching
  --review-threads-json PATH  Use existing GraphQL review thread JSON instead of fetching
  --raw-output PATH           Normalized pre-dedup JSON. Default: <tmp-dir>/copilot-review-items.raw.json
  --dedup-output PATH         Deduped JSON. Default: <tmp-dir>/copilot-review-items.json
  --copilot-pattern REGEX     Regex for Copilot author logins
  --help                      Show this message
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

merge_review_thread_page() {
  local aggregate_json="$1"
  local page_json="$2"
  local merged_json="${aggregate_json}.tmp"

  jq -s '
    .[0] as $aggregate
    | .[1] as $page
    | {
        data: {
          repository: {
            pullRequest: {
              reviewThreads: {
                nodes: (
                  ($aggregate.data.repository.pullRequest.reviewThreads.nodes // [])
                  + ($page.data.repository.pullRequest.reviewThreads.nodes // [])
                )
              }
            }
          }
        }
      }
  ' "$aggregate_json" "$page_json" >"$merged_json"

  mv "$merged_json" "$aggregate_json"
}

merge_thread_comment_page() {
  local aggregate_json="$1"
  local page_json="$2"
  local thread_id="$3"
  local merged_json="${aggregate_json}.tmp"

  jq \
    --arg thread_id "$thread_id" \
    --slurpfile page "$page_json" \
    '
      (.data.repository.pullRequest.reviewThreads.nodes) |= map(
        if .id == $thread_id then
          .comments.nodes += ($page[0].data.node.comments.nodes // [])
          | .comments.pageInfo = ($page[0].data.node.comments.pageInfo // .comments.pageInfo)
        else
          .
        end
      )
    ' "$aggregate_json" >"$merged_json"

  mv "$merged_json" "$aggregate_json"
}

fetch_all_review_threads() {
  local output_json="$1"
  local cursor=""
  local has_next="true"
  local page_number=1

  jq -n '
    {
      data: {
        repository: {
          pullRequest: {
            reviewThreads: {
              nodes: []
            }
          }
        }
      }
    }
  ' >"$output_json"

  while [[ "$has_next" == "true" ]]; do
    local page_json="$TMP_DIR/gh-pr-review-threads-page-$page_number.json"

    gh api graphql \
      -F owner="$REPO_OWNER" \
      -F name="$REPO_NAME" \
      -F number="$PR_NUMBER" \
      -F after="$cursor" \
      -f query='
        query($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $after) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  id
                  isResolved
                  isOutdated
                  path
                  line
                  startLine
                  originalLine
                  originalStartLine
                  diffSide
                  startDiffSide
                  comments(first: 100) {
                    pageInfo {
                      hasNextPage
                      endCursor
                    }
                    nodes {
                      id
                      databaseId
                      url
                      body
                      createdAt
                      authorAssociation
                      author {
                        login
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ' >"$page_json"

    merge_review_thread_page "$output_json" "$page_json"

    has_next=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false' "$page_json")
    cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""' "$page_json")
    page_number=$((page_number + 1))
  done
}

fetch_all_thread_comments() {
  local aggregate_json="$1"
  local comment_thread_ids

  comment_thread_ids=$(jq -r '
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.comments.pageInfo.hasNextPage == true)
    | .id
  ' "$aggregate_json")

  if [[ -z "$comment_thread_ids" ]]; then
    return
  fi

  while IFS= read -r thread_id; do
    [[ -n "$thread_id" ]] || continue

    local cursor
    local has_next
    local page_number=2

    cursor=$(jq -r '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | select(.id == $thread_id)
      | .comments.pageInfo.endCursor // ""
    ' --arg thread_id "$thread_id" "$aggregate_json")
    has_next=$(jq -r '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | select(.id == $thread_id)
      | .comments.pageInfo.hasNextPage // false
    ' --arg thread_id "$thread_id" "$aggregate_json")

    while [[ "$has_next" == "true" ]]; do
      local page_json="$TMP_DIR/gh-thread-comments-${thread_id//[^A-Za-z0-9._-]/_}-page-$page_number.json"

      gh api graphql \
        -F threadId="$thread_id" \
        -F after="$cursor" \
        -f query='
          query($threadId: ID!, $after: String) {
            node(id: $threadId) {
              ... on PullRequestReviewThread {
                id
                comments(first: 100, after: $after) {
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                  nodes {
                    id
                    databaseId
                    url
                    body
                    createdAt
                    authorAssociation
                    author {
                      login
                    }
                  }
                }
              }
            }
          }
        ' >"$page_json"

      merge_thread_comment_page "$aggregate_json" "$page_json" "$thread_id"

      has_next=$(jq -r '.data.node.comments.pageInfo.hasNextPage // false' "$page_json")
      cursor=$(jq -r '.data.node.comments.pageInfo.endCursor // ""' "$page_json")
      page_number=$((page_number + 1))
    done
  done <<<"$comment_thread_ids"
}

extract_repo_parts() {
  local pr_url="$1"
  local trimmed="$pr_url"

  trimmed="${trimmed#https://github.com/}"
  trimmed="${trimmed#http://github.com/}"
  trimmed="${trimmed#github.com/}"

  IFS='/' read -r REPO_OWNER REPO_NAME PULL_SEGMENT PR_NUMBER _ <<<"$trimmed"
  if [[ -z "${REPO_OWNER:-}" || -z "${REPO_NAME:-}" || "${PULL_SEGMENT:-}" != "pull" || -z "${PR_NUMBER:-}" ]]; then
    echo "unable to parse GitHub PR URL: $pr_url" >&2
    exit 1
  fi
}

TMP_DIR=".tmp"
PR_VIEW_JSON=""
REVIEW_THREADS_JSON=""
RAW_OUTPUT=""
DEDUP_OUTPUT=""
COPILOT_PATTERN='copilot|github-copilot|copilot-pull-request-reviewer'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmp-dir)
      TMP_DIR="$2"
      shift 2
      ;;
    --pr-view-json)
      PR_VIEW_JSON="$2"
      shift 2
      ;;
    --review-threads-json)
      REVIEW_THREADS_JSON="$2"
      shift 2
      ;;
    --raw-output)
      RAW_OUTPUT="$2"
      shift 2
      ;;
    --dedup-output)
      DEDUP_OUTPUT="$2"
      shift 2
      ;;
    --copilot-pattern)
      COPILOT_PATTERN="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

PR_URL="$1"
mkdir -p "$TMP_DIR"

if [[ -z "$RAW_OUTPUT" ]]; then
  RAW_OUTPUT="$TMP_DIR/copilot-review-items.raw.json"
fi

if [[ -z "$DEDUP_OUTPUT" ]]; then
  DEDUP_OUTPUT="$TMP_DIR/copilot-review-items.json"
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

require_cmd jq
require_cmd python3

if [[ -z "$PR_VIEW_JSON" || -z "$REVIEW_THREADS_JSON" ]]; then
  require_cmd gh
fi

if [[ -z "$PR_VIEW_JSON" ]]; then
  PR_VIEW_JSON="$TMP_DIR/gh-pr-view.json"
  gh pr view "$PR_URL" --json number,title,url,headRefName,baseRefName,files >"$PR_VIEW_JSON"
fi

CANONICAL_PR_URL=$(jq -r '.url' "$PR_VIEW_JSON")
extract_repo_parts "$CANONICAL_PR_URL"

if [[ -z "$REVIEW_THREADS_JSON" ]]; then
  REVIEW_THREADS_JSON="$TMP_DIR/gh-pr-review-threads.json"
  fetch_all_review_threads "$REVIEW_THREADS_JSON"
  fetch_all_thread_comments "$REVIEW_THREADS_JSON"
fi

jq -n \
  --slurpfile pr "$PR_VIEW_JSON" \
  --slurpfile threads "$REVIEW_THREADS_JSON" \
  --arg copilot_pattern "$COPILOT_PATTERN" \
  '
    ($pr[0]) as $prv
    | ($threads[0].data.repository.pullRequest.reviewThreads.nodes // []) as $thread_nodes
    | [
        $thread_nodes[]
        | select(.isResolved | not)
        | . as $thread
        | ($thread.comments.nodes // [])[]
        | select((.author.login // "") | test($copilot_pattern; "i"))
        | {
            pr: {
              url: $prv.url,
              number: $prv.number,
              title: $prv.title,
              head_ref: $prv.headRefName,
              base_ref: $prv.baseRefName
            },
            thread_id: $thread.id,
            comment_id: (.databaseId // .id),
            comment_graphql_id: .id,
            author_login: (.author.login // null),
            author_association: (.authorAssociation // null),
            created_at: (.createdAt // null),
            path: ($thread.path // null),
            line: ($thread.line // null),
            start_line: ($thread.startLine // null),
            original_line: ($thread.originalLine // null),
            original_start_line: ($thread.originalStartLine // null),
            diff_side: ($thread.diffSide // null),
            start_diff_side: ($thread.startDiffSide // null),
            is_resolved: $thread.isResolved,
            is_outdated: ($thread.isOutdated // false),
            body: (.body // ""),
            url: (.url // null)
          }
      ]
  ' >"$RAW_OUTPUT"

python3 "$SCRIPT_DIR/dedup_review_items.py" "$RAW_OUTPUT" "$DEDUP_OUTPUT"

echo "raw_items=$RAW_OUTPUT"
echo "deduped_items=$DEDUP_OUTPUT"
