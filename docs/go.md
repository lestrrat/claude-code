# Go

## Source Lookup

Standard library and runtime source: `go env GOROOT` returns the root directory. Use this to read Go source code when needed.

## Testing

- Prefer using github.com/stretchr/testify for testing over vanilla testing package, where applicable.
- Only use github.com/stretchr/testify/require and not github.com/stretchr/testify/assert.
- Unless there is no other way around it, write tests in the external package form `xxx_test` instead of `xxx`.
- Use `t.Context()` instead of `context.Background()` in tests. The test context is cancelled when the test ends.

## Examples

Write user-facing usage examples as Go executable examples (`Example*` functions verified by `go test`) — NEVER as README-only snippets or untested markdown code blocks.

NEVER write an example as a standalone executable (`package main` + `func main()`) — except when the user explicitly requests one.

- Location: `examples/` directory at repo root. One concept per file.
- File name: `<package>_<function_or_topic>_example_test.go`.
- Package: `package examples_test`.
- Function name: `Example_<package>_<topic>()` — package-level; name need not match an exported symbol.
- Self-contained: minimal inline input data. No external files unless the feature requires them.
- Deterministic: end with exact `// Output:` block — `go test` verifies it.
- Error handling: `fmt.Printf("failed to <action>: %s\n", err); return`. NEVER `log.Fatal`/`panic`.
- Comments explain what and why, not restating code.
- Temp files when required: `os.MkdirTemp(".", ".tmp-<topic>-*")` + `defer os.RemoveAll(dir)`.
- Verify: `go test ./examples/` + `go vet ./examples/` must pass.

## File Naming & Layout

Defaults, not hard rules — deviate when a clearer structure fits. The build-constraint suffix rule is the one hard edge.

- Name files by responsibility. Filename = snake_case of the concern owned (`tree_builder.go`, `parser_entity_ref.go`). snake_case only — NEVER camelCase or hyphens.
- Consolidate related declarations into one file. Avoid one-file-per-micro-topic sprawl (`topic_one.go … topic_n.go`). Avoid files <~50 lines unless the file owns one cohesive concept.
- Soft size cap: handwritten source ~500–1000 lines → split by responsibility past ~1000; test files up to ~2000 → split by production-code area past that. Same figures as `go-package-reorg`/`go-test-reorg` skills.
- `_test.go` sits beside the file it tests, same base name: `foo.go` → `foo_test.go`. When one concern's tests outgrow the cap, split by aspect (`foo_<aspect>_test.go`) — NEVER by authoring batch (`coverage_round2_test.go`).
- Avoid layer/authoring-order suffixes — `_core`, `_impl`, `_base`, `_misc`, `_helpers`, `_internal`, `_v2`, `_round2`. They name how the file was built, not what it owns → rename to the responsibility, or merge into the file they back.
- Avoid grab-bag filenames — `util.go`/`misc.go`/`helpers.go`/`common.go`. Name by responsibility.
- OS/arch suffixes (`_linux.go`, `_amd64.go`, `_windows.go`, …) are RESERVED by the toolchain for build constraints. NEVER use as topic separators — they silently change which builds compile the file.
- A filename pass can't catch every smell — a well-named, well-sized file may still hold two concerns. Verdict from declarations inside, not from `ls`. Procedure: `go-package-reorg` skill.

## Style

- Do not use named return values.
- For existence-check maps, use `map[T]struct{}` not `map[T]bool`.
- Prefer early returns from functions, and early continue/break from loops/blocks
- Prefer shorter `if` branch first. In `if/else`, put shorter/simpler clause on top.
- Prefer removing `else` via early return/continue/break when possible.
- Don't wrap a single function/method call in a closure when the function itself can be passed directly. Pass `foo` instead of `func() { foo() }` or `func(x T) { foo(x) }` — the wrapper adds no value and obscures the call. (A closure that adapts signatures, binds extra args, or adds logic is fine.)

## Design

- Prefer interfaces over function callbacks for public APIs, struct fields, and dependency injection. Interfaces are easier to mock in tests and compose with other abstractions. For example, prefer `http.Handler` (interface) over `http.HandleFunc` (function callback) — the interface version can carry state, implement multiple methods, and is easier to wrap with middleware.
- Simple one-off closures (e.g., `sort.Slice` comparators, short-lived callbacks in local scope) are fine and don't need an interface.
- **Entry-point methods must be goroutine-safe to invoke.** A main API entry point (`Compile()`, `Resolve()`, `Run()`, etc.) must be callable as `go obj.Compile()` — concurrent invocations on the same receiver must not race. To achieve this: treat the **receiver as immutable config**, and keep all per-call/process state **decoupled from the receiver** — it lives in locals, parameters, and return values, never in mutable fields on the receiver. One configured object can then be shared and fired across many goroutines safely. Corollary: don't stash mutable run state on the receiver "for convenience"; thread it through call parameters (or context) instead.
  - Canonical example: `lestrrat-go/acidns` `UDPServer` — receiver holds only validated config (doc: "does NOT carry runtime state… may be Run multiple times to spawn independent instances"); `Run(ctx) (*UDPController, error)` allocates the per-call runtime-state object (`udpLoop`) **locally inside the call**, hands it to the spawned goroutine, and returns a handle. The receiver is never mutated. Other reference repos for house style: `lestrrat-go/jwx`, `lestrrat-go/helium`.
  - Options are folded into a private `cfg` struct **in the constructor** (`NewXxx(...)`), not at call time, via `lestrrat-go/option/v3` (typed marker-interface options + `ident` structs).
