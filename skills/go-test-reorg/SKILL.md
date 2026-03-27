---
name: go-test-reorg
description: Reorganize Go test files — consolidate related tests into subtests, convert to table-driven style, shorten excessive test names, and reposition tests to match implementation ownership. Args: <package-dir>
---

# Go Test Reorg

Reorganize Go test files in a package for clarity and maintainability. Consolidate related tests into subtests, prefer table-driven style, and eliminate excessively long test names. Keep test behavior unchanged.

## Input

User provides a Go package directory path. If not provided, ask for it.

## Step 1: Inventory

Read all `*_test.go` files in the target directory. For each test function, record:

- **Function name** — the `TestXxx` or `FuzzXxx` identifier.
- **What it tests** — the production function, method, or behavior under test.
- **Style** — standalone assertion, table-driven, subtest-based, or mixed.
- **Size** — approximate line count.
- **File location** — which `_test.go` file it lives in today.
- **Related tests** — other test functions that exercise the same or closely related production code.

Also note:

- **Helpers** — shared test helpers, fixtures, `TestMain`, custom assertions.
- **Special suites** — fuzz tests, generated tests, compatibility suites. These are left alone.
- **Test file sizes** — flag files already near the ~2000 line ceiling.

## Step 2: Design new test layout

### Consolidation rules

- Group tests that exercise the same production function/method/type under one `TestXxx` with subtests.
- Example: `TestParseSimple`, `TestParseNested`, `TestParseEmpty`, `TestParseError` → `TestParse` with subtests `"Simple"`, `"Nested"`, `"Empty"`, `"Error"`.
- If a group of tests share setup/teardown logic, that is a strong signal they belong together.
- Do NOT force unrelated tests together just to reduce top-level test count.

### Naming rules

- Top-level test names should be short and map clearly to the thing being tested: `TestParse`, `TestWrite`, `TestNewBuilder`.
- Subtest names describe the scenario: `"empty input"`, `"duplicate keys"`, `"nil receiver"`.
- Avoid redundancy between test name and subtest name. `TestParse/"parse empty"` is redundant — use `TestParse/"empty input"`.
- If the original long name carries important context, preserve that context in the subtest name, not the top-level name.

### Nesting rules

- Maximum 2 levels of subtests: `TestFoo/Bar` or `TestFoo/Bar/Baz`. Never deeper.
- Use the first subtest level for logical grouping (e.g., by method, by input category).
- Use the second level only when there is a natural sub-categorization (e.g., `TestWriter/"Escape"/"special chars"`).
- If you are tempted to nest 3+ levels, flatten by making the grouping name more specific.

### Table-driven style

- Prefer table-driven tests when a test function exercises the same code path with varying inputs/expectations.
- Table struct fields should have clear names: `name`, `input`, `want`, `wantErr` — not `a`, `b`, `expected`.
- Each table entry MUST have a `name` field used as `t.Run(tc.name, ...)`.
- Do NOT force table-driven style when tests have fundamentally different setup, teardown, or assertion logic. A sequence of `t.Run` subtests with distinct bodies is fine in that case.
- When converting, preserve the original test's assertion logic exactly. Do not simplify or "improve" assertions.

### File placement rules

- Tests should live in the `_test.go` file that matches the production file being tested: `parse.go` ↔ `parse_test.go`.
- If tests were in the wrong file (testing `parse.go` behavior but living in `writer_test.go`), move them.
- Merge small `_test.go` files that cover the same production file.
- Keep distinct special-purpose files separate: fuzz tests, generated test suites, compatibility tests.

### Sizing rules

- Test files can be up to ~2000 lines. Do not split prematurely.
- If a single test file exceeds ~2000 lines after consolidation, split by production-code area, not arbitrarily.
- Prefer fewer, larger test files over many tiny ones.

### Helper rules

- Shared test helpers stay in a dedicated helpers file (e.g., `helpers_test.go` or `testutil_test.go`).
- If a helper is used by only one test function, inline it or keep it adjacent to that test.
- `TestMain` stays in its own file or in the primary test file for the package.

## Step 3: Present plan and get approval

Show the user the proposed changes organized by production area:

| Production area | Current tests | Proposed structure | Notes |
|----------------|--------------|-------------------|-------|

For each consolidation, show:
- Which test functions merge into what.
- The new top-level name and subtest names.
- Which file they move to (if any).

Ask: "Proceed with this reorganization? You can adjust before I start."

NEVER proceed without user approval.

## Step 4: Execute

Apply changes according to the approved plan:

1. Convert standalone tests to table-driven or subtest form as planned.
2. Move tests to correct `_test.go` files.
3. Merge test files where planned.
4. Preserve all test assertions, setup, teardown, and skip logic exactly.
5. Do NOT manually write import blocks — `goimports` handles this in Step 5.
6. Remove emptied test files.
7. Preserve test helpers and `TestMain` in their designated locations.

## Step 5: Verify

1. Run `goimports -w` on all new/modified `_test.go` files.
2. Run `gofmt` on changed files.
3. Run targeted package tests: `go test -v -count=1 ./path/to/package/...`
4. Confirm same number of test cases pass as before (compare `-v` output).
5. Run broader tests as appropriate for package impact.

If verification fails, diagnose and fix before proceeding. A failing test after reorganization means a conversion error — fix it immediately.

## Step 6: Report

- Summarize changes by production area.
- List consolidations performed (old names → new structure).
- Report test pass/fail counts before and after.
- Call out any tests intentionally left unconsolidated and why.

## Non-Goals

- Do NOT change what is being tested or assertion logic.
- Do NOT add new test cases.
- Do NOT remove or skip existing test cases.
- Do NOT refactor production code.
- Do NOT change test package (`package foo_test` vs `package foo`) unless required by a move.
