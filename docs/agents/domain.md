# Domain Docs

How the engineering skills should consume this repo's domain documentation
when exploring the codebase. This repo is single-context, and it keeps its
own names for the two files the skills expect:

| Skills expect   | This repo uses    |
| --------------- | ----------------- |
| `GLOSSARY.md`   | `CONTEXT.md`      |
| `docs/adr/`     | `docs/HISTORY.md` |

## Before exploring, read these

- **`CONTEXT.md`** at the repo root: the words this project uses for its own
  concepts (Reroll, Board, Prediction, Filters, ...). Game facts are in
  `AGENTS.md`.
- **`docs/HISTORY.md`**: the development log, newest first. It records why
  things are the way they are. Read the entries that touch the subsystem
  you're about to work in. Topic-specific research is in `docs/*RESEARCH.md`.

Don't create `GLOSSARY.md`, `GLOSSARY-MAP.md` or `docs/adr/`. When
`/domain-modeling` resolves a term, add it to `CONTEXT.md` in that file's
style (a bold term, the module path if one exists, then the definition).
When it records a decision, add a dated entry at the top of
`docs/HISTORY.md` instead of writing an ADR.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor
proposal, a hypothesis, a test name), use the term as `CONTEXT.md` defines
it. Don't drift to synonyms.

If the concept you need isn't in `CONTEXT.md` yet, that's a signal: either
you're inventing language the project doesn't use (reconsider) or there's a
real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts a decision recorded in `docs/HISTORY.md`, say so
explicitly instead of silently overriding it:

> _Contradicts the v0.35.1 entry (warm worker VMs on the ship), but worth
> reopening because…_
