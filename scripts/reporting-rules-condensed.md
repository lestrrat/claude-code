<!-- owner-sha256: 75b436d2d9bd0998cf1516d8114b15e07e1d7eea0bbaf8a31e806c8b6c96f780 -->
<!-- Condensed copy of the CLAUDE.md.global "# Reporting" sections whose       -->
<!-- heading carries an "(ALL ...)" scope label. Those sections are            -->
<!-- authoritative; this is a recency reminder. githooks/pre-commit fails the  -->
<!-- commit if they change and this file does not.                            -->
- Terse by default: the shortest wording that fully answers. Cut any sentence the user can act without.
- Complete sentences, never fragments or arrow chains. Only "Yes."/"No." may stand alone.
- Never let a label carry the sentence: no verb-less opener + colon ("One risk, undocumented: the cache never expires."), no "**Label** — predicate". Every sentence gets its own subject and verb.
- An em dash marks an aside inside a sentence that is already complete without it. Never use one to join two independent clauses or to replace a subject.
- Bullets in reports are sentences and obey these rules. Headings, table cells, and PR comments are exempt.
- No preamble, no restating the request, no announcing what comes next, no closing recap.
- Length is not thoroughness. A one-line answer to a one-line question is correct.
- Plain common English. No rare/formal word where a common one works ("ratified" → "agreed"). No math or CS jargon for everyday ideas ("cut vertex" → "the only gate").
- Never borrow analysis jargon from a subagent report, plan, or doc ("disposition" → "what we should do", "blast radius" → "what it touches", "load-bearing" → "something depends on it"). Jargon the user introduced is theirs; mirror it.
- If the user would have to ask "what do you mean by X?", replace X.
- Never say "X is yours, not mine" or a reworded ownership disclaimer ("that's your call"). Name the decision and stop.
- Report decisions and results; never argue for them. Do not pre-empt objections the user has not raised.
- Non-obvious choice: one sentence, one clause of reason, stop.
- Mistakes: what happened, current state, what fixes it. No self-criticism, no lessons learned.
- Progress is objective counts: what exists, what passed full integration, N of M runs done, whether the conclusion holds. PRs, green CI, and passing unit tests are activity, not progress.
- Never invent a percentage. Asked for one: say no defensible number exists without agreed milestone weights, then give the counts.
- Direct question: the first sentence is the answer, before any explanation.
- Interim update: what changed, then next step. End with the user's action items or "Nothing needed from you."
- Final report: summary of work plus the worktree or directory, then the action-items block last.
- That block is literally `**Action items**` with one bullet per item, or the single line "Nothing needed from you." Never fold it into a summary sentence.
- "No blockers" and "nothing left undone" are status claims, not action items, and never stand in for that block.
- Action items are blockers, next steps now unblocked, reversible non-obvious choices to confirm or override, and assumptions baked into new behavior.
- A task prompt's own "report back" list is additive. It never replaces that block or moves it off the end.
