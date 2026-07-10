## File locations

Everything under the run's own dir `<rundir>` = `.tmp/review-gauntlet/<run-id>/` (create at the start
of a fresh run; on resume, reuse the run's existing dir). Per-run dirs are what keep concurrent runs'
files from colliding — see "Run identity and concurrency".

| File (under `<rundir>`) | Contents |
|------|----------|
| `findings-raw-<shard>.md` | Codex's raw adversarial findings, one file per sweep shard (single-shard runs have one) |
| `verdicts-<chunk>.md` | Neutral verification verdicts per chunk (which findings survive) |
| `state.md` | Live per-finding ledger — a **cache/hint**, not the source of truth (see below) |
| `prs.json` | Batched `gh pr list` snapshot of this run's PRs — the per-wake reconcile input (Loop control) |
| `lease.json` | This run's active-driver lease (`{agent, updated}`; see "Run lease") |
| `review-<pr>-<n>.txt` | Codex's PR review output, round `n` |
| `review-<pr>-<n>.plan.jsonl` | Orchestrator-authored review work units for round `n` |
| `review-<pr>-<n>.progress.jsonl` | Round `n` review events: a mandatory `pass_identity` **first event** (orchestrator-written at dispatch — pr, pass, attempt, reviewed `head_sha`, `plan_id`), then reviewer progress against the plan, plus orchestrator `amendment_resolution` events |
| `ci-<pr>.txt` | Latest `gh pr checks` snapshot for a PR (re-polled after the watch, not the watch stream) |
| `abort-<id>.md` | Detailed log for an aborted finding-task |

Store ALL codex and `gh` output to `.tmp/` first, then Read/Grep it. NEVER `/tmp/`.

All of this is driver bookkeeping, **never repo content — do NOT commit it**: the whole `<rundir>`
(`.tmp/review-gauntlet/**`) and the carryover tree (`.review-gauntlet/**`) stay git-ignored, and a fix
commit stages only the specific source files it changes (explicit paths, never `git add -A`/`.`).

**Durable cross-run knowledge lives outside `.tmp/`.** `.tmp/` may be wiped between runs, so the
one thing a *new* run needs to remember from old ones — the carryover ledger — is kept at the repo
root under `.review-gauntlet/history/` (git-ignored; add `.review-gauntlet/` to `.gitignore` if
missing), **one file per run** (`<run-id>.md`) so concurrent runs never clobber a shared file. It
survives `.tmp` cleanup. Everything else stays ephemeral under the per-run `<rundir>`. See
"Fresh runs and carryover".

### The ledger — `state.md`

One row per surviving finding. It is a **cache**, not the authoritative state — **ground truth is
git + GitHub** (`gh pr list/view` for PRs and merged/open state, `git rev-parse HEAD` per branch for
the live SHA, `gh pr checks` for live CI, and each `review-<pr>-<n>.progress.jsonl`'s `pass_identity`
first event for which SHA a verdict reviewed — the `review-<pr>-<n>.txt` records the verdict, not its
SHA). Every wake re-derives what's due from those, then refreshes this file. So a
stale or half-written ledger is self-healing — never act on it without reconciling against git/gh
first.

The file opens with a short run-config header (`run_id`, `base_branch`, `api_changes`, `phase` —
re-read every wake, see Constraints and "Run identity and concurrency"), then one row per finding:

```
run_id: g260704-0915-a3f29c1b  # this run's identity — namespaces its dir/branches/label/wakes (set once)
base_branch: main       # the branch PRs target & diffs measure against (set once; see "Base branch")
api_changes: ask        # ask | allowed (run-wide; set once from the invocation)
phase: fanout           # reviewing (Stage 0) → fanout (Stage 1+); written at run start before Stage 0

id | slug | branch | worktree | pr | head_sha | reviews_ok | ci | attempts | started | api_approval | status
```

- `head_sha` — the branch tip (`git rev-parse HEAD`) that `reviews_ok` and `ci` describe. `ci` is
  pinned to this exact SHA. `reviews_ok` is pinned to this SHA **unless** the only change is a clean
  base-only rebase/merge with the PR diff unchanged; then carry `reviews_ok` forward to the new
  `head_sha` and set `ci = pending`.
- `reviews_ok` — number of fresh, context-isolated **admissible** SATISFIED verdicts (each passing
  `verdict_admissible` in `stage-2-review-gate.md`; a merely-present SATISFIED that fails any input does
  NOT increment) recorded against this PR's current content (need 2).
- `ci` — `green` / `red` / `pending` / `none` for `head_sha`.
- `attempts` — task attempts so far (for the retry-once bailout).
- `started` — wall-clock start of the current attempt (for the 1-hour cap).
- `api_approval` — durable record of the user's decision on this finding's API-changing fix: `-`
  (not an API change, or not yet decided) | `approved@<iso>` | `declined@<iso>`. Written the moment
  the user answers, so a later wake — or a fresh agent that adopted the run — reads it and never
  re-asks about a finding already decided. It records the decision (an input); `status` stays the
  live position, so the two never contradict: `approved` pairs with the finding back in normal
  fanout, `declined` with a terminal `aborted`. A one-off approval lands here only; it never flips
  the run-wide `api_changes` header.
- `status` — `pending` → `in_review` → `mergeable` → `merged`, or `aborted`; plus `awaiting-api`
  while parked for the user to approve an API-changing fix. That park resolves via `api_approval`:
  `approved` returns the finding to the normal flow, `declined` makes it `aborted` (terminal).

---
