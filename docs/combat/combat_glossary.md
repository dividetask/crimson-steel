# Combat — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `combat_config.yaml`. The Combat module owns round-by-round combat state (combatants, initiative, turn pointer, Combat Pool). It depends on the dice resolution module for die rolls and on the character module via a lookup callback for per-character derived values.

## Core

**Combat**: The round-by-round state machine that tracks who is fighting, the order they act in, and how many resources each has spent. Persists to a state file (`combat_data.yaml.example`) on every mutation; rules tunables live separately (`combat_config.yaml.example`).

**Combatant**: One participant in an active Combat. Identified by two IDs (Combat ID and Character ID — see below) and carrying its own `name`, current `initiative_string` snapshot, and remaining `combat_pool` count.

**Combat ID**: A per-instance integer unique within the current Combat, allocated at `add_combatant` time. Distinct from Character ID so that two copies of the same monster track separately. Computed on the fly as one past the highest in-use id rather than persisted as a counter — the state file stays describable without bookkeeping.

**Character ID**: The underlying creature identity supplied at `add_combatant`. Used to look up the Character's attributes via the supplied `character_lookup` callback whenever a derived value (initiative dice count, Combat Pool size) is needed.

**Round**: A signed integer counter incremented when the turn pointer wraps past the last combatant. Reset to 1 at the start of every initiative reroll. The current Round is part of the persisted state.

**Active**: A boolean indicating Combat is in progress. Flipped on by `reroll_all_initiative`, off by `end_combat`.

## Turn Order

**Turn Order**: Combatants ordered by Initiative String in ASCII descending order — the per-die encoding (see `dice_resolution_glossary.md`'s **Initiative String Encoding**) is monotonic, so character-by-character lex compare produces the correct ordering. Final ties (identical strings) are broken by Combat ID for stability. Recomputed on every read rather than cached, since combatants and Initiative Strings may change between reads.

**Current Turn Index**: An integer index into the Turn Order pointing at the active Combatant. Modulo'd over the Turn Order length on every read so the index remains valid even after combatants are removed.

**Current Combatant**: The Combatant at `Current Turn Index`. Returns null when there are no Combatants.

## Initiative

**Initiative Attribute**: The Character Attribute consulted to determine how many initiative dice the Character rolls. *(configurable, default `wis`)*

**Initiative Divisor**: The divisor applied to the Initiative Attribute to produce the dice count. `dice_count = floor(attribute / Initiative Divisor)`. *(configurable, default 2 — a Wis-16 character rolls 8 dice; a divisor of 3 would give 5 dice)*

**Initiative String**: The current Combatant's initiative result, encoded as a single string per the dice resolution module's Initiative String Encoding. One character per die, sorted highest-to-lowest. Empty until the first reroll. Compared lexicographically (descending) for turn order; combat does not interpret the encoding — it just stores the string and hands it back to dice resolution for ordering.

**Initiative Luck**: A signed integer effect applied during initiative rerolling that rerolls extreme dice. **Positive** values reroll the lowest non-critical dice (favoring the Combatant); **negative** values reroll the highest non-failure dice (working against). Magnitude rerolls that many dice in priority order. Distinct from the dice resolution module's generic Reroll Operation because initiative has no Target Number, so the generic helpers don't apply.

**Initiative Insight**: A signed integer effect applied during initiative rerolling that nudges a single die's value. **Positive** values raise the lowest die that could become a Critical (`value + insight ≥ die_size`); if no die qualifies, raise the highest non-Critical instead. **Negative** values penalize the highest die. Magnitude rerolls repeat the operation that many times.

## Combat Pool

**Combat Pool Attribute**: The Character Attribute consulted to derive the Combat Pool Budget. *(configurable, default `wis`)*

**Combat Pool Divisor**: The divisor applied to the Combat Pool Attribute when computing the Budget. *(configurable, default 2)*

**Combat Pool Step**: The size of each cost tier when spending Budget on pool points. Also the minimum Combat Pool size every Combatant is guaranteed (since the first tier is free). *(configurable, default 4)*

**Turns Per Round**: An integer array indexed by Tier giving the number of turns a Combatant takes per Round. Index 0 = Tier 0. A Tier beyond the array length is an error. *(configurable, default `[1, 1, 1, 2, 4, 8]`)*

**Combat Pool Budget**: An intermediate `floor((martial_skill_ranks + floor(combat_pool_attribute / Combat Pool Divisor)) / Turns Per Round[tier])`. Both attribute and ranks are read via the `character_lookup` callback.

**Combat Pool**: The Combatant's Combat Pool size for one turn — the largest non-negative integer P such that the cumulative purchase cost does not exceed the Combat Pool Budget. Purchase cost scales by tier of size Combat Pool Step:

- Points 1 through Step cost **0** Budget each (free tier).
- Points Step+1 through 2·Step cost **1** Budget each.
- Points 2·Step+1 through 3·Step cost **2** Budget each.
- Points (k·Step)+1 through (k+1)·Step cost **k** Budget each.

Closed form: with `T = floor(P / Step)` and `R = P mod Step`, total cost = `Step · T·(T-1)/2 + R · T`. Leftover Budget that can't afford the next point is discarded. Computed on demand — never persisted.

**Combat Pool (Remaining)**: The current Combatant's remaining Combat Pool for the turn. Stored on the Combatant record. Decremented by `spend_combat_pool`; reset to Combat Pool by `reset_combat_pool` (per-Combatant or all-at-once).

## Damage Severity

**Severity Calculation**: The operation that decides which Severity bucket each point of inflicted damage lands in. Combat owns this. For non-physical damage types the Severity comes from the damage type's catalog entry (`damage_types_glossary.md`). For physical damage Combat performs **Runtime Bucketing**: the first `Threshold + Damage Resilience` points fill Minor, the next `Threshold + Damage Resilience` fill Moderate, everything beyond goes to Major. After Combat splits a damage event into per-Severity counts, it calls `APPLY_HIT_POINT_DAMAGE` on the target's conditions instance with the resulting `{minor, moderate, major}` map.

**Threshold (combat-side)**: The non-negative integer used in Runtime Bucketing. For weapon attacks Combat reads it from the weapon (Equipment); for ability-driven Physical Damage it reads it from the ability's `threshold` field. Combat picks one input — the weapon's value typically wins when both are present.

**Damage Resilience (combat-side)**: The defender's `damage_resilience` value, read through the Character (which sums tier-derived base + Advancement contribution). Combined with Threshold to size each Severity bucket during Runtime Bucketing.

## State Files

**Rules File**: `combat_config.yaml`. Hand-edited; loaded once at boot. Carries Initiative Attribute, Initiative Divisor, Combat Pool Attribute, Combat Pool Divisor, Combat Pool Step, and Turns Per Round.

**State File**: `combat_data.yaml`. Atomically rewritten on every mutation. Carries `active`, `round`, `current_turn_index`, and the `combatants` list. Allowed fields per Combatant: `id`, `char_id`, `name`, `initiative_string`, `combat_pool`. The state file is the only place these values live across restarts.

## Module Scope

The Combat module:

- Owns a single in-memory Combat (one party, one fight at a time) plus its persisted state file.
- Tracks the active flag, round counter, turn pointer, and combatants list.
- Computes the initiative dice count and Combat Pool Budget on demand from the looked-up Character, and derives Combat Pool from the Budget.
- Rolls initiative through the dice resolution module (which returns the Initiative String) and applies Combat-specific Luck and Insight rules.
- **Owns Severity Calculation**: routes every damage event through the damage_types catalog (or, for physical damage, through Runtime Bucketing) before passing per-Severity counts to the conditions module. Reads the inputs (damage type, threshold, damage resilience) but does not own them.
- **Routes damage-type mechanics to consumers**: invokes `APPLY_ACID_DAMAGE`, `APPLY_SHOCK`, etc., when a damage type's mechanics declare those side-effects, applies `damage_multiplier` factors before bucketing, and substitutes the per-roll `critical_modifier` when a damage type carries a `critical_value`.
- Persists state atomically on every mutation.

It does **not**:

- Resolve attacks (combat-roll math is future work).
- Apply conditions or track HP changes — conditions module owns the storage; combat only routes inputs into it.
- Define damage type behavior — the catalog lives in `damage_types_config.yaml`; combat reads it.
- Know about more than one Combat at a time.
- Read characters directly — every Character read goes through the `character_lookup` callback supplied at construction.
