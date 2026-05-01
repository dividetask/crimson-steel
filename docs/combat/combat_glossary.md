# Combat — Glossary

Combat owns round-by-round state (combatants, initiative, turn pointer, Combat Pool). It depends on dice resolution for rolls and on the character module via a `character_lookup` callback. *(configurable)* values come from `combat_config.yaml`.

## Core

**Combat**: The round-by-round state machine. Persists to `combat_data.yaml` on every mutation; tunables live in `combat_config.yaml`.

**Combatant**: One participant in an active Combat. Carries `id` (Combat ID), `char_id` (Character ID), `name`, `initiative_string`, and `combat_pool`.

**Combat ID**: Per-instance integer unique within the current Combat, allocated at `add_combatant`. Distinct from Character ID so duplicate monsters track separately.

**Character ID**: The underlying creature identity; used by the `character_lookup` callback to read attributes for derived values.

**Active**: Boolean indicating Combat is in progress. Toggled by `reroll_all_initiative` / `end_combat`.

## Turn Order

**Turn Order**: Combatants sorted by Initiative String, ASCII descending. Final ties break by Combat ID. Recomputed on every read.

**Current Turn Index**: Integer index into Turn Order. Modulo'd over length on read so it stays valid after removals.

**Current Combatant**: The Combatant at Current Turn Index. Null when none.

## Initiative

**Initiative Attribute**: Attribute consulted to determine the initiative dice count. *(configurable, default `wis`)*

**Initiative Divisor**: `dice_count = floor(attribute / Initiative Divisor)`. *(configurable, default 2)*

**Initiative String**: The Combatant's initiative result, encoded per `dice_resolution_glossary.md`'s **Initiative String Encoding**, sorted highest-to-lowest.

**Initiative Luck**: Signed integer rerolling extreme dice during initiative reroll. Positive rerolls the lowest non-Critical dice; negative rerolls the highest non-Failure dice. Magnitude sets count. *(combat-specific because initiative has no Target Number)*

**Initiative Insight**: Signed integer nudging a single die's value. Positive raises the lowest die that could become a Critical (or the highest non-Critical if none qualify); negative lowers the highest die. Magnitude repeats the operation.

## Combat Pool

**Combat Pool Attribute**: Attribute consulted for the Budget. *(configurable, default `wis`)*

**Combat Pool Divisor**: Divisor applied to the attribute when computing the Budget. *(configurable, default 2)*

**Combat Pool Step**: Size of each cost tier and the guaranteed minimum pool size (first tier is free). *(configurable, default 4)*

**Turns Per Round**: Integer array indexed by Tier; out-of-range Tier is an error. *(configurable, default `[1, 1, 1, 2, 4, 8]`)*

**Combat Pool Budget**: `floor((martial_skill_ranks + floor(attribute / Combat Pool Divisor)) / Turns Per Round[tier])`.

**Combat Pool**: Combatant's pool size for one turn — the largest P such that purchase cost ≤ Budget, with cost rising every Step points. Points 1..Step cost 0 each (free tier, guarantees a minimum); points Step+1..2·Step cost 1 each; points 2·Step+1..3·Step cost 2 each; and so on. Closed form: with `T = floor(P/Step)`, `R = P mod Step`, cost = `Step·T·(T-1)/2 + R·T`. Leftover Budget is discarded. Computed on demand.

**Combat Pool (Remaining)**: Per-Combatant remaining pool for the turn. Decremented by `spend_combat_pool`; reset to Combat Pool by `reset_combat_pool`.

## Damage Severity

**Severity Calculation**: Combat routes each damage point to a Severity bucket before passing the result to `APPLY_HIT_POINT_DAMAGE`. Non-physical damage types use the catalog's declared severity. Physical damage uses **Runtime Bucketing**: the first `Threshold + Damage Resilience` points fill Minor, the next fill Moderate, everything beyond goes to Major. Threshold comes from the weapon for weapon attacks or from the ability's `threshold` field for ability-driven physical damage; Damage Resilience comes from the defender's Character.

## State Files

**Rules File** (`combat_config.yaml`): Initiative Attribute, Initiative Divisor, Combat Pool Attribute, Combat Pool Divisor, Combat Pool Step, Turns Per Round.

**State File** (`combat_data.yaml`): `active`, `round`, `current_turn_index`, `combatants`. Per-Combatant: `id`, `char_id`, `name`, `initiative_string`, `combat_pool`.

## Module Scope

Owns:
- One in-memory Combat plus its state file.
- Combatants list, turn pointer, round counter, active flag.
- Initiative dice count and Combat Pool derivation via `character_lookup`.
- Initiative reroll (delegating dice to dice resolution; applying Luck and Insight).
- Combat Pool spend / reset.
- Severity Calculation including Runtime Bucketing for physical damage.
- Damage-type side-effect routing (`APPLY_ACID_DAMAGE`, `APPLY_SHOCK`, etc.) and supplying `critical_modifier` to dice resolution.

Does not:
- Resolve full attacks end-to-end (future work).
- Store HP or conditions (conditions module).
- Own the damage type catalog (damage_types module).
- Track multiple concurrent Combats.
- Read Characters directly (always via `character_lookup`).
