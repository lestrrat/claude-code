## Stage 3 — Merge (serialized, auto)

A PR is mergeable when the **current** `git rev-parse HEAD` equals `head_sha` AND `reviews_ok == 2`
AND `ci == green` — i.e. two SATISFIED verdicts and green CI all recorded against the live tip.

1. **Serialize** — merge at most one PR per wake. Before merging, re-confirm both gates still hold for
   the current HEAD (a late push may have reset them), **and re-fetch `origin/<base>` and re-check
   `gh pr view <pr> --json mergeable,mergeStateStatus`** — a concurrent run sharing this base may have
   advanced it since the PR was last reviewed. If it now reads `BEHIND`/`DIRTY`/`CONFLICTING`, rebase
   onto `<base>` and apply step 5 instead of blindly resetting the review gate.
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
5. After the merge, other open PRs may need a base refresh. **Base advancement alone does NOT invalidate
   gauntlet reviews.** Rebase only if GitHub flags the PR behind/conflicting:
   - Clean rebase (no conflicts) → verify the PR's own diff/content is unchanged → keep `reviews_ok`,
     update `head_sha` to the new tip, but set `ci = pending`; CI must return green before merging.
   - Rebase requiring conflict resolution → PR content changed → **reset `reviews_ok` to 0**, re-enter
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
