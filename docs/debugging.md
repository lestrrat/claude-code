# Debugging

## Multi-Component Bug → Decompose First

Bug spans multiple functions/components or root cause unclear → decompose before fixing.

### Sequence

1. **Decompose** — identify sub-operations.
   - Composed: `foo(bar(baz()))` → `baz()`, `bar()`, `foo()`.
   - Sequential: `A → B → C` → test each step's output.
2. **Test innermost/earliest first** — minimal test per unit, leaf-inward / first-step-forward. Verify pass/fail independently.
3. **Locate fault** — first failing unit = likely root cause. All pass → check intermediate values between units.
4. **Regression test** — no existing test covers the bug → write minimal unit test reproducing it before fixing.
5. **Fix** — fix against failing test.
6. **Verify composition** — confirm full operation passes.

### Isolated Test Rules

- One unit per test. Assert only that unit's behavior.
- Self-contained. No shared fixtures/external state.
- Name after behavior: `TestBazReturnsValidToken` not `TestBaz`.
