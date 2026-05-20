# MissingClasses.md

Running log of domains whose canonical design has not yet landed in the
`docs/` submodule, but which the consuming project's existing code depends
on. When work blocks on a missing domain, the rule is **leave the existing
code alone** and add an entry here describing what is needed and what is
currently being deferred.

The file is appended to during refactor work and reviewed each time a new
domain design lands upstream. When a domain ships, its entry here is
deleted and the work it was blocking is unblocked.

Open design questions *within* domains that already have a file set —
e.g. mechanics still to be specified inside Combat or Chronicle — live
in `PendingDesign.md`, not here.

## How to use this file

For every entry:

- **Status** — current entry in `docs/domain_index.md` (Planned, Tentative,
  In progress with no files yet, etc.).
- **Existing code** — files in this project that currently implement what
  the domain will eventually own.
- **What's needed from the domain** — the contract gaps that block a clean
  port (entry points, data shapes, formulas, validation).
- **Deferred work** — what would have been changed in this refactor but
  was left untouched because the contract is missing.
- **Notes** — anything else worth remembering. Open questions, partial
  decisions, links to related entries.

## Process

1. While doing a refactor, if a step requires knowing how a not-yet-designed
   domain works, **stop the change for that domain**. Don't guess at the
   contract.
2. Find the domain's entry below (or add one if it doesn't exist) and
   record the deferred work plus what the domain needs to provide.
3. Continue the refactor on the parts that are unblocked.

## Entries

### Creatures

- **Status:** In progress in `docs/domain_index.md` but no design / glossary
  / tests / config files exist in `docs/creatures/`. The UI specs
  `docs/ui/creature_full_stub.md` and `docs/ui/creature_minimal_stub.md`
  reference it but neither defines its contract.
- **Existing code:**
  - `lib/character.rb`
  - `lib/race.rb`
  - `lib/advancement.rb`
  - `lib/dummy_data.rb` (per-creature state, including everything the
    orphan_data files would otherwise hold)
  - `stubs/character_full_stub.rb` + `views/stubs/_character_full_stub.erb`
  - `stubs/character_minimal_stub.rb` + `views/stubs/_character_minimal_stub.erb`
  - `pages/character.rb` + `views/pages/character.erb`
  - `spec/character_spec.rb`, `spec/race_spec.rb`, `spec/advancement_spec.rb`
- **What's needed from the domain:**
  - A creatures glossary, design, tests, config, and example data file.
  - Public entry points for: looking up a creature by ID, name, tier, race
    + classes summary, effective attributes, speed, initiative, perception,
    proficiency ranks, granted abilities. Chronicle and the creature stubs
    both call these.
  - The merged scope (Character + Race + Advancement) means the entry
    points need to cover identity + heritage + level/tier progression in
    one API.
- **Deferred work:**
  - Renaming `Character` to `Creature` throughout the project. Postponed
    until the canonical domain name and entry-point shapes are confirmed.
  - Splitting per-creature mutable state (HP, equipped items, conditions)
    out of `lib/dummy_data.rb` into a `data/creatures_data.json` style
    runtime file.
  - Wiring the creature stubs to a single Creatures lookup API instead of
    reaching into `Character`/`Race`/`Advancement` directly.
- **Notes:**
  - All test creatures in `lib/dummy_data.rb` are player characters, per
    user, so the `tags` filter for `player_character` in the minimal stub
    spec is trivially true today.

## Migration triggers

Quick reference for what to do once a domain lands:

- **Creatures** — rename Character→Creature, fold Race + Advancement
  callers into the unified API, split per-creature state out of
  `lib/dummy_data.rb`.
