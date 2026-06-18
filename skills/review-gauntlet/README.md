# review-gauntlet

Point it at your code and it runs a tough, end-to-end review cycle for you: an adversarial review
finds problems, each real one gets fixed in its own pull request, every PR is re-reviewed until it
passes a strict quality bar **and** CI is green, and then it merges — all on its own, hands-off.

Think of it as an automated senior reviewer that doesn't just leave comments, but follows through:
files the fixes, defends them through repeated review rounds, waits for CI, and ships.

## What it's good for

- Hardening a codebase or a feature area before a release.
- Turning "someone should really review this" into actual merged fixes.
- Running a thorough pass unattended while you do something else.

## How to use it

```
/review-gauntlet                 # review the whole repo
/review-gauntlet auth & sessions # review just that area or topic
```

Run it **once** — that's it. It schedules its own follow-ups and keeps working until everything is
resolved; you don't need to keep it open or re-run it.

## What to expect

It opens a pull request for each problem worth fixing and merges them itself once they pass two
independent reviews on the same commit and CI is green. There's no approval step along the way, so
starting it is your sign-off — and a whole-repo run can spin up several PRs and keep going for a
while before it's done.

It tidies up as it goes, deleting merged branches and their worktrees. If a fix just can't clear the
bar, it retries once, then sets that one aside with a note on why and moves on rather than stalling
everything else. When it's finished you get a short rundown: what merged, what it gave up on, and
anything it left for you to weigh in on.

## Flow

```mermaid
flowchart TD
    A([invoke review-gauntlet]) --> B{area or topic given?}
    B -- yes --> C[codex reviews that area]
    B -- no --> D[codex whole-repo sweep]
    C --> E[neutral verification pass]
    D --> E
    E --> F{more than 10 findings?}
    F -- yes --> G[parallel verifier shards] --> H[reconcile survivors: dedup + cross-ref]
    F -- no --> I[single verifier]
    H --> J
    I --> J[survivors = CONFIRMED or ADJUSTED]
    J --> K[Stage 1: fan out - one PR per finding]
    K --> L[per finding: worktree off main, fix, commit, push, open PR, launch CI watch]
    L --> M[[event loop: gate each PR]]

    M --> N{2 SATISFIED on current SHA?}
    N -- no --> O[run 2 concurrent codex reviews on HEAD SHA]
    O --> P{any NOT SATISFIED?}
    P -- yes --> Q[scoped fix subagent: commit + push, new SHA]
    P -- no --> M
    N -- yes --> R{CI status on current SHA?}
    R -- red --> S[scoped CI-fix subagent: commit + push, new SHA]
    R -- pending --> M
    Q --> T[reset gates - verdicts and CI are SHA-pinned]
    S --> T
    T --> M
    R -- green --> U[merge: serialized, auto, squash, delete-branch]
    U --> V[cleanup worktree + local branch, mark merged]
    V --> W{all PRs merged or aborted?}
    W -- no --> M
    W -- yes --> X([final report])

    M -. 1h cap exceeded .-> Y{first attempt?}
    Y -. yes .-> Z[retry once in fresh worktree]
    Z -.-> M
    Y -. no .-> AA[abort + write log, continue others]
    AA -.-> W
```

## Good to know

- It uses Codex as the reviewer, so Codex CLI needs to be available.
- It works through GitHub PRs via the `gh` CLI, so the repo needs a GitHub remote.
- Full mechanics live in [`SKILL.md`](./SKILL.md).
