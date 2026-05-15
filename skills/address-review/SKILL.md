---
name: address-review
description: Triage a single code-review comment. First verify the claim against source/tests; if invalid or not worth fixing, report the analysis and stop. If valid, enter plan mode, design the fix, and exit plan mode to get user confirmation before any edit.
---

# Address Review

Given one review comment, decide whether it should be fixed. NEVER assume the reviewer is right. NEVER edit code before user confirms the plan.

## Input

User supplies the review comment as text or paste. May include file path, line number, code snippet, or PR link. If file/line is missing and the target is not obvious from the text, ask the user once.

## Workflow

1. Parse the comment. Extract claim, referenced files/lines, and any suggested change.
2. **Investigate validity** (read-only, no edits):
   - Read the referenced code and its callers/tests.
   - Check whether the claim conflicts with intentional invariants, API contracts, repo conventions, or existing tests.
   - Determine outcome:
     - `invalid` — claim is wrong, contradicted by code/tests, or based on a misreading
     - `valid` — claim is correct and a fix improves correctness/quality
     - `subjective` — naming/style/wording/architecture call with no correctness issue
     - `already-fixed` — branch already addresses it
     - `constraint-driven` — only resolvable with info outside the code (deadlines, ownership, policy)
3. **If outcome is not `valid`**: stop. Report analysis to the user (see Report). Do NOT enter plan mode. Do NOT edit. For `subjective` or `constraint-driven`, present the trade-off and ask the user what to do — do not decide for them.
4. **If outcome is `valid`**: enter plan mode (`EnterPlanMode`).
   - Inside plan mode, do further read-only investigation as needed: what files change, what tests cover or need to cover the fix, blast radius.
   - Draft the smallest fix that addresses the verified issue. No opportunistic cleanup.
   - Exit plan mode (`ExitPlanMode`) with the plan for user approval.
5. Wait for user confirmation. Only edit after approval.

## Investigation rules

- Prefer the smallest proof that establishes validity. Read the file, grep for callers, run a focused test — do not boil the ocean.
- If existing tests already cover the claimed behavior, run them. Their pass/fail is strong evidence.
- If the claim is behavioral and uncovered, note that a regression test should accompany the fix (include it in the plan).
- NEVER add a test that just encodes the reviewer's preference when behavior is intentionally unspecified.

## Report (when NOT entering plan mode)

Plain text, no headings required. Include:

- Reviewer's claim (one line)
- Outcome: `invalid` / `subjective` / `already-fixed` / `constraint-driven`
- Evidence: file:line references, test names, or quotes from the code that justify the call
- Recommendation: leave as-is, ask reviewer to clarify, defer, or user-decides (for subjective/constraint-driven)

## Plan content (when entering plan mode)

The plan presented via `ExitPlanMode` should cover:

- Verified problem (one line) and where it lives (file:line)
- Files to change and the shape of the change
- Tests to add or run
- Anything intentionally NOT touched and why
