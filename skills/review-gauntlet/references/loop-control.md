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
   `review-<pr>-<n>.txt`, with `review-<pr>-<n>.progress.jsonl` as its liveness evidence), record
   the result against the SHA it ran on and act per Stage 2.
3. **Dispatch due work — non-blocking, idempotent, bounded, work-conserving.** Scan the whole run,
   not just the PR/job that woke you. Launch every due action that fits a free slot before returning.
   Launch only what is actually due *and not already in flight* (check ground truth first, never the
   ledger alone). This owns **both** the initial fan-out and all downstream work — there is no
   separate batched fan-out phase:
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
   - mergeable → queue for serialized merge drain.
   Treat ~8 as a **rolling concurrency cap**, not a wave size: keep up to ~8 fix subagents and ~8
   review processes in flight, refilling each free slot immediately; queue the rest. **Launch, do not
   wait — never barrier on a group of findings before dispatching the next.**
   Allowed idle state is narrow and explicit: no pending finding can launch, no PR can start a review,
   no CI/precondition fix is due, no PR is mergeable, and every remaining wait is external
   (background review/CI), user/API approval, or a genuinely full cap.
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
together — cannot corrupt state or act on a stale verdict (PR-content pinning rejects stale verdicts
at the gate). The worst case is a wasted duplicate review, which is harmless: it's an independent
re-roll anyway. The agent is also single-threaded per turn, so wake *decisions* never truly race — only
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
