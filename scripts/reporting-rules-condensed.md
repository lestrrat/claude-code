<!-- owner-sha256: da7d332ff969171f022d4957625807f6a1780cbee035d5c45e9caa19938295f9 -->
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
- Progress is objective counts: what exists, what passed full integration, N of M runs done, whether the conclusion holds. PRs, green CI, and passing unit tests are activity, not progress.
- Never invent a percentage. Asked for one: say no defensible number exists without agreed milestone weights, then give the counts.
- Direct question: the first sentence is the answer, before any explanation.
- Interim update: what changed, then next step. End with the user's action items or "Nothing needed from you."
