---
name: adversarial-review
description: Two-pass code review focused on security, API consistency/symmetry, and user experience. Pass 1 is hostile (assume the worst, surface everything). Pass 2 is a neutral audit that confirms, adjusts, or refutes each finding. Use when the user asks for a hostile, skeptical, or hard review — not a friendly pass.
---

# Adversarial Review

Two phases, in order. The hostile pass finds; the neutral pass filters. Skipping phase 2 means delivering noise.

## Phase 1 — Hostile Pass

Treat the code as a suspect, not a colleague. Goal: surface everything that *could* be wrong.

## Mindset

- Assume every input is malicious, every caller is confused, every assumption is wrong.
- "It works on happy path" is not evidence. Adversary picks the path.
- Author's intent does NOT excuse behavior. Only the code's actual behavior matters.
- No diplomatic softening. State the defect, the impact, the trigger.

## Scope

Resolve target before reviewing:

- PR / branch → `git diff <base>...HEAD` (and read full files for changed regions, not just hunks)
- Package / dir → enumerate files, read each
- Single file → read whole file

Always read enough surrounding context to understand callers and invariants. Hunks alone hide bugs.

## Sizing — pick a strategy

Measure surface BEFORE reading code:

- PR/branch: `git diff --stat <base>...HEAD` (changed-file count, lines added+removed)
- Dir/package: `find <path> -type f \( -name '*.go' -o -name '*.ts' -o ... \) | wc -l` and `wc -l <files>`

Pick by the larger of file count or LOC:

| Surface | Strategy |
|---------|----------|
| ≤ 5 files AND ≤ 1000 LOC | **Single-pass**: review all three lenses yourself |
| 6–30 files OR 1000–5000 LOC | **Parallel by lens**: spawn 3 subagents (security, api, ux), each covers the full target |
| 30–200 files, single package or small cluster | **Parallel by lens × area**: subdivide each lens across bounded areas (one subagent per lens × area) |
| > 200 files, whole-repo audit, or sprawling multi-package | **Triage-then-depth** (see "Whole-codebase mode" below) |

A whole-codebase adversarial review IS in scope. Do not narrow the target, sample a "representative subset", or push back on size. Pick the strategy and dispatch. Coverage gaps go in the "Unreviewed" section, not in a refusal.

In parallel mode, you are a **dispatcher**, not a reviewer. Spawn subagents in a single parallel Agent-tool block, wait for all to finish, then merge their outputs. Do NOT also review the code yourself — that produces duplicate findings and burns the main context. Your only Phase 1 reading is whatever sizing requires.

**Bounded parallelism**: dispatch at most ~8 subagents per Agent-tool block. For larger fan-outs, run waves of 8, merging output between waves. This keeps each subagent's findings reviewable and avoids overwhelming the runtime.

## Whole-codebase mode

Triggered by the > 200 files / whole-repo row. The codebase is too big to deep-audit every file with equal rigor in one pass; coverage is by tier, not uniform.

### Step 1 — Map risk surfaces

Spawn ONE `Explore` subagent to enumerate the codebase and rank files into tiers:

- **T1 (hot)**: untrusted-input entry points (HTTP/RPC handlers, message consumers, file parsers), auth + session code, crypto, deserialization, anything touching secrets/credentials, `unsafe` blocks, FFI/CGO, raw SQL, shell exec, template rendering, IPC.
- **T2 (warm)**: business logic the T1 surfaces call into, persistence layer, internal RPC, background jobs, anything mutating shared state.
- **T3 (cold)**: pure utilities, type defs, generated code, tests, docs, vendored deps.

Output: `.tmp/adversarial-review-tiers.md` with files grouped by tier, plus a short rationale per tier. Subagent prompt should explicitly say "do NOT review code — only classify by risk surface".

### Step 2 — Depth-audit T1

Run the full **parallel-by-lens × area** flow on T1 files only. All three lenses, full rigor, no severity floor.

### Step 3 — Breadth-scan T2

Spawn one subagent per lens with a tightened prompt:

```
This is a BREADTH SCAN, not a deep audit. Cover the assigned files for
the top defect classes of your lens only — do not exhaustively enumerate.

Lens: <LENS>
Severity floor: MEDIUM (drop LOW findings; raise borderline cases instead
of recording nits).

Top defect classes to look for:
  security → injection, missing auth, secret leaks, broken crypto
  api     → broken symmetric pairs, inconsistent error/return shapes,
            mixed naming for the same concept
  ux      → footguns, silently-wrong defaults, missing required-init traps

Otherwise follow Phase 1 rules from the SKILL.
```

### Step 4 — Spot-check T3

ONE subagent does a rapid pass for CRITICAL-only findings across T3: hardcoded secrets, obvious injection, world-writable artifacts, panics on user input, committed `.env`-style files. Anything below CRITICAL is dropped.

### Step 5 — Merge and Phase 2

Merge all tier outputs into the standard `.tmp/adversarial-review-findings.md`, tagging each finding with its tier (`[T1]`, `[T2]`, `[T3]`). Run **sharded Phase 2** as defined below. Sort chunks so T1 findings get audited first — that's where confirmation matters most.

The final report's "Unreviewed" section must explicitly state what tiering chose to scan-only or skip, so the user can escalate any tier on a follow-up run.

## Parallel Phase 1 — dispatcher protocol

For each lens, spawn one subagent (`subagent_type: Explore` — read-only is sufficient for Phase 1). Issue ALL subagent calls in a **single parallel Agent-tool block**.

Subagent prompt template:

```
You are running Phase 1 of an adversarial code review. Lens: <LENS>.

Read /home/<user>/.claude/skills/adversarial-review/SKILL.md and apply
ONLY the "<LENS>" subsection of "Lenses". Do not review the other lenses.

Repository root: <absolute path>
Review target: <git ref / files / dir as given by user>
Files in scope: <explicit list, or the command that produces it>
Area assignment (sharded mode only): <subset of files this subagent owns>

Read each in-scope file fully. Read enough surrounding code (callers,
init, validators, middleware, type defs) to make accurate claims about
reachability and invariants.

Output: write findings to .tmp/adversarial-review-findings-<lens>[-<area>].md
using the format, severity scale, and ID prefixes (SEC-/API-/UX-) defined
in the SKILL. Number sequentially within your lens (and area, if sharded).

End with an "Unreviewed" section listing what you did NOT examine and why.

Do NOT edit code. Do NOT verify findings — that is Phase 2's job. Bias
toward overclaiming.
```

After all subagents return, the dispatcher:

1. Concatenates lens files into `.tmp/adversarial-review-findings.md`.
2. Dedupes: same `file:line` + same root cause → keep the more specific finding, drop the duplicate. Different defects at the same line stay separate.
3. Renumbers if necessary so IDs remain unique within each lens.
4. Merges all "Unreviewed" lists.

If a subagent returns a thin or empty report for a lens that obviously has surface (e.g., security lens on a package with HTTP handlers), re-dispatch it with a sharper file list — do not paper over with your own findings.

## Lenses

Apply each lens explicitly. Do NOT collapse them — each finds different defects.

### 1. Security

Check, in order:

- **Input trust**: Any value from user / network / file / env treated as safe? Injection (SQL, shell, template, header, log, path traversal, SSRF, XXE, deserialization).
- **Auth**: Authentication present where required? Authorization checked AFTER authentication? IDOR (object refs without ownership check)? Privilege escalation paths?
- **Secrets**: Hardcoded keys, tokens, passwords? Secrets logged, returned in errors, or sent to telemetry? `.env` / config files committed?
- **Crypto**: Custom crypto? Weak algos (MD5, SHA1 for security, DES, ECB)? Hardcoded IVs / nonces? `math/rand` where `crypto/rand` required? Cert verification disabled?
- **Concurrency**: TOCTOU between check and use? Shared mutable state without sync? Map writes without lock? Goroutine leaks?
- **Resource limits**: Unbounded loops, allocations, recursion, request body reads, regex on user input (ReDoS)? Missing timeouts on network/IO?
- **Error info leakage**: Stack traces / internal paths / DB errors returned to clients?
- **Dependencies**: New deps — known CVEs? Maintained? Pinned? Typosquat risk?

### 2. API Consistency + Symmetry

Check across the package / module, not just the changed function:

- **Naming**: Same concept named the same way everywhere? `Get`/`Fetch`/`Load` mixed for same operation? Plural vs. singular for collections?
- **Parameter order**: `ctx` first? Receiver/subject before modifier? Same order across sibling funcs?
- **Symmetric pairs**: `Open`/`Close`, `Lock`/`Unlock`, `Begin`/`Commit`+`Rollback`, `Subscribe`/`Unsubscribe`, `Add`/`Remove`, `Create`/`Delete`, `Encode`/`Decode`, `Marshal`/`Unmarshal` — both halves present? Identical signatures where applicable?
- **Return types**: Error position consistent (last)? `(T, bool)` vs. `(T, error)` mixed for similar lookups? Nil vs. zero-value vs. error conventions consistent?
- **Optionality**: Options pattern used the same way? Required vs. optional split consistent? Defaults documented and applied uniformly?
- **Idempotency**: Operations that should be idempotent actually are? Retries safe?
- **Error types**: Sentinel errors vs. typed errors vs. wrapped — pattern consistent? Caller can distinguish cases it needs to?
- **Visibility**: Exported surface minimal? Internals leaked through return types (e.g., returning concrete `*Foo` when interface suffices, or vice versa)?

### 3. User Experience

"User" = downstream caller, integrator, operator, end user — whichever applies. Check each that applies:

- **Footguns**: Easy to misuse correctly? Zero value usable or trap? Required init step that compiles fine if skipped?
- **Errors**: Message tells caller what went wrong AND what to do? Or just "invalid input"? Wrapped errors preserve cause? Caller can programmatically handle (typed/sentinel) AND human can read (message)?
- **Surprises**: Function name implies one thing, does another? Side effects undocumented? Mutates input? Blocks unexpectedly? Allocates unexpectedly?
- **Defaults**: Default behavior safe? Or does silent fallback hide bugs?
- **Discoverability**: Required option / required call order obvious from signature? Or only from reading source?
- **Docs vs. behavior**: Doc comment matches actual behavior? Examples compile and run? Edge cases (nil, empty, zero, negative) documented?
- **Observability**: Failures debuggable from logs/metrics alone, or does user need a debugger?
- **Migration**: Breaking change? Deprecation path? Old + new coexist?

## Phase 1 Output (intermediate, NOT the final report)

Write findings to `.tmp/adversarial-review-findings.md`. One section per lens. Within each section, one finding per bullet:

```
[ID] [SEVERITY] <file>:<line> — <one-line defect>
  Trigger: <how to reproduce / when this fires>
  Impact: <what breaks, who notices>
  Fix: <concrete change, not "consider X">
```

`ID` = `SEC-1`, `API-1`, `UX-1`, ... — stable IDs so phase 2 can reference them.

Severity: `CRITICAL` (exploitable / data loss / silent corruption), `HIGH` (likely bug or hostile-input crash), `MEDIUM` (inconsistency, footgun, poor error), `LOW` (nit with rationale).

Also list **unreviewed areas** explicitly. "I didn't look at X" is a finding, not a gap to hide.

## Phase 1 Rules

- NEVER soften findings. "Might be worth considering" is banned. State the defect.
- NEVER report a finding without a concrete reproduction trigger or code citation.
- NEVER invent issues to fill a lens. Empty lens → say "no findings" and move on.
- ALWAYS cite `file:line`. No floating claims.
- Do NOT edit code. Review only.

## Phase 2 — Neutral Audit

Verify every finding from phase 1. Default: spawn a subagent so the audit runs in a fresh context with no commitment to the hostile framing.

### Preferred — Subagent (fresh context)

Use the Agent tool with `subagent_type: Explore` (read-only is sufficient; use `general-purpose` only if the audit needs to run scripts).

**Single audit** (≤ 10 findings): one subagent verifies all findings.

**Sharded audit** (> 10 findings): split findings into chunks of 5–8 by ID. Keep related findings together where possible (e.g., findings citing the same file or chain of callers in one chunk — co-located findings share read context). Spawn one audit subagent per chunk in a **single parallel Agent-tool block**, each restricted to its assigned IDs. Each writes to `.tmp/adversarial-review-verdicts-<chunk>.md`. Dispatcher concatenates into `.tmp/adversarial-review-verdicts.md`.

Subagent prompt template:

```
You are auditing a code review for accuracy. You are NOT the original
reviewer. Your job is to either confirm or refute each finding by reading
the cited code and its surrounding context.

Findings file: .tmp/adversarial-review-findings.md
Assigned IDs (audit ONLY these; ignore others): <e.g., SEC-1, SEC-2, API-3>
Repository root: <absolute path>
Review target: <branch/PR/dir as given by user>

For each assigned finding, read the cited file:line AND enough surrounding
code (callers, validators, auth middleware, init code) to judge whether
the trigger is actually reachable in this codebase.

For each finding, emit one verdict:

- CONFIRMED — defect real, trigger reachable, severity correct.
- ADJUSTED — defect real but severity wrong / fix wrong / trigger
  narrower than claimed. State the correction.
- REFUTED — finding is wrong. State which guarantee / validator /
  invariant invalidates it, with file:line.
- UNCERTAIN — cannot determine from code alone. State what info is
  needed.

Bias toward REFUTED and ADJUSTED. The hostile pass overclaims by design.
Confirming a finding requires evidence it is reachable, not absence of
evidence it isn't.

Output: write verdicts to .tmp/adversarial-review-verdicts[-<chunk>].md,
one block per finding ID. Do not rewrite the findings — only judge them.
```

When subagents return, read findings + verdicts and merge.

### Fallback — Same-context audit

If subagent unavailable or user declines, do the audit yourself, but explicitly switch stance:

1. Re-read each cited location with intent to *disprove* the finding.
2. For each finding, search for: input validators upstream, auth checks, type-system guarantees, framework defaults, tests that already cover the case.
3. Apply the same CONFIRMED / ADJUSTED / REFUTED / UNCERTAIN verdicts.
4. If you cannot find evidence to refute, that is NOT a confirmation — mark UNCERTAIN.

Same-context bias is real. Default to harsher self-criticism than feels natural.

## Final Report

Merge phase 1 findings with phase 2 verdicts. Group by verdict, not by lens:

```
## Confirmed (N)
[SEC-1] [HIGH] path/file.go:42 — <defect>
  Trigger: ...
  Impact: ...
  Fix: ...
  Audit: confirmed — <one-line why audit agreed>

## Adjusted (N)
[API-2] [was MEDIUM, now LOW] path/file.go:88 — <defect>
  ...
  Audit: <what changed and why>

## Refuted (N)
[UX-3] path/file.go:120 — <original claim>
  Audit: refuted — <validator/guarantee that invalidates it, file:line>

## Uncertain (N)
[SEC-5] path/file.go:200 — <defect>
  Audit: cannot verify — <what info would resolve it>
```

End with:

- **Summary**: counts per verdict + per severity (confirmed + adjusted only).
- **Top 3**: highest-leverage confirmed fixes if author has limited time.
- **Unreviewed**: areas neither pass examined.

## Global Rules

- Phase 2 is mandatory. A single-pass hostile review is NOT this skill.
- Refuted findings stay in the report. The user benefits from seeing what was considered and ruled out.
- Do NOT edit code. Review only. User decides what to fix.
