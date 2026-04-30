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

Action Dice Max is `(raw % Combat Pool Range) + Combat Pool Minimum`. The `raw` term is `martial_skill_ranks + floor(combat_pool_attribute / 2)`. Why the modulo? It caps the per-round pool at `Combat Pool Range + Combat Pool Minimum - 1` (e.g. defaults: 10 + 11 - 1 = 20), keeping high-rank Characters from dominating any single round. The integer-division half (`floor(raw / Combat Pool Range)`) is exposed as **Untyped Bonus** for future combat-roll math to consume — today it's read-only.

Action Dice Max is **never persisted**. It's computed every time it's needed by reading the Character's current stats. This means a temporary buff to martial or wisdom shows up immediately without combat needing to recompute or invalidate caches.

### Atomic state persistence

`save!` writes the state file atomically on every mutation. Reads at startup are tolerant: missing state file → empty Combat. Adding/removing combatants, rerolling initiative, advancing turns, spending action dice, ending combat — all save immediately. The rules file is loaded only at boot; mid-session changes to combat tunables require a restart.

## Responsibilities

### Owned by the combat domain

- The single in-memory Combat: combatants list, turn pointer, round counter, active flag.
- Combat ID allocation and Combatant identity (Combat ID + Character ID).
- Turn Order computation with die-by-die tie-break.
- Initiative dice count and Action Dice Max derivation (via the supplied `character_lookup`).
- Initiative reroll: rolling through the dice resolution module, then applying combat-specific Luck and Insight rules.
- Action dice spend / reset.
- Atomic state persistence and load.

### Explicitly *not* owned here

- **Character attributes and skill ranks** — read through `character_lookup` (the Character class).
- **Generic Reroll Operation and Value Adjustment semantics** — dice resolution. Combat owns *initiative-specific* variants because initiative has no Target Number.
- **Hit points, conditions, magic toxicity, shock** — conditions module, indexed per-Character externally.
- **Attack resolution and damage calculation** — future work; the current module exposes the inputs (initiative, action dice, untyped bonus) but doesn't consume them.
- **Multiple concurrent Combats** — by design, one fight at a time.

### Unassigned (no current owner)

- **Attack resolution.** Today there's no method that says "Combatant A attacks Combatant B with weapon W"; the combat-roll math is future work.
- **Untyped Bonus consumption.** The bonus is exposed but no combat-roll consumer exists.
- **Damage routing.** When attack resolution lands, it'll need to call into the conditions module's `APPLY_HIT_POINT_DAMAGE` with the right Severity per Damage Type. The wiring isn't pinned anywhere.
- **Counter wiring** (acid, etc.). When physical/elemental damage applies a counter mechanic per `damage_types_glossary.md`, combat is the natural caller — but the connection isn't implemented.
- **Initiative reroll edge cases.** The Luck loop reads dice in their pre-Luck order; running multiple iterations of Insight on the same dice list may repeatedly pick the same die unless values change. Both are tractable but unspecified.
