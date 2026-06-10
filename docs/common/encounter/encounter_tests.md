# Encounter — Tests

Externally-observable behavior of the Encounter domain's public entry points. Each section is a public entry point or a closely related cluster. Today every entry point is part of the Combat mode; Downtime and Travel tests will be added when those modes are designed.

## Test config

Tests use the defaults from `encounter_config.yaml` unless noted:

- Initiative Attribute = `wis`, Initiative Divisor = 2.
- Combat Pool Attribute = `wis`, Combat Pool Divisor = 2, Combat Pool Step = 4.
- Turns Per Round = `[1, 1, 1, 2, 4, 8]`.
- Free Action Cost = 0, Bonus Action Minimum = 2, Main Action Minimum = 4.
- Flatfooted Bonus = `{Circumstance, +1}`, Unaware Bonus = `{Circumstance, +2}`.
- Set Value Spend Ratio = 1. (Set Value is read from Dice Resolution's Die Size at use time; tests assume Die Size = 10 per the dice_resolution test config.)

Every test assumes Chronicle is present and `creature_lookup` resolves each Combatant's underlying Creature. Dice Resolution behavior is exercised through Combat — tests state rolled dice values rather than calling the random source.

## Start Combat

**Inactive state has nullable counters.** Before any *Start Combat* call: `time_ticks_per_round = null`, `time_tick = null`, `combat_anchor = null`, `acting_combatant_id = null`, `combatants = []`. *Is Stale?* returns `false`.

**Start Combat sets Time Ticks Per Round to the highest tier.** Inputs: three Combatants with Tiers 1, 3, 4. Defaults give Turns Per Round of `[1, 2, 4]` for those tiers; max is 4. After Start Combat: `time_ticks_per_round = 4`, `tick = 1`, `combat_anchor` = Chronicle's current Timestamp at call time, `elapsed_time_ticks = 0`, `acting_combatant_id = null`, `dm_luck_points = 0`. Each Combatant has its `time_tick_schedule` precomputed.

**Start Combat does not roll Initiative.** After Start Combat every Combatant has an empty `initiative_string`. The caller follows up with *Reroll Initiative* to populate them.

**Time Tick Schedule examples** (with Time Ticks Per Round = 4):
- Tier 1 Combatant (T = 1): `[2]`.
- Tier 3 Combatant (T = 2): `[1, 3]`.
- Tier 4 Combatant (T = 4): `[1, 2, 3, 4]`.

**Tier beyond Turns Per Round is an error.** Inputs include a Tier 6 Combatant with the default `[1,1,1,2,4,8]` (length 6, indices 0..5). Start Combat returns an error sentinel; no state is persisted. The campaign config must extend Turns Per Round before high-Tier Combatants enter Combat.

## End Combat

**End Combat notifies the post-combat consumer.** End Combat is called with three Combatants present. The post-combat consumer (Equipment / Loot — target domain pending) receives a list of three entries, each carrying the Combat ID and Creature ID. After the notification: state is cleared (`time_ticks_per_round = null`, `combatants = []`, etc.).

**End Combat does not end Concentrations.** A Combatant carrying two Concentration entries calls End Combat. State is cleared; no end-of-spell notification fires for either entry. Combat does not own how Concentrations behave once the fight is over.

## Add / Remove Combatant

**Add Combatant raising Time Ticks Per Round triggers Time Tick Schedule recompute.** Active Combat with Tiers `[0, 0]` (Time Ticks Per Round = 1). Adding a Tier-3 Combatant raises Time Ticks Per Round to 2. After the call: the two Tier-0 Combatants' Time Tick Schedules recompute to `[1]` (T = 1 at R = 2), and the Tier-3 Combatant (T = Turns Per Round\[3\] = 2) gets `[1, 2]` per the floored-midpoint formula.

**Add Combatant rolls Initiative for the new Combatant only.** Existing Combatants' `initiative_string` values are unchanged.

**Remove Combatant lowering Time Ticks Per Round triggers Time Tick Schedule recompute and tick clamp.** Active Combat with Tiers `[0, 4]` and `tick = 3`. Removing the Tier-4 Combatant drops Time Ticks Per Round to 1 and `time_tick` clamps to 1 (the new max). The remaining Combatant's Time Tick Schedule becomes `[1]`.

**Remove Combatant clears their Granted Actions.** Combatant 5 has a Granted Action `{combatant_id: 5, ...}` and another Granted Action with `eligible_targets: [5]`. Removing Combatant 5 drops both Granted Actions.

**Remove Combatant ends their Concentration entries.** Removed Combatant has two Concentration Entries. Both source domains receive an end-of-spell notification; entries are dropped.

## Set PC Exclusions

**The supplied list replaces the existing list wholesale.** Combat State has `excluded_pcs = ["7"]`. *Set PC Exclusions* with `["10"]`: `excluded_pcs` becomes `["10"]` (PC `7` is no longer excluded).

**Non-PC Creature IDs are rejected.** *Set PC Exclusions* with `["100"]` (creature `100` is tagged `enemy_template`, not `player_character`): rejected with a non-PC-ID error. `excluded_pcs` is unchanged.

**Unknown Creature IDs are rejected.** *Set PC Exclusions* with `["9999"]` (no such creature): rejected. `excluded_pcs` is unchanged.

**Newly-excluded PC currently in the roster is removed.** Active Combat has Combatant `{id: 8, creature_id: "10"}` for Pippin. *Set PC Exclusions* with `["10"]`: the roster no longer contains a Combatant whose `creature_id = "10"`. Time Ticks Per Round is recomputed (the Combatant's Tier may have contributed) and time-tick schedules are recomputed accordingly. *Remove Combatant*'s standard side effects (Granted Actions cleanup, Concentration end-notify, `acting_combatant_id` reset if matched) apply.

**Newly-unexcluded PC is NOT auto-added by this entry point.** Combat State has `excluded_pcs = ["10"]` and no Combatant for Pippin. *Set PC Exclusions* with `[]`: `excluded_pcs` becomes `[]`. The Combatant list is unchanged — re-adding excluded PCs is the consuming page's render-time reconciliation, not this entry point's job.

**Empty list clears all exclusions.** Combat State has `excluded_pcs = ["7", "10"]`. *Set PC Exclusions* with `[]`: `excluded_pcs` becomes `[]`. Combatants for `7` and `10` (if any) are NOT touched (they were already in the roster, which means they were already considered in-combat; clearing exclusions only affects future render-time reconciliation).

**Empty list with currently-excluded-and-absent PCs leaves the roster untouched.** Combat State has `excluded_pcs = ["10"]`, no Combatant for Pippin. *Set PC Exclusions* with `[]`: list cleared; Combatant list still has no entry for Pippin. The consuming page's next render adds Pippin via *Add Combatant*.

**`excluded_pcs` persists across End Combat.** Active Combat with `excluded_pcs = ["10"]`. Call *End Combat*: the Combat State is wiped (combatants, time ticks, etc.) but `excluded_pcs` remains `["10"]`. The next *Start Combat* sees the same exclusion set — sitting out persists across fights.

**`excluded_pcs` is unaffected by Add Combatant.** Active Combat with `excluded_pcs = ["10"]`. The DM manually calls *Add Combatant* with `creature_id = "10"` (override). The Combatant is added; `excluded_pcs` is unchanged. The next render-time reconciliation will respect `excluded_pcs` only for PCs *missing* from the roster — Pippin is now present, so reconciliation leaves him alone.

## Reroll Initiative

**Reroll Initiative with no parameters rolls every Combatant.** Dice are rolled (count from `floor(wis / 2)`), sorted descending, and encoded per the Dice Result String entry point in dice resolution. Test injects rolled dice `[8, 6, 5, 3]`; `initiative_string` becomes `"8653"`.

**`missing_only` skips Combatants who already rolled.** Two Combatants present — Combat ID 1 with `initiative_string = "X8"`, Combat ID 2 with `initiative_string = ""`. Reroll Initiative with `missing_only = true`: ID 1 keeps `"X8"`; ID 2 rolls and gets a new `initiative_string`.

**`prerolled_initiatives` overrides the roll.** Reroll Initiative with `prerolled_initiatives = {3: "X95"}`. Combatant 3's `initiative_string` becomes `"X95"` without any dice being rolled. Other Combatants roll normally.

**`prerolled_initiatives` wins over `missing_only`.** Combatant 1 has `initiative_string = "X8"`. Reroll Initiative with `missing_only = true, prerolled_initiatives = {1: "987"}`. Combatant 1's `initiative_string` becomes `"987"` — the explicit preroll overrides the missing-only filter.

**Positive Initiative Luck rerolls the lowest non-Critical dice.** Initial dice `[10, 6, 5, 2]`, `luck = 2`. The lowest two non-Critical dice (5 and 2) are rerolled. The 10 is skipped (already Critical). If the rerolls produce 7 and 9, the resulting sorted dice are `[10, 9, 7, 6]`.

**Negative Initiative Luck rerolls the highest non-Failure dice.** Initial dice `[9, 8, 1]`, `luck = -2`. The two highest non-Failure dice (9 and 8) are rerolled. The 1 is skipped (already Failure). If the rerolls produce 4 and 3, the resulting sorted dice are `[4, 3, 1]`.

**Positive Initiative Insight prefers a die that becomes Critical.** Initial dice `[6, 4]`, `insight = 4`. Both dice could reach 10 (4 + 4 = 8, no; 6 + 4 = 10, yes). Pick the *lowest* qualifying die — the 4 fails the qualifier, the 6 succeeds. Result: `[10, 4]`. (When `insight = 4` and both dice would qualify, lowest qualifying wins.)

**Positive Initiative Insight with no crit-capable dice falls back to the highest non-Critical die.** Initial dice `[10, 5, 3]`, `insight = 1`. None of `5+1`, `3+1` reach 10; the 10 is already Critical. Fallback: raise the highest non-Critical, which is 5. Result: `[10, 6, 3]`.

**Negative Initiative Insight lowers the highest die, clamped at 1.** Initial dice `[7, 4]`, `insight = -3`. Highest is 7; lower to 4. Result: `[4, 4]`. With `insight = -8`: 7 lowered, clamped to `max(1, 7-8) = 1`; result `[4, 1]`.

## Round label for the Combat Tracker UI

`encounter_initiative_stub.md` shows a `Round N` label (with an `s/TPR` sub-tick suffix when Time Ticks Per Round > 1). The label is derived from `time_ticks_per_round` and a cumulative tick count `cumulative = elapsed_time_ticks + 1` (1-based — `cumulative = 1` is the very first tick of Round 1).

Formula:

```
round    = floor((cumulative - 1) / time_ticks_per_round) + 1
sub_tick = (cumulative - 1) mod time_ticks_per_round
label    = (time_ticks_per_round == 1) ? "Round R" : "Round R s/TPR"
```

Cases:

- **TPR = 1, Round = 5** → label `Round 5`. The sub-tick row is suppressed because every Combatant takes exactly one turn per Round.
- **TPR = 2, cumulative = 1** → `Round 1 0/2`. Combat has just started; no sub-tick has fired yet.
- **TPR = 2, cumulative = 2** → `Round 1 1/2`. The first sub-tick of Round 1 has fired; the second is the active one.
- **TPR = 2, cumulative = 10** → `Round 5 1/2`. Four full rounds of two sub-ticks each (8 cumulative ticks) plus the second sub-tick of Round 5 → cumulative 10.

## Advance Turn / Advance Time Tick

**Advance Turn moves to the next Acting Combatant.** Time Tick has three Acting Combatants sorted A, B, C by Initiative; `acting_combatant_id` = A. After one Advance Turn: `acting_combatant_id` = B. After two more Advance Turns: pointer falls off the end → Combat calls Advance Time Tick → `acting_combatant_id` = the first Acting Combatant of the new Time Tick.

**Advance Turn applies Per-Turn Cleanup to the outgoing Combatant.** The outgoing Combatant's `luck_points` clears to 0. The Combat Pool is **not** refilled by cleanup — `combat_pool_spent` is left untouched (the pool refills at the start of a turn, not the end).

**Initiative ties break by Combat ID.** Acting Combatants at the current Time Tick include two Combatants with `initiative_string = "97"`, IDs 5 and 12. The sorted order is `[5, 12]` — ascending Combat ID breaks the tie. Advance Turn from `acting_combatant_id = 5` moves to `acting_combatant_id = 12`.

**Advance Time Tick wrapping the Round notifies Chronicle.** Active Combat with `time_ticks_per_round = 4`, `tick = 4`. Advance Time Tick sets `tick = 1`, calls Chronicle's *Advance current Timestamp* with `rounds = 1`, increments `elapsed_time_ticks` by 1.

**Advance Time Tick wrapping the Round triggers Per-Round Cleanup.** Per-Round Cleanup runs cleanly with no Concentration housekeeping (per-turn channel tracking is handled by Per-Turn Cleanup).

## Is Stale?

**Is Stale returns false when expected and actual Round agree.** `combat_anchor.round_of_day = 100`, `elapsed_time_ticks = 8`, `time_ticks_per_round = 4`. Expected Round = `100 + floor(8 / 4) = 102`. Chronicle's Current Round = 102. Result: `false`.

**Is Stale returns true when Chronicle moved further.** Same setup, but Chronicle's Current Round = 110 (someone called *Advance Time* between Combat time ticks). Result: `true`.

**Is Stale handles Day rollover.** Anchor has `round_of_day = Rounds Per Day - 2`, `day_index = 50`, `elapsed_time_ticks = 12`, `time_ticks_per_round = 4` → expected Round crosses one Day boundary. Chronicle's Timestamp must match the post-rollover values for `false`; deviation in either field returns `true`.

## Resolve Attack payload

`Combat.resolve_attack_payload(payload)` consumes the JSON the JS turn flow emits to `/combat/resolve_attack` (shape in `../ui/turn_action_stub.md` under *Confirm payload*). The handler spends Combat Pool for every participant, sums Supporting DoIS minus Opposing DoIS (per *Check Resolution*), and applies damage when the net DoS is positive.

**Spend reaches every participant.** Payload picks attacker dice = 4 with weapon Speed 2, defender dice = 3 with defense Speed 1, two ally reactions of 2 dice each (Reaction Speed 1). The Combat Pool cost of a Roll is the flat Speed surcharge plus one per die rolled — `Speed + dice`, not `Speed × dice`. After resolve:
- Attacker's `combat_pool_spent` increments by `2 + 4 = 6`.
- Defender's `combat_pool_spent` increments by `1 + 3 = 4`.
- Each ally's `combat_pool_spent` increments by `1 + 2 = 3`.

**Defense `choice: "none"` skips the defender's Combat Pool.** Payload defense = `{"choice": "none"}`. The defender's `combat_pool_spent` is unchanged; no Opposing Roll is summed.

**Net DoS sums Supporting minus Opposing.** Rolls: attacker `successes: 5`, ally reaction `successes: 1`, defender defense `successes: 3`. Net DoS = `5 + 1 − 3 = 3`. Damage applied = `weapon.damage_bonus + net_dos`.

**Negative net DoS deals no damage.** Attacker `successes: 2`, defender `successes: 4`. Net DoS = `−2`. No damage is dispatched. The endpoint still records the spends and returns `damage: 0`.

**Damage routes through apply_damage.** Resolved damage is dispatched to `apply_damage(target_id, damage, "physical")`. Per Severity Calculation, that bucket-sorts the raw damage into the `{minor, moderate, major}` Severity Map and forwards to `Conditions.apply_hit_point_damage`. The endpoint returns `severity_map` so the client can update the tracker.

### Magical weapon Damage Riders

A weapon carries `damage_riders` (from *Get Weapon Details*) when its Stack has a magical Property with a `damage_rider`. The rider's extra dice are rolled **at the attack's Target Number, only after the hit lands**, in their own **Roll Resolution Stub** that renders before the editable damage screen; on Confirm it collapses to its own row (with a Change button), then the damage screen appears with a **separate, editable Damage box per rider** (and a Self-damage box for a rider that bites the wielder). Rider (bonus) damage scores with `failure_modifier 0` — Successes and Crits count (Crits double, the Dice Resolution default) but a rolled `1` **never subtracts** from the bonus damage; a `1` only feeds a Vicious-style `self_damage` (its `minimum` plus its `amount` per `1`). The preview returns `riders` (metadata so the panel can build the roll stub); the commit carries the rolled, DM-editable amounts back in `rider_results: [{ id, damage, self_damage }]`. Each rider lands as its **own** Severity Calculation, separate from the weapon's base damage.

**Rider damage is a separate Severity Calculation.** A `slashing` hit also carries an Elemental(Fire) rider (`damage_type: fire`). The rolled `damage: 2` routes through `apply_damage(target, 2, "fire")` — fire's `damage_per_hit: 1` makes it `3`, bucketed Moderate — landing in Conditions separately from the weapon's slashing damage.

**A rider only fires on a hit.** When the net DoS is ≤ 0 (a miss), the payload returns no `riders` / `rider_outcomes` and rolls nothing extra.

**Vicious lands Major and bites the wielder.** A Vicious rider (`severity: major`, `self_damage: {severity: minor, …}`) with `rider_results: { damage: 6, self_damage: 3 }` applies `{major: 6}` to the target and `{minor: 3}` to the **attacker** — all of the bonus damage is Major regardless of its Damage Type, and the self-damage is its own box.

**Preview rolls nothing.** A `commit: false` preview returns the `riders` metadata but applies no rider damage and no wielder self-damage.

### Tier Mismatch weapon damage reduction + Glory

**Higher-Tier defender reduces weapon damage.** Attacker Tier 0 hits a Tier 2 defender for a pre-reduction `11` (base 10 + net 1). With the default `Inherent Damage Reduction Per Tier: 5`, the Tier Mismatch Inherent damage reduction `5 × Δ` (Tier 0 = 0.5) removes `floor(5 × 1.5) = 7`; the payload returns `inherent_dr: 7` and `damage: 4`.

**Glory shrinks the gap.** The same attack with a `tier_advantage: 1` (Glory) weapon raises the wielder's effective Tier to 1: `Δ = 2 − 1 = 1`, reduction `5`, `damage: 6`. Against a defender only one Tier higher, Glory closes the gap entirely — `inherent_dr: 0`, full `damage: 11`.

**No reduction at equal or lower Tier.** An attacker who equals or outranks the defender gets `inherent_dr: 0` (the gap is clamped at zero); the damage is unreduced.

### Inherent / Ascendancy Tier modifiers on the attack check

With `Tier Minimum Inherent Bonus: [0, 1, 2, 3, 4, 5]`:

**Attacker carries its Inherent Bonus.** `Encounter::Attack.attacker_tier_bonuses(attacker_tier: 1, defender_tier: 2, tier_advantage: 0, no_defense: false)` → `[['Inherent', 1]]`. The defender's Defense Roll carries `[['Inherent', 2]]`, which propagates onto the attacker's TN (fighting up is harder by the gap).

**Glory lifts the attacker's Inherent.** The same call with `tier_advantage: 1` → `[['Inherent', 2]]` — the wielder is treated as Tier 2, so its Inherent matches the defender's and the gap closes.

**No-defense adds an Ascendancy penalty — only across a Tier gap.** With `no_defense: true` and no Glory → `[['Inherent', 1], ['Ascendancy', -2]]` (the un-rolled Tier-2 defender's advantage, negated; nets −1 on the TN). With Glory the effective Tier rises to the defender's — equal Tiers exchange no Ascendancy — so → `[['Inherent', 2]]` (the gap is closed; only the lifted Inherent rides).

**Equal Tiers exchange no Ascendancy.** `attacker_tier_bonuses(attacker_tier: 2, defender_tier: 2, tier_advantage: 0, no_defense: true)` → `[['Inherent', 2]]` — no Ascendancy entry between same-Tier opponents (mirroring propagation, where the Inherent does not cross between equal-Tier Rolls).

**Tier 0 contributes nothing.** Tier-0 attacker vs Tier-0 defender yields `[]` from both `attacker_tier_bonuses` and `defender_tier_bonuses` (the Inherent Bonus at Tier 0 is 0).

## Get / Spend / Reset Combat Pool

**Get Combat Pool runs the buy formula.** Combatant has Tier 0, `martial_proficiency_ranks = 4`, attribute = 12. Budget = `floor((4 + floor(12/2)) / 1) = 10`. The tiered Buy cost function (per *Combat Pool computation*: `Step·T(T-1)/2 + R·T` with `T = floor(P/Step)`, `R = P mod Step`) gives `cost(11) = 4·1 + 3·2 = 10 ≤ 10 < cost(12) = 4·3 = 12`. So P = 11 is the largest fit. Result: 11.

**Get Combat Pool guarantees at least Combat Pool Step.** Combatant with Budget = 0 still gets Combat Pool = 4 (Step's free tier).

**Spend Combat Pool increments combat_pool_spent.** Combatant with Combat Pool = 8 and `combat_pool_spent` = 0. Spend Combat Pool of 3 → `combat_pool_spent` = 3, derived remaining = 5.

**Spend Combat Pool refuses to overdraft.** Combat Pool = 8, `combat_pool_spent` = 6 (derived remaining = 2). Spend of 3 returns an error sentinel; `combat_pool_spent` stays at 6.

**Reset Combat Pool zeros combat_pool_spent.** A Combatant whose `combat_pool_spent` was 7 after spending; Reset Combat Pool sets `combat_pool_spent` to 0. Subsequent *Get Combat Pool* − `combat_pool_spent` queries return the full Combat Pool value (e.g. 8).

**Start Combat empties every Combatant's Combat Pool.** After *Start Combat*, each Combatant's `combat_pool_spent` equals its full *Get Combat Pool* size, so derived remaining is 0. The pool refills at the start of the Combatant's turn.

**Start of Turn refills the Combat Pool.** A Combatant whose pool was emptied at *Start Combat* (derived remaining 0): the *Start of Turn* action sets `combat_pool_spent` to 0, so derived remaining returns to the full Combat Pool value.

**Apply Per-Turn Cleanup leaves combat_pool_spent untouched.** Outgoing Combatant had `combat_pool_spent` = 5. After cleanup, `combat_pool_spent` is still 5 — the pool is not refilled at end of turn; it refills at the start of the Combatant's next turn.

## Apply Damage / Severity Calculation

**Non-physical damage uses the catalog Severity.** Defender takes 5 fire damage. Catalog: fire severity = moderate, +1 per hit. Conditions receives `{moderate: 6}` (5 + 1 hit, all moderate).

**Sub-type inherits from parent.** Damage Type `slashing` declares `parent: physical`. Catalog lookup resolves to physical's `severity: { runtime_bucketed: true }`. Slashing-damage Apply Damage calls go through Runtime Bucketing.

**Runtime Bucketing fills Minor → Moderate → Major.** Defender's `Damage Resilience = 1`. Weapon (slashing) supplies `threshold = 2`. Bucket size = 3. Raw damage = 7. Buckets:
- Minor fills 0..3 (3 points).
- Moderate fills 3..6 (3 points).
- Major: remaining 1. Conditions receives `{minor: 3, moderate: 3, major: 1}`.

**Acid damage routes through Conditions' Acid Counter.** Defender takes 6 acid damage. Catalog: acid severity = moderate with `apply_acid_counter`. Conditions receives `APPLY_HIT_POINT_DAMAGE {moderate: 6}` and `APPLY_ACID_DAMAGE(6)`.

**Cold inflicts Shock.** Defender takes 4 cold damage. Conditions receives `APPLY_HIT_POINT_DAMAGE {minor: 4}` and a Shock apply of 4.

**Radiant upgrades undead targets.** Undead defender (subtype set via `creature_lookup`) takes 5 radiant damage. Base severity = moderate; the `upgrade_severity` mechanic upgrades to major. Conditions receives `{major: 5}`.

**Radiant against non-undead.** Non-undead defender takes 5 radiant damage. Base severity = moderate; the `upgrade_severity` mechanic does not fire. Conditions receives `{moderate: 5}`.

**Emotional damage uses critical_value: 3.** *Critical Modifier For* `emotional` returns 3. The attacker's Roll is built with `critical_modifier = 3`; each Critical Success on the attack Roll contributes 3 to DoIS (versus the default 2). Emotional damage that lands deals minor severity.

**Apply Damage triggers a Concentration Save per active entry.** Defender has two Concentration Entries when 5 damage lands. Combat issues two save Rolls — each keyed by its entry's `cast_skill` and carrying a Circumstance Penalty of `spell_tier + 5`. On failure for an entry, *End Concentration* runs for that entry's spell name (Reservoir included).

**Concentration Save penalty math.** Defender holds a Concentration Entry with `spell_tier = 3`. Apply Damage of 5 produces a save Roll whose `bonus_penalty_list` includes `(Circumstance, -8)`. Apply Damage of 0 (a hit that dealt no damage) still issues the save with the penalty equal to just the tier — `(Circumstance, -3)`.

## Granted Actions

**Grant Action persists.** Spell domain calls Grant Action with a `reaction` to Combatant 7 (`source = "Shield of Faith"`, `reaction_to = (3, "attack")`). After persistence: List Granted Actions for Combatant 7 returns the entry.

**Revoke Action removes by predicate.** Two Granted Actions with `source = "Shield of Faith"` exist on Combatant 7. Revoking by `source = "Shield of Faith"` removes both.

**List Granted Actions filters by combatant.** Combatant 7 has 2 actions; Combatant 8 has 1. List for 7 returns 2; List for 8 returns 1.

## Concentration

**Begin Concentration appends an entry.** Combatant 4 calls Begin Concentration with `spell_name = "Sacred Flame"`, `source = "spells:sacred_flame"`, `spell_tier = 0`, `cast_skill = "religion"`, `mode = "fire"`, `reservoir_reset = "per_turn"`, `initial_reservoir = 0`. After call: Combatant 4's `concentration` has one entry with `channeled_this_turn = true` (the cast counts as that turn's channel) and `reservoir = 0`.

**Begin Concentration with a reservoir.** Combatant 5 casts Shield of Faith and channels 5 dice into it on the cast. Begin Concentration is called with `mode = "reservoir"`, `reservoir_reset = "per_turn"`, and `initial_reservoir = 5` (caller pre-applied the Ability's fill ratio of 1). After call: the new entry has `reservoir = 5` and `channeled_this_turn = true`.

**Begin Concentration for an auto-mode spell.** Combatant 6 casts Spiritual Weapon with 4 dice. Begin Concentration is called with `mode = "auto"`, `reservoir_reset = "persistent"`, and `initial_reservoir = 4`. The entry persists with `reservoir = 4` and is exempt from Per-Turn Setup reset.

**Channel adds reservoir amount.** Combatant holds a Shield of Faith entry (`mode = "reservoir"`, `reservoir = 0` at start of their turn after Per-Turn Setup reset). On their turn the Combatant calls Channel with `dice_spent = 4`, `reservoir_delta = 4`. The entry's `reservoir` becomes 4 and `channeled_this_turn` becomes true.

**Channel below Main Action Minimum is rejected.** Combatant calls Channel with `dice_spent = 2`. The call is refused; the entry is unchanged.

**Channel on an auto-mode entry is rejected.** Combatant holds a Spiritual Weapon entry (`mode = "auto"`). A Channel call refuses.

**Discharge Reservoir decrements.** A reservoir-mode entry with `reservoir = 5` after a *Discharge Reservoir* call with `amount = 3` has `reservoir = 2`. A discharge with `amount = 6` against `reservoir = 5` is refused (over-discharge).

**Discharge Reservoir refuses against auto, fire, and maintain modes.** Auto-mode reservoirs are never spent; fire and maintain modes carry no reservoir. All three reject *Discharge Reservoir*.

**Per-Turn Setup resets per-turn reservoirs.** A Combatant with a Shield of Faith entry (`reservoir_reset = per_turn`, `reservoir = 4`) starts their next turn. Per-Turn Setup runs and the entry's `reservoir` becomes 0.

**Per-Turn Setup leaves persistent reservoirs alone.** A Combatant with a Spiritual Weapon entry (`reservoir_reset = persistent`, `reservoir = 4`) starts their next turn. Per-Turn Setup runs; the entry's `reservoir` is still 4.

**End-of-turn check ends spells that were not channeled.** During Apply Per-Turn Cleanup for a Combatant with two Concentration Entries — Sacred Flame `channeled_this_turn = true`, Vicious Mockery `channeled_this_turn = false` — the Vicious Mockery entry is removed and its `source` receives an end-of-spell notification. Sacred Flame persists.

**End-of-turn check skips auto-mode entries.** A Combatant with a Spiritual Weapon entry (`mode = "auto"`, `channeled_this_turn = false`) does not lose the entry on Per-Turn Cleanup; auto-mode entries persist regardless of channel.

**Per-Turn Cleanup resets channeled_this_turn.** After Per-Turn Cleanup runs, every retained Concentration Entry has `channeled_this_turn = false` ready for the Combatant's next turn.

**Apply Damage triggers one Concentration Save per entry.** Defender with three Concentration Entries takes damage; Combat issues three save Rolls; failures end the matching entries (and lose any Reservoir they held); successes leave them.

**End Concentration removes the entry and notifies the source.** Calling *End Concentration* on a Combatant for a specific `spell_name` removes that entry from `concentration` (Reservoir included) and dispatches an end-of-spell notification to the entry's `source`. Other entries are untouched.

## Long Cast

**Begin Long Cast appends a Casting Entry.** Combatant 7 starts a 3-turn cast: Begin Long Cast with `spell_name = "Greater Summoning"`, `source = "spells:greater_summoning"`, `spell_tier = 3`, `cast_skill = "arcana"`, `turns_required = 3`. After call: Combatant 7's `casting` has one entry with `turns_remaining = 2` (the call itself counts as the first turn's commitment) and `committed_this_turn = true`.

**End-of-turn cast check decrements turns_remaining.** A Casting Entry with `turns_remaining = 2`, `committed_this_turn = true` after Per-Turn Cleanup: `turns_remaining = 1`, `committed_this_turn = false`.

**End-of-turn cast check cancels when not committed.** A Casting Entry with `committed_this_turn = false` (the Combatant did not call *Commit to Long Cast* on this turn): Per-Turn Cleanup removes the entry and dispatches *Cancel Long Cast* with `reason: incomplete_commit` to the entry's source.

**End-of-turn cast check completes at zero.** A Casting Entry with `turns_remaining = 0`, `committed_this_turn = true` after Per-Turn Cleanup: the entry is removed and the source receives a completion notification (not a cancellation). The completion is the source domain's signal to resolve the spell's effect.

**Apply Damage triggers Concentration Save against Casting entries too.** Defender with one Concentration Entry and one Casting Entry takes 5 damage. Combat issues two save Rolls — each keyed by its entry's `cast_skill`. A failure for the Casting Entry calls *Cancel Long Cast* with `reason: damage`; a failure for the Concentration Entry calls *End Concentration*.

**Remove Combatant cancels their Long Casts.** Removed Combatant has one Casting Entry. The source receives *Cancel Long Cast* with `reason: caller`; the entry is dropped.

## Set-Value Spend

**Building a Roll with Preroll.** Combatant has Dice Cap 7, decides to preroll 4 dice. Combat:
1. Spends `4 × 1 = 4` extra dice from `combat_pool_spent` via Spend Combat Pool.
2. Builds a Roll with `dice_count = 7 - 4 = 3`, `preroll = +4`.
3. Hands to Dice Resolution.

**Set-Value Spend with all dice prerolled.** Dice Cap = 5, preroll =
5. Combat builds a Roll with `dice_count = 0`, `preroll = +5`. Dice Resolution rolls nothing and scores 5 prerolled Criticals.

**Set-Value Spend bounded by Dice Cap.** Attempting to preroll N > Dice Cap fails — Combat rejects the request before any Spend Combat Pool call. *(Combat enforces the cap; Dice Resolution does not need to know about it.)*

**Set-Value Spend bounded by remaining Combat Pool.** Combatant has 3 dice remaining. Attempting to preroll 4 fails — the Spend Combat Pool call would overdraft — and Combat rejects without modifying state.

## Luck Points

**Per-Combatant Luck clears at start of that Combatant's turn.** Bard Combatant has `luck_points = 5` when their turn begins. After Apply Per-Turn Cleanup (which runs as part of Advance Turn for the outgoing Combatant — i.e. the moment their turn *ends*): `luck_points = 0`.

**DM Luck Points persist across turns and rounds.** With `dm_luck_points = 4`, advancing through several turns and a Round boundary leaves `dm_luck_points = 4`. Only End Combat clears it.

## Creature Predicates

**Can Act delegates to Conditions.** Combat asks Conditions whether the Combatant has any "cannot act" Active Effect (Paralyzed, Stunned, Unconscious) or is Dying / Dead. Result is forwarded.

**Is Dying / Is Dead delegate to Conditions.** Same pattern.

## Critical Modifier For

**Damage Type with critical_value Mechanic.** A Damage Type with `critical_value: 4` mechanic returns 4. The attacker's Roll is built with `critical_modifier = 4`.

**Damage Type without critical_value.** Returns the Roll struct default of 2 (per `dice_resolution_design.md`).

## Tier Mismatch

The Ascendancy (Check) half is tested in the JavaScript suite (`test/check_resolution/tier_mismatch.test.js`); the Inherent damage-reduction half is tested here / in `spec/encounter`.

**Inherent damage reduction scales with the Tier difference.** `inherent_damage_reduction(defender, attacker)` returns `5 × Δ` when the defender out-Tiers the attacker (`(3, 1) → 10`), and 0 when the defender is equal or lower (`(1, 1)`, `(1, 3) → 0`). Tier 0 counts as 0.5 and the result is floored (`(1, 0) → 2`).

**Inherent DR is subtracted in resolve_attack_payload.** A Tier-3 defender struck by a Tier-1 attacker for net 12 takes `12 − (5 × 2) = 2`; the result reports `inherent_dr: 10`. No reduction applies when the attacker is equal or higher Tier.

**Inherent DR also applies to spell damage (resolve_cast_payload).** A Tier-3 target hit by a Tier-1 caster's 14-damage spell takes `14 − (5 × 2) = 4`; it is subtracted from each resolved damage Effect (after Save halving) so preview and commit agree. None applies when the caster is equal or higher Tier; `caster.tier_bonus` (Glorious Charge) shrinks the gap.

**Effective-Tier override shrinks the gap.** Passing `attacker.tier_bonus` to the attack payload raises the attacker's effective Tier for that attack — Glorious Charge's +1 against a one-Tier-higher foe drives Δ to 0, dropping the Inherent DR to `inherent_dr: 0`.

**Ascendancy on the Check (JS).** `TierMismatch.ascendancyModifier(actor, opponent)` returns `['Ascendancy', 2 × Δ]` — a Bonus when the actor out-Tiers the opponent (`(3, 1) → +4`), a Penalty when out-Tiered (`(1, 3) → −4`), and null at equal Tier or when a Tier is absent. Tier 0 counts as 0.5 and the magnitude is floored (`(1, 0) → +1`). `CheckResolution` runs it after Propagation, so a Tier-2 attacker vs a Tier-1 defender resolves to attacker TN 4 / defender TN 8 (the defender's Penalty is not inverted back onto the attacker).

