# Inter-agent messages

Use one UTF-8 JSON line for routine orchestrator↔worker messages. Use prose when these fields cannot carry the meaning.

## Envelope

Write exactly one JSON object with no surrounding text. Use envelope key order `v`, `type`, `id`, `reply_to`, `data`:

```json
{"v":1,"type":"task","id":"t1","data":{"goal":"check parser","deliverable":"findings","scope":["parser.go"]}}
```

Require `v` (number `1`), `type` (listed string), `id` (string), and `data` (object). Keep `id` short and unique within
the conversation. Set `reply_to` (string) to the prompting message's `id`; omit it only for an initial task. Omit empty
optional fields. Ignore unknown fields.

## Types

Use `data` keys in table order. All named fields are required unless marked optional. Scalars and array items are strings.

| `type` | Use when | `data` keys |
|--------|----------|-------------|
| `task` | Assign or revise work | `goal`, `deliverable`, optional `scope` (array) |
| `result` | Report an outcome | `state` (`done`, `partial`, `failed`), `summary`, optional `evidence` (array) |
| `question` | Request information or a choice | `ask`, optional `options` (array) |
| `blocker` | Progress requires an external action | `cause`, `needed` |
| `status` | Report ongoing work | `state` (`running`, `waiting`), optional `next` |
| `pushback` | Object to requested work | `issue`, optional `solution` |

Use `pushback` to identify a problem with the requested goal, scope, or approach. Include `solution` when a specific change
is known; an objection does not require a proposed solution. Use `blocker` when progress cannot continue until someone
provides `needed`. Keep values short and concrete.

## Prose fallback

Send prose when no listed type fits or the fields would lose needed meaning. Treat a message as structured only when it
parses as a JSON object with `v:1` and a listed `type`; otherwise, read it as prose.
