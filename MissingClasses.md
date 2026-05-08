# MissingClasses.md

Running log of domains whose canonical design has not yet landed in the
`docs/` submodule, but which the consuming project's existing code depends
on. When work blocks on a missing domain, the rule is **leave the existing
code alone** and add an entry here describing what is needed and what is
currently being deferred.

The file is appended to during refactor work and reviewed each time a new
domain design lands upstream. When a domain ships, its entry here is
deleted and the work it was blocking is unblocked.

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

### Proficiencies

- **Status:** Planned. No files in `docs/`.
- **Existing code:**
  - `lib/skills.rb`
  - `data/skills.yaml`
  - `spec/skills_spec.rb`
- **What's needed from the domain:**
  - The contract for "proficiency prowess" (the single integer dice
    resolution consumes), the mandatory-proficiency rules (`martial`,
    saves), the prefix-match rules referenced from
    `docs/common_glossary.md`.
  - Where proficiency ranks live (on the Creature? on the Class?), and
    how `floor(attribute / attribute_contribution_divisor)` is sourced.
- **Deferred work:**
  - Moving the prowess-to-roll-input translation into the Proficiencies
    layer. Today the prowess number flows directly into dice resolution
    via the Creature's skills.
- **Notes:**
  - `docs/common_glossary.md` already names several Proficiencies terms
    (`Proficiency Prowess`, `Mandatory Proficiency`, `Prefix Match`); the
    full domain is still pending.

### Equipment

- **Status:** Planned. No files in `docs/`.
- **Existing code:**
  - `lib/equipment.rb`
  - `lib/item_use.rb`
  - `data/equipment_config.yaml` (catalog: weapons, armor, currency,
    magical properties, naming rules)
  - `spec/equipment_spec.rb`, `spec/item_use_spec.rb`
- **Orphan-data counterpart:** `docs/orphan_data/equipment.yaml` holds
  per-creature equipped/consumable/other lists, prepared spells, rituals,
  and item descriptions. The catalog of *what items can exist* is project
  config and not in orphan data.
- **What's needed from the domain:**
  - Public entry points for looking up an item, evaluating its bonuses /
    penalties / starting modifiers, computing damage type / threshold,
    and applying conditions on hit. The Combat / item_use code calls
    these today through `lib/equipment.rb`.
  - A canonical config for the catalog so `data/equipment_config.yaml`
    can become an override file or move upstream.
- **Deferred work:**
  - Migrating `data/equipment_config.yaml` to the new `data/` overrides
    convention. The catalog has no canonical doc home yet, so it stays
    in `data/` checked in via a gitignore exception.
  - Replacing the orphan-data instance lists with calls to the Equipment
    domain.

### Conditions

- **Status:** Planned. No files in `docs/`.
- **Existing code:**
  - `lib/conditions.rb`
  - `data/conditions.yaml` (catalog: severities, affliction rules)
  - `spec/conditions_spec.rb`
- **Orphan-data counterpart:** `docs/orphan_data/conditions.yaml` holds
  per-creature current HP / mana / toxicity / damage tracking and active
  condition flags. The catalog of *what conditions exist* is project
  config and not in orphan data.
- **What's needed from the domain:**
  - Public entry points for the Acceptance Check, Magic Toxicity, Magic
    Poisoning, and Affliction lifecycle named in `docs/common_glossary.md`.
  - Storage rules for the per-creature state currently living in
    `orphan_data/conditions.yaml` and `lib/dummy_data.rb`.
- **Deferred work:**
  - Migrating `data/conditions.yaml` to the new `data/` overrides
    convention. Stays checked in until a canonical config exists.

### Combat

- **Status:** Planned. No files in `docs/`.
- **Existing code:**
  - `lib/combat.rb`
  - `pages/combat.rb` + `views/pages/combat.erb`
  - `stubs/attack_stub.rb` + `views/stubs/_attack_stub.erb`
  - `stubs/initiative_stub.rb` + `views/stubs/_initiative_stub.erb`
  - `stubs/turn_action_stub.rb` + `views/stubs/_turn_action_stub.erb`
  - `spec/combat_spec.rb`
- **What's needed from the domain:**
  - Turn order rules, action economy, combat-specific Roll modifications.
  - How attacks compose Rolls into Checks (Initiating Roll = attacker,
    Defending Roll = defender). The `attack_stub` currently builds a
    multi-Roll panel directly; under the new check_resolution contract
    it would call `resolve_check`.
- **Deferred work:**
  - Re-platforming `attack_stub` on top of `check_resolution`. The
    combat-level decisions about which Rolls comprise an attack belong
    to Combat, not to check_resolution itself, so this waits for the
    Combat domain to land.

### Abilities

- **Status:** Planned. No files in `docs/`.
- **Existing code:**
  - `lib/abilities.rb`
  - `data/abilities_config.yaml` + `data/abilities_data.yaml`
  - `spec/abilities_spec.rb`
- **Orphan-data counterpart:** `docs/orphan_data/abilities.yaml` holds
  ability description text used by the creature stubs.
- **What's needed from the domain:**
  - Public entry points for the three flavors named in
    `docs/common_glossary.md` (Procedural, Stateful, Always-On
    Modifier), and for the Effect string parsing rules.
- **Deferred work:**
  - Migrating `data/abilities_*.yaml` to the new convention. Stays
    checked in.

### Damage Types

- **Status:** Tentative. May be merged with another domain.
- **Existing code:**
  - `lib/damage_types.rb`
  - `data/damage_types.yaml`
  - `spec/damage_types_spec.rb`
- **What's needed from the domain:**
  - Confirmation of whether Damage Types stays standalone or merges into
    Equipment / Combat. Several terms (`Severity`, `Threshold`, `Damage
    Resilience`) already live in `docs/common_glossary.md`.
- **Deferred work:**
  - None active; the existing code's contract is small and stable.

### Modifiers

- **Status:** Tentative. May end up part of another domain.
- **Existing code:**
  - `lib/modifiers.rb`
  - `spec/modifiers_spec.rb`
- **Upstream data:** `docs/orphan_data/modifiers.yaml` holds the canonical
  `Bonus Types List`.
- **What's needed from the domain:**
  - Confirmation of where modifier-key validation lives (in a Modifiers
    library, at the dice resolution boundary, or upstream). Today
    `lib/dice_system.rb` validates modifier keys against the list it
    finds in `data/dice_resolution.yaml`; the new dice resolution design
    explicitly does not validate.
  - The workflow for registering a new modifier type when a class /
    ability / item / condition introduces one (open question in
    `docs/orphan_data/orphans.md`).
- **Deferred work:**
  - Moving the Bonus Types validation out of dice resolution. Awaiting
    the Modifiers contract before deciding the validation entry point.

### Atlas

- **Status:** Planned. No files in `docs/`. No existing project code.
- **Existing code:** none.
- **What's needed from the domain:** TBD.
- **Deferred work:** none.

## Migration triggers

Quick reference for what to do once a domain lands:

- **Creatures** — rename Character→Creature, fold Race + Advancement
  callers into the unified API, split per-creature state out of
  `lib/dummy_data.rb`.
- **Proficiencies** — move prowess translation up out of dice resolution.
- **Equipment** — move `data/equipment_config.yaml` to the canonical home
  (override file or upstream); replace orphan_data per-creature lists.
- **Conditions** — same pattern as Equipment for `data/conditions.yaml`
  and the orphan_data instance state.
- **Combat** — re-platform `attack_stub` on `check_resolution`.
- **Abilities** — same pattern as Equipment for `data/abilities_*.yaml`.
- **Modifiers** — pick a validation home; remove the deferred validation
  in dice resolution.
