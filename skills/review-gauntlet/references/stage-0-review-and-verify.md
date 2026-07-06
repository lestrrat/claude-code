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
