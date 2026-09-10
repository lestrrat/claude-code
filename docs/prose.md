# Writing Prose

Rules for prose a human reads: `README.md`, `docs/`, guides, and doc comments. Agent-consumed files follow
`~/.claude/docs/agent-instructions.md` instead. User-facing reports follow `CLAUDE.md`'s `# Reporting` section.

## The test every sentence must pass

Ask of each sentence: **what would I run, read, or observe to confirm this?**

- No answer → the sentence conveys nothing. Rewrite it as the observable behavior.
- Answer is "read the source" → read the source, then write what it does. NEVER rephrase a vague sentence into a
  differently vague sentence.
- Sentence survived from an earlier draft → it still has to pass. Inherited text gets no exemption.

## Shapes that fail the test

Each row is one recurring defect. Examples are invented; do not grep for them.

| Shape | Rewrite as |
|-------|-----------|
| Metaphor with no mechanism | The operation the code performs |
| Verb that asserts without naming an action | The action, with its subject and object |
| Self-praise or a quality claim | The behavior that earns the claim |
| Rule stated as a property | The input that fails and the error it produces |
| Reason invented to fill a clause | Delete the clause, or cite where the reason is stated |

### Metaphor with no mechanism

Spatial or bodily verbs stand in for the actual call: `stands on`, `sits on top of`, `is half of`, `is the heart of`,
`powers`, `backs`, `drives`, `feeds`, `lives in`.

- Bad: `Both encoders stand on a token table.`
- Good: `Both encoders read every keyword from the token table.`

Metaphor is allowed where it names something the code has no word for AND the sentence still says what happens.

### Verb that asserts without naming an action

`remains`, `retains`, `handles`, `manages`, `supports`, `deals with`, `is responsible for`, `takes care of`. Each one
claims a relationship and hides the operation.

- Bad: `The session store retains default expiry behavior.`
- Good: `The session store deletes an entry 30 minutes after its last read.`
- Bad: `Timeouts remain the source of cancellation.`
- Good: `Only a timeout cancels an in-flight request; a closed channel does not.`

### Self-praise or a quality claim

`nothing is guessed`, `fully supported`, `works correctly`, `shows what X is worth`, `is robust`. A reader cannot act on
praise, and the claim is unverifiable as written.

- Bad: `Nothing is inferred, and the loader never guesses an encoding.`
- Good: `The loader reads the encoding from the byte-order mark, and returns an error when the file has none.`

A denial stays ONLY where a reader would plausibly expect the opposite (`the command opens no database`). See the
project's own prose rules when it has them.

### Rule stated as a property

A validation described as a quality of the data, rather than as the input that fails.

- Bad: `Duplicate entries require qualified identities.`
- Good: `A bare name that two namespaces both hold is an error. Name it with its namespace instead.`

Name the failing input, and the error or panic the caller gets. Read the validation code to get both right.

### Reason invented to fill a clause

`for compatibility`, `for performance`, `for safety`, `by design` — appended to a true statement without a source.

- Cite the reason only when code, a comment, or a commit states it.
- NEVER infer a reason from the behavior alone. Drop the clause; the behavior is what the reader needs.

## Idioms that read as noise

Non-standard verb phrases cost a reader a re-read and mean nothing precise: `quoted around`, `falls out of`,
`stands in for`, `bakes in`, `speaks to`. Replace with the plain operation (`wrapped in quotes to make it legal`).

## Working on an existing page

- Fix these shapes in the sentences you are already editing. Do NOT open a separate rewrite pass unless asked.
- A fix that changes a technical claim needs the source read first. Rewording is not license to restate behavior.
- Report any clause you deleted for lacking a source, so the author can restore it if they know the reason.
