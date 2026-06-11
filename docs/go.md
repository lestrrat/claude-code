# Go

## Source Lookup

Standard library and runtime source: `go env GOROOT` returns the root directory. Use this to read Go source code when needed.

## Testing

- Prefer using github.com/stretchr/testify for testing over vanilla testing package, where applicable.
- Only use github.com/stretchr/testify/require and not github.com/stretchr/testify/assert.
- Unless there is no other way around it, write tests in the external package form `xxx_test` instead of `xxx`.
- Use `t.Context()` instead of `context.Background()` in tests. The test context is cancelled when the test ends.

## Style

- Do not use named return values.
- For existence-check maps, use `map[T]struct{}` not `map[T]bool`.
- Prefer early returns from functions, and early continue/break from loops/blocks
- Prefer shorter `if` branch first. In `if/else`, put shorter/simpler clause on top.
- Prefer removing `else` via early return/continue/break when possible.

## Design

- Prefer interfaces over function callbacks for public APIs, struct fields, and dependency injection. Interfaces are easier to mock in tests and compose with other abstractions. For example, prefer `http.Handler` (interface) over `http.HandleFunc` (function callback) — the interface version can carry state, implement multiple methods, and is easier to wrap with middleware.
- Simple one-off closures (e.g., `sort.Slice` comparators, short-lived callbacks in local scope) are fine and don't need an interface.
- **Entry-point methods must be goroutine-safe to invoke.** A main API entry point (`Compile()`, `Resolve()`, `Run()`, etc.) must be callable as `go obj.Compile()` — concurrent invocations on the same receiver must not race. To achieve this: treat the **receiver as immutable config**, and keep all per-call/process state **decoupled from the receiver** — it lives in locals, parameters, and return values, never in mutable fields on the receiver. One configured object can then be shared and fired across many goroutines safely. Corollary: don't stash mutable run state on the receiver "for convenience"; thread it through call parameters (or context) instead.
  - Canonical example: `lestrrat-go/acidns` `UDPServer` — receiver holds only validated config (doc: "does NOT carry runtime state… may be Run multiple times to spawn independent instances"); `Run(ctx) (*UDPController, error)` allocates the per-call runtime-state object (`udpLoop`) **locally inside the call**, hands it to the spawned goroutine, and returns a handle. The receiver is never mutated. Other reference repos for house style: `lestrrat-go/jwx`, `lestrrat-go/helium`.
  - Options are folded into a private `cfg` struct **in the constructor** (`NewXxx(...)`), not at call time, via `lestrrat-go/option/v3` (typed marker-interface options + `ident` structs).
