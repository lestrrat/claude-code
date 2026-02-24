# Go

## Testing

- Prefer using github.com/stretchr/testify for testing over vanilla testing package, where applicable.
- Only use github.com/stretchr/testify/require and not github.com/stretchr/testify/assert.

## Style

- Do not use named return values.

## Design

- Prefer interfaces over function callbacks for public APIs, struct fields, and dependency injection. Interfaces are easier to mock in tests and compose with other abstractions. For example, prefer `http.Handler` (interface) over `http.HandleFunc` (function callback) — the interface version can carry state, implement multiple methods, and is easier to wrap with middleware.
- Simple one-off closures (e.g., `sort.Slice` comparators, short-lived callbacks in local scope) are fine and don't need an interface.
