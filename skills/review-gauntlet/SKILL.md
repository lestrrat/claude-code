---
name: review-gauntlet
description: Self-looping adversarial-review-to-merge pipeline. Codex runs an adversarial review (a given area/topic, else the whole repo), findings are neutrally verified, each survivor becomes its own PR, and a per-PR review gauntlet (two consecutive independent SATISFIED verdicts, final pass over the whole diff) plus event-driven CI monitoring gate an auto-merge. Drives its own loop via ScheduleWakeup — invoke once, no /loop wrapper. Args: [area or topic]
---

# Review Gauntlet

A self-looping, reactive pipeline. **Codex is the adversarial reviewer; you (Claude Code) are the
orchestrator and implementer.** Fixes fan out in parallel, but you own every gate — the codex review
gauntlet, CI watching, and merges run centrally so verdicts and merge ordering stay coherent.

Act on each result the moment it lands. NEVER block on a whole batch.

## Args

`/review-gauntlet [area or topic]`

- With an argument → codex reviews that area/topic.
- Without one → codex does a **whole-repo** adversarial sweep. No pre-fan-out checkpoint; it proceeds.

Invoke it **once**. The skill drives its own loop (see "Loop control") — you do NOT wrap it in `/loop`.

## Authorization note

Invoking this skill is the user's explicit, per-invocation authorization for the git operations it
performs **on the branches/PRs it creates** (`add`, `commit`, `push`, `gh pr merge`) and for the
worktrees it sets up. It does NOT touch unrelated branches, and worktree removal still goes through
the merged-branch check (Stage 3). This scoped authorization does not relax the standing per-instance
git confirmation rule anywhere else.

## File locations

Everything under `.tmp/review-gauntlet/` (create at start of a fresh run; on resume, reuse it):

| File | Contents |
|------|----------|
| `findings-raw.md` | Codex's raw adversarial findings |
| `verdicts.md` | Neutral verification verdicts (which findings survive) |
| `state.md` | Live per-finding ledger — a **cache/hint**, not the source of truth (see below) |
| `review-<pr>-<n>.txt` | Codex's PR review output, round `n` |
| `ci-<pr>.txt` | Latest `gh pr checks` result for a PR (written by its background watch) |
| `abort-<id>.md` | Detailed log for an aborted finding-task |

Store ALL codex and `gh` output to `.tmp/` first, then Read/Grep it. NEVER `/tmp/`.

### The ledger — `state.md`

One row per surviving finding. It is a **cache**, not the authoritative state — **ground truth is
git + GitHub** (`gh pr list/view` for PRs and merged/open state, `git rev-parse HEAD` per branch for
the live SHA, `gh pr checks` for live CI, and the `review-<pr>-<n>.txt` files for which verdicts
exist on which SHA). Every wake re-derives what's due from those, then refreshes this file. So a
stale or half-written ledger is self-healing — never act on it without reconciling against git/gh
first.

```
id | slug | branch | worktree | pr | head_sha | reviews_ok | ci | attempts | started | status
```

- `head_sha` — the branch tip (`git rev-parse HEAD`) that `reviews_ok` and `ci` describe. Both are
  pinned to this SHA; if the live tip differs, they are stale (treat as 0 / `pending`).
- `reviews_ok` — number of independent SATISFIED verdicts recorded against `head_sha` (need 2).
- `ci` — `green` / `red` / `pending` / `none` for `head_sha`.
- `attempts` — task attempts so far (for the retry-once bailout).
- `started` — wall-clock start of the current attempt (for the 1-hour cap).
- `status` — `pending` → `in_review` → `mergeable` → `merged`, or `aborted`.

---

## Loop control

The skill is **event-driven**. Wakes come from three sources, all handled identically: the first
invocation, a `ScheduleWakeup` firing (heartbeat fallback), and a **background task completing** — a
CI watch *or* a review. Reviews and CI both run as background tasks, so nothing blocks; each
completion is its own wake.

**Every wake — reconcile, dispatch, reschedule:**

1. **Init or resume.** If neither `state.md` nor any skill-created `fix-*` branch/PR exists → first
   run: do Stage 0 then Stage 1. Otherwise **reconcile against ground truth** (do NOT redo Stage
   0/1): for each branch/PR read the live SHA, CI status, and verdict files, and refresh the ledger.
2. **Fold in completions.** For any background task that finished (CI watch → `ci-<pr>.txt`; review →
   `review-<pr>-<n>.txt`), record the result against the SHA it ran on and act per Stage 2.
3. **Dispatch due work — non-blocking, idempotent, bounded.** For every PR, launch only what is
   actually due *and not already in flight* (check ground truth first, never the ledger alone):
   - current tip has < 2 SATISFIED verdicts and no review running for that SHA → launch the two
     review passes as **background** tasks (Stage 2a);
   - CI red and no fix in flight → dispatch a scoped fix subagent (Stage 2b);
   - mergeable → queue for merge.
   Cap concurrent review processes at ~8; queue the rest. **Launch, do not wait.**
4. **Merge** at most one queued PR this wake, serialized, after re-confirming its gate against the
   live SHA (Stage 3).
5. **Reschedule or exit.**
   - Any non-terminal PR remains → set a `ScheduleWakeup` heartbeat (`prompt: "/review-gauntlet
     <args>"`, delay ~3–4 min, cache-warm) as a fallback; background completions will usually wake
     you sooner. Return.
   - All PRs `merged` or `aborted` → emit the final report and **do not reschedule**. The loop ends.

**Idempotency is the load-bearing property.** Because every wake re-derives from git/gh and launches
only work not already in flight, a relaunch after a killed session — or two completions landing close
together — cannot corrupt state or act on a stale verdict (SHA-pinning rejects stale verdicts at the
gate). The worst case is a wasted duplicate review, which is harmless: it's an independent re-roll
anyway. The agent is also single-threaded per turn, so wake *decisions* never truly race — only
in-flight tasks do.

**Resume after a killed session:** in-flight background tasks die with the session, but nothing
authoritative is lost. A fresh `/review-gauntlet <args>` reconciles against git/gh, relaunches
whatever is due, and continues — no Stage 0/1 once PRs/branches already exist.

---

## Stage 0 — Review and verify

1. Run the codex adversarial review. Scope = the arg if given, else the whole repo.

   ```
   codex exec --full-auto -o .tmp/review-gauntlet/findings-raw.md \
     "Perform an adversarial code review of <SCOPE>. For each finding give: a stable ID, \
      severity, file:line, the defect, a concrete reproduction trigger, the impact, and a \
      concrete fix. Be hostile — surface everything that could be wrong. Do not edit code."
   ```

   For a whole-repo sweep, mirror the tiering strategy in the `adversarial-review` skill if the
   surface is large.

2. **Neutral verification pass.** Audit every finding with the `adversarial-review` Phase 2 scheme —
   `CONFIRMED` / `ADJUSTED` / `REFUTED` / `UNCERTAIN`, biased toward refuting — into
   `.tmp/review-gauntlet/verdicts.md`. Scale by finding count:
   - **≤ 10 findings** → one fresh `Explore` subagent audits them all (it sees the whole set, so no
     cross-finding gap).
   - **> 10 findings** → shard into chunks of 5–8 and spawn one `Explore` subagent per chunk in
     parallel, each auditing only its assigned IDs into `verdicts-<chunk>.md`; then concatenate into
     `verdicts.md`.

   Only **CONFIRMED** and **ADJUSTED** survive as work items. Drop REFUTED; list UNCERTAIN in the
   final report for the user to triage.

3. **Reconcile survivors — sharded mode only.** Sharded verifiers are blind across chunks. Before
   building the ledger, read the merged survivors in one pass and dedup / cross-reference them
   yourself: collapse findings that are the same underlying bug into a single work item, and flag
   causally-linked findings to share one PR or be sequenced. This is what prevents two chunks'
   confirmations from spawning colliding PRs on the same code. It's a set-level dedup, NOT a
   re-verification — the shards already judged each finding. (Single-verifier mode already had the
   whole-set view, so skip this there.)

4. Seed `state.md` with one row per surviving work item, status `pending`.

If zero findings survive, report that and stop (no loop).

---

## Stage 1 — Fan out (one PR per finding)

Spawn one subagent per surviving finding (bounded ~8 per parallel block; run waves for more). Each
subagent:

1. `git worktree add $PROJECT/.worktrees/<branch> -b <branch>`, `<branch>` = `fix-<short-slug>`.
2. Implement the fix for **that finding only**. Keep the diff tight and scoped.
3. Commit, push, open the PR off `main`: `gh pr create --base main --title ... --body ...`
   (no "Test plan" section).
4. Return: finding id, branch, worktree path, PR number, one-line fix summary.

For each PR: record it in `state.md` (status `in_review`, `started` = now, `attempts` += 1) and
launch its background CI watch:

```
gh pr checks <pr> --watch > .tmp/review-gauntlet/ci-<pr>.txt   # run in background
```

The fix subagents only produce the fix + PR. They do NOT run reviews, watch CI, or merge — those
are yours.

---

## Stage 2 — Gates (orchestrator-owned, reactive)

### 2a. The review gauntlet

When a PR's tip (`head_sha`) has fewer than two SATISFIED verdicts and no review running for that
SHA, the wake's dispatch step launches **two independent review passes** against it — each a
**fresh** `codex exec` over the whole `main...HEAD` diff, no shared context, run as **background**
tasks (their completion is a wake; the loop folds each verdict in at step 2). Independence is what
makes two clean verdicts mean something; separate concurrent processes maximize it and halve the
gauntlet's latency.

```
codex exec --full-auto -C $PROJECT/.worktrees/<branch> \
  -o .tmp/review-gauntlet/review-<pr>-<n>.txt \
  "Review the changes on this branch vs main (the whole git diff main...HEAD). List any issues with \
   file:line and a concrete fix. End with exactly one line: 'VERDICT: SATISFIED' or \
   'VERDICT: NOT SATISFIED'."   # run in background
```

As verdicts land, tally them for the SHA they ran on:

- **Any NOT SATISFIED** → dispatch a scoped fix subagent into that worktree with that review's issue
  list; it commits + pushes → HEAD advances → all verdicts for the old SHA go stale. A later wake
  relaunches the two passes against the new tip. (No need to wait for the other pass — a single NOT
  SATISFIED already forces a fix; any still-running pass on the old SHA is now moot.)
- **Both SATISFIED on the same `head_sha`** → review gate met for this HEAD.

Every pass reviews the whole `main...HEAD` diff (not just the last fix-delta), so accumulated fixes
are always judged as one piece.

**Gate is two independent SATISFIED verdicts on the same HEAD SHA.** Record the reviewed SHA
(`git rev-parse HEAD`) with each pass. A verdict counts only while its SHA equals the live tip; the
moment HEAD advances — review fix, CI fix, conflict-resolving rebase, a formatter/bot commit, or a
base merge — every earlier verdict is stale and `reviews_ok` drops to 0. Pinning to the SHA (rather
than trusting yourself to remember to reset) makes the gate verifiable from git and catches commits
you didn't initiate. A `NOT SATISFIED` invalidates the SHA's tally even before a fix lands. The two
satisfied verdicts and green CI must all describe the *same* HEAD SHA.

### 2b. CI (event-driven)

Each PR has a background `gh pr checks --watch` writing `ci-<pr>.txt`. When a watch completes, the
result arrives as a wake; read the file and update `ci`:

- **green** → CI gate met for the current HEAD.
- **red** → diagnose from the check logs, dispatch a scoped CI-fix subagent into that worktree. Its
  fix commits + pushes → code changed → **reset `reviews_ok` to 0**, relaunch the watch, re-enter 2a.

Every CI failure must be handled; never merge over a red or pending check.

---

## Stage 3 — Merge (serialized, auto)

A PR is mergeable when the **current** `git rev-parse HEAD` equals `head_sha` AND `reviews_ok == 2`
AND `ci == green` — i.e. two SATISFIED verdicts and green CI all recorded against the live tip.

1. **Serialize** — merge at most one PR per wake. Before merging, re-confirm both gates still hold
   for the current HEAD (a late push may have reset them).
2. Push guard: `gh pr view <branch> --json state --jq .state` must be `OPEN`.
3. Merge: `gh pr merge <pr> --squash --delete-branch` (use the repo's prevailing merge method if not
   squash).
4. After the merge, other open PRs may be stale. **Rebase only if** GitHub flags the PR
   behind/conflicting:
   - Clean rebase (no conflicts) → the PR's own diff is unchanged → keep `reviews_ok`, but `ci` goes
     `pending` and must return green before merging.
   - Rebase requiring conflict resolution → code changed → **reset `reviews_ok` to 0**, re-enter
     Stage 2.
5. **Clean up on successful merge.** Once the merge is confirmed (`gh pr view <branch> --json state
   --jq .state` → `MERGED`), tear down that PR's local footprint:
   - `--delete-branch` above already removed the **remote** branch.
   - Verify the merge with the `git-detect-merged` skill, then use `git-cleanup-merged` to remove the
     **worktree** (`.worktrees/<branch>`) and delete the **local branch**.
   - Set status `merged` and stop its background tasks.

   This runs only after the merge is verified, and only ever touches the skill's own `fix-*`
   worktrees/branches (per the Authorization note). Leave the worktree in place if the merge cannot
   be confirmed — treat that as a bailout condition, not a cleanup.

---

## Bailout

- **1-hour cap per task** (measured from `started`). If a finding's task exceeds one hour without
  merging, abort it cleanly and **retry once** from a fresh worktree (`attempts` += 1, reset
  `started`).
- On the **second** stuck/failure, abort permanently: stop work on that finding, write
  `.tmp/review-gauntlet/abort-<id>.md` with the full history (reviews, CI failures, diffs, what
  blocked it), set status `aborted`, and **continue the other findings**.

Other stop conditions — escalate rather than loop: a worktree won't build, codex keeps returning the
same unactionable verdict, or CI fails identically after a fix attempt.

---

## Final report

When the loop exits, summarize:

- **Merged** — finding id, PR number, one-line fix.
- **Aborted** — finding id, why, pointer to `abort-<id>.md`.
- **Skipped** — REFUTED findings, and UNCERTAIN ones the user should triage.
- Any worktrees left for inspection.

## Rules

- NEVER pass destructive instructions (delete, force-push, reset) to `codex exec`.
- NEVER use `--dangerously-bypass-approvals-and-sandbox`; always `--full-auto`.
- One finding = one tightly-scoped PR. Do not bundle unrelated fixes.
- Reviews are independent re-rolls: separate `codex exec` each pass, no shared context.
- Verdicts are pinned to the reviewed HEAD SHA: any new commit (incl. rebase / base-merge / bot
  commit) makes prior verdicts stale. Re-derive from `git rev-parse HEAD`, don't trust memory.
- Never redo Stage 0/1 when `state.md` already exists — that path is resume-only.
- If codex exec fails or times out, retry once; if it still fails, fall back to reviewing that PR
  yourself with an equally adversarial pass, and note it in the report.
- No "Test plan" section in PR bodies.
