# Go Server Lifecycle

Pattern for any long-lived background goroutine caller observes or stops: network listeners, workers, schedulers, file watchers, pub/sub consumers. NOT for short-lived helpers (`go func(){...}()` inside a request handler).

Reference impl: `github.com/lestrrat-go/acidns` — `server.go`, `internal/serverctl/serverctl.go`.

## Invariant

- `Run(ctx) (*Controller, error)` — bind/setup synchronously, spawn work goroutine, return immediately.
- Cancelling `ctx` is the ONLY way to stop. NEVER add `Start`, `Stop`, `Shutdown`, `Close`, `Quit` methods on server or controller.
- Returned `*Controller` is the sole handle. No other path into the running instance.
- `Run` returns ONLY bind-time/setup errors. Runtime termination errors → reported via controller, NEVER returned from `Run`.

## Controller Surface

Default trio — include unless app has specific reason not to:

| Method | Returns |
|--------|---------|
| `Done() <-chan struct{}` | Closed when work goroutine has fully exited |
| `Err() error` | Terminal error; nil for ctx-driven clean exit |
| `Wait() error` | `<-Done(); return Err()` |

Beyond those: per-app. Examples — bound `Addr()` (for port=0), drop counters, connection counts, queue depth, config-reload signal, app-specific introspection.

`ErrServerClosed` sentinel recorded on controller for ctx-driven clean exit → distinguishes clean shutdown from genuine failure. Sub-package transports re-export it so `errors.Is` matches across layers.

Multiple variants sharing infra (e.g. UDP/TCP/TLS/QUIC) → extract `Done`/`Err`/`Wait` plumbing into tiny internal package (acidns uses `internal/serverctl`), each variant's controller embeds `Core` by value. Implemented once, promoted automatically.

## By-Design Omissions

- NO `recover()` around handler / work-unit dispatch. Panics propagate. Operator chooses policy (process restart, structured log, crash-loop detector). Document this in package doc.
- NO "is-running" boolean. NO start-while-stopping guard. The ctx contract makes both unnecessary.
- NO second ctx parameter downstream. The ctx passed to `Run` owns the lifecycle.

## Skeleton

```go
package thing

import (
	"context"
	"errors"
	"sync/atomic"
)

var ErrServerClosed = errors.New("thing: server closed")

type Controller struct {
	done chan struct{}
	err  atomic.Pointer[error]
	// app-specific fields (counters, bound addr, ...)
}

func (c *Controller) Done() <-chan struct{} { return c.done }
func (c *Controller) Err() error {
	if p := c.err.Load(); p != nil {
		return *p
	}
	return nil
}
func (c *Controller) Wait() error { <-c.done; return c.Err() }

type Server struct {
	// config
}

func (s *Server) Run(ctx context.Context) (*Controller, error) {
	// bind/setup synchronously; return error on bind failure
	ctrl := &Controller{done: make(chan struct{})}
	go func() {
		defer close(ctrl.done)
		// work loop; select on ctx.Done()
		<-ctx.Done()
		err := ErrServerClosed
		ctrl.err.Store(&err)
	}()
	return ctrl, nil
}
```
