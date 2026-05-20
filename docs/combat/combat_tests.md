# Combat — Tests

Externally-observable behavior of Combat's public entry points. Each section is a public entry point or a closely related cluster.

## Test config

Tests use the defaults from `combat_config.yaml` unless noted:

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

**Add Combatant raising Time Ticks Per Round triggers Time Tick Schedule recompute.** Active Combat with Tiers `[0, 0]` (Time Ticks Per Round = 1). Adding a Tier-3 Combatant raises Time Ticks Per Round to 2. After the call: the new Combatant's Time Tick Schedule is `[1]`; the existing Combatants' Time Tick Schedules are `[1]` (recomputed for the new R = 2).

**Add Combatant rolls Initiative for the new Combatant only.** Existing Combatants' `initiative_string` values are unchanged.

**Remove Combatant lowering Time Ticks Per Round triggers Time Tick Schedule recompute and tick clamp.** Active Combat with Tiers `[0, 4]` and `tick = 3`. Removing the Tier-4 Combatant drops Time Ticks Per Round to 1 and `time_tick` clamps to 1 (the new max). The remaining Combatant's Time Tick Schedule becomes `[1]`.

**Remove Combatant clears their Granted Actions.** Combatant 5 has a Granted Action `{combatant_id: 5, ...}` and another Granted Action with `eligible_targets: [5]`. Removing Combatant 5 drops both Granted Actions.

**Remove Combatant ends their Concentration entries.** Removed Combatant has two Concentration Entries. Both source domains receive an end-of-spell notification; entries are dropped.

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

## Advance Turn / Advance Time Tick

**Advance Turn moves to the next Acting Combatant.** Time Tick has three Acting Combatants sorted A, B, C by Initiative; `acting_combatant_id` = A. After one Advance Turn: `acting_combatant_id` = B. After two more Advance Turns: pointer falls off the end → Combat calls Advance Time Tick → `acting_combatant_id` = the first Acting Combatant of the new Time Tick.

**Advance Turn applies Per-Turn Cleanup to the outgoing Combatant.** The outgoing Combatant's `combat_pool_remaining` resets to its Combat Pool size, `luck_points` clears to 0, `performed_this_turn` becomes true.

**Initiative ties break by Combat ID.** Acting Combatants at the current Time Tick include two Combatants with `initiative_string = "97"`, IDs 5 and 12. The sorted order is `[5, 12]` — ascending Combat ID breaks the tie. Advance Turn from `acting_combatant_id = 5` moves to `acting_combatant_id = 12`.

**Advance Time Tick wrapping the Round notifies Chronicle.** Active Combat with `time_ticks_per_round = 4`, `tick = 4`. Advance Time Tick sets `tick = 1`, calls Chronicle's *Advance current Timestamp* with `rounds = 1`, increments `elapsed_time_ticks` by 1.

**Advance Time Tick wrapping the Round triggers Per-Round Cleanup.** Per-Round Cleanup runs cleanly with no Concentration housekeeping (per-turn channel tracking is handled by Per-Turn Cleanup).

## Is Stale?

**Is Stale returns false when expected and actual Round agree.** `combat_anchor.round_of_day = 100`, `elapsed_time_ticks = 8`, `time_ticks_per_round = 4`. Expected Round = `100 + floor(8 / 4) = 102`. Chronicle's Current Round = 102. Result: `false`.

**Is Stale returns true when Chronicle moved further.** Same setup, but Chronicle's Current Round = 110 (someone called *Advance Time* between Combat time ticks). Result: `true`.

**Is Stale handles Day rollover.** Anchor has `round_of_day = Rounds Per Day - 2`, `day_index = 50`, `elapsed_time_ticks = 12`, `time_ticks_per_round = 4` → expected Round crosses one Day boundary. Chronicle's Timestamp must match the post-rollover values for `false`; deviation in either field returns `true`.

## Get / Spend / Reset Combat Pool

**Get Combat Pool runs the buy formula.** Combatant has Tier 0, `martial_proficiency_ranks = 4`, attribute = 12. Budget = `floor((4 + floor(12/2)) / 1) = 10`. Buy formula: 4 free; 4 more cost `1·4 = 4` (running total 8); the next 4 cost `2·4 = 8` (running total 16, exceeds 10). So P=8 is the largest fit. Result: 8.

**Get Combat Pool guarantees at least Combat Pool Step.** Combatant with Budget = 0 still gets Combat Pool = 4 (Step's free tier).

**Spend Combat Pool decrements remaining.** Combatant with `combat_pool_remaining` = 8. Spend Combat Pool of 3 → 5.

**Spend Combat Pool refuses to overdraft.** Remaining = 2. Spend of 3 returns an error sentinel; remaining stays at 2.

**Reset Combat Pool restores to the formula's value.** A Combatant whose `combat_pool_remaining` was 1 after spending; Reset Combat Pool sets it to *Get Combat Pool*'s result (e.g. 8 from above).

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

**Begin Concentration appends an entry.** Combatant 4 calls Begin Concentration with `spell_name = "Sacred Flame"`, `source = "spells:sacred_flame"`, `spell_tier = 0`, `cast_skill = "religion"`, `mode = "fire"`, `initial_reservoir = 0`. After call: Combatant 4's `concentration` has one entry with `channeled_this_turn = true` (the cast counts as that turn's channel) and `reservoir = 0`.

**Begin Concentration with a reservoir.** Combatant 5 casts Shield of Faith and channels 5 dice into it on the cast. Begin Concentration is called with `mode = "reservoir"` and `initial_reservoir = 5` (caller pre-applied the `reservoir_ratio = 1`). After call: the new entry has `reservoir = 5` and `channeled_this_turn = true`.

**Channel adds reservoir dice.** Combatant holds a Shield of Faith Concentration Entry (`mode = "reservoir"`, `reservoir = 5`). On their next turn the Combatant calls Channel with `dice_spent = 4`. The entry's `reservoir` becomes 9 and `channeled_this_turn` becomes true.

**Channel below Main Action Minimum is rejected.** Combatant calls Channel with `dice_spent = 2`. The call is refused; the entry is unchanged.

**Channel on an auto-mode entry is rejected.** Combatant holds a Spiritual Weapon entry (`mode = "auto"`). A Channel call refuses.

**Spend Reservoir decrements.** A reservoir-mode entry with `reservoir = 3` after Spend Reservoir has `reservoir = 2`. Spending against `reservoir = 0` is refused.

**End-of-turn check ends spells that were not channeled.** During Apply Per-Turn Cleanup for a Combatant with two Concentration Entries — Sacred Flame `channeled_this_turn = true`, Vicious Mockery `channeled_this_turn = false` — the Vicious Mockery entry is removed and its `source` receives an end-of-spell notification. Sacred Flame persists.

**End-of-turn check skips auto-mode entries.** A Combatant with a Spiritual Weapon entry (`mode = "auto"`, `channeled_this_turn = false`) does not lose the entry on Per-Turn Cleanup; auto-mode entries persist regardless of channel.

**Per-Turn Cleanup resets channeled_this_turn.** After Per-Turn Cleanup runs, every retained Concentration Entry has `channeled_this_turn = false` ready for the Combatant's next turn.

**Apply Damage triggers one Concentration Save per entry.** Defender with three Concentration Entries takes damage; Combat issues three save Rolls; failures end the matching entries (and lose any Reservoir they held); successes leave them.

**End Concentration removes the entry and notifies the source.** Calling *End Concentration* on a Combatant for a specific `spell_name` removes that entry from `concentration` (Reservoir included) and dispatches an end-of-spell notification to the entry's `source`. Other entries are untouched.

## Set-Value Spend

**Building a Roll with Preroll.** Combatant has Dice Cap 7, decides to preroll 4 dice. Combat:
1. Spends `4 × 1 = 4` extra dice from `combat_pool_remaining` via Spend Combat Pool.
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

