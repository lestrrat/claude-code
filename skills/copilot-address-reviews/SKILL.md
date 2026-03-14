---
name: copilot-address-reviews
description: Evaluate and address GitHub Copilot PR review items for a GitHub pull request. Use when user provides a GitHub PR link and wants Copilot review comments checked, verified, fixed, committed, and summarized. Fetch review items with `gh`, verify each claim against source/tests before changing code, ask user before making subjective or constraint-driven changes, then work items one by one.
---

# Copilot Address Reviews

Given a GitHub PR link, process Copilot review items one at a time. NEVER assume review is correct. NEVER change code only to satisfy review text.

## Inputs

- PR URL
- Local checkout for PR branch, or clear path to fetch/switch to it
- User confirmation for subjective, design, or constraint-driven items

## Workflow

1. Resolve bundled scripts relative to directory containing this `SKILL.md`, not current working directory. `cd` to skill directory first when needed.
2. Run `./scripts/fetch-review-items.sh <pr-url>` from skill directory.
3. Read `.tmp/copilot-review-items.json` as primary worklist of unresolved items only.
4. Inspect `.tmp/copilot-review-items.raw.json`, `.tmp/gh-pr-view.json`, and `.tmp/gh-pr-review-threads.json` when dedup or extraction needs verification.
5. Select next unhandled unresolved item from worklist. NEVER work resolved items.
6. For current item, choose exactly one outcome before moving on:
   - valid → fix
   - invalid → no code change
   - subjective/constraint-driven/ambiguous → ask user
   - already fixed on branch → no code change
7. After each valid item:
   - make smallest code change that addresses verified issue
   - run focused tests first
   - add/update tests when they materially prove claim or prevent regression
   - run broader relevant tests when change touches shared behavior
   - commit only files for that item
8. After each invalid or already-fixed item:
   - record why no code change is needed
   - if current source/tests do not already make decision obvious, add concise code comment near relevant logic so future reviewers can see reasoning or constraint
   - do not make speculative edits
9. Mark current item handled, then look up whether more unhandled items remain.
10. If more items remain, return to step 5. Continue until worklist is empty.
11. After all items, report every item, decision, evidence, and commit hash when applicable.

## Scripts

Resolve bundled resources relative to this `SKILL.md`. Script directory = `scripts/` next to this file.

- Installed skill layout: skill directory contains `SKILL.md` + `scripts/` as siblings.
- Repository layout: skill directory = `skills/copilot-address-reviews/`.
- Prefer `cd` to skill directory, then run `./scripts/...`.
- NEVER assume current working directory already is skill directory.

### `scripts/fetch-review-items.sh`

- Entry point for PR review item discovery.
- Use `gh` CLI only. NEVER scrape HTML.
- Save raw GitHub output to `.tmp/` first.
- Fetch PR metadata + all pages of review threads/comments.
- Normalize unresolved Copilot-authored review comments into `.tmp/copilot-review-items.raw.json`.
- Invoke `scripts/dedup_review_items.py` to write `.tmp/copilot-review-items.json`.
- If GitHub response shape is incomplete for current PR, extend GraphQL query or inspect raw JSON before changing code.

### `scripts/dedup_review_items.py`

- Python scope is dedup only.
- Input: normalized raw item JSON array.
- Output: deduped JSON object with representative items + grouped ids.
- NEVER expand Python script into code validation, test selection, or fix synthesis.

## Fetch Review Items

- Start with `scripts/fetch-review-items.sh <pr-url>`.
- Treat `.tmp/copilot-review-items.json` as candidate worklist of unresolved items, not truth.
- Inspect Copilot review submissions as well as inline discussion comments. Do not assume a `#pullrequestreview-...` URL is represented directly in normalized output.
- If user points to review submission URL or review id, map it to attached inline review comments and confirm those comments are present in worklist before proceeding.
- Filter results to authors that represent GitHub Copilot review bots. Do not assume exact login string is stable if raw output shows another Copilot variant.
- Exclude resolved items from scope. Ignore them unless raw GitHub output suggests resolution state is wrong.
- Capture for each item:
  - review/comment id
  - file path + line/range
  - exact claim/request
  - thread state if available
- Read raw GitHub output when:
  - review submission URL needs to be mapped to inline comments
  - dedup merged items unexpectedly
  - line/path metadata looks wrong
  - thread state affects whether item still needs work

## Validate Before Editing

Verify claim with source and tests before changing code.

### Code Analysis

- Read surrounding implementation, callers, tests, and PR diff context.
- Check whether review conflicts with intentional invariants, API contracts, compatibility rules, performance limits, or repository conventions.
- Prefer smallest proof that establishes whether review is valid.

### Test Strategy

- Use R/G testing for general development: make failing case visible first, then change code until test passes.
- If existing tests already cover claim, run them first.
- If claim is behavioral and uncovered, add focused test that fails before fix and passes after fix.
- If claim is not directly testable, explain why and use code-level reasoning instead.
- NEVER add a test that merely encodes Copilot preference when behavior is intentionally unspecified.

## Ask User Instead Of Deciding

Ask user before changing code when item is primarily about:

- naming, style, or readability with no correctness issue
- API shape, public behavior, or compatibility policy
- performance vs. simplicity tradeoff
- logging/error wording
- architectural direction or ownership boundaries
- possible arbitrary local constraint that cannot be verified from code/tests

When asking user, include:

- review item summary
- current behavior
- why item appears subjective or constraint-driven
- recommended options

## Fix Rules

- Keep fix scoped to verified issue.
- Avoid opportunistic cleanup unless required for fix or approved by user.
- If multiple Copilot items map to same defect, ask user before combining them into one commit.
- If current branch already addresses item, record it as already fixed and move on.

## Review Interaction

- NEVER post GitHub comments, review replies, review submissions, or issue comments on user's behalf.
- Report decisions to user in local output instead.
- If a GitHub comment would help, ask user first. Draft text only when user asks for it.

## Commit Rules

- One focused commit per addressed item.
- Stage only files relevant to current item.
- Write commit message around behavioral change, not around Copilot.
- Follow repository/user git rules before `git add` / `git commit`.
- Do not create no-op commit for rejected, subjective, deferred, or already-fixed items.

## Final Report

Report items in review order or grouped by file. For each item include:

- item identifier or file/line
- Copilot claim summary
- decision: fixed / rejected / user-confirmed / deferred / already fixed
- evidence: code reading, tests run, or user instruction
- commit hash for fixed items
