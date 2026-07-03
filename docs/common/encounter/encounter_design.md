# Encounter — Design

Encounter governs what is happening in the present moment of play — combat, downtime, travel, and any other mode that wants a single owner for "what is going on right now." Today the only mode designed is **Combat**, a state machine over the lifetime of one fight; Downtime and Travel are planned but not yet specified. The Encounter domain owns the persisted state of the active Combat (Combatants, Initiative, per-Combatant Time Tick Schedule, Concentration entries, Luck Points), reads canonical time from Chronicle, and computes per-Combatant derived values on demand by looking up the Creature through a `creature_lookup` callback.

Sibling domains:
- **Chronicle** owns the canonical Timestamp. Encounter reads it and notifies Chronicle when a Round elapses.
- **Conditions** owns per-Creature mutable state (HP damage, ability damage, Active Effects, Acid Counter, Shock, Magic Toxicity, etc.) plus the module-level Zone Effects list. Encounter tells Conditions what damage / side-effect to apply but never stores any of it.
- **Atlas** owns spatial state (Tokens and Zones). Encounter receives Atlas Movement Notifications when Combatant Tokens enter or exit Zones and surfaces them to the GM as event options.
- **Dice Resolution** owns Roll mechanics. Encounter builds Rolls and invokes Dice Resolution; Combat-specific Roll variants for Initiative (no Target Number) live here.
- **Damage Types** is folded into Encounter — the catalog is part of `encounter_config.yaml` and the Severity Calculation pipeline is owned here.

## Common types

### Combatant

| Field | Type | Description |
|---|---|---|
| `id` | integer | Combat ID. Unique within the active Combat. |
| `creature_id` | string | Identity passed to `creature_lookup`. |
| `name` | string | Display name. |
| `initiative_string` | string | Per *Initiative String* in the glossary. Empty until first Reroll Initiative. |
| `combat_pool_spent` | integer | Combat Pool dice spent so far in this turn. At *Start Combat* it is set to the full pool size so every Combatant begins with an **empty** pool; the pool refills (reset to 0) automatically when the Combatant's turn begins (*Begin Turn*), **not** at end of turn. Remaining is derived as `Get Combat Pool − combat_pool_spent`. |
| `main_actions_remaining` | integer | Main Actions the Combatant has left this turn. `-1` before the Combatant's first turn; set to `MAIN_ACTIONS_PER_TURN` (2) when the turn begins; decremented by a committed Attack / Move / Cast / Item. The cap is **not** enforced (it may go negative) — it is tracked so the DM can see how many a Combatant has used. |
| `time_tick_schedule` | list of integer | Time Ticks within a Round on which this Combatant acts. Recomputed when Time Ticks Per Round changes. |
| `luck_points` | integer | Per-Combatant Luck Points. Cleared at the start of this Combatant's turn. |
| `concentration` | list of Concentration Entry | Channeled spells the Combatant is currently holding. |
| `casting` | list of Casting Entry | Long Casts the Combatant is currently performing. |

### Concentration Entry

One entry per Channeled spell (or long-cast in-progress spell) a Combatant currently holds.

| Field | Type | Description |
|---|---|---|
| `spell_name` | string | Display name. Combat does not interpret it. |
| `source` | string | Opaque domain reference handed back when Combat needs the source domain to tear down the effect. |
| `spell_tier` | integer | The cast spell's tier. Used in the Concentration Save penalty formula. |
| `cast_skill` | string | The skill the spell was cast with. The Concentration Saving Throw uses this skill. |
| `mode` | enum | Channel Mode mirrored from the Ability — `fire`, `reservoir`, `maintain`, or `auto`. |
| `reservoir` | integer | Current Reservoir amount. Always 0 for `fire` and `maintain` modes. For `reservoir` mode, reset to 0 at the start of the holder's turn (Reservoir Reset = per_turn). For `auto` mode, set at cast and never reset (Reservoir Reset = persistent). |
| `reservoir_reset` | enum | `per_turn` or `persistent`. Mirrors the Reservoir Block's `reset` field. |
| `channeled_this_turn` | boolean | True once the Combatant has spent a Main Action channeling this entry on their current turn. Reset to false at the start of each of the Combatant's turns. End-of-turn check ends any entry where this is still false (auto-mode is exempt). |

### Casting Entry

One entry per Long Cast a Combatant is currently performing. Tracked separately from Concentration Entries (which are for Channeled spells already in effect).

| Field | Type | Description |
|---|---|---|
| `spell_name` | string | Display name. Combat does not interpret it. |
| `source` | string | Opaque domain reference handed back when Combat needs the source domain to resolve or cancel the cast. |
| `spell_tier` | integer | The cast spell's tier. Used in the Concentration Save penalty formula. |
| `cast_skill` | string | The skill the spell is being cast with. Used by the Concentration Saving Throw. |
| `turns_remaining` | integer | Turns left before the cast completes. Decrements at end-of-turn cleanup when both Main Actions were committed. |
| `committed_this_turn` | boolean | True once the Combatant has spent both their Main Actions on the cast this turn. Reset at the start of each of the Combatant's turns. End-of-turn check cancels the cast if this is still false. |

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
| `excluded_pcs` | list of Creature ID | PCs the consuming project should **not** auto-add to this Combat at render time. See *Player Characters always belong in active Combat* under *Start Combat*. Persisted across End/Start cycles so "Pippin is sitting this session out" survives between fights. Mutated via *Set PC Exclusions*. Excluded PCs are absent from `combatants` entirely (they are not Combatants — the list is the source of truth for "currently in this fight"). |
| `phase` | one of `combat`, `looting`, `traveling`, `social`, `downtime` | The Encounter Phase — a DM-set view selector for the consuming project's Encounter page. It is **independent of the Combat state machine**: setting the Phase does not start or stop Combat, and *Start Combat* / *End Combat* do not change the Phase. Mutated via *Set Phase*. Defaults to `downtime`. |

## Public entry points

These are the operations other domains call. Function names below are conceptual labels; implementations choose the actual symbols.

### Start Combat

Inputs: a list of Creature IDs (and optional name overrides).

Behavior:
1. Read the current Timestamp from Chronicle and store as Combat Anchor.
2. Allocate Combat IDs and create one Combatant per input. Each Combatant starts with empty `initiative_string`.
3. Compute Time Ticks Per Round = `max(Turns Per Round[tier])` across the Combatants (read each Tier through `creature_lookup`).
4. Compute each Combatant's Time Tick Schedule.
5. Reset `time_tick` to 1; `elapsed_time_ticks` to 0; `acting_combatant_id` to null; `dm_luck_points` to 0; per-Combatant `luck_points` to 0, `concentration` to empty, `casting` to empty. Each Combatant's Combat Pool starts **empty** (`combat_pool_spent` is set to the full pool size); the pool refills at the start of the Combatant's turn.
6. Persist.

#### Player Characters always belong in active Combat

Player Characters — Creatures whose `tags` include `player_character` — are part of every active Combat by rule, **except** PCs whose Creature ID appears in `excluded_pcs`. The consuming project enforces this at Combat-page render time: any PC missing from the Combatant roster and absent from `excluded_pcs` is added via *Add Combatant* before the page renders. The DM does not have to add PCs manually; the only PCs left out are those the DM has explicitly excluded (typically because the player is sitting out the session). This means the Encounter domain itself doesn't gate or filter PCs at *Start Combat* time; the rule lives in the consuming page layer so the Encounter module stays group-agnostic.

`excluded_pcs` persists across End/Start cycles — a player sitting out one fight is presumed to be sitting out the next fight as well, until the DM toggles them back on. Mutate the list with *Set PC Exclusions*.

A future variant of *Start Combat* may take this rule directly. Until then, callers either pass PC IDs explicitly or rely on the consuming project's render-time reconciliation.

Rolling Initiative is not part of *Start Combat*. The caller follows up with *Reroll Initiative* (typically with no prerolled values, to roll every Combatant). Splitting the two lets the caller batch-set initiative from a prepared sheet or roll on demand.

Returns: the resulting Combat State.

### End Combat

Inputs: none.

Behavior:
1. Clear the Combat-mode fields — `time_ticks_per_round`, `time_tick`, `combat_anchor`, `elapsed_time_ticks`, `acting_combatant_id`, `granted_actions`, `dm_luck_points` — and reset each Combatant's `initiative_string` (Initiative is per-fight).
2. **Leave the Combatant roster in place.** The defeated enemies remain as Combatants so the consuming project can loot and clear them afterward (Crimson Steel does this through the *Looting* Phase and the post-combat creatures stub — see `equipment_post_combat_creatures_stub.md`). Combat itself neither removes nor loots Creatures.
3. Persist.

Concentration Entries and Casting Entries are **not** terminated by End Combat — a caster may continue holding a spell or completing a Long Cast into the post-combat window. They become subject to the wider system's out-of-combat handling, which is out of scope here.

### Set Phase

Inputs: a Phase — one of `combat`, `looting`, `traveling`, `social`, `downtime`.

Behavior: set the Encounter `phase` (ignoring an unrecognized value, leaving the current Phase in place) and persist. The Phase is a pure view selector for the consuming project's Encounter page — it does **not** start or stop Combat, touch the roster, or change any other state. Likewise *Start Combat* / *End Combat* leave the Phase untouched; the two concerns are independent.

Returns: the Phase in effect after the call.

### Add Combatant

Inputs: Creature ID, optional name override.

Behavior: Allocate a Combat ID one past the current maximum, create the Combatant with empty `initiative_string`, recompute Time Ticks Per Round (the new Combatant's Tier may raise it). If Time Ticks Per Round changed, recompute every Combatant's Time Tick Schedule. Persist.

Rolling the newcomer's Initiative is not part of *Add Combatant*. The caller follows up with *Reroll Initiative* in `missing_only` mode (or with a prerolled-initiative override) to fill in the new entry without disturbing existing ones.

### Remove Combatant

Inputs: Combat ID.

Behavior: Drop the Combatant from the list. Recompute Time Ticks Per Round; if it dropped, recompute every remaining Combatant's Time Tick Schedule and clamp `time_tick` to the new range if needed. Clear any Granted Actions that referenced the removed Combatant as actor or eligible target. Notify each of the removed Combatant's Concentration sources that the spell has ended; notify each of their Casting sources via *Cancel Long Cast* with `reason: caller`. If `acting_combatant_id` matched the removed Combatant, set it to null (the caller is expected to call *Advance Turn* to find the next one). Persist.

*Remove Combatant* only removes the Combatant from this Combat — the underlying Creature record is untouched. Deleting the Creature itself (e.g., when cleaning up a spawned enemy after looting) is Creatures' *Delete Creature*; the consuming loot stub composes the two in sequence.

### Set PC Exclusions

Inputs: a list of PC Creature IDs (the new exclusion set; replaces any existing list).

Behavior:
1. Validate every supplied ID resolves to a PC (`tags` includes `player_character`) via `creature_lookup`. Reject the call if any ID does not.
2. Replace `excluded_pcs` with the supplied list.
3. If a Combat is currently active: for every newly-excluded PC that has a Combatant in the current roster, call *Remove Combatant* on it. The consuming project's render-time reconciliation handles re-adding newly-unexcluded PCs on the next render.
4. Persist.

Returns: nothing.

The DM typically calls this through the Initiative stub's per-PC inclusion toggle. The list survives *End Combat* — it represents an out-of-combat scheduling concern (which players are present this session), not an in-combat state.

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
2. Compute the Acting Combatants for the current Time Tick — every Combatant whose `time_tick_schedule` contains the current Time Tick, sorted by `initiative_string` ASCII-descending then by Combat ID. Combatants who have not rolled Initiative (empty `initiative_string`) sort **last**, so the turn order matches the Combat Tracker's display order — the bottom row is the last to act, and ending its turn rolls the Round over.
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

Behavior: Increment the Combatant's `combat_pool_spent` by `amount`. Refuses negative amounts and amounts that would push `combat_pool_spent` above *Get Combat Pool* (returns an error sentinel; persistence does not happen). The pool **remaining** value the UI shows is computed on demand as `Get Combat Pool − combat_pool_spent`.

Returns: the new remaining value, or an error sentinel.

### Reset Combat Pool

Input: Combat ID.

Behavior: Set the Combatant's `combat_pool_spent` to 0 — refilling the pool. Invoked automatically when a Combatant's turn begins (*Begin Turn*); also exposed for explicit calls. Implementations that need to report the resulting "remaining" value compute it as *Get Combat Pool*.

### Apply Damage

Inputs: defender Combat ID, raw damage integer, Damage Type name, optional `threshold` (used only for Damage Types that Runtime-Bucket).

Behavior: Run the *Severity Calculation* pipeline (see Operations) and call Conditions' `APPLY_HIT_POINT_DAMAGE` with the resulting `{minor, moderate, major}` map. Apply Damage Type Mechanic side effects (e.g. Acid → call Conditions' `APPLY_ACID_DAMAGE`; Cold → call Conditions' Shock apply). If the defender has any Concentration entries or Casting entries, trigger one Concentration Save per entry (see *Concentration Damage Save* in Operations); on a failed save, call *End Concentration* for the matching Concentration entry, or *Cancel Long Cast* with `reason: damage` for the matching Casting entry.

Returns: a struct with the per-Severity damage, the Concentration save results, and any Damage Type Mechanic outputs (e.g. residual acid).

### Apply Falling Damage

Inputs: defender Combat ID, fall distance in feet (integer), optional `modifier` (per-10-feet adjustment, default 0), optional `acrobatics_successes` (integer, default 0).

Behavior:

1. Compute the per-10-feet figure: `Falling Damage Per 10 Feet + modifier`. Clamp at zero.
2. Compute raw damage: `(fall_distance / 10) × per-10-feet figure`. The division is floored at the 10-foot grain — a 14-foot fall is one 10-foot increment.
3. Subtract `acrobatics_successes`. Clamp at zero.
4. Call *Apply Damage* with the raw damage, Damage Type `physical` (treated as Runtime-Bucketed using `Falling Damage Threshold`), and the appropriate side-effect for Bleed.
5. Bleed amount applied to Conditions = `Falling Damage Bleed Constant + raw_damage` (the same convention used for weapon Bleed). Bleed is applied via Conditions' bleed channel.

Returns: the *Apply Damage* return struct.

The Acrobatics Roll itself is built and resolved by the caller (typically Combat surfaces the option to the GM, who decides whether the fall allows the check; if so, the falling Creature builds an Acrobatics Roll through Proficiencies the standard way). Combat does not roll the Acrobatics check inside *Apply Falling Damage* — it consumes the successes the caller supplies.

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

Inputs: Combat ID, spell name, source, spell tier (integer), cast skill (string), Channel Mode (`fire` / `reservoir` / `maintain` / `auto`), Reservoir Reset (`per_turn` / `persistent`), initial reservoir amount (integer, may be 0).

Behavior: Append a Concentration Entry to the Combatant with `channeled_this_turn` set to true (the cast itself counts as that turn's channel), `reservoir_reset` set to the supplied value, and `reservoir` set to the initial reservoir amount. Persist. The caller — typically a Spell domain casting routine — is responsible for ensuring the casting itself paid the appropriate dice through *Spend Combat Pool*, that the on-target effect was added to Conditions, and that the initial reservoir amount already accounts for the Ability's Reservoir fill ratio. Combat only owns the channel and breakage flags from this point on.

For `fire` and `maintain` modes the initial reservoir is always 0 and `reservoir_reset` is irrelevant (no Reservoir is held). For `reservoir` mode the caller passes `per_turn`. For `auto` mode the caller passes `persistent`.

### Channel

Inputs: Combat ID, spell name, dice spent (integer), reservoir delta (integer).

Behavior: Validate that the Combatant holds a Concentration Entry by that name. Refuse if the dice spent is below Main Action Minimum, or — for `maintain` mode — anything other than Main Action Minimum. For `fire` mode the caller is responsible for using the dice spent as the Roll's dice count (Dice Cap does not apply to channeling). For `reservoir` mode, add `reservoir_delta` to the entry's `reservoir` (the caller pre-applies the Ability's fill ratio). For `auto` mode and `maintain` mode, `reservoir_delta` must be 0. Set `channeled_this_turn` to true. Combat does not itself debit `combat_pool_spent` — the caller is expected to call *Spend Combat Pool* for the dice cost in coordination.

### Discharge Reservoir

Inputs: Combat ID, spell name, amount (integer).

Behavior: For a Concentration Entry with `reservoir_reset = per_turn` and `mode = reservoir`, decrement `reservoir` by the supplied `amount`. Refuse when `amount` exceeds the current `reservoir` or is below the Ability's declared minimum. Refuse for `auto`, `fire`, and `maintain` modes (auto-mode Reservoirs are never spent; the other two carry no Reservoir). Persist. The caller is responsible for invoking the Discharge effect through the source domain using `amount` as the discharged size.

### End Concentration

Inputs: Combat ID, spell name.

Behavior: Remove the matching Concentration Entry from the Combatant (including any held Reservoir) and notify the source domain (via the entry's `source` reference). The source domain is responsible for telling Conditions to clear the on-target Active Effect. Persist.

### Begin Long Cast

Inputs: Combat ID, spell name, source, spell tier (integer), cast skill (string), turns required (integer ≥ 1).

Behavior: Append a Casting Entry to the Combatant with `turns_remaining` set to `turns_required - 1` (since the call itself begins the cast, and that turn's commitment is implied) and `committed_this_turn = true`. Persist. The caller is responsible for accounting for the caster's two Main Actions on this turn and for blocking other Main-Action use through the action economy interface. Concentration Saves apply per the normal damage handling.

When `turns_required` is 1 (a Full-Turn cast that completes in one turn), Combat does not need to add a Casting Entry — the caller may resolve the cast immediately at end-of-turn. The Casting Entry is only required when the cast spans multiple turns.

### Commit to Long Cast

Inputs: Combat ID, spell name.

Behavior: Validate that the Combatant holds a Casting Entry by that name. Set `committed_this_turn = true`. Combat does not debit `combat_pool_spent` — the caller is expected to coordinate the two Main Actions through *Spend Combat Pool*.

### Cancel Long Cast

Inputs: Combat ID, spell name, reason (`damage` / `incomplete_commit` / `caller`).

Behavior: Remove the Casting Entry. Notify the source domain that the cast was cancelled (no mana refund, no spell effect). Persist.

### Handle Movement Notification

Inputs: an Atlas Movement Notification — `{creature_id, map_id, entered, exited}`.

Behavior: For each `source_id` in `entered`, fetch the Zone Effect's `on_enter` trigger via Conditions' *Get Zone Triggers* and surface the trigger to the GM as an event option keyed to the moved Combatant. The GM decides whether to apply the trigger; on approval, Combat builds the appropriate Saving Throw. `exited` is informational — Combat surfaces the exit so the GM can clear conditional effects (e.g. removing a creature-leaving-Grease bonus), but no automatic save fires on exit.

Combat does not gate triggers itself. The GM is the authority on whether a given enter/exit qualifies; Combat's role is to make the option visible.

### Handle End-of-Turn Zone Triggers

Called as part of *Apply Per-Turn Cleanup* on the outgoing Combatant. For each Zone Effect whose footprint currently contains the Combatant's Token (queried via Atlas's *Zones In Position*), fetch the Zone Effect's `on_end_of_turn` trigger via Conditions' *Get Zone Triggers* and surface it to the GM as an event option. As with Movement Notifications, the GM decides whether to apply the trigger.

### Creature Can Act?

Input: Combat ID.

Returns: boolean. Delegates to Conditions: false if the Combatant is Dying or Dead, or carries a "cannot act" Active Effect (Paralyzed, Stunned, Unconscious, etc.). Combat does not enumerate the list — it asks Conditions.

### Creature Is Dying?

Input: Combat ID. Returns: boolean. Delegates to Conditions.

### Creature Is Dead?

Input: Combat ID. Returns: boolean. Delegates to Conditions.

### Critical Modifier For

Input: Damage Type name.

Returns: the integer `critical_modifier` to put on the attacker's Roll for a Roll resolving an attack of that Damage Type. Reads the Type's `critical_value` Mechanic from `encounter_config.yaml`. When the Type has no `critical_value` Mechanic, returns the Roll struct default (`critical_modifier = 2`). Used at Roll-construction time, not in the damage pipeline.

### Tier Mismatch modifiers

When two Creatures of different Tiers oppose each other, the higher-Tier Creature gains advantages scaled by the Tier difference `Δ = higher.tier − lower.tier` (Tier 0 counts as 0.5). The two Bonus Types involved — **Inherent** and **Ascendancy** — are defined in `abilities/abilities_config.yaml`'s `Bonus Types List`.

- **Inherent damage reduction.** Against the lower-Tier Creature's attacks, the higher-Tier Creature gains `Inherent Damage Reduction Per Tier × Δ` damage reduction (`encounter_config.yaml`, default 5, the product floored) — an Inherent Bonus reflecting its own elevated Tier.
- **Ascendancy on checks.** On an opposed **combat** check between the two — a weapon attack or a spell cast (the attacker/caster Roll versus the defender's Defensive Action or Saving Throw; for an area Spell, the caster versus **each** caught creature's Saving Throw) — each Roll carries its Inherent Bonus, the opponent's Inherent crosses onto it as an Inherent Penalty via propagation, and **TN computation** (Roll Resolution) amplifies the imbalance into an **Ascendancy** entry of `floor(2 × gap)` — a Bonus for the side whose Inherent is stronger, a Penalty for the weaker. Because the Inherent Bonus comes straight from the per-Tier table, the gap *is* the Tier difference: the higher-Tier Creature ends with `+2 × Δ` and the lower with `−2 × Δ`. Ascendancy fires wherever a Roll carries an Inherent **Penalty** — combat Rolls, and the one-sided Affliction save (saver Inherent vs inflicter Inherent); opposed *skill* check Rolls carry no Inherent entries, so they derive none.

These modifiers are computed from the two Combatants' Tiers at resolution time; they are not stored on the Creature. The two halves resolve in two different places, because Rolls resolve client-side while damage is applied server-side:

- **Ascendancy (the Check half) is owned by Roll Resolution (TN computation)**, not by Combat or Check Resolution. It is a dice-resolution operation — see `../dice_resolution/dice_resolution_design.md` → *Ascendancy* — derived per Roll from its Inherent imbalance, after Check Resolution's cross-side Propagation has supplied the opponent's crossed Inherent. Combat's only role is to supply the input: an `Inherent` entry on each combat Roll's `bonus_penalty_list` (the attacker's and each defender's Tier Inherent from the attack builder; the caster's and the target's Tier Inherents from the cast builder — the Spell's Tier rides separately as a Guidance Bonus and stays out of the Ascendancy; and, for an area Spell, each caught creature's Tier Inherent on its Save Roll from `GET /encounter/cast_area_rolls`). These Inherent entries are emitted even at Tier 0 (a `0`), so a Tier-0 Creature's Inherent still crosses and the gate (which needs a present Inherent Penalty, `0` included) fires. No Tier is passed anywhere — Rolls carry no `tier` field; the skill-check builders put no Inherent entries on their Rolls, so they derive no Ascendancy.
- **Inherent damage reduction (the damage half) stays server-side**, since damage is applied server-side. `Encounter::TierMismatch.inherent_damage_reduction` is subtracted from the dealt damage of both weapon attacks (`Encounter::State#resolve_attack_payload`, reported as `inherent_dr`) and damaging spells (`#resolve_cast_payload`, subtracted from each resolved damage Effect after Save halving so preview and commit agree).

**Effective Tier overrides.** An Ability may raise a Creature's *effective* Tier for a single resolution, shrinking `Δ`. The Glory domain Channel Divinity **Glorious Charge** (`abilities/talents.yaml`) raises the channeler's effective Tier by 1 for one attack: against a foe exactly one Tier higher this drives `Δ` to 0 — fully negating both that attack's Ascendancy Penalty and the foe's Inherent damage reduction against it — and against a foe more than one Tier higher it reduces both by one step. On the damage side the bump is plumbed through the attack payload's `attacker.tier_bonus`; on the Check side it is applied by lifting the attacker Roll's Inherent Bonus to the raised Tier's table value before resolution.

A weapon's **Glory** Property (`tier_advantage`, surfaced by *Get Weapon Details*) is likewise an effective-Tier override, but **weapon-only**: when the wielder is fighting up it treats them as that many Tiers higher, shrinking `Δ` before the Inherent damage reduction (and lifting the Inherent Bonus on the attack check — see below). It applies only to weapon attacks; a damaging spell or ability never gets it. The damage-side bump is folded into the attacker's effective Tier by `resolve_attack_payload` (via `Encounter::Attack.effective_attacker_tier`) before `Encounter::TierMismatch.inherent_damage_reduction` is computed.

### Attack / Cast / Use Item *(partially implemented)*

Inputs: actor Combat ID, target spec, the action data (weapon, spell name, item, etc.).

Behavior: resolution is client-side (the JS Dice/Check engine) and comes back to Combat as a *resolved payload* that Combat applies. **Attack** is implemented via `resolve_attack_payload`; **Cast** via `resolve_cast_payload` (with the pure helpers in `Encounter::Cast`) — it spends Combat Pool (`Speed + dice`), debits Mana, applies Magic Toxicity (gated over threshold), nets the casting check against each target's Save, routes the resolved Effects (damage through *Apply Damage*; heal / mana / Temporary HP / named Active Effect through Conditions; and a buff Spell's `modifiers:` — Magic Weapon, Magic Vestments, Expeditious Retreat, Resistance, Protection from Poison — evaluated against the caster and applied as timed modifier Active Effects via Conditions' *Apply Effect*, a turns-based `duration` setting expiry), and registers a Concentration / Long Cast Entry for a sustained spell. The spell's Effects are produced by the Abilities domain (`Abilities.resolve_spell`); Combat never reads spell data, it only routes the resolved Effects, exactly as the Attack flow routes an already-evaluated weapon. **Use Item** is still future work (it needs the Equipment-consumable wiring).

**Area Spells place a Zone.** A committed area Spell (Obscuring Mist, Darkness, Web, Create Pit, Silence) drops its footprint on the active Map: Combat anchors an Atlas Zone at the target's Token and pairs it with a Conditions Zone Effect carrying the area's triggers, with `ends_on_round` computed from the Spell's `duration` (turns count as Rounds; minutes/hours convert via Timekeeping's Round Length). The Zone **auto-expires at the caster's start of turn** — the turn-start side effects (`begin_turn_side_effects!`, run by the `start_combat` and `advance_turn` routes) remove the caster's elapsed Zone Effects via Conditions' *Expire Zone Effects For* and drop the paired Atlas Zones. Resolving the Zone's on-enter / on-end-of-turn Saves during movement is still future work.

**No-roll casts skip the roll and Luck.** The cast builder only asks the caster to roll a casting check when its Successes matter — a Save, attack-roll, or damage Spell. The Dice step adapts to the Spell: a Spell with a **variable** dice count — a rolled cast, or a reservoir-channel pour (Shield of Faith), whose dice are **poured into the Reservoir** at cast (`register_cast_sustain`'s `channel_dice`) rather than rolled — asks for a count from the Spell's **Action Minimum** (Main 4 / Bonus 2, `encounter_config.yaml`) up to the casting-skill Dice Cap. A Spell with a **known** dice count — a no-roll, no-Reservoir buff (Ward, Bless, Cure Wounds) costs exactly its Action Minimum — **skips the Dice step entirely**: its option is auto-applied with no button, so the DM never picks a count it can't change. For any no-roll Spell the builder also skips the Luck steps and hides *Roll All*, so the DM just confirms. The builder **hides Spells that take a minute or longer to cast** — they aren't cast in the heat of combat.

**Shield of Faith hangs a defended ally.** A Spell whose Reservoir discharge is `defends: target` (Shield of Faith) grants the caster, on cast, a reaction tied to the chosen ally (`grant_action` with `defends: <ally combatant id>`); the Reservoir itself rides the cast's sustain (a `reservoir`-mode Concentration the caster channels into). When that ally is attacked, the attack builder offers the **caster's block as a second Opposing Roll** (the alternative is simply not defending), which leaves the target's own Defense Roll out. The block rolls up to the **caster's Dice Cap in the casting skill** (stored on the grant), bounded by the Reservoir, **spending one Reservoir die per die rolled**. `resolve_attack_payload` adds the shield's Successes to the attack's Opposing total (`p.shield = { id: caster, successes, dice }`) and, on commit, discharges that many Reservoir dice (no Combat Pool spent).

**A Roll Table Reaction answers an attack from the table.** A Reaction Ability that fires on a provided table (talents.yaml `roll_table:`, e.g. Kesser's Gambit → the Kesser Reversal Table) is offered, during an attack, to a Combatant **other than the attacker** — in the same place as the Standard Shield's ally block. The channeler spends Combat Pool dice (rolled for **Channel Successes** in its Evocation or Invocation skill — Kesser's Ring channels with Evocation, a Cleric's Channel Divinity with Invocation) plus the Ability's Mana; a die is rolled on the table (`Encounter::State#use_roll_table_payload`) and the matched entry reported for the DM. Combat does **not** apply the entry — the DM adjudicates it. See `../ui/encounter_roll_table_stub.md`.

**Spiritual Weapon strikes from a persistent Reservoir.** An `auto`-channel Spell (Spiritual Weapon) fills a **persistent** Reservoir with its cast dice — `register_cast_sustain` pours `channel_dice` into it, and Per-Turn Cleanup leaves persistent Reservoirs untouched. While the caster channels it, the attack builder offers a virtual **Spiritual Weapon** force weapon whose Dice Cap is the current Reservoir; its dice are not pool-gated and `resolve_attack_payload` sets `free_attacker_pool` so the strike costs no Combat Pool and does **not** spend the Reservoir (it strikes again next turn from the same pool).

**Spell Tier and damage.** A Spell's Tier adds a **Guidance** Bonus to the casting-check Roll — magical potency, deliberately not typed `Inherent` so it shifts the TNs (and crosses onto the target like any Bonus) without feeding the Ascendancy; the caster's own Tier Inherent rides the Roll alongside it. A damage-dealing Spell that states no damage formula of its own deals the **default Spell damage**: `floor(casting stat / 4) + Spell Tier + casting-skill Competency + Successes rolled`, where the casting stat is the attribute backing the Spell's casting skill (Tier 0 counts as 0.5, floored total). Combat computes this default in `resolve_cast_payload` (`Encounter::Cast.default_spell_damage`).

**Competency applies to both the Roll and the damage.** The Competency Modifier — a Spell's casting-skill Competency, or a weapon attack's martial Competency — rides the attack/casting Roll *and* is added to the damage. For Spells this is the Competency term of the default-damage formula above; for weapon attacks it is folded into the weapon's base damage in `enrich_attack_payload!` (so `resolve_attack_payload`'s `base + net` already includes it). A **Spiritual Weapon** strike is an attack-roll Spell resolved through the Attack path: its base damage is the default Spell damage (`floor(casting stat / 4) + Tier + Competency`) computed in `enrich_attack_payload!`, with the net Successes added downstream — Competency and Guidance ride its strike Roll as well. The target usually either rolls a **Save for half** (the Cast path's `on_success: halved`) or takes a Defensive Action — **Dodge / Block**:

- **Save-based Spells** net the casting check against the target's Save; on a successful Save the `on_success` directive (`halved` / `none`) reduces or negates the Effects.
- **Attack-roll Spells** (`attack_roll: true`, e.g. Elemental Dart) resolve as a spell attack: `resolve_cast_payload` nets the casting check against the target's Defensive Action (Block / Dodge, eligibility + Combat-Pool cost reused from `Encounter::Attack`) and computes damage from the *net* Successes. The cast still debits Mana / Magic Toxicity and registers any sustain, so a spell attack is one unified action rather than a separate Attack.

A Spell that declares its own damage formula overrides the default (the Abilities engine evaluates it).

**Weapon damage reduction (Tier Mismatch).** A weapon attack on a higher-Tier defender is reduced by the same **Inherent damage reduction** as every other damaging effect — `Inherent Damage Reduction Per Tier × Δ` (`encounter_config.yaml`, default 5), `Δ = defender Tier − attacker effective Tier` (Tier 0 counts as 0.5, the result floored), clamped at a zero gap — computed by `resolve_attack_payload` and reported as `inherent_dr`. So at the default rate a Tier 0 attacker hitting a Tier 2 defender deals `floor(5 × 1.5) = 7` less; a Tier 1 hitting a Tier 4 deals `15` less; an attacker of equal or higher Tier deals full damage. The weapon's **Glory** Property (`tier_advantage`) raises the wielder's effective Tier when fighting up, shrinking `Δ` first — a Glory weapon makes a one-Tier-higher foe take full damage and (for a Tier 2 vs Tier 3) closes the gap entirely, where the same attack without Glory loses `5`. The reduction applies to the base weapon damage (the editable Damage box already shows the reduced figure); the magical rider bonus dice are not reduced here, and Glory never applies to spells or abilities.

**Inherent & Ascendancy on the attack check.** A Creature's **Inherent Bonus** — the per-Tier value from Creatures' `Tier Minimum Inherent Bonus` (`[0, 1, 2, 3, 4, 5]`, i.e. +Tier) — applies to its checks, not only its Effective Attributes. `attack_builder_blob` puts an `Inherent` entry on the attacker's Attack Roll *and* on each defender's Defense Roll — emitted even at Tier 0 (a `0`). Against a defended attack, each side's Inherent inverts onto the other's TN through Check Resolution's cross-side propagation (keeping its name), and **TN computation** amplifies any imbalance into the Ascendancy — fighting up hurts twice over. When the defender declares **No defense** it does not roll — nothing propagates — so the attack builder instead injects the un-rolled defender's Inherent, negated (`0` included), onto the attacker's Roll; the imbalance, and therefore the derived Ascendancy, match the defended case. The **Glory** Property (`tier_advantage`) raises the wielder's *effective* Tier when fighting up, lifting its Inherent Bonus to the higher Tier's and closing the gap — a Glory tier-1 attacking a tier-2 rolls the attack with the tier-2 Inherent Bonus, balanced Inherents, and so no Ascendancy. Combat draws every magnitude from the Inherent table; the ×2 amplification lives in TN computation (Roll Resolution). (These ride the combat checks only — opposed skill checks carry no Inherent entries and are unaffected.)

### Defensive Actions

A Defensive Action is a Reaction the defender declares on the attacker's turn against an incoming attack. Three Defensive Actions exist: Parry, Block, and Dodge. Each contributes an Opposing Roll to the attack Check; per Check Resolution, the Opposing Roll's Successes subtract from the attack Roll's Successes within a single Check. There is no "defender wins" outcome — the only question Check Resolution answers is whether the attacker succeeds.

| Defense | Skill / Attribute | Applies against |
|---|---|---|
| Parry | Martial | Melee attack rolls only. Not usable against ranged attacks or against spells. |
| Block | Martial | Melee, ranged, and spell attack rolls. |
| Dodge | `dex_save` proficiency (Dice Cap + Modifiers only) | Melee, ranged, and spell attack rolls. |

Weapon-specific bonuses (e.g. Weapon Training for a particular weapon family) apply on top of Martial when the defender is using that weapon for Parry, or that shield for Block. Such bonuses are surfaced via the Abilities domain's Modifier system; Combat does not enumerate them.

**Cost:** All three Defensive Actions consume one Reaction allowance plus dice from the defender's Combat Pool. The defender chooses the dice count from Reaction Action Minimum up to Combat Pool Remaining (Dice Cap still applies as a per-Roll cap).
- Parry costs that weapon's Speed + dice; Block and Dodge are Speed 0 + dice.
- Dodge is **not** a Saving Throw: it merely borrows the `dex_save` proficiency to compute its Dice Cap and Competency Modifier. Mechanically it is a pool-costed Defensive Action like Block, so the defender picks how many dice to spend (it does **not** automatically spend the full Dice Cap, and it is **not** exempt from the Combat Pool cost).
- A Dodge's **Competency does not propagate to the attacker.** It helps the dodger's own defence Roll but is not inverted onto the attacker's Target Number — the attack builder marks the dodger Roll's `Competency` in Check Resolution's `no_propagate` field. (Parry / Block competency still propagates; only Dodge holds its Competency local. The dodger's Tier **Inherent** still crosses, so the Ascendancy still applies.)

**Eligibility:** Combat refuses ineligible Defensive Action declarations up front — e.g., a Parry declared against a ranged attack is rejected before the Reaction allowance or dice are committed. The defender cannot "spend" a Reaction on an ineligible defense.

**Helpless:** A target that **cannot act** — Conditions' *Creature Can Act?* is false (incapacitated, Paralyzed, or Dying) — is **Helpless**. It is offered **no Defensive Action at all** (only *No defense*; `attack_builder_blob` builds no Dodge / Block / Parry branches for it), and attacks against it gain the **Helpless** attacker advantage: a single Circumstance Bonus (`Helpless Bonus`, `encounter_config.yaml`, default 3) that is **more severe than, and supersedes,** Flatfooted (+1) and Unaware (+2) — only the one Helpless advantage applies, not also the lesser two. Combat computes Helpless from `creature_can_act?`, and `Encounter::Attack.attacker_bonuses(helpless: true)` returns that single advantage.

**Outcome:** Defensive Actions are Opposing Rolls within the single attack Check. The Check's resolution uses Check Resolution's standard machinery — Supporting Roll successes (attacker, ally Reactions) minus Opposing Roll successes (defender's defense + ally Defensive Reactions) yields net DoIS. The attack succeeds iff net DoIS clears the Default Success Threshold. There is no special damage-reduction step keyed off the defense type.

**Flatfooted interaction:** Declaring an accepted Defensive Action removes the defender's Flatfooted status against this attack regardless of how the Roll resolves — zero or even negative successes still count as "declared a defense." Conditions that force or prevent Flatfooted (Paralyzed forces it; Uncanny Dodge prevents it; Paralyzed overrides Uncanny Dodge) are evaluated first. See the Flatfooted entry in `encounter_glossary.md`.

**Zero-dice Defensive Reactions like Better Lucky Than Good** are *not* Defensive Actions in this sense — they don't go through the Opposed-Roll machinery and don't remove Flatfooted. They are Reaction-triggered Talents that modify the attacker's Roll dice before any roll is made (e.g. halving the attacker's dice count). See the Abilities domain for individual Talent specs.

### Saving Throws

A Saving Throw is the defender's response to an effect that targets a Save Attribute (a spell with a `save:` block, an environmental hazard, etc.). Construction:

1. Resolve the Save Attribute (`str`, `dex`, `con`, `int`, `wis`, `cha`) named by the triggering effect.
2. Call Proficiencies' *Compute Roll inputs for a Proficiency* with `key = "<attr>_save"`, `attribute_override = "<attr>"`. Creatures supplies the per-key ranks (every Class trains every Save per `creatures/creatures_design.md`).
3. Build the Roll with `dice_count = dice_cap` (Saving Throws always spend the defender's full Dice Cap; the defender does not choose a smaller value). Add the returned Competency Modifier and any Modifiers the consuming domain layers on top.
4. Resolve through Dice / Check Resolution as a standalone Roll or an Opposing Roll within a larger Check.

**Saving Throws do not cost Combat Pool dice.** This is the standing exception. Filling out a Save's Dice Cap costs nothing; the dice are conjured for the roll. Combat does not call *Spend Combat Pool* for save Rolls.

The **Concentration Save** is *not* a Saving Throw in this sense — it uses the spell's casting skill (`cast_skill`), not a save attribute. The two share the term "Save" but are mechanically distinct. See *Concentration enforcement* below.

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
budget = floor(((martial_proficiency_ranks * 2) + combat_pool_attribute)
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

1. Spend `N × Set Value Spend Ratio` extra dice from `combat_pool_spent` via *Spend Combat Pool*.
2. Build the Roll with `dice_count = D - N` and `preroll = +N`.
3. Hand to Dice Resolution. The Preroll field (per `dice_resolution_glossary.md`) folds N dice at Die Size into scoring — each prerolled die is a Critical. When `dice_count = 0`, Dice Resolution rolls nothing and scores the prerolled dice alone.

Combat does not store Die Size — it queries Dice Resolution's config at the point of use. There is no combat-side Set Value override.

### Affliction scheduling (combat)

An Affliction resolves at the start of the afflicted Creature's turn, and a freshly-inflicted Affliction is due on that Creature's **next turn**. Because turns run in initiative order within a Round, "next turn" is **this Round** when the victim still has a turn coming (it sits later in the Round's turn order than the Acting Combatant — *Turn Pending This Round?*) and **next Round** when the victim has already acted (or is the one acting).

Combat owns this timing decision (it is a function of turn order, which Conditions does not know) and hands Conditions' *Inflict Affliction* the `current_round` that lands the first resolution on the right turn. For a Round-frequency Affliction such as weapon Bleed — where *Inflict Affliction* schedules the first resolution at `current_round + 1` — Combat passes `next-turn Round − 1`: when the victim's turn is still pending the next-turn Round is the current Round, otherwise it is the next Round. After the first resolution, *Resolve Affliction* reschedules survivors by the Affliction's own frequency, so a Bleed then ticks on every subsequent turn of the victim.

### Concentration enforcement

Three enforcement points.

**End-of-turn channel check** (during *Apply Per-Turn Cleanup*): for each of the Combatant's Concentration Entries, if `channeled_this_turn` is false **and** the entry's mode is not `auto`, end the Concentration — remove the entry (including any Reservoir) and notify the source domain via *End Concentration*.

**End-of-turn cast check** (during *Apply Per-Turn Cleanup*): for each of the Combatant's Casting Entries, if `committed_this_turn` is false, cancel the Long Cast — remove the entry and notify the source domain via *Cancel Long Cast* with `reason: incomplete_commit`. Otherwise, decrement `turns_remaining` by 1; when it reaches 0, notify the source domain that the cast has completed and remove the entry.

**Concentration Damage Save** (during *Apply Damage*): for each Concentration or Casting Entry on the defender, build a check Roll keyed by the entry's `cast_skill` and add a `Circumstance` Penalty of magnitude `spell_tier + damage_dealt` to `bonus_penalty_list`. Resolve through Dice / Check Resolution; TN clamping and outcome are theirs to compute. On failure: for Concentration Entries, end the Concentration as above (the Reservoir is lost with it); for Casting Entries, *Cancel Long Cast* with `reason: damage`. The penalty is unstacked within the entry — Combat appends a single Penalty entry; Roll Resolution's same-type stacking handles interaction with any other Circumstance Penalties already on the Roll.

### Channeling and Dice Cap

Channeling — adding dice to a Reservoir, or fueling a fire-mode channel's effect Roll — is an exception to the Dice Cap rule. A Combatant may spend up to `combat_pool_spent` dice on a channel; Dice Cap (from Proficiencies) does not apply. When a Combatant later rolls dice **from** a Reservoir (e.g. the auto-mode per-turn attack roll), the normal Dice Cap rule applies to that Roll.

### Drift detection (Stale Combat)

The expected Round at any moment during Combat is `combat_anchor.round_of_day + floor(elapsed_time_ticks / Time Ticks Per Round)`, mod `Rounds Per Day` (with the appropriate Day rollover into `combat_anchor.day_index`). Combat compares this to Chronicle's canonical Timestamp on every *Is Stale?* call. Mismatch indicates time advanced through a non-Combat path while Combat was still active. No automatic remediation in this design — the stub layer is expected to flag the condition and request a Reroll Initiative to resync.

## Per-turn / per-round cleanup

**Apply Per-Turn Cleanup** (called as part of *Advance Turn* on the outgoing Combatant):
- Clear `luck_points` (per the Luck Points clear rule).
- The Combat Pool is **not** refilled here. It refills automatically at the *start* of a Combatant's turn (*Begin Turn*), so a spent pool stays spent until then. (Combat itself starts every Combatant's pool empty — see *Start Combat*.)
- Run the End-of-turn channel check.
- Run the End-of-turn cast check.
- Reset `channeled_this_turn` to false on each of the Combatant's Concentration Entries (ready for next turn).
- Reset `committed_this_turn` to false on each of the Combatant's Casting Entries (ready for next turn).
- Run *Handle End-of-Turn Zone Triggers* for the outgoing Combatant.

**Apply Per-Turn Setup** (called as part of *Advance Turn* on the incoming Combatant, before that Combatant's turn begins):
- For each of the Combatant's Concentration Entries with `reservoir_reset = per_turn`, reset `reservoir` to 0.

**Apply Per-Round Cleanup** (called as part of *Advance Time Tick* when `time_tick` resets to 0):
- No per-Round Concentration bookkeeping is required under the per-turn channel model. Place for future per-Round housekeeping.

DM Luck Points are **not** cleared by either cleanup; they clear only at *End Combat*.

## Atomic state persistence

Mutations write `encounter_data.json` atomically. Reads at startup are tolerant: missing state file → empty Combat (`time_ticks_per_round = null`). The rules file is loaded only at boot; mid-session changes to combat tunables require a restart.

## Responsibilities

### Owned by the encounter domain

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
- Attacker Bonus eligibility: Flatfooted, Unaware. Unaware ("has not yet acted") is inferred from the Round and initiative order — a Combatant is Unaware only in Round 1, before its turn comes up (it sits later in the Round's turn order than the Acting Combatant); from Round 2 on everyone has acted. It is not a stored flag. Hidden is resolved per attacker-defender pair and grants the Unaware Bonus on that attack.
- Set-Value Spend translation to Dice Resolution's Preroll.
- Concentration: per-Combatant Concentration entries, Reservoir tracking, per-turn channeling enforcement, damage-triggered saves, end-of-spell notification to the source domain.
- Long Cast: per-Combatant Casting entries, per-turn commit tracking, completion at zero turns_remaining, damage-triggered saves, cancellation notification to the source domain.
- Severity Calculation including Runtime Bucketing, pre-bucketing Damage Type Mechanics, and routing the result to Conditions.
- Damage Type catalog (`encounter_config.yaml`).
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
- **Validation of Damage Type names against any external catalog** — the catalog *is* `encounter_config.yaml`'s damage_types section.

### Unassigned (no current owner)

- **Downtime.** The non-Combat activities a Creature performs between Combats — rest, recovery of HP and mana, downtime ritual casting, surgery, medical services, and similar passage-of-time activities. Lives in Combat for now because the action economy and recovery rules grew out of Combat; the domain may be renamed (e.g. *Encounters*) once the scope settles. Timekeeping advances the calendar but does not own downtime activities. Mechanics to be designed.
- **The full attack-resolution pipeline.** *Attack / Cast / Use Item* are declared but the multi-step pipeline (Roll construction → Check Resolution → ally Reactions → Apply Damage) is future work. Pieces exist, the composition does not.
- **Non-divisible Turns Per Round mixes.** When a Combatant's `Turns Per Round[tier]` does not divide cleanly into the active Time Ticks Per Round (e.g., 3 vs 5), the floor-midpoint formula produces unevenly-spaced time ticks. Needs explicit LCM-based handling.
- **Initiative reroll edge cases.** Multiple iterations of Insight on the same dice list may repeatedly pick the same die unless values change.
- **Reserved Defense Dice / ally-block flow** (e.g. Shield of Faith). Combat's Granted Action registry can carry such an action, but the exact integration with the attack pipeline depends on the pipeline landing first.
- **Metal Armor classification.** Listed as a configurable list in `encounter_config.yaml` for now; will likely move to Equipment when that domain is designed.

