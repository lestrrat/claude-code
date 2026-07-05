---
name: review-gauntlet
description: Self-looping adversarial-review-to-merge pipeline. Codex runs an adversarial review (a given area/topic, else the whole repo), findings are neutrally verified, each survivor becomes its own PR, and a per-PR review gauntlet (two independent SATISFIED verdicts on the same commit, reviewed one at a time over the whole diff) plus event-driven CI monitoring gate an auto-merge. Multiple isolated runs (each keyed by a run-id, with a lease so only one agent drives each) can run concurrently in one repo. Drives its own loop via ScheduleWakeup — invoke once, no /loop wrapper. Args: [--run <id>] [area or topic]
---

# Review Gauntlet

A self-looping, reactive pipeline. **Codex is the adversarial reviewer; you (Claude Code) are the
orchestrator and implementer.** Fixes fan out in parallel, but you own every gate — the codex review
gauntlet, CI watching, and merges run centrally so verdicts and merge ordering stay coherent.

**PR-first invariant.** For every survivor and every follow-up fix: implement → commit → push →
open/update PR → watch CI + review that PR's current HEAD. The gauntlet reviews GitHub PR heads, not
unpublished local work. NEVER hold a fix locally until review passes before opening/updating the PR.

Act on each result the moment it lands. NEVER block on a whole batch.

## Args

`/review-gauntlet [--run <id>] [--new] [area or topic]`

- With an argument → codex reviews that area/topic. A scope arg on a **bare** invocation always starts
  a **new** run (that's how you launch a second concurrent run); it never adopts an existing run.
- Without one → codex does a **whole-repo** adversarial sweep (the intended default); an **arg-less**
  bare invocation is also the resume path — it adopts the sole orphaned run, or asks among several.
- `--run <id>` → bind to a specific existing run (resume it). Threaded automatically through every
  self-wake (with an internal `--token`, agent-managed — users don't pass it). See "Run identity and
  concurrency".

**Do NOT ask the user to confirm the scope.** A no-arg invocation means whole-repo on purpose —
proceed immediately, no "are you sure you want the whole repo?" prompt, no pre-fan-out checkpoint.
The only thing that narrows scope is an explicit argument.

Invoke it **once**. The skill drives its own loop (see "Loop control") — you do NOT wrap it in `/loop`.

**Multiple runs can share a repo.** Every fresh invocation is its own **isolated run** with a private
ledger, tmp dir, branches, and PRs — two runs (e.g. `/review-gauntlet auth` and
`/review-gauntlet storage`) never touch each other's state. `--run <id>` targets a specific existing
run (used to resume it, and threaded automatically through every self-wake); omit it to resume the
sole live run, choose among several, or start a new one. See "Run identity and concurrency".

**Fresh-run signal.** An explicit `--new` flag (or a phrase like "fresh run" / "start over") forces a
brand-new run even when a prior run's state is still around — see "Loop control" step 1 for exactly
when it applies and how a finished prior run is handled. The arg, if any, is still the scope:
`/review-gauntlet --new auth` is a fresh whole-area run on `auth`.

## Base branch

The run targets a **base branch** — the branch every PR merges into and every fix diff is measured
against. It is **not assumed to be `main`**: it defaults to the branch checked out at invocation
(`git rev-parse --abbrev-ref HEAD`; fall back to the repo's default branch if HEAD is detached), which
may be a release or integration branch. Resolve it **once** at the start of a run and record it in the
ledger header as `base_branch`; re-read it from the ledger every wake, never from memory (a run is
long and the checked-out branch can drift).

Throughout this doc, `<base>` means that branch and `origin/<base>` its remote-tracking branch.
Concretely: fix worktrees branch off `<base>`, PRs open with `--base <base>`, every review diffs
`<base>...HEAD`, carryover entries are re-judged against current `<base>`, and after each merge local
`<base>` is fast-forwarded to `origin/<base>`. Where examples below show `main`, read it as `<base>` —
`main` is only the common default.

## Run identity and concurrency

Multiple review-gauntlet runs can execute concurrently in one repo, and a new agent instance can pick
up a run a prior instance left mid-flight — but **never two agents driving the same ledger at once**
(that is the bug this guards against). Two mechanisms: a **run ID** that namespaces everything a run
owns, and a **run lease** that marks whether an agent is actively driving that run right now.

### Run ID — namespacing

Minted once at the start of a fresh run — compact, filesystem- and label-safe. Create the run dir
**atomically** (`mkdir` fails if it already exists) so a run-id collision can't silently share a dir;
retry with a fresh id on the rare clash:

```
run_id="g$(date +%y%m%d-%H%M)-$(openssl rand -hex 4)"   # e.g. g260704-0915-a3f29c1b (32 bits entropy)
mkdir "$PROJECT/.tmp/review-gauntlet/$run_id" || run_id=…   # retry on collision
```

Record it in the ledger header (`run_id:`) and re-read it every wake (like `base_branch`); never trust
in-context memory for it — a wake may be a fresh agent instance. It flows into:

| Owned by the run | Namespaced form |
|------------------|-----------------|
| tmp working dir  | `<rundir>` = `.tmp/review-gauntlet/<run-id>/` (all findings/verdicts/state/review/ci/abort/lease files) |
| ledger header    | `run_id: <run-id>` |
| fix branch       | `fix-<run-id>-<finding-id>-<slug>` (finding-id keeps same-slug findings from colliding) |
| worktree         | `$PROJECT/.worktrees/fix-<run-id>-<finding-id>-<slug>` |
| PR owner label   | `gauntlet-run-<run-id>` (every PR the run opens carries it; authoritative "mine" marker) |
| self-wake prompt | `/review-gauntlet --run <run-id> --token <agent-token> <args>` (carries the id **and** the driver token so a summarized wake re-proves ownership without guessing) |

**Isolation invariant — a run touches ONLY its own work.** It reads/writes only its `<rundir>`, only
its `state.md`, only PRs carrying its `gauntlet-run-<run-id>` label (equivalently on a `fix-<run-id>-`
branch), and only those worktrees/branches. It MUST NOT reconcile, relabel, review, fix, merge, or
clean up another run's PRs/branches — **every git/gh scan is filtered to this run's label or branch
prefix.** The status labels `gauntlet-reviewing` / `gauntlet-accepted` describe gate state and are
shared across runs; ownership is the per-run label, never a status label.

**Shared across runs:** the carryover ledger tree `.review-gauntlet/history/` (kept race-free by one
file per run — see "Fresh runs and carryover"), the two status labels, and the Copilot precondition's
scratch file `.tmp/copilot-review-items.json` (written by `/copilot-address-reviews`) — treat that
last one as ephemeral to a single fetch→address cycle and re-fetch rather than trusting a stale
snapshot another run may have overwritten.

### Run lease — one active driver at a time

Namespacing keeps two *runs* apart; the **lease** keeps two *agents* from driving the **same** run.
Each run has `<rundir>/lease.json`:

```
{ "agent": "<token>", "updated": <unix-ts> }   # token = the agent holding the run; ts = last heartbeat
```

- **Mint** an agent token (`openssl rand -hex 4`) when you first take a run — at fresh-run start or on
  adoption — keep it in context, **and put it in your self-wake prompt** (`--token <tok>`) so a
  summarized/amnesiac wake recovers it from the prompt instead of guessing. **You own the run iff the
  token you present (prompt `--token`, else in-context) equals the lease's `agent`.**
- **Claim atomically.** Taking or adopting a run is a check-and-set that MUST be serialized against
  other agents: acquire an atomic lock first — `mkdir <rundir>/claim.lock` (fails if held) — then read
  the lease, decide, write your token + fresh `updated`, and `rmdir` the lock. Two agents racing to
  adopt can't both win because only one `mkdir` succeeds. (A crashed claim leaves a stale
  `claim.lock`; treat one whose mtime is older than a few minutes as abandoned and clear it.)
- **Heartbeat.** Rewrite the lease with `updated = $(date +%s)` every wake once you're the confirmed
  owner, **and** immediately before and after any long *foreground* step (a Stage 0 sweep, a
  verification pass) so a busy turn still looks alive. Long *review/CI* work is already backgrounded,
  so between those the turn is short. A lease is **stale** only once `now - updated` exceeds **~30
  min** — comfortably longer than any single foreground operation, so liveness flags a *dead* driver,
  not a busy one.
- **Never hold the run hostage on a user prompt.** Do NOT block the loop waiting on a user answer —
  that freezes the heartbeat and could let the run be declared stale mid-drive. Park the finding
  `awaiting-api`, surface the question, keep driving the other findings, reschedule, and fold the
  answer in when it lands as its own wake (Constraints).
- **Adopt only an orphaned run.** Safe to take over only when the lease is **absent or stale** (under
  the claim lock). After writing your token, re-read: if it isn't yours, you lost the race — stand down.
- **Stand down if superseded.** On a self-wake, present your `--token`: if the lease is **fresh** and
  its `agent` is a **different** token, you were superseded (a takeover while you were hung) — do NOT
  drive; report and stop. Never overwrite a fresh lease you don't own. (Carrying the token in the
  prompt removes any amnesia ambiguity — a self-wake always knows its own token.)
- **Release** on normal exit: delete `lease.json` (with the owner label) so the finished run shows no
  active driver.

### Resolving a wake (Loop control step 1 applies this)

1. **`--run <id>` given** (every self-wake; also a manual targeted resume). Load `<rundir>/state.md`.
   Under the claim lock, compare the token you present to the lease: **matches** (self-wake with
   `--token`) → refresh lease, reconcile, continue; **lease absent/stale** → adopt (write token, fresh
   ts, read-back); **lease fresh but a different token** → for a self-wake, stand down (superseded);
   for a **manual** `--run` with no matching token, another agent appears active, so **confirm takeover
   with the user** before adopting.
2. **Bare invocation** → the arg decides intent:
   - **A scope arg is given** (`/review-gauntlet <area>`, no `--run`) → **start a NEW run** on that
     scope. A scope is an explicit "sweep this now", so it never silently adopts an existing run — this
     is how you launch a second concurrent run (`auth` alongside `storage`). To resume a specific run
     instead, pass `--run <id>`.
   - **No arg at all** (`/review-gauntlet`) → resume-oriented: **discover runs** and bucket by lease —
     distinct `gauntlet-run-*` labels on open `fix-*` PRs ∪ run-ids with a `<rundir>/` (its `state.md`
     or `lease.json`; a run mid-Stage-0 has a dir before any PR), each **actively-driven** (fresh
     lease), **orphaned** (non-terminal, lease absent/stale), or **finished** (terminal, no open PR):
     - exactly one **orphaned** → adopt and resume it ("pick up where the previous instance left off");
     - several orphaned → list them (id, scope, #open PRs) and **ask which to resume, or start new**;
     - only **actively-driven** → each has a live driver; do NOT hijack — offer to start a **new** run;
     - only **finished** → the finished-run prompt (Loop control step 1), per run;
     - none at all → first run: mint a run-id, Stage 0 → Stage 1.
3. **`--new`** (or "fresh run" / "start over") → always mint a NEW run-id + token and start fresh with
   carryover; it creates an independent run and does **not** pre-empt other runs (they keep their own
   drivers). Scope is the arg, if any.

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

Everything under the run's own dir `<rundir>` = `.tmp/review-gauntlet/<run-id>/` (create at the start
of a fresh run; on resume, reuse the run's existing dir). Per-run dirs are what keep concurrent runs'
files from colliding — see "Run identity and concurrency".

| File (under `<rundir>`) | Contents |
|------|----------|
| `findings-raw.md` | Codex's raw adversarial findings |
| `verdicts.md` | Neutral verification verdicts (which findings survive) |
| `state.md` | Live per-finding ledger — a **cache/hint**, not the source of truth (see below) |
| `lease.json` | This run's active-driver lease (`{agent, updated}`; see "Run lease") |
| `review-<pr>-<n>.txt` | Codex's PR review output, round `n` |
| `ci-<pr>.txt` | Latest `gh pr checks` snapshot for a PR (re-polled after the watch, not the watch stream) |
| `abort-<id>.md` | Detailed log for an aborted finding-task |

Store ALL codex and `gh` output to `.tmp/` first, then Read/Grep it. NEVER `/tmp/`.

**Durable cross-run knowledge lives outside `.tmp/`.** `.tmp/` may be wiped between runs, so the
one thing a *new* run needs to remember from old ones — the carryover ledger — is kept at the repo
root under `.review-gauntlet/history/` (git-ignored; add `.review-gauntlet/` to `.gitignore` if
missing), **one file per run** (`<run-id>.md`) so concurrent runs never clobber a shared file. It
survives `.tmp` cleanup. Everything else stays ephemeral under the per-run `<rundir>`. See
"Fresh runs and carryover".

### The ledger — `state.md`

One row per surviving finding. It is a **cache**, not the authoritative state — **ground truth is
git + GitHub** (`gh pr list/view` for PRs and merged/open state, `git rev-parse HEAD` per branch for
the live SHA, `gh pr checks` for live CI, and the `review-<pr>-<n>.txt` files for which verdicts
exist on which SHA). Every wake re-derives what's due from those, then refreshes this file. So a
stale or half-written ledger is self-healing — never act on it without reconciling against git/gh
first.

The file opens with a short run-config header (`run_id`, `base_branch`, `api_changes`, `phase` —
re-read every wake, see Constraints and "Run identity and concurrency"), then one row per finding:

```
run_id: g260704-0915-a3f29c1b  # this run's identity — namespaces its dir/branches/label/wakes (set once)
base_branch: main       # the branch PRs target & diffs measure against (set once; see "Base branch")
api_changes: ask        # ask | allowed (run-wide; set once from the invocation)
phase: fanout           # reviewing (Stage 0) → fanout (Stage 1+); written at run start before Stage 0

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

1. **Resolve the run + lease, then init / resume / start fresh.** First bind **which run this wake is
   for** and confirm you may drive it, per "Run identity and concurrency": a `--run <id>` self-wake
   presents its `--token` and, under the run's claim lock, continues if the token matches the lease,
   adopts if the lease is absent/stale, or **stands down** if a fresh lease bears a different token; a
   **scoped** bare invocation starts a NEW run, while an **arg-less** bare invocation discovers runs
   and adopts the sole **orphaned** one (asks among several, refuses to hijack an actively-driven one).
   This claim-locked lease check is what guarantees **no two agents drive one ledger**.

   Once bound and confirmed owner, decide on **liveness of THIS run**, not on whether some `state.md`
   exists — and scope **every** git/gh scan to this run's `gauntlet-run-<run-id>` label / `fix-<run-id>-`
   branch prefix so another run's PRs are never mistaken for your own. Live work (this run) = any open
   PR carrying this run's label / on a `fix-<run-id>-` branch **OR** any non-terminal row in this run's
   `state.md` (`pending` / `in_review` / `mergeable` / `awaiting-api`). Three cases:

   - **This run has live work → resume.** **Reconcile against ground truth** (do NOT redo Stage 0/1):
     for each of this run's branches/PRs read the live SHA, CI status, and verdict files, and refresh
     the ledger. Re-read `run_id`, `base_branch`, and `api_changes` from the ledger header — they
     govern namespacing, the merge/diff target, and API-change handling, and must be consulted fresh
     each wake, never from memory (a wake may be a fresh agent instance that just adopted the run;
     Constraints, Base branch). Refresh the lease. This is the path every `--run` self-wake takes.
   - **No run bound and none live (no `gauntlet-run-*` PR, no non-terminal `<rundir>`) → first run.**
     Mint a run-id + agent token, atomically create `<rundir>`, write the lease **and a minimal
     `state.md` header** (`run_id`/`base_branch`/`api_changes`, `phase: reviewing`) *before* Stage 0 —
     so a death mid-sweep leaves a discoverable, adoptable run rather than an invisible one — then do
     Stage 0 then Stage 1.
   - **This run's `state.md` is fully terminal — every row `merged`/`aborted`, no open `fix-<run-id>-*`
     PR → the run is finished.** Do **not** silently exit "all fixed" (the old bug) and do **not**
     silently restart. **Ask the user** whether to start a new run — e.g. "review-gauntlet run
     <run-id> finished (N merged, M aborted). Start a new run?" On yes, start a fresh run **with
     carryover** (see "Fresh runs and carryover"). On no, emit that run's final report and stop. This
     prompt is the *only* wake that asks the user about scope.

   **The `--new` fresh-run signal short-circuits the above:** `--new` (or "fresh run" / "start over")
   mints a NEW run-id + token and starts a fresh run with carryover immediately, regardless of any
   run's liveness — no prompt, and **other live runs are left untouched** (they keep running under
   their own drivers). Its scope is the arg, if any.

   **Reconcile labels too** (idempotent, retroactive, **scoped to this run**). Ensure the labels exist
   (`gh label create … --force`, as in Stage 1 — including this run's `gauntlet-run-<run-id>`), then
   for every PR **of this run** (its label, or on a `fix-<run-id>-` branch): ensure it carries
   `gauntlet-run-<run-id>`, and set its status label to match its **live** gate state —
   `gauntlet-accepted` if its current HEAD holds two SATISFIED verdicts, else `gauntlet-reviewing`;
   add the status label if it has none. **Never touch another run's PRs.**
2. **Fold in completions.** For any background task that finished (CI watch → `ci-<pr>.txt`; review →
   `review-<pr>-<n>.txt`), record the result against the SHA it ran on and act per Stage 2.
3. **Dispatch due work — non-blocking, idempotent, bounded.** Launch only what is actually due *and
   not already in flight* (check ground truth first, never the ledger alone). This owns **both** the
   initial fan-out and all downstream work — there is no separate batched fan-out phase:
   - any `pending` finding with no PR yet, while fewer than ~8 fix subagents are in flight → launch
     its fix subagent (Stage 1). This **backfills continuously**: as each fix subagent finishes and a
     slot frees, pull the next `pending` finding in — never wait for a whole group to drain before
     starting more.
   - current tip has < 2 SATISFIED verdicts, its **review preconditions are clear** (no unaddressed
     Copilot review items, CI not red, no merge conflict with `<base>` — see Stage 2a preconditions),
     and no review running for that SHA → launch **one** review pass as a **background** task (one at
     a time per PR — the second only after the first is SATISFIED; Stage 2a). If a precondition is
     dirty, clear it first (address Copilot items / fix CI / rebase) instead of spending a review;
   - CI red and no fix in flight → dispatch a scoped fix subagent (Stage 2b);
   - mergeable → queue for merge.
   Treat ~8 as a **rolling concurrency cap**, not a wave size: keep up to ~8 fix subagents and ~8
   review processes in flight, refilling each free slot immediately; queue the rest. **Launch, do not
   wait — never barrier on a group of findings before dispatching the next.**
4. **Merge** at most one queued PR this wake, serialized, after re-confirming its gate against the
   live SHA (Stage 3).
5. **Reschedule or exit.**
   - Any non-terminal PR remains → refresh this run's lease, then set a `ScheduleWakeup` heartbeat
     (`prompt: "/review-gauntlet --run <run-id> --token <agent-token> <args>"` — `--run` rebinds the
     wake to this run and `--token` re-proves ownership of its lease; delay ~3–4 min, cache-warm) as a
     fallback; background completions will usually wake you sooner. Return.
   - All this run's PRs `merged` or `aborted` → **distill the run into the carryover ledger** (write
     this run's block to its own file `.review-gauntlet/history/<run-id>.md` — merged fixes, aborted
     findings + why, declined-API findings, and the REFUTED/UNCERTAIN sets; per-run files never
     contend, see "Fresh runs and carryover"), **release the run** (delete this run's
     `gauntlet-run-<run-id>` owner label via `gh label delete gauntlet-run-<run-id> --yes`, and delete
     `<rundir>/lease.json`; the shared status labels stay), emit the final report, and **do not
     reschedule**. This run's loop ends. **Leave
     `<rundir>` in place** (do NOT delete it here) — its terminal `state.md` is what lets a later bare
     invocation detect *this* *finished* run and take the "ask the user" branch in step 1 instead of a
     silent exit. (A stale heartbeat firing after exit harmlessly re-hits the finished-run branch via
     its `--run <run-id>`; with the lease released it reads as an un-driven finished run.)

**Idempotency is the load-bearing property.** Because every wake re-derives from git/gh and launches
only work not already in flight, a relaunch after a killed session — or two completions landing close
together — cannot corrupt state or act on a stale verdict (SHA-pinning rejects stale verdicts at the
gate). The worst case is a wasted duplicate review, which is harmless: it's an independent re-roll
anyway. The agent is also single-threaded per turn, so wake *decisions* never truly race — only
in-flight tasks do.

**Resume after a killed session — including by a different agent instance:** in-flight background
tasks die with the session, but nothing authoritative is lost. A new invocation reconciles against
git/gh and continues — no Stage 0/1 once PRs/branches already exist. It binds to the run via
`--run <id>` (what every self-wake carries, so a fresh instance adopting an orphaned run's heartbeat
just works) or, for a bare re-invocation, by discovering live runs and adopting the sole **orphaned**
one (asking among several). Adoption is gated on the **run lease**: an agent takes over only a run
whose lease is absent or stale, so it can always tell whether another agent is still driving that
ledger and never double-drives an actively-held run (see "Run identity and concurrency" and Loop
control step 1). This is how a later agent picks up exactly where a previous instance left off.

---

## Fresh runs and carryover

A **fresh run** is a new Stage 0/1 cycle started when a prior run already happened — triggered either
by the user answering "yes" to the finished-run prompt (Loop control step 1) or by an explicit
`--new`. It is *not* a resume: it does a brand-new codex sweep. What makes it more than a blind
re-run is **carryover** — it inherits what earlier runs already learned.

### The carryover ledger — `.review-gauntlet/history/`

A durable, git-ignored store at the repo root (NOT under `.tmp/`, which can be wiped). To stay
concurrency-safe it is **one file per run**, `.review-gauntlet/history/<run-id>.md` — never a single
shared file two runs could clobber. Each finished run writes **its own** file exactly once; a fresh
run reads **every file in the directory** (concatenated) so knowledge compounds across runs. A per-run
file records:

- **merged** — finding slug + one-line fix, per PR that shipped.
- **aborted** — finding slug + why it couldn't clear the bar (pointer to its `abort-<id>.md` if still
  present).
- **declined-api** — findings parked under `ask` that the user declined, with the change they'd have
  needed.
- **refuted** — findings the verification pass rejected as non-issues, with a one-line reason.
- **uncertain** — findings left for the user to triage.

If `.review-gauntlet/history/` doesn't exist, create it (and add `.review-gauntlet/` to the repo's
`.gitignore` if it's not already ignored). When the directory is empty, a fresh run is just a normal
first run.

**Why per-run files.** Because each run only ever writes and prunes its **own** file, appends never
contend and there is no shared-file rewrite to race — the append/prune hazard of a single `history.md`
is gone. (A legacy single `history.md`, if present from before this split, is still read for carryover;
leave it in place as read-only history.)

### Pruning the ledger

The ledger grows append-only during runs, so **prune it regularly** — at the start of every fresh
run (right before feeding carryover into Stage 0), and any time the user asks. The goal is to drop
entries that **no longer apply to the current code**, so stale context can't mislead the new sweep.
Check each entry against current `<base>`:

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

A run is distilled into the ledger **exactly once**, on its **normal exit** (all its PRs terminal) —
Loop control step 5 writes that run's own `.review-gauntlet/history/<run-id>.md`. The finished-run
"ask the user → yes" path reuses *that* file; it does not re-distill. (`--new` no longer pre-empts
other runs — each run is isolated and always distills itself on its own exit — so there is no
mid-flight snapshot path.)

### Starting a fresh run

1. **Mint the new run-id + agent token; atomically create its clean `<rundir>`.** Per-run dirs make a
   fresh run isolated by construction — `mkdir` of `.tmp/review-gauntlet/<new-run-id>/` starts empty
   (retry on the rare id clash); there is nothing to archive and no prior `.tmp` to wipe. Write the
   lease and a minimal `state.md` header immediately (so the run is discoverable before Stage 0
   finishes). Any already-live run keeps its own dir, lease, and heartbeat; a fresh run never closes,
   merges, or stops driving another run's PRs (abandoning a specific run is a separate explicit ask).
2. **Read every file in `.review-gauntlet/history/`, then prune** (drop entries no longer applicable
   to current `<base>`; confirm any uncertain deletions with the user — see "Pruning the ledger").
   Pruning only ever edits **finished** runs' own files (no live writer), so there's nothing to race.
   Feed the pruned carryover into Stage 0 (below).
3. Proceed through Stage 0 → Stage 1 → the loop as normal, on the clean `<rundir>`.

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

## Codex fallback — quota / system errors

`codex exec` is the default reviewer, but it can fail in a way that yields **no usable verdict**:
quota/rate-limit exhaustion, auth failures, timeouts, or other system errors. Distinguish this from a
real review — a codex run that returns an actual finding list or a `VERDICT: …` line is a *result*,
act on it. A *failure* is the absence of a verdict.

When codex can't deliver a verdict, retry once. If it still can't, **do the equivalent work with your
own subagents** rather than stalling, looping on codex, or skipping the gate — then note in the final
report that the pass ran on the Claude-subagent fallback.

- **Stage 0 (adversarial review)** → run the adversarial sweep with your own subagents: follow the
  `adversarial-review` skill over the same scope (tier/shard it for a large surface, as Stage 0
  already describes), writing findings to `findings-raw.md` in the same shape codex would have. The
  neutral verification pass (Stage 0 step 2) is unchanged.
- **Stage 2a (per-PR review)** → spawn a **fresh** subagent to review the whole `<base>...HEAD` diff
  with an equally adversarial pass, ending in exactly one `VERDICT: SATISFIED` / `VERDICT: NOT
  SATISFIED` line. Each fallback pass is still an independent re-roll in its own subagent/context, so
  the two-independent-SATISFIED gate holds exactly as it does with codex.

This is a fallback for *system* failure, not a preference — use codex whenever it can actually run.

## Stage 0 — Review and verify

1. Run the codex adversarial review. Scope = the arg if given, else the whole repo.

   ```
   codex exec --sandbox workspace-write -o <rundir>/findings-raw.md \
     "Perform an adversarial code review of <SCOPE>. For each finding give: a stable ID, \
      severity, file:line, the defect, a concrete reproduction trigger, the impact, and a \
      concrete fix. Be hostile — surface everything that could be wrong. Do not edit code."
   ```

   For a whole-repo sweep, mirror the tiering strategy in the `adversarial-review` skill if the
   surface is large — and shard it rather than running one giant foreground call, so each codex call
   stays short enough that the driver can heartbeat its lease between shards (a single sweep longer
   than the ~30-min stale window would otherwise let another agent adopt the run mid-Stage-0; see "Run
   lease"). If codex can't produce findings (quota/rate-limit, auth, timeout, hang, or other system
   error — see "Codex fallback"), retry once, then run this sweep with your own subagents into
   `findings-raw.md` and continue with verification as normal.

   **On a fresh run, load carryover first** (all of `.review-gauntlet/history/`, pruned of stale
   entries per "Pruning the ledger") and pass the prior unresolved items (aborted / declined-api / uncertain)
   to the reviewer as known areas of interest, so a re-find is recognized rather than treated as
   net-new. See "Fresh runs and carryover".

2. **Neutral verification pass.** Audit every finding with the `adversarial-review` Phase 2 scheme —
   `CONFIRMED` / `ADJUSTED` / `REFUTED` / `UNCERTAIN`, biased toward refuting — into
   `<rundir>/verdicts.md`. On a fresh run, hand the verifier the carryover sets (refuted
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

4. Fill in `<rundir>/state.md`: the run-config header (`run_id`, `base_branch`, `api_changes`) was
   already written at run start (Loop control step 1 / "Starting a fresh run"); now append one row per
   surviving work item, status `pending`, and flip `phase` from `reviewing` to `fanout`.

If zero findings survive, **release the run before stopping** — write its (empty) carryover file
`.review-gauntlet/history/<run-id>.md`, delete `<rundir>/lease.json` and the `gauntlet-run-<run-id>`
label *if it exists* (Stage 1 hasn't run yet on a zero-survivor exit, so the owner label is usually
not created — skip it then), mark `state.md` terminal — then report and stop (no loop). Do not leave
the lease dangling.

---

## Stage 1 — Fan out (one PR per finding)

**Ensure the labels exist** first — the two shared status labels plus this run's owner label
(idempotent — `--force` creates or updates, safe on every resume):

```
gh label create gauntlet-reviewing --color FBCA04 --description "review-gauntlet: under review" --force
gh label create gauntlet-accepted  --color 0E8A16 --description "review-gauntlet: passed two reviews" --force
gh label create gauntlet-run-<run-id> --color 5319E7 --description "review-gauntlet: run <run-id>" --force
```

Spawn one subagent per surviving finding, up to a **rolling cap of ~8 in flight** — NOT in barrier
waves. Launch the first ~8 immediately, then refill: the moment any fix subagent finishes (and its PR
enters the gates), pull the next `pending` finding into the freed slot. Never wait for a group of ~8
to fully drain before starting more — a small remainder of one group must not stall the rest of the
backlog. From the first wake onward this refilling is owned by Loop-control step 3 (the same dispatch
that launches reviews/CI fixes/merges), so initial fan-out and resume use one identical slot-driven
path; this Stage 1 description is just what each fix subagent does. Each subagent:

1. `git worktree add $PROJECT/.worktrees/<branch> -b <branch> <base>`, `<branch>` =
   `fix-<run-id>-<finding-id>-<short-slug>` (the `<run-id>` prefix scopes the branch to this run so
   concurrent runs never collide; the `<finding-id>` keeps two findings with the same slug apart;
   branch off `<base>`, not whatever HEAD happens to be).
2. Implement the fix for **that finding only**, diff tight and scoped. If it would modify the public
   API surface or behavior, follow **Constraints**: under `ask`, park the finding (`awaiting-api`)
   and confirm with the user before changing anything; under `allowed`, proceed.
3. Commit, push, open the PR off `<base>` **before any gauntlet review or CI gate**, tagged with this
   run's owner label **and**
   `gauntlet-reviewing`:
   `gh pr create --base <base> --label gauntlet-run-<run-id> --label gauntlet-reviewing --title ... --body ...`
   (no "Test plan" section).
4. Return: finding id, branch, worktree path, PR number, one-line fix summary.

For each PR: record it in `state.md` (status `in_review`, `started` = now, `attempts` += 1) and
launch its background CI watch. The `--watch` only **blocks** until the run settles; immediately
after, **re-poll a fresh snapshot** into the file — that snapshot, not the watch, is what you read:

```
# run in background. ';' (not '&&') so the re-poll ALWAYS runs, even when --watch exits non-zero on failure
gh pr checks <pr> --watch ; gh pr checks <pr> > <rundir>/ci-<pr>.txt
```

The fix subagents only produce the fix + PR. They do NOT run reviews, watch CI, or merge — those
are yours.

---

## Stage 2 — Gates (orchestrator-owned, reactive)

### 2a. The review gauntlet

**Preconditions — clear Copilot items, CI, and conflicts before reviewing.** A codex review pass is
expensive and is invalidated by any new commit, so never spend one on a PR whose current tip still
has review-blocking issues. Before launching a pass, check three things and clear any that are dirty.
Each fix moves HEAD, so `reviews_ok` resets to 0 (SHA-pinning) and the review re-starts on the clean
tip:

- **GitHub Copilot review items.** If the PR has any unresolved Copilot review comments, address them
  with `/copilot-address-reviews <pr>` before reviewing (that skill verifies each item against source
  before changing code, works them one at a time, and resolves the threads). Detect them from a
  stored `gh` snapshot — the copilot skill's `fetch-review-items.sh` normalizes unresolved
  Copilot-authored comments into `.tmp/copilot-review-items.json` — never scrape HTML. That path is
  **shared across runs**, so treat it as ephemeral: fetch immediately before acting and **verify the
  JSON is for THIS PR** (re-fetch if a concurrent run overwrote it), and don't interleave two runs'
  copilot-address cycles. No items → no-op.
- **CI failures.** If `ci` is red for the current tip, do NOT review — fix CI first (Stage 2b).
  Handle failures **one at a time**, and **prefer a scoped subagent** per failure; use your own
  judgement on each fix.
- **Merge conflicts with `<base>`.** If GitHub flags the PR conflicting/behind
  (`gh pr view <pr> --json mergeable,mergeStateStatus` → `CONFLICTING` / `DIRTY`), rebase it onto
  `<base>` and resolve the conflict before reviewing — a conflict-resolving rebase changes code, so
  it resets the gate (Stage 3 step 5).

Only launch a review pass once all three are clear for the current tip.

Run reviews **one at a time per PR** — never two at once for the same SHA. When a PR's tip
(`head_sha`) has fewer than two SATISFIED verdicts and no review already running for it, the wake's
dispatch step launches **one** review pass: a **fresh** `codex exec` over the whole `<base>...HEAD`
diff, no shared context, run as a **background** task (its completion is a wake; the loop folds the
verdict in at step 2). The second, corroborating review is launched only **after** the first comes
back SATISFIED — so a still-broken commit never burns the second review before the first has said
"fix it". (Reviews for *different* PRs still run concurrently, up to the ~8 cap; it's only the two
reviews for the same PR that serialize.) Each pass is a separate process, so the two verdicts stay
independent regardless.

If a pass's `codex exec` can't return a verdict (quota/rate-limit, auth, timeout, or other system
error — see "Codex fallback"), retry it once, then run that pass as a **fresh subagent** reviewing the
whole `<base>...HEAD` diff and ending in the same `VERDICT:` line. A subagent fallback pass counts
toward the two-independent-SATISFIED gate exactly like a codex pass — it's an independent re-roll in
its own context.

```
codex exec --sandbox workspace-write -C $PROJECT/.worktrees/<branch> \
  -o <rundir>/review-<pr>-<n>.txt \
  "Review the changes on this branch vs <base> (the whole git diff <base>...HEAD). List any issues with \
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

Every pass reviews the whole `<base>...HEAD` diff (not just the last fix-delta), so accumulated fixes
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

### 2a-deep. Root-cause pass — one decision made at N sites

**The archetype — recognize it on sight.** The most common root cause behind a run of review findings
is **one decision duplicated at N independent sites**: the same error-classification across every
loader + caller, the same notation/resolution across every code path, the same attribute-value
handling per read-site. Each site is a sibling in a finite space the code must cover **identically**.
The fix is almost never per-site — it is a **single chokepoint every site routes through**, and the
enumeration's whole job is to find **all N sites, including the ones no reviewer has hit yet**. Treat
each review finding as a *symptom of the shared decision*, not a new problem.

**Trigger on the finding's SHAPE, not on a round count.** Fire this the moment the **first** finding
takes the form "this check / resolution / classification is missing (or wrong) at site X" — i.e. a
decision applied independently at more than one site. Do **NOT** wait for the reviewer to surface
sites 2..N over successive rounds — that is the reviewer mapping *your* space for you, one expensive
review at a time. One such finding is enough to suspect the archetype and map the whole space now. (A
string of `NOT SATISFIED` findings that are siblings in one structured space — same function/concept,
different instance — is the same signal arriving late; treat it identically, and see the Bailout
escalation rung, which forces this pass no later than the 2nd `NOT SATISFIED` on a PR.)

**Enumeration is a SEPARATE read-only pass — NEVER folded into a fix.**

1. **Name the space and its axes.** What is the finite set every site must cover identically, and what
   are its axes? (The set of cases/inputs/states a function must handle; a `{variant} × {code-path}`
   grid; both directions of a round-trip or other symmetric relation; every call site of one operation
   that must behave the same.) The axes are domain-specific — derive them from the finding, don't
   assume a fixed shape.
2. **Dispatch a dedicated MAPPER subagent whose SOLE deliverable is the map** — read-only, in a
   *fresh* worktree at the PR tip (NOT the fix worktree). It enumerates every cell, marks each
   `HANDLED` / `GAP` / `N-A` with a one-line why, and returns **the complete cell table + a
   one-sentence root-cause statement** — each gap with `file:line` + a minimal repro confirmed by a
   throwaway test (deleted before it reports). Emit the table literally.

   **NEVER ask one subagent to both enumerate and fix.** A fixer under-maps toward what it can reach:
   it finds the sites next to its diff and misses the caller two layers up or the code path it has no
   handle on. A mapper carries no fix pressure, so it maps the space exhaustively — which is the point.
   Enumeration and fix are two subagents, in that order, always.
3. **One batch-fix round** for all confirmed gaps. Route every site through **ONE shared
   chokepoint/helper** so the cells can't diverge again. Add a test per cell.
4. **Resume the gauntlet** (two independent SATISFIED) on the batched result.

Caveats:

- A cell's verdict can be **wrong** — the analysis is a hypothesis (e.g. "handled by X" when X doesn't
  actually cover it). The adversarial gauntlet still arbitrates; the deep pass *accelerates*
  convergence, it does NOT replace the gate. Re-feed any reviewer-found gap into the enumeration.
- Completeness = no false-positive AND no false-negative across the space. The pass surfaces both: an
  over-strict path that rejects valid cells is as much a gap as a missing one.
- A whole AXIS can be missed. When a later finding reveals a dimension the enumeration didn't have,
  RE-RUN it on the expanded space rather than patching the single new cell.

Pairs with the **Codex fallback** subagents, and — when the user authorizes the spend for a large PR
— a **parallel adversarial reviewer** running the same enumeration independently for breadth while
codex runs the gate; reviewer diversity catches different cells.

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

1. **Serialize** — merge at most one PR per wake. Before merging, re-confirm both gates still hold for
   the current HEAD (a late push may have reset them), **and re-fetch `origin/<base>` and re-check
   `gh pr view <pr> --json mergeable,mergeStateStatus`** — a concurrent run sharing this base may have
   advanced it since the PR was last reviewed. If it now reads `BEHIND`/`DIRTY`/`CONFLICTING`, rebase
   onto `<base>` and reset the gate per step 5 instead of merging.
2. Push guard: `gh pr view <branch> --json state --jq .state` must be `OPEN`.
3. Merge: `gh pr merge <pr> --squash --delete-branch` (use the repo's prevailing merge method if not
   squash).
4. **Sync the local base branch with the remote.** The merge landed on `origin/<base>`, but local
   `<base>` is now behind — and Stage 1 worktrees branch off it (`git worktree add … -b <branch>
   <base>`). Fast-forward it so every subsequent fan-out, rebase, and `<base>...HEAD` diff is measured
   against the just-merged tip, not a stale one (`<base>` = the run's base branch, not assumed `main`).
   Local `<base>` is **shared** with any concurrent run on the same base; the fast-forward is
   idempotent, so if another run already advanced it, a no-op "already up to date" is fine — just never
   force it.

   **Run the fast-forward from wherever `<base>` is actually checked out** — don't assume it's the
   root checkout. A branch can be checked out in at most one working tree, so first locate that tree
   (`git worktree list` shows the branch per path; the root package counts as one), then fast-forward
   there. If `<base>` is checked out **nowhere**, update the ref directly instead — a plain `fetch`
   into the local branch (this form is refused while the branch is checked out, which is why it's the
   no-working-tree case):

   ```
   git -C $PROJECT fetch origin <base>
   # case A — <base> is checked out in some working tree <dir> (root or a worktree):
   git -C <dir> merge --ff-only origin/<base>
   # case B — <base> is checked out in no working tree:
   git -C $PROJECT fetch origin <base>:<base>
   ```

   Fast-forward only — never a merge commit or reset. If the fast-forward fails (local `<base>` somehow
   diverged), do NOT force it: that's a bailout condition (stop and surface it), since branching new
   fixes off a wrong base would corrupt every downstream diff.
5. After the merge, other open PRs may be stale. **Rebase only if** GitHub flags the PR
   behind/conflicting:
   - Clean rebase (no conflicts) → the PR's own diff is unchanged → keep `reviews_ok`, but `ci` goes
     `pending` and must return green before merging.
   - Rebase requiring conflict resolution → code changed → **reset `reviews_ok` to 0**, re-enter
     Stage 2.
6. **Clean up on successful merge.** Once the merge is confirmed (`gh pr view <branch> --json state
   --jq .state` → `MERGED`), tear down that PR's local footprint:
   - `--delete-branch` above already removed the **remote** branch.
   - Verify the merge with the `git-detect-merged` skill, then use `git-cleanup-merged` to remove the
     **worktree** (`.worktrees/<branch>`) and delete the **local branch**.
   - Set status `merged` and stop its background tasks.

   This runs only after the merge is verified, and only ever touches **this run's own**
   `fix-<run-id>-*` worktrees/branches (per the Authorization note and the isolation invariant) — never
   another run's. Leave the worktree in place if the merge cannot be confirmed — treat that as a
   bailout condition, not a cleanup.

---

## Bailout

- **1-hour cap per task** (measured from `started`). If a finding's task exceeds one hour without
  merging, abort it cleanly and **retry once** from a fresh worktree (`attempts` += 1, reset
  `started`).
- On the **second** stuck/failure, abort permanently: stop work on that finding, write
  `<rundir>/abort-<id>.md` with the full history (reviews, CI failures, diffs, what
  blocked it), set status `aborted`, and **continue the other findings**.
- **Converging-but-expensively → escalate to the root-cause pass.** The bailouts above catch a *stuck*
  task; this catches one that's *progressing by whack-a-mole*. A targeted per-finding fix is right for
  the **first** `NOT SATISFIED` on a PR, or for genuinely independent findings. But on the **second**
  `NOT SATISFIED` on the same PR, **stop targeted patching and run the §2a-deep root-cause pass** — map
  the whole space with a dedicated read-only mapper and fix at one chokepoint. This is a hard backstop:
  even if the archetype wasn't obvious on finding 1, the 2nd sibling finding forces the pass no later.

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

The same outcomes are written to this run's durable carryover file
(`.review-gauntlet/history/<run-id>.md`) on exit (Loop control step 5), so the next fresh run inherits them.

## Rules

- Runs are isolated by `run_id`: a run touches ONLY its own `<rundir>`, its `state.md`, and PRs/branches
  carrying its `gauntlet-run-<run-id>` label / `fix-<run-id>-` prefix. NEVER reconcile, review, fix,
  merge, relabel, or clean up another run's work — scope every git/gh scan by that label or prefix.
- One active driver per run, enforced by `<rundir>/lease.json` under an atomic `mkdir <rundir>/claim.lock`:
  take/adopt a run only inside the claim lock, and adopt ONLY when its lease is absent or stale
  (`now - updated` > ~30 min); refresh the lease every wake AND around long foreground ops; on a
  self-wake whose lease is fresh but bears a different token, **stand down** — never double-drive a ledger.
- Every self-wake carries `--run <run-id> --token <agent-token>` (ScheduleWakeup + background
  completions); the token re-proves lease ownership so a summarized wake never mistakes its own run for
  another's. Re-read `run_id` from the ledger each wake, never from memory.
- Resume is intent-scoped: a fresh instance resumes via `--run <id>` or an **arg-less** bare invocation
  (adopts the sole orphaned run). A **scoped** bare invocation and `--new` start an independent new run
  and never pre-empt other live runs.
- Carryover is **one file per run** under `.review-gauntlet/history/<run-id>.md`: a run writes and
  prunes only its own file, so appends never contend and there's no shared-file rewrite to race.
- NEVER pass destructive instructions (delete, force-push, reset) to `codex exec`.
- NEVER use `--dangerously-bypass-approvals-and-sandbox`; always `--sandbox workspace-write`.
- One finding = one tightly-scoped PR. Do not bundle unrelated fixes.
- PR-first loop is mandatory: implement → commit → push → create/update PR → watch CI + review PR
  HEAD. NEVER do local gauntlet reviews first and wait to push/open a PR until the end.
- Fan-out is a **rolling cap (~8 in flight), never a barrier wave**: backfill each freed slot with the
  next `pending` finding immediately. Never let a draining group of findings stall the backlog —
  Loop-control step 3 owns this refill for both initial fan-out and resume.
- Public API surface/behavior changes need user confirmation by default (see Constraints). The
  `api_changes` flag lives in the ledger header and is re-read every wake — never trust memory, never
  auto-merge an unapproved API break.
- Before queueing a review pass on a PR, clear its preconditions on the current tip: address any
  GitHub Copilot review items (`/copilot-address-reviews <pr>`), fix any CI failures (one at a time,
  prefer a scoped subagent), and rebase away any conflict with `<base>`. Each moves HEAD → verdicts
  reset. Never spend a review over open Copilot items, a red check, or a conflicting PR (Stage 2a).
- Reviews are independent re-rolls: separate `codex exec` each pass, no shared context.
- One decision at N sites is the most common root cause. Trigger the §2a-deep root-cause pass on the
  **first** "missing/wrong at site X" finding (its shape, not a round count), map the whole space with
  a dedicated **read-only mapper** subagent — never one that also fixes, which under-maps toward what
  it can reach — and fix at a **single chokepoint**. Hard backstop: a 2nd `NOT SATISFIED` on one PR
  forces the pass (Bailout).
- The two reviews on a PR run **sequentially, never queued together**: launch the first, wait for its
  verdict, and launch the second **only if the first came back SATISFIED**. A NOT-SATISFIED first
  review means a fix lands and the SHA changes, so a concurrently-queued second review would be burned
  on a commit that's about to be replaced — wasted tokens. (Reviews for *different* PRs still run
  concurrently; only the two for the same PR serialize. See Stage 2a.)
- Verdicts are pinned to the reviewed HEAD SHA: any new commit (incl. rebase / base-merge / bot
  commit) makes prior verdicts stale. Re-derive from `git rev-parse HEAD`, don't trust memory.
- Resume vs. fresh run is decided by **liveness**, not by `state.md` existing: live work → resume
  (no Stage 0/1); a finished prior run → ask the user before a fresh run; `--new` → fresh run with
  carryover (Loop control step 1). A finished run must never silently exit "all fixed" or silently
  restart.
- A fresh run carries over prior knowledge from `.review-gauntlet/history/` (refuted to suppress,
  unresolved to re-surface, merged to dedup) but still judges every finding fresh — carryover is
  advisory, never auto-accept/reject.
- Prune `.review-gauntlet/history/` at every fresh run: drop only entries unambiguously moot against
  current `<base>`; for anything uncertain, list it and ask the user before deleting. Never silently
  prune an entry you're unsure about.
- If `codex exec` can't deliver a verdict (quota/rate-limit, auth, timeout, or other system error —
  *not* a real finding list / `VERDICT:` line), retry once, then do the equivalent work with your own
  subagents: the Stage 0 adversarial sweep, or an independent fresh-subagent pass in Stage 2a. The
  gate is unchanged — note any fallback pass in the report. See "Codex fallback".
- CI status comes from a re-polled `gh pr checks` snapshot with **zero fail AND zero pending lines** —
  never from the `--watch` exit code (it can exit 0 on pending/unregistered checks). No green, no merge.
- The run targets a **base branch** (`base_branch` in the ledger header), which is **not assumed to
  be `main`** — it defaults to the branch checked out at invocation. PRs open with `--base <base>`,
  worktrees branch off `<base>`, and reviews diff `<base>...HEAD`. Re-read it each wake (see "Base
  branch").
- After every merge, fast-forward local `<base>` to `origin/<base>` (Stage 3 step 4) so subsequent
  fan-out worktrees and `<base>...HEAD` diffs branch off the just-merged tip, not a stale base. If the
  fast-forward fails, bail out — never force it.
- No "Test plan" section in PR bodies.
