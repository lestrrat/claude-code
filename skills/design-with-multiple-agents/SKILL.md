---
name: design-with-multiple-agents
description: Multi-agent design collaboration — Claude Code (reviewer) and Codex (designer) iterate on a design doc via file-based chat. Gathers requirements from user, then runs a review loop until design is satisfactory. Args: <topic>
---

# Design Chat

Create a design document through iterative collaboration between you (Claude Code, the reviewer)
and Codex (the designer). You gather requirements, Codex drafts/revises, you review, repeat until
the design is solid.

## Args

`/design-chat <topic>`

- `<topic>` — short description of what needs designing. If missing, ask the user.

## Roles

- **You (Claude Code)** — requirements gatherer, reviewer, quality gate.
- **Codex** — designer, author of the design document.

## File Locations

All files live in `.tmp/design-chat/`:

- `design.md` — the design document (Codex writes/revises this)
- `review-N.md` — your review for round N (N = 1, 2, 3, ...)

Create `.tmp/design-chat/` at the start. Clean up old contents if present.

## Step 1: Gather Requirements

Ask the user targeted questions to understand:

- **Goal** — what problem does this solve?
- **Scope** — what is in/out of scope?
- **Constraints** — performance, compatibility, dependencies, existing code patterns?
- **Deliverables** — what artifacts result? (code, config, API, schema, etc.)
- **Context** — relevant files, packages, or systems in the codebase?

Keep questions focused. 3-5 questions max per round. Stop when you have enough to write a brief.

## Step 2: Write Brief

Write `.tmp/design-chat/brief.md` containing:

- Goal (1-2 sentences)
- Scope (in/out)
- Constraints
- Deliverables
- Relevant codebase context (file paths, package names, patterns observed)

This file is the seed for Codex.

## Step 3: Codex Drafts Design

Run Codex to create the initial design:

```
codex -s danger-full-access exec "Read .tmp/design-chat/brief.md. Based on the brief, \
create a detailed design document at .tmp/design-chat/design.md. \
Include: overview, proposed approach, data flow, key interfaces/types, \
file structure, edge cases, and open questions. \
For every major decision, state WHY — what alternatives were considered and why they were rejected. \
The reviewer will challenge any decision without a clear rationale. \
Read relevant source files referenced in the brief to ground the design in existing code."
```

Read `.tmp/design-chat/design.md` after Codex completes.

## Step 4: Review

Read the design. Be adversarial — your job is to stress-test the reasoning, not rubber-stamp it.
Challenge WHY before evaluating HOW. A well-implemented bad idea is worse than a rough sketch of the right idea.

Write `.tmp/design-chat/review-N.md` (N = current round) with:

- **Verdict**: `approved` or `revise`
- **Why-challenges**: question the rationale behind key decisions:
  - Why this approach over alternatives? Were alternatives considered?
  - Why is this problem worth solving this way? Is the complexity justified?
  - Why these abstractions/boundaries? What would break if they were different?
  - Flag any decision that lacks stated rationale as `must-fix`.
- **Strengths**: what the design gets right (be specific)
- **Issues**: problems, gaps, contradictions, or missed requirements — each with:
  - severity: `must-fix` or `suggestion`
  - description of the issue
  - what the fix should address (not how — let Codex decide the how)
- **Questions**: anything unclear or underspecified

Criteria for `approved`:
- Every major decision has a stated rationale (why, not just what)
- Alternatives were considered and rejection reasons are clear
- All requirements from the brief are addressed
- No `must-fix` issues remain
- Approach is feasible given constraints
- Key interfaces/types are well-defined
- Edge cases are handled or explicitly deferred with rationale

## Step 5: Codex Revises (if verdict = revise)

Run Codex to revise:

```
codex -s danger-full-access exec "Read .tmp/design-chat/design.md (current design) \
and .tmp/design-chat/review-N.md (review feedback). \
Revise the design in-place at .tmp/design-chat/design.md to address all must-fix issues. \
Pay special attention to why-challenges — if the reviewer questioned your rationale, \
strengthen it with concrete reasoning or change the approach if you cannot justify it. \
Do not hand-wave — if you chose X over Y, explain what makes X better for THIS problem. \
Consider suggestions but use your judgment on those. \
Add a changelog section at the bottom noting what changed in this revision."
```

Read the revised design after Codex completes.

## Step 6: Loop or Finish

- If verdict was `revise` → go back to Step 4 (increment N).
- If verdict is `approved` → proceed to Report.

Cap at **5 review rounds**. If still not `approved` after 5 rounds:
- Report to user with current state
- List remaining issues
- Let user decide whether to continue, adjust requirements, or accept as-is

## Report

Present to user:

- **Design file**: `.tmp/design-chat/design.md`
- **Review rounds**: count + final verdict
- **Summary**: 3-5 sentence overview of the design
- **Remaining concerns**: any `suggestion`-level items not addressed, or open questions

Ask the user if they want to move the design to a permanent location (e.g., `docs/`).

## Rules

- NEVER edit `design.md` yourself — only Codex writes/revises it.
- NEVER skip the review step — always read and evaluate before approving.
- NEVER approve a design with `must-fix` issues remaining.
- ALWAYS ground reviews in the original brief — don't introduce new requirements mid-loop.
- ALWAYS let Codex read relevant source files — don't paste large code blocks in prompts.
- If Codex fails or times out, retry once. If still fails, report to user.
- Keep Codex prompts focused. Reference file paths, don't inline content.
