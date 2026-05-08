# Spells

Spell list page, spell detail page, an add-spell flow, casting-time human-readable labels, and target-classification driving the cast UI. Three new spells were added: Cure, Ward, Obscuring Mist.

## Glossary

- **Spell List** (`/spells`) — Master list of all spells available to the casting character.
- **Spell Detail** (`/spell/<name>`) — Full description, casting parameters, and cast button for one spell.
- **Add Spell** (`POST /spells/add`) — Adds a spell to a character's known list.
- **Casting Time** — Stored as a token (e.g. `1_round`, `1_minute`, `concentration`); rendered as a human-readable label.
- **Target Classification** — One of `single`, `multi`, `no` target. Drives whether the cast UI shows a target picker, a checkbox list, or auto-casts.
- **Cure** — Heals damage and lifts ability damage on a target via a cure cascade (lower-severity tracks healed before higher).
- **Ward** — Grants temporary hit points to a target.
- **Obscuring Mist** — Creates an obscuring area effect.

## Design

Spell entries carry `casting_time`, `target` (`single` / `multi` / `no`), `cost`, and an effect block. The cast UI reads `target` and renders:

- `single` — target selector dropdown.
- `multi` — checkbox list of valid targets.
- `no` — no picker; cast button auto-resolves.

Casting time tokens are formatted to readable strings in the view layer; storage stays normalized.

### Cure

Heals minor damage first, then moderate, then major, up to the spell's heal amount. Ability damage uses a parallel cascade via `Combat.apply_ability_cure_cascade` — pop one minor ability-damage entry per rank, then moderate, then major. Target selection is `single`.

### Ward

Grants `temporary_hit_points` to the target. Temp HP stacks additively on `CombatTurn.temporary_hit_points` and is included in displayed current HP. Damage absorbs into temp HP first.

### Obscuring Mist

Area effect, no target picker (`target: no`); creates an obscuring zone that affects perception/attack rolls within it.

## Cross-domain interactions

- New spell data lives in `../../common/data/spells.yaml.example`.
- Casting from scrolls reuses the spell cast path — see [scrolls-and-potions.md](scrolls-and-potions.md).
- Temp HP semantics are documented in [hp-mana-display.md](hp-mana-display.md).
- Cure and ability-cure cascade are implemented as `Combat.apply_cure_cascade` and `Combat.apply_ability_cure_cascade`.
