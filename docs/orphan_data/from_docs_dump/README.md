# `from_docs_dump/` — potentially obsolete reference dump

The contents of this directory came from a single bulk import (`docs/`
in the upstream commit titled "Added old documentation. Please delete
this directory after reading it"). They are reference designs from a
prior pass and have **not** been audited against the current canonical
domain files at the project root.

**Status: potentially obsolete.** Treat every file here as advisory
context, not authoritative rules. When something here disagrees with a
project-root domain doc, the project-root doc wins.

## Layout

The original layout under `docs/` is preserved. The Combat reference
material that had its rules absorbed into the project-root
`combat/` files lives under `combat_reference/`.

## When to consult these files

- Looking for a rule that hasn't been written into the canonical domain
  files yet — these may have a draft of it.
- Tracing the lineage of a decision in the canonical files.

## When **not** to consult these files

- As the source of truth for any current behavior.
- As the catalog of what's configurable in any domain.

## Migration plan

Rules from this directory should migrate into the appropriate
project-root domain files when those domains are written. Once a file
here has been fully absorbed (or determined to be irrelevant), delete
it. The directory itself is expected to shrink over time; when empty,
delete it.
