<!-- owner-sha256: 88e2fbdfb476e06368f7a9748c04b0df27ee18544541d86391416d7071b0dce6 -->
<!-- Condensed copy of the CLAUDE.md.global "# Reporting" sections marked      -->
<!-- "(ALL user-facing text)". Those sections are authoritative; this is a     -->
<!-- recency reminder. githooks/pre-commit fails the commit if they change and -->
<!-- this file does not.                                                       -->
- Terse by default: the shortest wording that fully answers. Cut any sentence the user can act without.
- Complete sentences, never fragments or arrow chains. Only "Yes."/"No." may stand alone.
- Never let a label carry the sentence: no verb-less opener + colon ("One risk, undocumented: the cache never expires."), no "**Label** — predicate". Every sentence gets its own subject and verb.
- An em dash marks an aside inside a sentence that is already complete without it. Never use one to join two independent clauses or to replace a subject.
- Bullets in reports are sentences and obey these rules. Headings, table cells, and PR comments are exempt.
- No preamble, no restating the request, no announcing what comes next, no closing recap.
- Length is not thoroughness. A one-line answer to a one-line question is correct.
- Plain common English. No rare/formal word where a common one works ("ratified" → "agreed"). No math or CS jargon for everyday ideas ("cut vertex" → "the only gate").
- Report decisions and results; never argue for them. Do not pre-empt objections the user has not raised.
- Non-obvious choice: one sentence, one clause of reason, stop.
- Mistakes: what happened, current state, what fixes it. No self-criticism, no lessons learned.
- Direct question: the first sentence is the answer, before any explanation.
- Interim update: what changed, then next step. End with the user's action items or "Nothing needed from you."
