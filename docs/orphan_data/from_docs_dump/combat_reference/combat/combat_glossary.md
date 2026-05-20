# Combat — Glossary

Combat owns the per-tick combat state (combatants, initiative, tick schedule, Combat Pool). Round / Tick counters and time-of-day live in Timekeeping (see common glossary); Combat asks Timekeeping for the current Tick and notifies Timekeeping when a Tick completes. Depends on dice resolution for rolls and on the character module via a `character_lookup` callback. *(configurable)* values come from `combat_config.yaml`.

## Core

**Combat**: The tick-driven combat state machine. Persists to `combat_data.yaml` on every mutation; tunables live in `combat_config.yaml`.

**Combatant**: One participant in an active Combat. Carries `id` (Combat ID), `char_id` (Character ID), `name`, `initiative_string`, `combat_pool`, and a precomputed `tick_schedule` (the list of Ticks within a Round on which the Combatant acts).

**Combat ID**: Per-instance integer unique within the current Combat, allocated at `add_combatant`. Distinct from Character ID so duplicate monsters track separately.

**Character ID**: The underlying creature identity; used by the `character_lookup` callback to read attributes for derived values.

**Active**: Boolean indicating Combat is in progress. Toggled by `reroll_all_initiative` / `end_combat`. Starting combat calls `Timekeeping.start_combat(ticks_per_round)` with the max `Turns Per Round[tier]` across present Combatants; ending combat calls `Timekeeping.end_combat`.

## Tick Scheduling

**Tick Schedule**: A precomputed list of Ticks (within a Round) on which a Combatant acts. Computed at `add_combatant` and recomputed when Ticks Per Round changes (a Combatant joining or leaving may change the max). Formula: for `i = 1..Turns Per Round[tier]`, `tick_i = floor((Ticks Per Round * (2i - 1) + Turns Per Round) / (2 * Turns Per Round))` — the floored midpoint of the i-th equal segment of the Round (see Timekeeping in common glossary).

**Acting Combatants**: All Combatants whose Tick Schedule contains the current Tick (read from Timekeeping). Within a single Tick, ties break by Initiative String (ASCII descending), then by Combat ID for stability.

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

## Defensive actions

**Defensive Action**: One of `parry`, `block`, or `dodge` — declared by a defender on the attacker's turn. Each kind triggers an Opposed Roll with its own dice cost; the type is the only branch the to-hit pipeline cares about.

**Flatfooted**: Defender state when *no* Defensive Action is taken against an incoming attack. The attacker gains the **Flatfooted Bonus** (default `+1 Circumstance Bonus`) on the to-hit Roll. *(configurable: `Flatfooted Bonus: { type:, amount: }` in `combat_config.yaml`)*

## Damage Severity

**Severity Calculation**: Combat routes each damage point to a Severity bucket before passing the result to `APPLY_HIT_POINT_DAMAGE`. Non-physical damage types use the catalog's declared severity. Physical damage uses **Runtime Bucketing**: the first `Threshold + Damage Resilience` points fill Minor, the next fill Moderate, everything beyond goes to Major. Threshold comes from the weapon for weapon attacks or from the ability's `threshold` field for ability-driven physical damage; Damage Resilience comes from the defender's Character.

## State Files

**Rules File** (`combat_config.yaml`): Initiative Attribute, Initiative Divisor, Combat Pool Attribute, Combat Pool Divisor, Combat Pool Step, Turns Per Round.

**State File** (`combat_data.yaml`): `active`, `combatants`. Per-Combatant: `id`, `char_id`, `name`, `initiative_string`, `combat_pool`, `tick_schedule`. The Round and within-Round Tick counters live on Timekeeping, not here.

## Module Scope

Owns:
- One in-memory Combat plus its state file.
- Combatants list, active flag, per-Combatant Tick Schedule.
- Initiative dice count and Combat Pool derivation via `character_lookup`.
- Initiative reroll (delegating dice to dice resolution; applying Luck and Insight).
- Combat Pool spend / reset.
- Notifying Timekeeping at combat start (`start_combat(ticks_per_round)`), each tick advance (`advance_tick`), and combat end (`end_combat`).
- Severity Calculation including Runtime Bucketing for physical damage.
- Damage-type side-effect routing (`APPLY_ACID_DAMAGE`, `APPLY_SHOCK`, etc.) and supplying `critical_modifier` to dice resolution.

Does not:
- Track Round or Tick counters (Timekeeping owns those; Combat reads Timekeeping's Tick to find Acting Combatants).
- Resolve full attacks end-to-end (future work).
- Store HP or conditions (conditions module).
- Own the damage type catalog (damage_types module).
- Track multiple concurrent Combats.
- Read Characters directly (always via `character_lookup`).
