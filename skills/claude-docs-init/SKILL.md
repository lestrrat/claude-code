---
name: claude-docs-init
description: Initialize .claude/docs/ and CLAUDE.md for a repository. Analyzes the codebase and creates agent-optimized documentation so Claude Code can navigate, modify, and test the project effectively.
---

# Claude Docs Init

Create `.claude/docs/` files and a `CLAUDE.md` that give future agent sessions the context they need to work effectively in this repository. All output is agent-optimized: terse, unambiguous, machine-parseable.

## Workflow

### 1. Analyze the repository

Read the project root to determine:

- **Language/ecosystem** (Go module, npm package, Python project, Rust crate, etc.)
- **Build system** (go build, make, npm, cargo, etc.)
- **Project structure** (monorepo, single package, multi-package, CLI + library, etc.)
- **Test framework** (go test, jest, pytest, cargo test, etc.)
- **CI/CD** (.github/workflows, Makefile targets, etc.)
- **Existing docs** (README, CONTRIBUTING, existing CLAUDE.md)

### 2. Generate core docs (all projects)

These docs apply to every repository regardless of language:

| Doc | Content |
|-----|---------|
| `packages.md` | Package/module map: purpose, public API (key functions/types with signatures), key files. One section per package/module. |
| `testing.md` | Test data layout, test helpers, how to run tests, golden file patterns, env vars, skip maps, CI commands. |
| `dependencies.md` | Internal dependency graph between packages/modules. Arrows show import direction. Layer grouping (leaf → core → processing → application). |

### 3. Generate ecosystem-specific docs

Based on language/ecosystem detected in step 1, generate additional docs from the applicable section below.

### 4. Generate CLAUDE.md

Create `CLAUDE.md` at project root with:

1. One-line project description
2. **Pre-Read Rules** table — maps triggers to doc files. Every doc from steps 2-3 must appear.
3. **Cache Maintenance** section — rules for keeping docs in sync + table mapping each doc to its update trigger.

### 5. Present summary

Show the user what was created and ask them to review.

---

## Ecosystem: Go Module

Detect: `go.mod` in project root.

### Additional analysis

- Run `go list ./...` to enumerate packages.
- For each package, read exported symbols via source (or `go doc ./pkg`).
- Check for `cmd/` directories (CLI tools).
- Check for `internal/` packages.
- Check for golden test patterns (`testdata/`, `.expected`, `.golden` files).
- Check for build tags, generate directives.

### Additional docs

| Doc | Content | When |
|-----|---------|------|
| `error-formatting.md` | Error types, format strings, error wrapping patterns, ErrorHandler interfaces. | Project defines custom error types or formatting. |
| `cli.md` | CLI flags, subcommands, pipeline, exit codes. | Project has `cmd/` or `main.go` CLI entry points. |
| `internals.md` | Core data structures, state machines, processing pipelines. | Project has complex internal architecture (parser, compiler, runtime, etc.). |
| `data-model.md` | Key types, struct hierarchies, interface contracts, node/object graphs. | Project defines a rich type hierarchy (DOM, AST, IR, etc.). |
| `validation.md` | Compile→validate flow, schema data model, error reporting. | Project implements schema/validation logic. |
| `parity.md` | Feature status vs reference implementation, test counts, known gaps, limitations. | Project reimplements or ports another system. |

### packages.md format (Go)

For each package:

```
## pkgname/

One-line purpose.

- **FuncName(params) → (returns)** — description
- Key types: `Type1`, `Type2`
- Options/config: `WithX()`, `WithY()`
- Files: `file1.go`, `file2.go`
- Imports: pkg1, pkg2
```

Rules:
- Include `error` in return signatures when present.
- List only public API. Skip unexported helpers.
- Group related functions (e.g., Parse/ParseReader/ParseFile together).
- For large packages, focus on entry points and key types — not every exported function.

### testing.md format (Go)

Include:
- Test package naming convention (`xxx_test` vs `xxx`).
- Test data directory layout (tree diagram).
- Golden file naming/extensions.
- Common test helpers with signatures and purpose.
- Environment variable filters for running test subsets.
- Build tags used in CI.
- How to run: `go test ./...`, specific flags, race detector.

### dependencies.md format (Go)

```
pkg → dep1, dep2
  → transitive (via dep1)
```

Then group by layer:
- Leaf packages (no internal deps)
- Core layer
- Processing layer (depends on core)
- Composition layer (depends on processing)
- Application layer (cmd/, main)

---

## Ecosystem: Node.js / TypeScript

Detect: `package.json` in project root.

### Additional analysis

- Read `package.json` for scripts, dependencies, workspaces.
- Check for `tsconfig.json` (TypeScript).
- Check for monorepo tools (lerna, nx, turborepo).
- Enumerate exports from `index.ts`/`index.js` or `package.json` exports field.

### Additional docs

| Doc | Content | When |
|-----|---------|------|
| `api.md` | REST/GraphQL endpoint map, request/response types, auth. | Project is a web server or API. |
| `components.md` | Component tree, props interfaces, state management. | Project is a React/Vue/Svelte app. |
| `config.md` | Environment variables, config files, feature flags. | Project has significant runtime configuration. |

### packages.md format (Node.js)

For each package/workspace:

```
## package-name

One-line purpose.

- **export function funcName(params): ReturnType** — description
- Key types: `Interface1`, `Type2`
- Entry: `src/index.ts`
- Files: `src/router.ts`, `src/middleware.ts`
```

---

## Ecosystem: Python

Detect: `pyproject.toml`, `setup.py`, or `setup.cfg` in project root.

### Additional analysis

- Read `pyproject.toml` for project metadata, dependencies, entry points.
- Check for `src/` layout vs flat layout.
- Check for type hints (`py.typed`, `*.pyi` stubs).
- Enumerate modules via directory structure.

### Additional docs

| Doc | Content | When |
|-----|---------|------|
| `api.md` | Endpoint map, serializers, auth. | Django/Flask/FastAPI project. |
| `cli.md` | CLI commands, arguments, entry points. | Click/argparse/typer CLI. |
| `config.md` | Settings, environment variables, config hierarchy. | Project uses settings module or env vars. |

---

## Ecosystem: Rust

Detect: `Cargo.toml` in project root.

### Additional analysis

- Read `Cargo.toml` for workspace members, features, dependencies.
- Check for `src/lib.rs` vs `src/main.rs`.
- Enumerate public API via `pub` exports.

### Additional docs

| Doc | Content | When |
|-----|---------|------|
| `unsafe.md` | Unsafe blocks, FFI boundaries, safety invariants. | Project uses `unsafe`. |
| `features.md` | Cargo features, conditional compilation, feature gates. | Project has non-trivial feature flags. |

---

## Doc Authoring Rules

All docs MUST follow these rules:

- Optimize for agent/LLM consumption, not human readability.
- Terse, imperative, unambiguous. No filler, hedging, or politeness.
- Use `→` for cause/effect. Use `NEVER`/`ALWAYS`/`MUST` for hard rules.
- Prefer tables and bullet lists over prose.
- One rule per bullet. No compound sentences joining unrelated rules.
- Omit articles (`a`, `an`, `the`) where meaning is clear.
- No redundant examples — one example per pattern is enough.
- No motivational text. State rules only.
- Commands/paths in backticks.

## CLAUDE.md Format

```markdown
<!-- Agent-consumed file. Keep terse, unambiguous, machine-parseable. -->

# Project Name

One-line description.

## Pre-Read Rules

Read the linked doc BEFORE working in that area. No exceptions.

| Trigger | Doc |
|---------|-----|
| {trigger description} | `.claude/docs/{file}.md` |
...

## Cache Maintenance

These docs cache repository state. Still read source before modifying code.

1. When your changes affect a doc below, update it in the same commit.
2. If you notice any doc is wrong or stale — even on an unrelated task — fix it immediately.

| Doc | Update trigger |
|-----|----------------|
| `{file}.md` | {what changes require updating this doc} |
...
```

## Rules

- NEVER overwrite an existing CLAUDE.md without showing the user a diff first.
- If CLAUDE.md already exists, merge new pre-read rules and cache maintenance entries into it.
- Read actual source code to populate docs — do not guess or hallucinate APIs.
- For large projects (>50 packages), focus on the most important packages and note "see source for full list" for the rest.
- Each doc file should be self-contained. No cross-references between docs except in CLAUDE.md's pre-read table.
- Keep individual doc files under 300 lines. Split if larger.
