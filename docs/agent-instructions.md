# Writing Agent Instructions

Rules for authoring CLAUDE.md, docs/, and other agent-consumed files.

## Wording

- Optimize ALL text for agent/LLM consumption, not human readability.
- Terse, imperative, unambiguous. No filler, hedging, or politeness.
- Use `→` for cause/effect. Use `NEVER`/`ALWAYS`/`MUST` for hard rules.
- Prefer tables and bullet lists over prose.
- One rule per bullet. No compound sentences joining unrelated rules.

## Structure

- `CLAUDE.md.global` is loaded into EVERY conversation. Keep it minimal — only rules that apply universally.
- Detail belongs in `docs/` files, referenced via the pre-read rules table.
- Each `docs/` file covers one topic. Do not merge unrelated topics.

## Token Efficiency

- Omit articles (`a`, `an`, `the`) where meaning is clear without them.
- Omit subjects when the agent is the implied actor (e.g., "Read file first" not "You should read the file first").
- Use shorthand: `e.g.`, `i.e.`, `→`, `+`, `vs.`, `/` for alternatives.
- No redundant examples — one example per pattern is enough.
- No filler motivation ("this is important because…", "be diligent"). Load-bearing rationale — the why that stops a rule from being simplified away — is allowed, placed AFTER the rule (see "Rationale — load-bearing, subordinated").

## Content Guidelines

- Rules must be actionable. No vague guidance ("be careful", "consider").
- Negative rules (`NEVER X`) must include the correct alternative (`NEVER X. Use Y instead.`).
- Commands/paths in backticks. Exact syntax, not paraphrased descriptions.
- When a rule has exceptions, state them inline (`X — except when Y`).
- Group related rules under a heading. Keep heading names short.

## Ordering — rule first

- Every section/bullet LEADS with the operative rule. Rationale, history, edge cases AFTER.
- First sentence of a block answers "what do I do"; the rest answers "why / when not".
- NEVER bury an instruction in a parenthetical or at the tail of a rationale paragraph — promote it to the block's lead.

## Canonical owners — never restate

- Every definition, command, threshold, and canned message has ONE owning site. Every other site points to it by name.
- A pointer names the owner's heading/anchor text, never a line or step number (numbers move).
- Pointer-with-gloss is restatement: do not unpack a definition beside its pointer ("reset the counters (`a`, `b`)" → say "reset the counters (owner section)"). The gloss drifts while the pointer stays right.
- A deliberate copy (prompt payload, summary block) must be MARKED non-authoritative ("the owner wins over this") — and machine-checked against the owner where possible.
- Changing a definition = sweeping every restating site. Enumerate the restating sites semantically first; grep for old strings is one input to the sweep, never the sweep.

## Navigation — headings are the agent's index

- Every distinct topic gets a REAL markdown heading. A bold paragraph lead is not a heading — heading-scanning agents cannot see it.
- Heading text carries the exact anchor phrase other files quote; keep it stable, cross-references resolve by it.
- Numbered procedures keep the number IN the heading ("Step 3 — dispatch due work") so "step 3" citations survive restructuring.
- Files >300 lines open with a question router: "your question → section name", marked as navigation, not authority.
- Rough bar: one heading per screenful. A 400-line file with 2 headings is unnavigable.

## Emphasis discipline

- Bold marks exactly: (1) the one operative imperative per block, (2) anchor names other files quote, (3) literal state/flag values. Nothing else.
- No intensifier bold (**never**, **only**, **all** as lone words). When most lines are bold, none stand out.

## Rationale — load-bearing, subordinated

- Keep the why that stops a future "cleanup" from deleting the rule; rules that look arbitrary get simplified away and regress.
- One full derivation per why, at the owning site; every repeat becomes claim + pointer.
- Illustrate defects with INVENTED examples, never live strings from the tree — a quoted real "bad" line turns the doc into a false-positive generator for future sweeps.
- Volatile facts (live counts, dated observations) are marked as dated illustrations; documented API constants stay exact.

## Maintaining agent docs

- Before restructuring, find what machines pin: tests grepping for needle sentences, doc-parsers, verbatim-extracted command blocks. Pinned text may MOVE, never be reworded — verify with the pinning test after editing.
- Every trim needs a preservation audit: map each deleted clause to the site where it survives; a clause with no surviving equivalent stays.
- Prefer mechanical doc/code checks over exhortations: a comparison that can FAIL beats "keep these in sync".
- Commit structure-only changes (headings, reordering) separately from content changes (trims, rewording) — the diff stays reviewable.
