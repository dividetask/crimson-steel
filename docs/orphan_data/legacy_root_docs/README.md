# `legacy_root_docs/` — pre-domain-split design notes

These uppercase Markdown files lived at the project root before the
domain split (`combat/`, `chronicle/`, `dice_resolution/`, etc.)
became the canonical structure. They are kept here as **reference
only** — most of their content has been (or will be) absorbed into the
relevant domain glossary / design files.

Treat each file as advisory: when something here disagrees with a
project-root domain doc, the domain doc wins.

## Files

- `DAMAGE_TYPES.md` — categorical and per-type rules. Folded into
  `combat/combat_glossary.md` and `combat/combat_config.yaml`.
- `CONDITIONS.md` — pre-Conditions-domain notes. Will be absorbed when
  Conditions is written.
- `SKILLS.md` — pre-Proficiencies notes. Partially absorbed into
  `proficiencies/`.
- `SPELLS.md`, `SPELL_REDESIGN.md`, `MagicRefactor.md` — magic system
  notes. Will be absorbed when Spells / Magic is written.
- `DEFINITIONS.md` — old project-wide glossary. Largely superseded by
  `common_glossary.md` and per-domain glossaries.

## Migration

Delete each file as its rules land in the canonical domain docs. When
the directory is empty, delete it.
