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
- **Residual risk** — for each merged PR, the `RESIDUAL-RISK` line its accepting SATISFIED reviews
  recorded (the least-certain area), and a flag when both accepting passes named the same area. This is
  non-actionable, non-gating calibration metadata — a place a human might look, never a reopened
  finding (Stage 2a).
- **Aborted** — finding id, why, pointer to `abort-<id>.md`.
- **Skipped** — REFUTED findings, UNCERTAIN ones the user should triage, and any API-changing fix the
  user was asked about and declined (with the change each would have needed).
- Any worktrees left for inspection.

The same outcomes are written to this run's durable carryover file
(`.review-gauntlet/history/<run-id>.md`) on exit (Loop control step 5), so the next fresh run inherits them.
