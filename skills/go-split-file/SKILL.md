---
name: go-split-file
description: Split a large Go file into smaller files with logical groupings. Analyzes code structure and extracts cohesive units (types, functions, interfaces) into separate files within the same package.
---

# Go Split File

Split a large `.go` file into multiple smaller files, grouping related declarations logically. All files remain in the same package.

## Input

User provides a `.go` file path. If not provided, ask for it.

Optional: user specifies desired grouping strategy or target file count. Default: auto-detect logical groupings.

## Step 1: Analyze the file

Read the entire file. Identify:

- **Package name** — all output files share this.
- **Top-level declarations** — functions, types/structs, interfaces, constants, variables, `init()` functions.
- **Method receivers** — map each method to its receiver type.
- **Dependency graph** — which declarations reference which others within the file.
- **Logical groups** — declarations that belong together (e.g., a struct + its methods + its constructor, an interface + closely related types).
- **Build tags / generate directives** — `//go:build`, `//go:generate` lines at file top.

## Step 2: Propose groupings

Create a split plan. Each proposed file gets:

- **Filename** — snake_case, derived from the primary type/function in the group. Must end in `.go`.
- **Contents** — list of declarations moving to this file.
- **Rationale** — one-line explanation of why these belong together.

### Grouping rules

1. A struct + all its methods (by receiver) + its `New*` constructor → same file. Filename: snake_case of the type name (e.g., `TokenSet` → `token_set.go`).
2. An interface + closely related types that exist solely to implement it → same file (unless implementations are large enough to warrant their own files).
3. Constants/variables used by only one group → move with that group.
4. Constants/variables used across multiple groups → keep in a shared file (e.g., `constants.go`, `types.go`).
5. `init()` functions → stay in the original filename or move with the group they initialize.
6. Test files: if splitting `foo.go`, corresponding test declarations in `foo_test.go` should be split to match (e.g., `bar.go` gets `bar_test.go`). Ask user before splitting test files.
7. Each resulting file should ideally be 50–200 lines. Avoid files under 20 lines unless they contain a single cohesive unit.
8. Preserve doc comments — they move with the declaration they document.
9. Build tags and generate directives: only include in files that need them.

## Step 3: Present plan and get approval

Show the user a table:

| New file | Declarations | Lines (approx) | Rationale |
|----------|-------------|-----------------|-----------|

Ask: "Proceed with this split? You can adjust groupings before I start."

NEVER proceed without user approval.

## Step 4: Execute the split

For each new file in the plan:

1. Write the `package` declaration.
2. Copy the relevant declarations in their original order.
3. Preserve all comments, doc strings, and blank-line spacing from the original.
4. Do NOT manually write import blocks — `goimports` handles this in Step 5.

After all new files are created:

5. Remove extracted declarations from the original file.
6. If the original file is now empty (or contains only the package declaration), delete it.

## Step 5: Verify

1. Run `goimports -w` on all new/modified `.go` files in the package directory.
2. Run `go build ./...` from the module root to confirm compilation.
3. Run `go vet ./...` to catch issues.

If verification fails, diagnose and fix. Common issues:
- Circular dependencies → cannot happen within same package, but check for build tag issues.
- Unexported symbols referenced across files → fine in Go (same package), no action needed.
- Duplicate declarations → a declaration was copied but not removed from the original.

## Step 6: Report

Show the user:

- List of files created/modified/deleted.
- Line counts before and after.
- Any manual follow-up needed (e.g., updating documentation, build configs).
