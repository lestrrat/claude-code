# Learnings Log

Agent-agnostic store of meaningful, repeatable learnings. Location: `~/.agents/learnings/`. Plain markdown, no
tool-specific format → Claude Code, Codex, any other agent reads/writes it the same way.

## Lookup — before starting non-trivial work

Starting a build/debug/perf/refactor task, or stuck on one → search narrow-to-wide. NEVER `cat` the whole tree.

1. List areas: `ls ~/.agents/learnings/`.
2. Scan titles of the relevant area: `grep -rH '^title:' ~/.agents/learnings/<area>/`.
3. No hit → search all: `grep -ril <keyword> ~/.agents/learnings/` (matches error strings, tags, bodies).
4. Read only matching files. Apply where "Applies when" holds. Proven wrong → fix the entry (see "Maintenance").

Dir missing or empty → continue; NEVER block on it.

## Record — only learnings that pass the bar

Trigger: an obstacle (build failure, perf issue, refactoring obstacle, etc.) was overcome AND the way past it yields
a rule that would help on a future task. Write the entry before the final report. Record ONLY if ALL hold:

- Repeatable: same situation can recur in other tasks, repos, or sessions. A one-off fix fails this.
- Generalizable: states a rule or cause, not just the patch that worked here.
- Verified: outcome confirmed (test passed, measurement improved). NEVER record a guess.
- Non-obvious: cost real time or contradicted an expectation. Obvious fixes fail this.
- Not already recorded: absent from the repo's code, docs, and git history, and from existing learnings.

Fails the bar → do NOT record. A short log of strong entries beats a long log of noise.

- Dead end that cost real time AND exposes a general trap → record it as the learning, with why it fails.
- Repo-specific learning → put it in that repo's docs/CLAUDE.md, not here.
- Path: `~/.agents/learnings/<area>/<slug>.md`. One learning per file. `mkdir -p` the area first.
- Area = one lowercase word for the domain, e.g. `go`, `git`, `build`, `perf`, `testing`, `shell`, `refactor`.
  Reuse an existing area (`ls ~/.agents/learnings/`) before creating one. Spans areas → pick the primary, list the rest in `tags`.
- Slug = kebab-case rule or trap, e.g. `test-failure-output-can-exhaust-memory`. Area is in the path, NEVER in the slug.
- Before writing, scan the area's titles (see "Lookup"). Overlapping entry exists → extend it, NEVER duplicate.
- NEVER keep an index file. It drifts and becomes a merge conflict point. Titles in frontmatter are the index.

## Entry Format

```markdown
---
title: <the learning as one sentence>
tags: [<tool>, <language>, <area>]
date: <YYYY-MM-DD>
---

## Learning
The rule or cause, stated generally.

## Applies when
Concrete conditions/symptoms that signal this learning is relevant. Exact error text in backticks.

## Doesn't apply when
Known limits. Omit if none.

## Evidence
What was observed and how it was verified (command, measurement, test). Dated if version-specific.
```

- Exact error strings + commands in backticks → grep must find them.
- Volatile facts (versions, dates) stated explicitly in the body.
- NEVER include secrets, tokens, customer data, personal names/emails.

## Maintenance

- Entry proven wrong or fixed upstream → edit or delete it. Wrong entries cost more than missing ones.
- Entry hit again and still correct → leave as is. NEVER pad it with new instances.
- Keep entries short, roughly a screenful. Guideline only: a longer entry is fine when the content needs it.
- Area grows crowded, or several entries share one cause → consider merging them into one general learning, or
  splitting the area by sub-domain (`go/` → `go/concurrency/`). Guideline only, no fixed count. Do it while already
  working in that area; NEVER as a separate sweep.
- Merging → keep every distinct "Applies when" symptom and exact error string; delete only true duplicates.
