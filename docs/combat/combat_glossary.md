# Combat — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `combat_config.yaml`. The Combat module owns round-by-round combat state (combatants, initiative, turn pointer, action dice). It depends on the dice resolution module for die rolls and on the character module via a lookup callback for per-character derived values.

## Core

**Combat**: The round-by-round state machine that tracks who is fighting, the order they act in, and how many resources each has spent. Persists to a state file (`combat_data.yaml.example`) on every mutation; rules tunables live separately (`combat_config.yaml.example`).

**Combatant**: One participant in an active Combat. Identified by two IDs (Combat ID and Character ID — see below) and carrying its own `name`, current `initiative_dice` snapshot, and remaining `action_dice` count.

**Combat ID**: A per-instance integer unique within the current Combat, allocated at `add_combatant` time. Distinct from Character ID so that two copies of the same monster track separately. Computed on the fly as one past the highest in-use id rather than persisted as a counter — the state file stays describable without bookkeeping.

**Character ID**: The underlying creature identity supplied at `add_combatant`. Used to look up the Character's attributes via the supplied `character_lookup` callback whenever a derived value (initiative dice count, action dice max) is needed.

**Round**: A signed integer counter incremented when the turn pointer wraps past the last combatant. Reset to 1 at the start of every initiative reroll. The current Round is part of the persisted state.

**Active**: A boolean indicating Combat is in progress. Flipped on by `reroll_all_initiative`, off by `end_combat`.

## Turn Order

**Turn Order**: Combatants ordered highest-initiative first. Ties are broken **die-by-die descending** — `[10, 7]` beats `[10, 6]` because the second die is larger; final ties are broken by Combat ID for stability. Recomputed on every read rather than cached, since combatants and dice may change between reads.

**Current Turn Index**: An integer index into the Turn Order pointing at the active Combatant. Modulo'd over the Turn Order length on every read so the index remains valid even after combatants are removed.

**Current Combatant**: The Combatant at `Current Turn Index`. Returns null when there are no Combatants.

## Initiative

**Initiative Attribute**: The Character Attribute consulted to determine how many initiative dice the Character rolls. *(configurable, default `wis`)*

**Initiative Divisor**: The divisor applied to the Initiative Attribute to produce the dice count. `dice_count = floor(attribute / Initiative Divisor)`. *(configurable, default 2 — a Wis-16 character rolls 8 dice; a divisor of 3 would give 5 dice)*

**Initiative Dice**: The current Combatant's rolled dice, sorted high-to-low. Empty until the first reroll. Compared die-by-die for tie-breaking.

**Initiative Luck**: A signed integer effect applied during initiative rerolling that rerolls extreme dice. **Positive** values reroll the lowest non-critical dice (favoring the Combatant); **negative** values reroll the highest non-failure dice (working against). Magnitude rerolls that many dice in priority order. Distinct from the dice resolution module's generic Reroll Operation because initiative has no Target Number, so the generic helpers don't apply.

**Initiative Insight**: A signed integer effect applied during initiative rerolling that nudges a single die's value. **Positive** values raise the lowest die that could become a Critical (`value + insight ≥ die_size`); if no die qualifies, raise the highest non-Critical instead. **Negative** values penalize the highest die. Magnitude rerolls repeat the operation that many times.

## Action Dice (Combat Pool)

**Combat Pool Attribute**: The Character Attribute consulted to derive action dice max. *(configurable, default `wis`)*

**Combat Pool Range**: The modulus applied to the raw action-dice value. *(configurable, default 10)*

**Combat Pool Minimum**: The floor added to the modulo result. *(configurable, default 11)*

**Action Dice Raw**: An intermediate `martial_skill_ranks + floor(combat_pool_attribute / 2)`. Both halves are computed at lookup time via the `character_lookup` callback.

**Action Dice Max**: The Character's maximum action dice for one Round, derived as `(action_dice_raw % Combat Pool Range) + Combat Pool Minimum`. Computed on demand — never persisted.

**Untyped Bonus**: The integer-division half of the same formula: `floor(action_dice_raw / Combat Pool Range)`. Exposed for callers but **not yet consumed** by combat-roll math; future passes will apply it as an untyped bonus.

**Action Dice (Remaining)**: The current Combatant's remaining action dice for the Round. Stored on the Combatant record. Decremented by `spend_action_dice`; reset to Action Dice Max by `reset_action_dice` (per-Combatant or all-at-once).

## State Files

**Rules File**: `combat_config.yaml`. Hand-edited; loaded once at boot. Carries Initiative Attribute, Initiative Divisor, Combat Pool Attribute, Combat Pool Range, and Combat Pool Minimum.

**State File**: `combat_data.yaml`. Atomically rewritten on every mutation. Carries `active`, `round`, `current_turn_index`, and the `combatants` list. Allowed fields per Combatant: `id`, `char_id`, `name`, `initiative_dice`, `action_dice`. The state file is the only place these values live across restarts.

## Module Scope

The Combat module:

- Owns a single in-memory Combat (one party, one fight at a time) plus its persisted state file.
- Tracks the active flag, round counter, turn pointer, and combatants list.
- Computes initiative dice count and action dice max on demand from the looked-up Character.
- Rolls initiative through the dice resolution module and applies Combat-specific Luck and Insight rules.
- Persists state atomically on every mutation.

It does **not**:

- Resolve attacks or compute damage (combat-roll math is future work).
- Apply conditions or track HP changes — conditions module.
- Know about more than one Combat at a time.
- Read characters directly — every Character read goes through the `character_lookup` callback supplied at construction.
