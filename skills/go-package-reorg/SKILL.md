---
name: go-package-reorg
description: Reorganize Go package file layout by actual responsibility. Inspects file contents, fixes naming mismatches, merges tiny files, splits oversized ones, consolidates tests, and regenerates generated files — all without changing behavior or public API. Args: <package-dir>
---

# Go Package Reorg

Reorganize Go files in a package by actual responsibility, not historical accident. Keep behavior unchanged. Keep package boundary unchanged. Prefer fewer, clearer files over fragmented file sprawl.

## Input

User provides a Go package directory path. If not provided, ask for it.

The package name is inferred from the `package` declaration in the `.go` files.

## Step 1: Inventory

Read all `.go` files in the target directory. For each file, identify:

- **Dominant responsibility** — from actual types/functions/methods/tests inside, NOT from filename.
- **Content/name mismatch** — filename does not reflect what the file actually contains.
- **Size** — flag files over ~1000 lines (too large) or under ~50 lines (candidate for merging).
- **Generated files** — files with `// Code generated` headers or `//go:generate` directives.
- **Test files** — `*_test.go` files and what they actually test.

## Step 2: Design new layout

Design a new file layout around coherent responsibility groups.

### File naming rules

- Align filename with dominant responsibility of code inside.
- Prefer themed filenames: `parser_element.go`, `writer_escape.go`, `tree_builder.go` — not `misc.go`, `stuff.go`, `util.go`.
- Keep naming consistent across sibling files.

### Sizing rules

- Target ~500–1000 lines per handwritten file.
- If one file grows too large, split by coherent responsibility, not arbitrarily.
- Do NOT create tiny placeholder files unless the file owns a real coherent concept.
- If code is too small to justify a standalone file, fold into closest coherent owner.
- Prefer merging five tiny leaf files into one coherent `node_leaf.go` over leaving many 20–50 line files.
- Prefer one more themed file over one oversized mixed-responsibility file.

### Placement rules

- Public API surface → dedicated API file, not mixed with deep internals.
- Writer/serializer code → `writer_*` or similarly explicit filenames.
- Context/state-machine internals → `*_context.go`, `*_state.go`, or similar.
- Subsystem declarations/types → group under subsystem-specific files (e.g., `dtd_attr.go`, `dtd_elem.go`).
- Namespace/base/tree helpers → with their owning concept, not scattered.
- Do NOT collapse unrelated concepts into one file merely to reduce file count.

### Test file rules

- Prefer simple pairings: `foo.go` ↔ `foo_test.go` when size stays reasonable.
- Merge test files when they cover the same implementation area and combined file remains readable.
- Keep distinct special-purpose suites separate (fuzz tests, lint tests, compatibility suites, generated suites).
- Move tests to file matching the API/behavior actually being tested.

### Generated file rules

- Generated files MUST include `gen` in filename.
- NEVER edit generated files by hand.
- Update owning generator directives or commands so regenerated output uses new filename.

## Step 3: Present plan and get approval

Show the user the proposed layout organized by responsibility area (not raw file list).

For each responsibility group, show:

| Responsibility | New file(s) | Source(s) | Notes |
|---------------|-------------|-----------|-------|

Include a summary of renames, merges, splits, and deletions.

Ask: "Proceed with this reorganization? You can adjust before I start."

NEVER proceed without user approval.

## Step 4: Execute

Apply renames/moves/splits/merges according to the approved plan:

1. Create new files with correct `package` declaration.
2. Move declarations preserving original order, comments, doc strings, and spacing.
3. Do NOT manually write import blocks — `goimports` handles this in Step 5.
4. Consolidate tests to match new ownership boundaries.
5. Remove emptied files.
6. Regenerate generated files after renames/splits.

## Step 5: Verify

1. Run `goimports -w` on all new/modified `.go` files.
2. Run `gofmt` on changed files.
3. Run targeted package tests first.
4. Run broader tests as appropriate for package impact.
5. If package has generated files, verify regeneration leaves committed state clean.

If verification fails, diagnose and fix before proceeding.

## Step 6: Report

- Summarize new layout by responsibility area.
- Call out any remaining intentional exceptions.
- Report verification performed.
- Update any package-local docs that describe file layout if they became stale.

## Non-Goals

- Do NOT redesign public API unless required for structural consistency.
- Do NOT make opportunistic behavior changes.
- Do NOT change semantics just because code moved.
