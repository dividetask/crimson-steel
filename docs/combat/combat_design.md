# Combat — Design

Combat is a state machine over the lifetime of one fight. It owns the persisted state of the active Combat (Combatants, Initiative, per-Combatant Time Tick Schedule, Concentration entries, Luck Points), reads canonical time from Chronicle, and computes per-Combatant derived values on demand by looking up the Creature through a `creature_lookup` callback.

Sibling domains:
- **Chronicle** owns the canonical Timestamp. Combat reads it and notifies Chronicle when a Round elapses.
- **Conditions** owns per-Creature mutable state (HP damage, ability damage, Active Effects, Acid Counter, Shock, Magic Toxicity, etc.). Combat tells Conditions what damage / side-effect to apply but never stores any of it.
- **Dice Resolution** owns Roll mechanics. Combat builds Rolls and invokes Dice Resolution; Combat-specific Roll variants for Initiative (no Target Number) live here.
- **Damage Types** is folded into Combat — the catalog is part of `combat_config.yaml` and the Severity Calculation pipeline is owned here.

## Common types

### Combatant

| Field | Type | Description |
|---|---|---|
| `id` | integer | Combat ID. Unique within the active Combat. |
| `creature_id` | string | Identity passed to `creature_lookup`. |
| `name` | string | Display name. |
| `initiative_string` | string | Per *Initiative String* in the glossary. Empty until first Reroll Initiative. |
| `combat_pool_remaining` | integer | Combat Pool (Remaining). Reset to Combat Pool at the start of this Combatant's turn. |
| `time_tick_schedule` | list of integer | Time Ticks within a Round on which this Combatant acts. Recomputed when Time Ticks Per Round changes. |
| `luck_points` | integer | Per-Combatant Luck Points. Cleared at the start of this Combatant's turn. |
| `performed_this_turn` | boolean | Whether this Combatant has acted yet in the active Combat. Drives the Unaware Bonus eligibility. Set true at first turn end; never reset back to false within the Combat. |
| `concentration` | list of Concentration Entry | Concentration spells the Combatant is currently holding (Channeled spells and long-cast in-progress spells). |

### Concentration Entry

One entry per Channeled spell (or long-cast in-progress spell) a Combatant currently holds.

| Field | Type | Description |
|---|---|---|
| `spell_name` | string | Display name. Combat does not interpret it. |
| `source` | string | Opaque domain reference handed back when Combat needs the source domain to tear down the effect. |
| `spell_tier` | integer | The cast spell's tier. Used in the Concentration Save penalty formula. |
| `cast_skill` | string | The skill the spell was cast with. The Concentration Save Roll uses this skill. |
| `mode` | enum | Channel Mode mirrored from the Ability — `fire`, `reservoir`, `maintain`, or `auto`. |
| `reservoir` | integer | Reservoir dice currently held. Always 0 for `fire` and `maintain` modes. |
| `channeled_this_turn` | boolean | True once the Combatant has spent a Main Action channeling this entry on their current turn. Reset to false at the start of each of the Combatant's turns. End-of-turn check ends any entry where this is still false (auto-mode is exempt). |

### Granted Action

| Field | Type | Description |
|---|---|---|
| `combatant_id` | integer | The Combatant the action is granted to. |
| `name` | string | Display name. |
| `source` | string | Display label for the source — e.g. the granting spell's name. Used for UI surfacing. |
| `category` | enum | `main` \| `bonus` \| `free` \| `reaction`. |
| `eligible_targets` | list of Combat ID | Restricts which Combatants may be targeted. Empty list means no restriction (Combat presents the full Combatant roster). |
| `reaction_to` | (Combat ID, action name) or null | For `reaction` category only. Identifies the Main Action that granted this Reaction allowance. |
| `callback` | opaque | Invoked by Combat when the action is chosen. Combat does not interpret the callback's payload. |

### Combat State

| Field | Type | Description |
|---|---|---|
| `time_ticks_per_round` | integer or null | `null` when no Combat is active. |
| `time_tick` | integer or null | Current Time Tick within the Round, in the range `1..time_ticks_per_round`. `null` when no Combat is active. |
| `combat_anchor` | Chronicle Timestamp or null | The Timestamp captured at *Start Combat*. `null` when no Combat is active. |
| `elapsed_time_ticks` | integer | Cumulative Time Ticks completed since *Start Combat*. Used for the Stale Combat check. Reset to 0 at *Start Combat*. |
| `acting_combatant_id` | integer or null | Combat ID of the Combatant whose turn it currently is. `null` when no Combat is active. Storing the Combat ID rather than a list index keeps the pointer stable across mid-Time Tick list reorderings (add/remove Combatant). |
| `combatants` | list of Combatant | |
| `granted_actions` | list of Granted Action | |
| `dm_luck_points` | integer | Cleared only at *End Combat*. |

## Public entry points

These are the operations other domains call. Function names below are conceptual labels; implementations choose the actual symbols.

### Start Combat

Inputs: a list of Creature IDs (and optional name overrides).

Behavior:
1. Read the current Timestamp from Chronicle and store as Combat Anchor.
2. Allocate Combat IDs and create one Combatant per input. Each Combatant starts with empty `initiative_string`.
3. Compute Time Ticks Per Round = `max(Turns Per Round[tier])` across the Combatants (read each Tier through `creature_lookup`).
4. Compute each Combatant's Time Tick Schedule.
5. Reset `time_tick` to 1; `elapsed_time_ticks` to 0; `acting_combatant_id` to null; `dm_luck_points` to 0; per-Combatant `performed_this_turn` to false, `luck_points` to 0, `concentration` to empty.
6. Persist.

Rolling Initiative is not part of *Start Combat*. The caller follows up with *Reroll Initiative* (typically with no prerolled values, to roll every Combatant). Splitting the two lets the caller batch-set initiative from a prepared sheet or roll on demand.

Returns: the resulting Combat State.

### End Combat

Inputs: none.

Behavior:
1. Notify the post-combat consumer (Equipment / Loot — target domain pending) of the list of participating Combatants, each entry carrying its Combat ID and Creature ID. The consumer is expected to drive loot distribution, XP, post-combat recovery, etc.
2. Clear `time_ticks_per_round`, `time_tick`, `combat_anchor`, `elapsed_time_ticks`, `acting_combatant_id`, `combatants`, `granted_actions`, `dm_luck_points`.
3. Persist.

Concentration Entries are **not** ended by End Combat — a caster may continue holding a spell into the post-combat window. They become subject to the wider system's out-of-combat handling, which is out of scope here.

### Add Combatant

Inputs: Creature ID, optional name override.

Behavior: Allocate a Combat ID one past the current maximum, create the Combatant with empty `initiative_string`, recompute Time Ticks Per Round (the new Combatant's Tier may raise it). If Time Ticks Per Round changed, recompute every Combatant's Time Tick Schedule. Persist.

Rolling the newcomer's Initiative is not part of *Add Combatant*. The caller follows up with *Reroll Initiative* in `missing_only` mode (or with a prerolled-initiative override) to fill in the new entry without disturbing existing ones.

### Remove Combatant

Inputs: Combat ID.

Behavior: Drop the Combatant from the list. Recompute Time Ticks Per Round; if it dropped, recompute every remaining Combatant's Time Tick Schedule and clamp `time_tick` to the new range if needed. Clear any Granted Actions that referenced the removed Combatant as actor or eligible target. Notify each of the removed Combatant's Concentration sources that the spell has ended. If `acting_combatant_id` matched the removed Combatant, set it to null (the caller is expected to call *Advance Turn* to find the next one). Persist.

### Reroll Initiative

Inputs:
- `luck_insight` — optional map from Combat ID to `(luck, insight)`. Combat IDs not present in the map roll with no Luck or Insight applied.
- `prerolled_initiatives` — optional map from Combat ID to Initiative String. Combat IDs present in the map skip the random roll entirely; their `initiative_string` is set to the supplied value. The map may include any subset of Combatants — including none, in which case every Combatant rolls normally.
- `missing_only` — optional boolean, default false. When true, only Combatants whose `initiative_string` is currently empty are considered for rolling. Combatants with an existing `initiative_string` are left untouched (unless they appear in `prerolled_initiatives`, which always takes precedence).

Behavior: For each Combatant selected by the parameters above:
1. If the Combat ID is in `prerolled_initiatives`, set `initiative_string` to the supplied value and skip the roll.
2. Otherwise compute initiative dice count = `floor(Initiative Attribute / Initiative Divisor)` (read through `creature_lookup`).
3. Call Dice Resolution's *Resolve a Roll without a Target Number* with `dice_count` set; apply this Combatant's Initiative Luck and Initiative Insight from the `luck_insight` map (see Operations); store the resulting Dice Result String as `initiative_string`.
4. Persist.

Common call patterns:
- Bulk roll at encounter start: no `prerolled_initiatives`, `missing_only = false` — every Combatant rolls.
- After *Add Combatant*: no `prerolled_initiatives`, `missing_only = true` — only the new Combatants (whose `initiative_string` is empty) roll.
- DM-set initiative: pass `prerolled_initiatives` mapping the relevant Combat IDs to the desired strings.

### Advance Turn

Inputs: none.

Behavior:
1. Apply Per-Turn Cleanup to the Combatant identified by `acting_combatant_id` (the Combatant whose turn just ended).
2. Compute the Acting Combatants for the current Time Tick — every Combatant whose `time_tick_schedule` contains the current Time Tick, sorted by `initiative_string` ASCII-descending then by Combat ID.
3. Find the outgoing Acting Combatant's position in that list and pick the next entry as the new `acting_combatant_id`. If the move falls off the end of the list, call *Advance Time Tick* and pick the first Acting Combatant of the new Time Tick.
4. **Skip Combatants who cannot act.** Before settling on a new `acting_combatant_id`, query *Creature Can Act?*. If it returns false, repeat steps 2–3 to find the next Combatant. Combatants whose turn is skipped remain in the Combat's roster so the Game Master can see them and intervene on their behalf.
5. Persist.

Acting Combatants is an internal computation, not a public entry point — callers don't need to enumerate the list; they query the Acting Combatant directly via `acting_combatant_id`.

### Advance Time Tick

Inputs: none.

Behavior: Increment `time_tick` by 1 and `elapsed_time_ticks` by 1. If the new `time_tick` exceeds Time Ticks Per Round, reset `time_tick` to 1 and call Chronicle's *Advance current Timestamp* with `rounds = 1` — Chronicle handles Day rollover. When `time_tick` resets to 1, also apply *Apply Per-Round Cleanup*. Set `acting_combatant_id` to the first Acting Combatant of the new Time Tick (highest Initiative String, Combat ID tie-breaker). Persist.

### Is Stale?

Inputs: none.

Returns: boolean. True iff `combat_anchor` is non-null and Chronicle's Current Round ≠ `combat_anchor.round_of_day + floor(elapsed_time_ticks / Time Ticks Per Round)` (mod Rounds Per Day, with Day rollover handled). Used by stub-layer UIs to flag drift; takes no corrective action.

### Get Combat Pool

Input: Combat ID.

Returns: the Combatant's Combat Pool size (computed on demand from the underlying Creature's stats — never persisted). See *Combat Pool Computation* in Operations.

### Spend Combat Pool

Inputs: Combat ID, integer `amount`.

Behavior: Decrement the Combatant's `combat_pool_remaining` by `amount`. Refuses negative amounts and amounts that would drop `combat_pool_remaining` below 0 (returns an error sentinel; persistence does not happen).

Returns: the new remaining value, or an error sentinel.

### Reset Combat Pool

Input: Combat ID.

Behavior: Set the Combatant's `combat_pool_remaining` to *Get Combat Pool*'s result. Called as part of *Apply Per-Turn Cleanup*; also exposed for explicit calls.

### Apply Damage

Inputs: defender Combat ID, raw damage integer, Damage Type name, optional `threshold` (used only for Damage Types that Runtime-Bucket).

Behavior: Run the *Severity Calculation* pipeline (see Operations) and call Conditions' `APPLY_HIT_POINT_DAMAGE` with the resulting `{minor, moderate, major}` map. Apply Damage Type Mechanic side effects (e.g. Acid → call Conditions' `APPLY_ACID_DAMAGE`; Cold → call Conditions' Shock apply). If the defender has any Concentration entries, trigger one Concentration Save per entry (see *Concentration Damage Save* in Operations); a failed save calls *Break Concentration* for that entry.

Returns: a struct with the per-Severity damage, the Concentration save results, and any Damage Type Mechanic outputs (e.g. residual acid).

### Grant Action

Inputs: Granted Action.

Behavior: Append to `granted_actions`. Persist. No interpretation of the action itself.

### Revoke Action

Inputs: a predicate over Granted Actions (e.g. matching `source` and `combatant_id`).

Behavior: Remove every Granted Action that matches. Persist.

### List Granted Actions

Input: Combat ID.

Returns: the Granted Actions targeting that Combatant as actor. The caller filters by category as needed.

### Begin Concentration

Inputs: Combat ID, spell name, source, spell tier (integer), cast skill (string), Channel Mode (`fire` / `reservoir` / `maintain` / `auto`), initial reservoir dice (integer, may be 0).

Behavior: Append a Concentration Entry to the Combatant with `channeled_this_turn` set to true (the cast itself counts as that turn's channel) and `reservoir` set to the initial reservoir dice value. Persist. The caller — typically a Spell domain casting routine — is responsible for ensuring the casting itself paid the appropriate dice through *Spend Combat Pool* and that the on-target effect was added to Conditions. Combat only owns the channel and breakage flags from this point on.

For `fire` and `maintain` modes the initial reservoir is always 0. For `reservoir` mode the initial reservoir is the dice channeled at cast time, multiplied by the Ability's `reservoir_ratio`. For `auto` mode the initial reservoir is the dice paid at cast time, multiplied by `reservoir_ratio`, and remains fixed for the spell's duration.

### Channel

Inputs: Combat ID, spell name, dice spent (integer).

Behavior: Validate that the Combatant holds a Concentration Entry by that name. Refuse if the dice spent is below Main Action Minimum, or — for `maintain` mode — anything other than Main Action Minimum. For `fire` mode the caller is responsible for using the dice spent as the Roll's dice count (Dice Cap does not apply to channeling). For `reservoir` mode, add `dice_spent * reservoir_ratio` to the entry's `reservoir`. For `auto` mode, refuse (auto spells require no channel). Set `channeled_this_turn` to true. Combat does not itself debit `combat_pool_remaining` — the caller is expected to call *Spend Combat Pool* for the dice cost in coordination.

### Spend Reservoir

Inputs: Combat ID, spell name.

Behavior: For a `reservoir`-mode Concentration Entry, decrement `reservoir` by 1. Refuse when `reservoir` is 0. Persist. The caller is responsible for invoking the spell's Activation effect through its source domain.

### End Concentration

Inputs: Combat ID, spell name.

Behavior: Remove the matching Concentration Entry from the Combatant (including any held Reservoir) and notify the source domain (via the entry's `source` reference). The source domain is responsible for telling Conditions to clear the on-target Active Effect. Persist.

### Creature Can Act?

Input: Combat ID.

Returns: boolean. Delegates to Conditions: false if the Combatant is Dying or Dead, or carries a "cannot act" Active Effect (Paralyzed, Stunned, Unconscious, etc.). Combat does not enumerate the list — it asks Conditions.

### Creature Is Dying?

Input: Combat ID. Returns: boolean. Delegates to Conditions.

### Creature Is Dead?

Input: Combat ID. Returns: boolean. Delegates to Conditions.

### Critical Modifier For

Input: Damage Type name.

Returns: the integer `critical_modifier` to put on the attacker's Roll for a Roll resolving an attack of that Damage Type. Reads the Type's `critical_value` Mechanic from `combat_config.yaml`. When the Type has no `critical_value` Mechanic, returns the Roll struct default (`critical_modifier = 2`). Used at Roll-construction time, not in the damage pipeline.

### Attack / Cast / Use Item *(declared, future work)*

Inputs: actor Combat ID, target spec, the action data (weapon, spell name, item, etc.).

Behavior: **The full multi-step attack-resolution pipeline is not implemented yet.** These entry points are declared so other domains can target them, and so they appear in `granted_actions` dispatch without callers needing to invent an interface. The pipeline will include: building the attacker's Roll (with `preroll` for Set-Value Spend, `critical_modifier` from *Critical Modifier For*, the Flatfooted Bonus when the defender takes no Defensive Action, and the Unaware Bonus when the defender has not yet acted or when the attacker is Hidden from the defender), building the defender's Opposed Roll, optional ally-Reaction Rolls (e.g. Shield of Faith block check via a Granted Action's callback), invoking Check Resolution, and routing the result through *Apply Damage*. Pinned in *Module Scope → Unassigned* until designed.

## Operations

### Time Tick Schedule formula

For a Combatant of Tier `tier` with `T = Turns Per Round[tier]` and the active `Time Ticks Per Round` value `R`, their Time Tick Schedule is the list `[floor((R * (2i - 1) + T) / (2T)) for i = 1..T]` — the floored midpoints of T equal segments of the Round. Example with `R = 4`:

- `T = 1`: `[2]`.
- `T = 2`: `[1, 3]`.
- `T = 4`: `[1, 2, 3, 4]`.

This formula assumes `T` divides cleanly into `R`. Mixes that don't divide cleanly produce unevenly-spaced time ticks; full LCM handling is deferred.

### Initiative Luck (combat-specific Reroll Operation)

Initiative has no Target Number, so Dice Resolution's generic Reroll Operation (which classifies dice against a TN) does not apply. Combat's variant:

- **Positive Luck**: sort dice ascending. Reroll up to `|luck|` of the lowest values, **skipping any die already at Critical (`Die Size`)** — re-rolling a Critical might produce a worse value, defeating the bonus's intent.
- **Negative Luck**: sort dice descending. Reroll up to `|luck|` of the highest values, **skipping any die already at Failure (1)**.

Each die is rerolled at most once per Luck application.

### Initiative Insight (combat-specific Value Adjustment)

- **Positive Insight**: look for "crit-capable" dice — non-Critical dice whose value plus `insight` would meet or exceed Die Size. If any qualify, pick the **lowest** of them. If none qualify, fall back to the **highest** non-Critical die.
- **Negative Insight**: pick the **highest** die and lower it (clamped at 1).

Magnitudes greater than 1 repeat the operation; the chosen die may differ between iterations as values change.

### Combat Pool computation

Two stages.

**Stage 1 — Budget**:
```
budget = floor((martial_proficiency_ranks
                + floor(combat_pool_attribute / Combat Pool Divisor))
               / Turns Per Round[tier])
```

A Tier beyond the `Turns Per Round` array is an error rather than a clamp.

**Stage 2 — Buy Combat Pool**: Points 1..Step are free (every Combatant therefore guaranteed at least `Combat Pool Step` points); points (k·Step)+1..(k+1)·Step cost `k` each. Combat Pool is the largest count P that fits within the Budget. Closed form: with `T = floor(P / Step)` and `R = P mod Step`, total cost = `Step · T·(T-1)/2 + R · T`.

### Severity Calculation (Runtime Bucketing)

Combat takes raw damage + Damage Type and turns it into per-Severity Hit Point Damage on the defender, then calls Conditions' `APPLY_HIT_POINT_DAMAGE`. The pipeline:

1. Look up the Damage Type catalog entry. If the entry declares a `parent`, inherit `severity` and `mechanics` from the parent (and recursively up the chain). The entry's own fields override what it inherits. Read the resolved declared Severity (or `runtime_bucketed: true`) and the resolved Mechanic list.
2. Apply pre-bucketing Mechanics:
   - `damage_per_hit` adjustments.
   - `damage_multiplier` factors.
   - `upgrade_severity` and other conditional tags
     (`target_has_metal_armor`, `target_has_subtype:undead`, etc.) —
     interpreted here against equipment / Creature state read through
     `creature_lookup`.
3. Determine Severity:
   - Non-Runtime-Bucketed: every point lands at the resolved Severity
     (after any `upgrade_severity` mechanic fired).
   - Runtime-Bucketed (e.g. Physical and its sub-types): read Threshold
     (caller-supplied — from the weapon for weapon attacks, from the
     ability's `threshold` for ability damage) and Damage Resilience
     (read from the defender's Creature). Fill Minor up to
     `Threshold + Damage Resilience`, then Moderate up to another
     `Threshold + Damage Resilience`, then everything else into Major.
4. Call Conditions' `APPLY_HIT_POINT_DAMAGE` with the resulting `{minor, moderate, major}` map.
5. Apply post-damage side-effects:
   - Acid → call Conditions' `APPLY_ACID_DAMAGE`.
   - Cold → call Conditions' Shock apply with the damage amount.
   - Damage Types may declare additional `inflict` Mechanics that route
     through Conditions' generic effect application.

### Set-Value Spend translation

When a Combatant chooses to preroll N dice on a Roll with Dice Cap D:

1. Spend `N × Set Value Spend Ratio` extra dice from `combat_pool_remaining` via *Spend Combat Pool*.
2. Build the Roll with `dice_count = D - N` and `preroll = +N`.
3. Hand to Dice Resolution. The Preroll field (per `dice_resolution_glossary.md`) folds N dice at Die Size into scoring — each prerolled die is a Critical. When `dice_count = 0`, Dice Resolution rolls nothing and scores the prerolled dice alone.

Combat does not store Die Size — it queries Dice Resolution's config at the point of use. There is no combat-side Set Value override.

### Concentration enforcement

Two enforcement points.

**End-of-turn check** (during *Apply Per-Turn Cleanup*): for each of the Combatant's Concentration Entries, if `channeled_this_turn` is false **and** the entry's mode is not `auto`, end the Concentration — remove the entry (including any Reservoir) and notify the source domain via *End Concentration*. (`channeled_this_turn` resets to false at the start of each of the Combatant's turns.)

**Concentration Damage Save** (during *Apply Damage*): for each Concentration Entry on the defender, build a check Roll keyed by the entry's `cast_skill` and add a `Circumstance` Penalty of magnitude `spell_tier + damage_dealt` to `bonus_penalty_list`. Resolve through Dice / Check Resolution; TN clamping and outcome are theirs to compute. On failure, end the Concentration as above (the Reservoir is lost with it). The penalty is unstacked within the entry — Combat appends a single Penalty entry; Roll Resolution's same-type stacking handles interaction with any other Circumstance Penalties already on the Roll.

### Channeling and Dice Cap

Channeling — adding dice to a Reservoir, or fueling a fire-mode channel's effect Roll — is an exception to the Dice Cap rule. A Combatant may spend up to `combat_pool_remaining` dice on a channel; Dice Cap (from Proficiencies) does not apply. When a Combatant later rolls dice **from** a Reservoir (e.g. the auto-mode per-turn attack roll), the normal Dice Cap rule applies to that Roll.

### Drift detection (Stale Combat)

The expected Round at any moment during Combat is `combat_anchor.round_of_day + floor(elapsed_time_ticks / Time Ticks Per Round)`, mod `Rounds Per Day` (with the appropriate Day rollover into `combat_anchor.day_index`). Combat compares this to Chronicle's canonical Timestamp on every *Is Stale?* call. Mismatch indicates time advanced through a non-Combat path while Combat was still active. No automatic remediation in this design — the stub layer is expected to flag the condition and request a Reroll Initiative to resync.

## Per-turn / per-round cleanup

**Apply Per-Turn Cleanup** (called as part of *Advance Turn* on the outgoing Combatant):
- Reset `combat_pool_remaining` to *Get Combat Pool*.
- Clear `luck_points` (per the Luck Points clear rule).
- Set `performed_this_turn = true`.
- Run the End-of-turn Concentration check.
- Reset `channeled_this_turn` to false on each of the Combatant's Concentration Entries (ready for next turn).

**Apply Per-Round Cleanup** (called as part of *Advance Time Tick* when `time_tick` resets to 0):
- No per-Round Concentration bookkeeping is required under the per-turn channel model. Place for future per-Round housekeeping.

DM Luck Points are **not** cleared by either cleanup; they clear only at *End Combat*.

## Atomic state persistence

Mutations write `combat_data.json` atomically. Reads at startup are tolerant: missing state file → empty Combat (`time_ticks_per_round = null`). The rules file is loaded only at boot; mid-session changes to combat tunables require a restart.

## Responsibilities

### Owned by the combat domain

- The single in-memory Combat: combatants, per-Combatant Time Tick Schedule, Time Tick, Time Ticks Per Round, Combat Anchor, Acting Combatant ID.
- Combat ID allocation and the two-ID identity scheme.
- Turn ordering via Initiative String compare within a Time Tick.
- Time Tick Schedule computation per Combatant.
- Acting Combatants determination per Time Tick (internal — drives *Advance Turn* / *Advance Time Tick* picks).
- Chronicle notifications: *Advance current Timestamp* on Round wrap.
- Initiative dice count and Combat Pool derivation via `creature_lookup`.
- Initiative reroll: rolling through Dice Resolution, applying combat-specific Luck and Insight.
- Combat Pool computation, Spend, Reset.
- Action Economy rules: Main / Bonus / Free / Reaction categories, minimum costs, Reaction allowances and scoping.
- Granted Action registry and dispatch.
- Attacker Bonus eligibility: Flatfooted, Unaware. Hidden is resolved per attacker-defender pair and grants the Unaware Bonus on that attack.
- Set-Value Spend translation to Dice Resolution's Preroll.
- Concentration: per-Combatant entries, Reservoir tracking, per-turn channeling enforcement, damage-triggered saves, end-of-spell notification to the source domain.
- Severity Calculation including Runtime Bucketing, pre-bucketing Damage Type Mechanics, and routing the result to Conditions.
- Damage Type catalog (`combat_config.yaml`).
- Damage Type side-effect routing (`APPLY_ACID_DAMAGE`, Shock apply, etc.).
- Telling Dice Resolution which Damage Type's `critical_value` applies via *Critical Modifier For*.
- Luck Points (per-Combatant; per-turn clear).
- DM Luck Points (Combat-level; per-Combat clear).
- *Is Stale?* drift detection against Chronicle.
- Atomic state persistence and load.

### Explicitly *not* owned here

- **Round, Day, Time of Day, Game Day** — Chronicle owns the canonical Timestamp; Timekeeping owns calendar arithmetic.
- **Creature attributes, max HP, Tier, equipment, ability lists** — read through `creature_lookup`.
- **Generic Reroll Operation and Value Adjustment semantics** — Dice Resolution. Combat owns the *initiative-specific* variants because initiative has no Target Number.
- **Hit points, conditions, Magic Toxicity, Shock, Acid Counter, Mana, Active Effects** — Conditions owns the storage; Combat invokes the Conditions APIs to mutate it.
- **Spell mechanics** — Spells own how a spell works. Combat presents Granted Actions for spells that surface a combat action; Combat does not interpret what the spell does on resolution.
- **Bonus Type names** — Abilities owns the canonical list. **Per-Bonus-Type stacking** — owned here (Combat).
- **Multiple concurrent Combats** — by design, one fight at a time.
- **Validation of Damage Type names against any external catalog** — the catalog *is* `combat_config.yaml`'s damage_types section.

### Unassigned (no current owner)

- **Downtime.** The non-Combat activities a Creature performs between Combats — rest, recovery of HP and mana, downtime ritual casting, surgery, medical services, and similar passage-of-time activities. Lives in Combat for now because the action economy and recovery rules grew out of Combat; the domain may be renamed (e.g. *Encounters*) once the scope settles. Timekeeping advances the calendar but does not own downtime activities. Mechanics to be designed.
- **The full attack-resolution pipeline.** *Attack / Cast / Use Item* are declared but the multi-step pipeline (Roll construction → Check Resolution → ally Reactions → Apply Damage) is future work. Pieces exist, the composition does not.
- **Non-divisible Turns Per Round mixes.** When a Combatant's `Turns Per Round[tier]` does not divide cleanly into the active Time Ticks Per Round (e.g., 3 vs 5), the floor-midpoint formula produces unevenly-spaced time ticks. Needs explicit LCM-based handling.
- **Initiative reroll edge cases.** Multiple iterations of Insight on the same dice list may repeatedly pick the same die unless values change.
- **Reserved Defense Dice / ally-block flow** (e.g. Shield of Faith). Combat's Granted Action registry can carry such an action, but the exact integration with the attack pipeline depends on the pipeline landing first.
- **Metal Armor classification.** Listed as a configurable list in `combat_config.yaml` for now; will likely move to Equipment when that domain is designed.

