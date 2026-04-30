# Combat — Design

Companion to `combat_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Combat module is a thin state machine: it owns the **persisted state** of one in-progress Combat (combatants, dice, turn pointer) and computes per-Combatant derived values on demand by looking up the Character through a callback.

## Key Operations

### Two-ID Combatant scheme

Each Combatant has a Combat ID (per-instance, unique within this Combat) and a Character ID (the underlying creature, possibly shared by multiple Combatants of the same monster). Two copies of the same monster track separately because each gets its own Combat ID, but both look up the same Character record for derived stats.

`next_combat_id!` returns one past the highest in-use Combat ID. Computed rather than persisted — the state file describes only the values that matter to combat itself, not bookkeeping.

### Turn order with die-by-die tie-break

`turn_order` recomputes on every read. The sort key for each Combatant is the dice list sorted descending and negated (so Ruby's ascending sort places the highest values first), with the Combat ID as the final tie-break.

The die-by-die tie-break is what makes `[10, 7]` beat `[10, 6]`: the comparator runs left-to-right through the sorted-descending dice. This is observable: a Combatant who rolled `[10, 9, 1]` outranks a Combatant who rolled `[10, 8, 8]` despite having a worse second die because of when comparison stops? No — the comparator continues until one side wins, so `[10, 9]` wins on the second die regardless of what comes after. The full dice list participates in the key.

### Current Turn Index modulo

`Current Turn Index` is stored without modulo applied, so the raw value can grow indefinitely if combatants are added/removed. Every read takes `index % length` so removals don't leave the pointer dangling. `next_turn` advances the raw index and bumps the Round counter when the index wraps.

`remove_combatant` is more careful: if the removed Combatant wasn't the active one, the pointer is updated to keep the same Combatant on deck after the removal shifts positions. If the removed Combatant *was* the active one, the index stays put and naturally points at whoever inherits the slot.

### Initiative Luck (combat-specific Reroll Operation)

Initiative has no Target Number, so the dice resolution module's generic Reroll Operation (which prefers dice on the wrong side of the TN) doesn't apply. Combat implements its own variant:

- **Positive Luck (improve):** sort dice ascending and reroll up to `|luck|` of the lowest values, **skipping dice that are already Critical** (`value == die_size`). Already-critical dice are off-limits because rerolling them might produce a worse result, defeating the bonus's intent.
- **Negative Luck (worsen):** sort dice descending and reroll up to `|luck|` of the highest values, **skipping dice that are already Failure** (`value == 1`). Same logic in reverse.

Each die is rerolled at most once per Luck application (the iteration consumes each die in turn). Multiple iterations would require a second pass — today there's only one.

### Initiative Insight (combat-specific Value Adjustment)

Insight nudges a single die's value:

- **Positive Insight:** look for "crit-capable" dice (non-Critical dice where `value + insight ≥ die_size`). If any qualify, pick the **lowest** of them — bumping a low die to a Critical is the highest-impact use of the bonus. If none qualify, fall back to the **highest non-Critical** die, since that produces the largest non-Critical value.
- **Negative Insight:** pick the **highest** die and lower it (clamped at 1).

Magnitudes greater than 1 repeat the operation. The current implementation runs the same selection rules on each iteration — the chosen die may differ between iterations as values change.

### Action dice formula

Action Dice Max is `(raw % Combat Pool Range) + Combat Pool Minimum`. The `raw` term is `martial_skill_ranks + floor(combat_pool_attribute / 2)`. Why the modulo? It caps the per-round pool at `Combat Pool Range + Combat Pool Minimum - 1` (e.g. defaults: 10 + 11 - 1 = 20), keeping high-rank Characters from dominating any single round. The integer-division half (`floor(raw / Combat Pool Range)`) is exposed as **Unused Bonus** as a placeholder — the design hasn't decided what it should do, but the value is preserved so a future consumer can pick it up without a recompute.

Action Dice Max is **never persisted**. It's computed every time it's needed by reading the Character's current stats. This means a temporary buff to martial or wisdom shows up immediately without combat needing to recompute or invalidate caches.

### Atomic state persistence

`save!` writes the state file atomically on every mutation. Reads at startup are tolerant: missing state file → empty Combat. Adding/removing combatants, rerolling initiative, advancing turns, spending action dice, ending combat — all save immediately. The rules file is loaded only at boot; mid-session changes to combat tunables require a restart.

### Severity Calculation and damage routing

When attack resolution lands a damage event, Combat is the layer that turns *"N points of damage type T inflicted on Combatant C"* into per-Severity Hit Point Damage on C's Conditions instance. The pipeline:

1. **Look up the damage type's catalog entry** in damage_types. Read its declared severity (or `runtime_bucketing: true` for physical) and its mechanics list.
2. **Apply pre-bucketing mechanics**: `damage_per_dice` adjustments (fire's +1/2dice), `damage_multiplier` factors (electricity vs metal armor, radiant vs undead/shadow). The condition tags (`target_has_metal_armor`, `target_has_subtype:undead`) are interpreted here against equipment / character state.
3. **Determine Severity**:
   - Non-physical: every point lands at the catalog's declared severity. The `{minor: 0, moderate: N, major: 0}` shape (or whichever bucket the type names) goes to Conditions.
   - **Physical (Runtime Bucketing)**: read Threshold (from the weapon, or the ability for direct physical damage from an ability), and Damage Resilience (from the defender's Character). Fill Minor up to `Threshold + Damage Resilience`, then Moderate up to another `Threshold + Damage Resilience`, then everything else into Major.
4. **Call `APPLY_HIT_POINT_DAMAGE`** on the defender's Conditions instance with the resulting `{minor, moderate, major}` map. Conditions handles Temp HP absorption from there.
5. **Apply post-damage side-effect mechanics**: `apply_acid_counter` (call `APPLY_ACID_DAMAGE` on Conditions with `damage * per_damage`), `inflict` for shock and similar (call `APPLY_SHOCK`), and any future hardcoded side-effects.

The `critical_value` mechanic is consumed earlier — at the dice-resolution layer when the attack roll is rolled, not in this damage pipeline. Combat is responsible for telling dice resolution which damage type's `critical_value` (if any) applies to the Roll.

Combat does **not** own the catalog itself or any Conditions storage; it just sequences the lookups and the calls. A misconfigured damage type (unrecognized `condition` tag, unknown `condition_name`) surfaces here as a silent fallthrough — the consumer-side validation gap is in the unassigned list across damage_types.

## Responsibilities

### Owned by the combat domain

- The single in-memory Combat: combatants list, turn pointer, round counter, active flag.
- Combat ID allocation and Combatant identity (Combat ID + Character ID).
- Turn Order computation with die-by-die tie-break.
- Initiative dice count and Action Dice Max derivation (via the supplied `character_lookup`).
- Initiative reroll: rolling through the dice resolution module, then applying combat-specific Luck and Insight rules.
- Action dice spend / reset.
- Atomic state persistence and load.
- **Severity Calculation** for incoming damage events: looking up the damage type's catalog entry, applying pre-bucketing mechanics (`damage_per_dice`, `damage_multiplier`), performing Runtime Bucketing for physical damage from `Threshold + Damage Resilience`, and routing the resulting `{minor, moderate, major}` map to the conditions module's `APPLY_HIT_POINT_DAMAGE`.
- **Side-effect routing** for damage-type mechanics: invoking `APPLY_ACID_DAMAGE`, `APPLY_SHOCK`, and similar conditions APIs based on the damage type's `apply_acid_counter` / `inflict` mechanics.
- Telling dice resolution which damage type's `critical_value` (if any) applies to an attack Roll.

### Explicitly *not* owned here

- **Character attributes and skill ranks** — read through `character_lookup` (the Character class).
- **Generic Reroll Operation and Value Adjustment semantics** — dice resolution. Combat owns *initiative-specific* variants because initiative has no Target Number.
- **Hit points, conditions, magic toxicity, shock** — conditions module, indexed per-Character externally.
- **The damage type catalog itself** — lives in `damage_types_config.yaml`. Combat reads it but does not own it.
- **HP storage, condition tracking, the Acid Counter, Shock, magic toxicity** — conditions module owns the storage; combat invokes the conditions APIs to mutate it.
- **Attack resolution math (the to-hit roll itself)** — future work; the current module exposes the inputs (initiative, action dice, unused bonus) but doesn't consume them.
- **Multiple concurrent Combats** — by design, one fight at a time.

### Unassigned (no current owner)

- **Attack resolution.** Today there's no method that says "Combatant A attacks Combatant B with weapon W"; once it lands, the Severity Calculation pipeline above takes over.
- **Unused Bonus.** The integer-division half of the action dice formula. The design hasn't decided how (or whether) to apply it; it's stored as a placeholder so a future use doesn't have to recompute.
- **Initiative reroll edge cases.** The Luck loop reads dice in their pre-Luck order; running multiple iterations of Insight on the same dice list may repeatedly pick the same die unless values change. Both are tractable but unspecified.
