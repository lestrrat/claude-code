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
- No motivational text ("this is important because…"). State the rule only.

## Content Guidelines

- Rules must be actionable. No vague guidance ("be careful", "consider").
- Negative rules (`NEVER X`) must include the correct alternative (`NEVER X. Use Y instead.`).
- Commands/paths in backticks. Exact syntax, not paraphrased descriptions.
- When a rule has exceptions, state them inline (`X — except when Y`).
- Group related rules under a heading. Keep heading names short.
