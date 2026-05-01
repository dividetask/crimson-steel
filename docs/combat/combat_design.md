# Combat — Design

The Combat module is a thin state machine: it owns the **persisted state** of one in-progress Combat (combatants, dice, turn pointer) and computes per-Combatant derived values on demand by looking up the Character through a callback.

## Key Operations

### Two-ID Combatant scheme

Each Combatant has a Combat ID (per-instance, unique within this Combat) and a Character ID (the underlying creature, possibly shared by multiple Combatants of the same monster). Two copies of the same monster track separately because each gets its own Combat ID, but both look up the same Character record for derived stats.

`next_combat_id!` returns one past the highest in-use Combat ID. Computed rather than persisted — the state file describes only the values that matter to combat itself, not bookkeeping.

### Turn order via Initiative String compare

The Initiative String Encoding (defined in `dice_resolution_glossary.md`) is monotonic — higher die values map to higher ASCII characters — so plain lex compare on the strings reproduces a die-by-die comparison without combat needing to interpret the encoding. `XX95` beats `XX88` because position 2 differs (`9 > 8`). `X775` beats `X77` because, with the prefix matching, the longer string is greater under lex compare. A Combatant who rolled an 8 on a single die outranks one whose three dice all rolled 7-or-lower — first character `8 > 7` decides. Combat does not need to special-case mismatched dice counts.

Final ties break by Combat ID. `turn_order` recomputes on every read.

### Current Turn Index modulo

`Current Turn Index` is stored without modulo applied, so the raw value can grow indefinitely if combatants are added/removed. Every read takes `index % length` so removals don't leave the pointer dangling. `next_turn` advances the raw index and bumps the Round counter when the index wraps.

`remove_combatant` is more careful: if the removed Combatant wasn't the active one, the pointer is updated to keep the same Combatant on deck after the removal shifts positions. If the removed Combatant *was* the active one, the index stays put and naturally points at whoever inherits the slot.

### Initiative Luck (combat-specific Reroll Operation)

Initiative has no Target Number, so the dice resolution module's generic Reroll Operation (which prefers dice on the wrong side of the TN) doesn't apply. Combat's variant:

- **Positive Luck:** sort dice ascending and reroll up to `|luck|` of the lowest values, **skipping dice already Critical**. Already-critical dice are off-limits because rerolling them might produce a worse result, defeating the bonus's intent.
- **Negative Luck:** sort dice descending and reroll up to `|luck|` of the highest values, **skipping dice already Failure**. Same logic in reverse.

Each die is rerolled at most once per Luck application.

### Initiative Insight (combat-specific Value Adjustment)

- **Positive Insight:** look for "crit-capable" dice (non-Critical dice where `value + insight ≥ die_size`). If any qualify, pick the **lowest** of them — bumping a low die to a Critical is the highest-impact use of the bonus. If none qualify, fall back to the **highest non-Critical** die, since that produces the largest non-Critical value.
- **Negative Insight:** pick the **highest** die and lower it (clamped at 1).

Magnitudes greater than 1 repeat the operation; the chosen die may differ between iterations as values change.

### Combat Pool formula

Two stages.

**Stage 1 — Budget:**
```
budget = floor((martial_skill_ranks
                + floor(combat_pool_attribute / Combat Pool Divisor))
               / Turns Per Round[tier])
```

A Tier beyond `Turns Per Round`'s length is an error rather than a clamp — the campaign config must extend the list before high-Tier Combatants enter combat.

**Stage 2 — Buy Combat Pool.** Points 1..Step are free (every Combatant therefore guaranteed at least `Combat Pool Step` points regardless of Budget); points (k·Step)+1..(k+1)·Step cost k each. Combat Pool is the largest count P that fits within the Budget. Closed form: with `T = floor(P / Step)` and `R = P mod Step`, total cost = `Step · T·(T-1)/2 + R · T`.

Combat Pool is **never persisted**. It's computed every time it's needed by reading the Character's current stats, so a temporary buff to martial ranks or the Combat Pool Attribute shows up immediately without combat needing to invalidate caches.

### Atomic state persistence

`save!` writes the state file atomically on every mutation. Reads at startup are tolerant: missing state file → empty Combat. The rules file is loaded only at boot; mid-session changes to combat tunables require a restart.

### Attack resolution pipeline

An attack resolves in two halves. Either half may be implemented in either language (today the attack roll itself happens client-side and the damage routing happens server-side, but that's an implementation detail).

**Attack roll half:**

1. Build the attacker's Roll: dice count from `attack_dice` (the Combatant's combat-pool spend), TN from the attacker's modifiers plus dice resolution rules.
2. Build the target's Opposed Roll for their defense action.
3. Roll both through dice resolution. The damage type's `critical_value` mechanic, if any, becomes the `critical_modifier` for the attacker's Roll (`critical_modifier_for(damage_type)`).
4. Compute the Degree of Success (attacker DoIS minus defender DoIS). DoS ≥ Default Success Threshold → attack lands.
5. Compute raw damage:
   - Entry declares an explicit damage Effect → evaluate through `evaluate_damage` with the attacker's `success`/`critical` counts.
   - Entry has `attack_roll: true` and **no** declared damage Effect → Combat infers `Tier + Degree of Success + attack bonus`.

**Damage routing half (Severity Calculation):**

Combat takes raw damage + damage type and turns it into per-Severity Hit Point Damage on the defender's Conditions. The pipeline:

1. Look up the catalog entry. Read declared severity (or `runtime_bucketing: true`) and mechanics.
2. Apply pre-bucketing mechanics: `damage_per_dice` adjustments, `damage_multiplier` factors. Condition tags (`target_has_metal_armor`, `target_has_subtype:undead`) are interpreted here against equipment / character state.
3. Determine Severity:
   - Non-physical: every point lands at the catalog's declared severity.
   - Physical (Runtime Bucketing): read Threshold (weapon or ability) and Damage Resilience (defender). Fill Minor up to `Threshold + Damage Resilience`, then Moderate up to another `Threshold + Damage Resilience`, then everything else into Major.
4. Call `APPLY_HIT_POINT_DAMAGE` on the defender's Conditions with the resulting `{minor, moderate, major}` map. Conditions handles Temp HP absorption from there.
5. Apply post-damage side-effects: `apply_acid_counter` → `APPLY_ACID_DAMAGE`, `inflict` for shock and similar → `APPLY_SHOCK`.

The `critical_value` mechanic is consumed earlier — at the dice-resolution layer — not in this damage pipeline. Combat is responsible for telling dice resolution which damage type's `critical_value` (if any) applies to the Roll.

A misconfigured damage type (unrecognized `condition` tag, unknown `condition_name`) surfaces here as a silent fallthrough — the consumer-side validation gap is in the unassigned list across damage_types.

## Responsibilities

### Owned by the combat domain

- The single in-memory Combat: combatants, turn pointer, round counter, active flag.
- Combat ID allocation and the two-ID identity scheme.
- Turn Order computation with die-by-die tie-break.
- Initiative dice count and Combat Pool derivation via `character_lookup`.
- Initiative reroll: rolling through dice resolution, then applying combat-specific Luck and Insight.
- Combat Pool spend / reset.
- Atomic state persistence and load.
- Severity Calculation including Runtime Bucketing, pre-bucketing mechanics, and routing the resulting `{minor, moderate, major}` map to Conditions' `APPLY_HIT_POINT_DAMAGE`.
- Side-effect routing for damage-type mechanics (`APPLY_ACID_DAMAGE`, `APPLY_SHOCK`, etc.).
- Telling dice resolution which damage type's `critical_value` applies to an attack Roll.

### Explicitly *not* owned here

- **Character attributes and skill ranks** — read through `character_lookup`.
- **Generic Reroll Operation and Value Adjustment semantics** — dice resolution. Combat owns *initiative-specific* variants because initiative has no Target Number.
- **Hit points, conditions, magic toxicity, shock, the Acid Counter** — conditions module owns the storage; combat invokes the conditions APIs to mutate it.
- **The damage type catalog itself** — lives in `damage_types_config.yaml`. Combat reads it but does not own it.
- **Multiple concurrent Combats** — by design, one fight at a time.

### Unassigned (no current owner)

- **A canonical attack-resolution entry point** that wires both halves end-to-end. The pieces exist; a single "Combatant A attacks Combatant B with weapon W" composition is still future work.
- **Initiative reroll edge cases.** Multiple iterations of Insight on the same dice list may repeatedly pick the same die unless values change.
