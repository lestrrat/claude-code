---
name: review-gauntlet
description: Self-looping adversarial-review-to-merge pipeline. Codex runs an adversarial review (a given area/topic, else the whole repo), findings are neutrally verified, each survivor becomes its own PR, and a per-PR review gauntlet (two independent SATISFIED verdicts on the same commit, reviewed one at a time over the whole diff) plus event-driven CI monitoring gate an auto-merge. Drives its own loop via ScheduleWakeup — invoke once, no /loop wrapper. Args: [area or topic]
---

# Review Gauntlet

A self-looping, reactive pipeline. **Codex is the adversarial reviewer; you (Claude Code) are the
orchestrator and implementer.** Fixes fan out in parallel, but you own every gate — the codex review
gauntlet, CI watching, and merges run centrally so verdicts and merge ordering stay coherent.

Act on each result the moment it lands. NEVER block on a whole batch.

## Args

`/review-gauntlet [area or topic]`

- With an argument → codex reviews that area/topic.
- Without one → codex does a **whole-repo** adversarial sweep. This is the intended default.

**Do NOT ask the user to confirm the scope.** A no-arg invocation means whole-repo on purpose —
proceed immediately, no "are you sure you want the whole repo?" prompt, no pre-fan-out checkpoint.
The only thing that narrows scope is an explicit argument.

Invoke it **once**. The skill drives its own loop (see "Loop control") — you do NOT wrap it in `/loop`.

**Fresh-run signal.** An explicit `--new` flag (or a phrase like "fresh run" / "start over") forces a
brand-new run even when a prior run's state is still around — see "Loop control" step 1 for exactly
when it applies and how a finished prior run is handled. The arg, if any, is still the scope:
`/review-gauntlet --new auth` is a fresh whole-area run on `auth`.

## Authorization note

Invoking this skill is the user's explicit, per-invocation authorization for the git operations it
performs **on the branches/PRs it creates** (`add`, `commit`, `push`, `gh pr merge`) and for the
worktrees it sets up. It does NOT touch unrelated branches, and worktree removal still goes through
the merged-branch check (Stage 3). This scoped authorization does not relax the standing per-instance
git confirmation rule anywhere else.

## Constraints

**Public API changes require user confirmation — on by default.** A fix may not modify the project's
public API *surface or its observable behavior* without the user's say-so:

- *Surface* — exported functions, types, and methods and their signatures; public constants/enums;
  serialized formats and wire/HTTP contracts; CLI flags; config keys.
- *Behavior* — the observable contract of the above (return/error semantics, defaults, output shape)
  even when the signature is unchanged.

Internal-only changes that leave both identical need no confirmation.

Handling depends on the run's `api_changes` flag, stored in the ledger header:

- **`ask` (default)** — when a fix would cross the line, do NOT make the change. Park that finding
  (status `awaiting-api`), show the user the proposed change and what it would break, and ask whether
  to proceed. Keep working the other findings meanwhile. Apply it only on approval; if the user
  declines, set it aside as skipped and report it.
- **`allowed`** — proceed without asking. Set this *only* when the user, at invocation, explicitly
  said API breakage is acceptable (e.g. "allow API changes" / "ignore breakage").

**Store the flag in the ledger and re-consult it every wake.** Derive `api_changes: ask|allowed` once
from the invocation and record it in the ledger header. A run is long, so NEVER trust in-context
memory for this — re-read the flag from the ledger before any API-affecting change, so the behavior
can't drift mid-run. A blanket "yes, stop asking" from the user flips the header to `allowed`; a
one-off "yes" approves only that finding and leaves the flag at `ask`.

Backstop: when you scan a PR you built, flag any public-API change in its diff. Under `ask`, an
unapproved API change must not merge — revert it or get approval first (grounds for `NOT SATISFIED`).

## File locations

Everything under `.tmp/review-gauntlet/` (create at start of a fresh run; on resume, reuse it):

| File | Contents |
|------|----------|
| `findings-raw.md` | Codex's raw adversarial findings |
| `verdicts.md` | Neutral verification verdicts (which findings survive) |
| `state.md` | Live per-finding ledger — a **cache/hint**, not the source of truth (see below) |
| `review-<pr>-<n>.txt` | Codex's PR review output, round `n` |
| `ci-<pr>.txt` | Latest `gh pr checks` snapshot for a PR (re-polled after the watch, not the watch stream) |
| `abort-<id>.md` | Detailed log for an aborted finding-task |

Store ALL codex and `gh` output to `.tmp/` first, then Read/Grep it. NEVER `/tmp/`.

**Durable cross-run knowledge lives outside `.tmp/`.** `.tmp/` may be wiped between runs, so the
one thing a *new* run needs to remember from old ones — the carryover ledger — is kept at the repo
root in `.review-gauntlet/history.md` (git-ignored; add the entry to `.gitignore` if missing). It
survives `.tmp` cleanup. Everything else stays ephemeral under `.tmp/review-gauntlet/`. See
"Fresh runs and carryover".

### The ledger — `state.md`

One row per surviving finding. It is a **cache**, not the authoritative state — **ground truth is
git + GitHub** (`gh pr list/view` for PRs and merged/open state, `git rev-parse HEAD` per branch for
the live SHA, `gh pr checks` for live CI, and the `review-<pr>-<n>.txt` files for which verdicts
exist on which SHA). Every wake re-derives what's due from those, then refreshes this file. So a
stale or half-written ledger is self-healing — never act on it without reconciling against git/gh
first.

The file opens with a one-line run config (re-read every wake — see Constraints), then one row per
finding:

```
api_changes: ask        # ask | allowed (run-wide; set once from the invocation)

id | slug | branch | worktree | pr | head_sha | reviews_ok | ci | attempts | started | status
```

- `head_sha` — the branch tip (`git rev-parse HEAD`) that `reviews_ok` and `ci` describe. Both are
  pinned to this SHA; if the live tip differs, they are stale (treat as 0 / `pending`).
- `reviews_ok` — number of independent SATISFIED verdicts recorded against `head_sha` (need 2).
- `ci` — `green` / `red` / `pending` / `none` for `head_sha`.
- `attempts` — task attempts so far (for the retry-once bailout).
- `started` — wall-clock start of the current attempt (for the 1-hour cap).
- `status` — `pending` → `in_review` → `mergeable` → `merged`, or `aborted`; plus `awaiting-api`
  while parked for the user to approve an API-changing fix.

---

## Loop control

The skill is **event-driven**. Wakes come from three sources, all handled identically: the first
invocation, a `ScheduleWakeup` firing (heartbeat fallback), and a **background task completing** — a
CI watch *or* a review. Reviews and CI both run as background tasks, so nothing blocks; each
completion is its own wake.

**Every wake — reconcile, dispatch, reschedule:**

1. **Init, resume, or start fresh.** Decide on **liveness**, not on whether `state.md` exists. Live
   work = any open skill-created `fix-*` PR/branch **OR** any non-terminal ledger row (`pending` /
   `in_review` / `mergeable` / `awaiting-api`). Three cases:

   - **Live work exists → resume.** **Reconcile against ground truth** (do NOT redo Stage 0/1): for
     each branch/PR read the live SHA, CI status, and verdict files, and refresh the ledger. Also
     re-read the `api_changes` flag from the ledger header — it governs API-change handling and must
     be consulted fresh each wake, never from memory (Constraints). This is also the path every
     `ScheduleWakeup` / background-completion wake takes.
   - **No state at all (no `state.md`, no `fix-*` branch/PR) → first run.** Do Stage 0 then Stage 1.
   - **`state.md` exists but is fully terminal — every row `merged`/`aborted`, no open `fix-*` PR →
     the previous run is finished.** Do **not** silently exit "all fixed" (the old bug) and do **not**
     silently restart. **Ask the user** whether to start a new run — e.g. "The previous
     review-gauntlet run finished (N merged, M aborted). Start a new run?" On yes, start a fresh run
     **with carryover** (see "Fresh runs and carryover"). On no, emit the prior run's final report and
     stop. This prompt is the *only* wake that asks the user about scope.

   **The `--new` fresh-run signal short-circuits the above:** if the user invoked with `--new` (or
   "fresh run" / "start over"), start a fresh run with carryover immediately, regardless of liveness —
   no prompt. Live work, if any, is handled per "Fresh runs and carryover" (open PRs are left intact;
   the new run is a new sweep, and live state is archived into the carryover ledger first).

   **Reconcile labels too** (idempotent, and retroactive). Ensure the labels exist
   (`gh label create … --force`, as in Stage 1), then for every gauntlet PR — those in the ledger or
   on a `fix-*` branch — set its label to match its **live** gate state: `gauntlet-accepted` if its
   current HEAD holds two SATISFIED verdicts, else `gauntlet-reviewing`; add the label if it has
   none. This is what labels PRs that a review-gauntlet run opened **before** labeling existed —
   they simply get the right label on the next wake.
2. **Fold in completions.** For any background task that finished (CI watch → `ci-<pr>.txt`; review →
   `review-<pr>-<n>.txt`), record the result against the SHA it ran on and act per Stage 2.
3. **Dispatch due work — non-blocking, idempotent, bounded.** For every PR, launch only what is
   actually due *and not already in flight* (check ground truth first, never the ledger alone):
   - current tip has < 2 SATISFIED verdicts and no review running for that SHA → launch **one**
     review pass as a **background** task (one at a time per PR — the second only after the first is
     SATISFIED; Stage 2a);
   - CI red and no fix in flight → dispatch a scoped fix subagent (Stage 2b);
   - mergeable → queue for merge.
   Cap concurrent review processes at ~8; queue the rest. **Launch, do not wait.**
4. **Merge** at most one queued PR this wake, serialized, after re-confirming its gate against the
   live SHA (Stage 3).
5. **Reschedule or exit.**
   - Any non-terminal PR remains → set a `ScheduleWakeup` heartbeat (`prompt: "/review-gauntlet
     <args>"`, delay ~3–4 min, cache-warm) as a fallback; background completions will usually wake
     you sooner. Return.
   - All PRs `merged` or `aborted` → **distill the run into the carryover ledger** (append a run
     block to `.review-gauntlet/history.md` — merged fixes, aborted findings + why, declined-API
     findings, and the REFUTED/UNCERTAIN sets; see "Fresh runs and carryover"), emit the final report,
     and **do not reschedule**. The loop ends. **Leave `.tmp/review-gauntlet/` in place** (do NOT
     archive it here) — the terminal `state.md` is what lets the next manual invocation detect a
     *finished* run and take the "ask the user" branch in step 1 instead of the old silent exit. (If a
     stale heartbeat fires after exit, it harmlessly re-hits the finished-run branch rather than a
     blank "first run".) Archiving of the old `.tmp` happens only when a fresh run actually starts.

**Idempotency is the load-bearing property.** Because every wake re-derives from git/gh and launches
only work not already in flight, a relaunch after a killed session — or two completions landing close
together — cannot corrupt state or act on a stale verdict (SHA-pinning rejects stale verdicts at the
gate). The worst case is a wasted duplicate review, which is harmless: it's an independent re-roll
anyway. The agent is also single-threaded per turn, so wake *decisions* never truly race — only
in-flight tasks do.

**Resume after a killed session:** in-flight background tasks die with the session, but nothing
authoritative is lost. A new `/review-gauntlet <args>` invocation (without `--new`) sees the live
work, reconciles against git/gh, relaunches whatever is due, and continues — no Stage 0/1 once
PRs/branches already exist. (Resume vs. fresh run is decided in Loop control step 1.)

---

## Fresh runs and carryover

A **fresh run** is a new Stage 0/1 cycle started when a prior run already happened — triggered either
by the user answering "yes" to the finished-run prompt (Loop control step 1) or by an explicit
`--new`. It is *not* a resume: it does a brand-new codex sweep. What makes it more than a blind
re-run is **carryover** — it inherits what earlier runs already learned.

### The carryover ledger — `.review-gauntlet/history.md`

A durable, git-ignored, append-only log at the repo root (NOT under `.tmp/`, which can be wiped).
Each finished run appends one block; a fresh run reads the **whole file** so knowledge compounds
across many runs. A block records:

- **merged** — finding slug + one-line fix, per PR that shipped.
- **aborted** — finding slug + why it couldn't clear the bar (pointer to its `abort-<id>.md` if still
  present).
- **declined-api** — findings parked under `ask` that the user declined, with the change they'd have
  needed.
- **refuted** — findings the verification pass rejected as non-issues, with a one-line reason.
- **uncertain** — findings left for the user to triage.

If the file or `.review-gauntlet/` dir doesn't exist, create it (and add `.review-gauntlet/` to the
repo's `.gitignore` if it's not already ignored). "carry over knowledge from previous runs, **if
any**" — when there's no history file, a fresh run is just a normal first run.

### Pruning the ledger

The ledger grows append-only during runs, so **prune it regularly** — at the start of every fresh
run (right before feeding carryover into Stage 0), and any time the user asks. The goal is to drop
entries that **no longer apply to the current code**, so stale context can't mislead the new sweep.
Check each entry against current `main`:

- **refuted / aborted / uncertain** whose cited `file:line` no longer exists, or whose code has
  materially changed since — the finding as recorded can't still hold. A changed refuted/aborted site
  should be *re-judged fresh* by the new sweep, not carried as a settled verdict, so drop the stale
  entry.
- **declined-api** whose referenced surface no longer exists, or that has since shipped — moot.
- **merged** entries are historical record and cheap; keep them unless the user wants them condensed.

**Confirm before deleting when unsure — this is the load-bearing rule.** Delete outright *only*
entries that are unambiguously moot: the exact cited site is gone and there's nothing to re-judge.
For anything you're not certain about — the site moved but the concern might still stand, an aborted
finding you can't confirm was resolved, a declined-api you're unsure shipped — **do NOT delete it.
List those candidates with why each looks stale and ask the user** which to remove. Never silently
drop an entry you're uncertain about; a wrongly-pruned `refuted` re-opens a settled non-issue, and a
wrongly-pruned `aborted` loses a real unfinished thread.

Note what was pruned (and what the user kept) so the decision is auditable on the next run.

A run is distilled into the ledger **exactly once**, at whichever of these happens to it:

- **Normal exit** (all PRs terminal) — Loop control step 5 appends the finished run's block. The
  finished-run "ask the user → yes" path reuses *that* block; it does not re-distill.
- **Pre-empted by `--new` while still live** — the fresh-run start (step 1 below) snapshots the
  not-yet-finished run before abandoning it.

### Starting a fresh run

1. **Distill/snapshot the prior `.tmp` state, then archive it.** If the prior run exited normally its
   block is already in the ledger — skip straight to archiving. If you're pre-empting still-live work
   under `--new`, first append the current `state.md` rows to a history block as-is so nothing is
   lost. Either way, then archive `.tmp/review-gauntlet/` to a sibling `.tmp/review-gauntlet-<run-id>/`
   (a timestamp works as `<run-id>`) so the new run gets a clean `.tmp/review-gauntlet/`. **Leave open
   `fix-*` PRs and their worktrees intact** — a fresh run does not close or merge them; it just stops
   driving them. (If the user wants those abandoned, that's a separate explicit ask.)
2. **Read the full carryover ledger, then prune it** (drop entries no longer applicable to current
   `main`; confirm any uncertain deletions with the user — see "Pruning the ledger"). Feed the pruned
   ledger into Stage 0 (below).
3. Proceed through Stage 0 → Stage 1 → the loop as normal, on a clean `.tmp/review-gauntlet/`.

### How carryover shapes Stage 0

- **Re-surface unresolved items.** Seed the verification pass with the prior **aborted**,
  **declined-api**, and **uncertain** findings as priority candidates: if the new codex sweep
  re-finds them (or they're still live in the code), they survive into the ledger ahead of net-new
  findings rather than being silently forgotten. A declined-api finding stays parked under `ask`
  unless the user has since OK'd it.
- **Suppress known false-positives.** Give the neutral verifier the prior **refuted** set so it
  doesn't re-litigate the same non-issues — a finding matching a prior refutation is dropped unless
  the code at that site has since changed (in which case re-judge it fresh).
- **Dedup already-merged fixes.** Give the verifier the prior **merged** set so it doesn't re-propose
  work already shipped. (Usually moot — the merged fix changed the code — but it catches a sweep that
  re-flags the same site from a different angle.)

Carryover is advisory context for the verifier, never an auto-accept or auto-reject: every finding
still goes through normal CONFIRMED/ADJUSTED/REFUTED/UNCERTAIN judgement.

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

   **On a fresh run, load carryover first** (`.review-gauntlet/history.md`, pruned of stale entries
   per "Pruning the ledger") and pass the prior unresolved items (aborted / declined-api / uncertain)
   to the reviewer as known areas of interest, so a re-find is recognized rather than treated as
   net-new. See "Fresh runs and carryover".

2. **Neutral verification pass.** Audit every finding with the `adversarial-review` Phase 2 scheme —
   `CONFIRMED` / `ADJUSTED` / `REFUTED` / `UNCERTAIN`, biased toward refuting — into
   `.tmp/review-gauntlet/verdicts.md`. On a fresh run, hand the verifier the carryover sets (refuted
   to suppress, merged to dedup, unresolved to prioritize) per "Fresh runs and carryover". Scale by
   finding count:
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

4. Seed `state.md`: write the run-config header (`api_changes: allowed` only if the user explicitly
   OK'd API breakage at invocation, else `ask`), then one row per surviving work item, status
   `pending`.

If zero findings survive, report that and stop (no loop).

---

## Stage 1 — Fan out (one PR per finding)

**Ensure the status labels exist** first (idempotent — `--force` creates or updates, safe on every
resume):

```
gh label create gauntlet-reviewing --color FBCA04 --description "review-gauntlet: under review" --force
gh label create gauntlet-accepted  --color 0E8A16 --description "review-gauntlet: passed two reviews" --force
```

Spawn one subagent per surviving finding (bounded ~8 per parallel block; run waves for more). Each
subagent:

1. `git worktree add $PROJECT/.worktrees/<branch> -b <branch>`, `<branch>` = `fix-<short-slug>`.
2. Implement the fix for **that finding only**, diff tight and scoped. If it would modify the public
   API surface or behavior, follow **Constraints**: under `ask`, park the finding (`awaiting-api`)
   and confirm with the user before changing anything; under `allowed`, proceed.
3. Commit, push, open the PR off `main`, tagged `gauntlet-reviewing`:
   `gh pr create --base main --label gauntlet-reviewing --title ... --body ...` (no "Test plan"
   section).
4. Return: finding id, branch, worktree path, PR number, one-line fix summary.

For each PR: record it in `state.md` (status `in_review`, `started` = now, `attempts` += 1) and
launch its background CI watch. The `--watch` only **blocks** until the run settles; immediately
after, **re-poll a fresh snapshot** into the file — that snapshot, not the watch, is what you read:

```
# run in background. ';' (not '&&') so the re-poll ALWAYS runs, even when --watch exits non-zero on failure
gh pr checks <pr> --watch ; gh pr checks <pr> > .tmp/review-gauntlet/ci-<pr>.txt
```

The fix subagents only produce the fix + PR. They do NOT run reviews, watch CI, or merge — those
are yours.

---

## Stage 2 — Gates (orchestrator-owned, reactive)

### 2a. The review gauntlet

Run reviews **one at a time per PR** — never two at once for the same SHA. When a PR's tip
(`head_sha`) has fewer than two SATISFIED verdicts and no review already running for it, the wake's
dispatch step launches **one** review pass: a **fresh** `codex exec` over the whole `main...HEAD`
diff, no shared context, run as a **background** task (its completion is a wake; the loop folds the
verdict in at step 2). The second, corroborating review is launched only **after** the first comes
back SATISFIED — so a still-broken commit never burns the second review before the first has said
"fix it". (Reviews for *different* PRs still run concurrently, up to the ~8 cap; it's only the two
reviews for the same PR that serialize.) Each pass is a separate process, so the two verdicts stay
independent regardless.

```
codex exec --full-auto -C $PROJECT/.worktrees/<branch> \
  -o .tmp/review-gauntlet/review-<pr>-<n>.txt \
  "Review the changes on this branch vs main (the whole git diff main...HEAD). List any issues with \
   file:line and a concrete fix. End with exactly one line: 'VERDICT: SATISFIED' or \
   'VERDICT: NOT SATISFIED'."   # run in background
```

As each verdict lands, tally it for the SHA it ran on:

- **NOT SATISFIED** → dispatch a scoped fix subagent into that worktree with the issue list; it
  commits + pushes → HEAD advances → the SHA's tally is void. A later wake starts a fresh review on
  the new tip. (Because reviews are sequential, no second review was spent on this broken commit.)
- **SATISFIED** → record it. If it's the **first** for this SHA, the next wake launches the second
  (corroborating) review on the same SHA. If it's the **second** SATISFIED on the same SHA, the
  review gate is met for this HEAD — swap the PR's label:
  `gh pr edit <pr> --remove-label gauntlet-reviewing --add-label gauntlet-accepted`.

Every pass reviews the whole `main...HEAD` diff (not just the last fix-delta), so accumulated fixes
are always judged as one piece.

**Gate is two independent SATISFIED verdicts on the same HEAD SHA.** Record the reviewed SHA
(`git rev-parse HEAD`) with each pass. A verdict counts only while its SHA equals the live tip; the
moment HEAD advances — review fix, CI fix, conflict-resolving rebase, a formatter/bot commit, or a
base merge — every earlier verdict is stale and `reviews_ok` drops to 0. Pinning to the SHA (rather
than trusting yourself to remember to reset) makes the gate verifiable from git and catches commits
you didn't initiate. A `NOT SATISFIED` invalidates the SHA's tally even before a fix lands. The two
satisfied verdicts and green CI must all describe the *same* HEAD SHA.

**Status labels mirror the review gate.** A PR carries `gauntlet-reviewing` until its current HEAD
holds two SATISFIED verdicts, then `gauntlet-accepted`. Because any code change resets the gate, if
an accepted PR's HEAD later advances — a CI fix, rebase, etc. — swap the label back
(`--remove-label gauntlet-accepted --add-label gauntlet-reviewing`). Reconcile labels against the
live gate state each wake so they never lie.

### 2b. CI (event-driven)

Each PR has a background task that waits on `gh pr checks --watch`, then **re-polls** `gh pr checks
<pr>` into `ci-<pr>.txt`. The watch only blocks; the re-polled snapshot is the source of truth. When
the task completes, a wake reads the file and decides `ci` **from the file's contents — never from
the watch exit code**:

- **green** → ONLY if the snapshot shows **zero failing lines AND zero pending lines** and the
  expected checks are actually present. `gh pr checks --watch` can exit 0 while checks are still
  pending or have not yet registered, so a clean exit is not evidence of green.
- **pending** → any line still pending, or the expected checks haven't appeared yet → not green;
  leave `ci = pending` and re-poll on a later wake (relaunch the watch if it already exited).
- **red** → any failing line → diagnose from the check logs, dispatch a scoped CI-fix subagent into
  that worktree. Its fix commits + pushes → code changed → **reset `reviews_ok` to 0**, relaunch the
  watch, re-enter 2a.

Every CI failure must be handled; never merge over a red or pending check, and never infer green from
the watch's exit code alone — always confirm against the re-polled snapshot.

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
- **Skipped** — REFUTED findings, UNCERTAIN ones the user should triage, and any API-changing fix the
  user was asked about and declined (with the change each would have needed).
- Any worktrees left for inspection.

The same outcomes are appended to the durable carryover ledger (`.review-gauntlet/history.md`) on
exit (Loop control step 5), so the next fresh run inherits them.

## Rules

- NEVER pass destructive instructions (delete, force-push, reset) to `codex exec`.
- NEVER use `--dangerously-bypass-approvals-and-sandbox`; always `--full-auto`.
- One finding = one tightly-scoped PR. Do not bundle unrelated fixes.
- Public API surface/behavior changes need user confirmation by default (see Constraints). The
  `api_changes` flag lives in the ledger header and is re-read every wake — never trust memory, never
  auto-merge an unapproved API break.
- Reviews are independent re-rolls: separate `codex exec` each pass, no shared context.
- Verdicts are pinned to the reviewed HEAD SHA: any new commit (incl. rebase / base-merge / bot
  commit) makes prior verdicts stale. Re-derive from `git rev-parse HEAD`, don't trust memory.
- Resume vs. fresh run is decided by **liveness**, not by `state.md` existing: live work → resume
  (no Stage 0/1); a finished prior run → ask the user before a fresh run; `--new` → fresh run with
  carryover (Loop control step 1). A finished run must never silently exit "all fixed" or silently
  restart.
- A fresh run carries over prior knowledge from `.review-gauntlet/history.md` (refuted to suppress,
  unresolved to re-surface, merged to dedup) but still judges every finding fresh — carryover is
  advisory, never auto-accept/reject.
- Prune `.review-gauntlet/history.md` at every fresh run: drop only entries unambiguously moot against
  current `main`; for anything uncertain, list it and ask the user before deleting. Never silently
  prune an entry you're unsure about.
- If codex exec fails or times out, retry once; if it still fails, fall back to reviewing that PR
  yourself with an equally adversarial pass, and note it in the report.
- CI status comes from a re-polled `gh pr checks` snapshot with **zero fail AND zero pending lines** —
  never from the `--watch` exit code (it can exit 0 on pending/unregistered checks). No green, no merge.
- No "Test plan" section in PR bodies.
