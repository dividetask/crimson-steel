# Equipment — Tests

Tests for the public entry points of the Equipment domain.

Unless a test specifies otherwise, all tests use the values in `equipment_config.yaml`:
- Default Tier Surcharge: `{1: 250, 2: 1000, 3: 4000, 4: 16000, 5: 80000}`.
- Default Bonus Surcharge: `{1: 500, 2: 1000, 3: 2000, …}`.
- Magical Ammunition Divisor: 100.
- Consumable Surcharge Divisor: 10.
- Innately Usable Price Multiplier: 2.0.
- Tier Prefix Format: `"+{tier}"`, Tier Hidden For: `[Consumable]`, Default Property Position: `prefix`.
- Consumable Saturation: `Base = [2, 4, 6, 8, 10, 12]`, `Minimum = [1, 2, 3, 4, 5, 6]`, `Lower Tier Multiplier = 2`.
- Slots, Weapons, Armor, Weapon / Armor Properties, Materials, Items, Consumables, Books, Misc Items: as configured.

Test Owners are referenced by Owner ID. `creature:42` denotes a Creature whose accessor returns the listed Inventory; `party`, `ground:<location>`, `shop:<id>`, `generic_shop:<id>` follow the conventions defined in `equipment_design.md`.

Conditions, Combat, and Abilities are mocked as recorded-call stubs. A test asserting on a Conditions side-effect names the *Conditions entry point* called and the arguments passed.

---

## Stack Identity and Merge

### Add Item

**Adding a Stack to an empty Inventory appends it.** Given Owner `party` with empty Inventory, calling *Add Item* with `{item_type: Long sword, quantity: 1, tier: 0}` produces a one-Stack Inventory at index 0.

**Two Stacks with identical identity merge.** Given an Inventory containing `{Long sword, tier: 0, properties: []}` Quantity 1, *Add Item* with the same identity and Quantity 1 leaves a single Stack at index 0 with Quantity 2.

**Two Stacks differing on `tier` do not merge.** Given an Inventory with `{Long sword, tier: 0}`, *Add Item* with `{Long sword, tier: 1}` produces two Stacks. Order: index 0 is the pre-existing Stack; index 1 is the new one.

**Properties matter in order.** Stacks of `Long sword` with `properties: [Elemental(Fire), Keen]` and `properties: [Keen, Elemental(Fire)]` do not merge — list equality is order-sensitive.

**Equipped and unequipped copies do not merge.** Given an Inventory with `{Long sword, tier: 1, equipped: false}` Quantity 1, *Add Item* with `{Long sword, tier: 1, equipped: true, quantity: 1}` produces two Stacks. The wearer can distinguish the equipped from the carried copy.

**Inscribed Spells are an identity field.** Given a `Ritual book` with `inscribed_spells: [mending, light]`, *Add Item* of a `Ritual book` with `inscribed_spells: [light, mending]` (same set, different order) produces two Stacks. *Add Item* with the identical order merges.

**Gem identity requires `value_in_gold` and `gem_name` to match.** A Gem Stack with `{value_in_gold: 50, gem_name: ruby}` and a Gem Stack with `{value_in_gold: 50, gem_name: sapphire}` do not merge. Two unnamed Gem Stacks with the same `value_in_gold` do.

**Guidance Bonus is an identity field on Guidance Items.** Two `Belt of Strength` Stacks with `guidance_bonus: 2` and `guidance_bonus: 4` do not merge, even though both are Tier 1.

**Restock Target conflict logs a warning and keeps the earlier value.** Given an Inventory with `{Arrow, tier: 0, restock_target: 20}`, *Add Item* with `{Arrow, tier: 0, restock_target: 50, quantity: 5}` merges (identity matches), produces Quantity 25, leaves `restock_target` at 20, and logs a warning.

### Cleanup

**Zero-Quantity Stacks without Restock Target are removed.** Given an Inventory with `{Long sword, quantity: 0, restock_target: null}` and `{Arrow, quantity: 0, restock_target: 20}`, *Cleanup* removes the Long sword but preserves the Arrow Stack.

**Zero-Quantity Stack with Restock Target survives Cleanup.** Confirms the previous test's preservation case in isolation.

**Cleanup is a no-op on positive-Quantity Stacks.** Given an Inventory with one Stack of Quantity 1, *Cleanup* leaves it untouched.

---

## Remove Item, Adjust Stack Quantity, Transfer Stack

**Remove Item decrements without deleting.** Given an Inventory with `{Alchemist's fire, quantity: 2}`, *Remove Item* with `quantity: 1` produces `{Alchemist's fire, quantity: 1}`. The Stack remains at its index.

**Remove Item with default `quantity` removes the whole Stack.** Given `{Alchemist's fire, quantity: 2}`, *Remove Item* with no `quantity` argument sets Quantity to 0. *Cleanup* would then delete the Stack.

**Remove Item refuses to go negative.** Given Quantity 2, *Remove Item* with `quantity: 5` returns an error sentinel and does not persist.

**Remove Item refuses negative `quantity`.** Returns an error sentinel.

**Adjust Stack Quantity sets the value directly.** Given `{Gold, quantity: 12}`, *Adjust Stack Quantity* with `new_quantity: 0` sets Quantity to 0. The Stack persists until Cleanup.

**Transfer Stack moves a Quantity between Owners.** Given `creature:1` with `{Long sword, quantity: 1}` and `party` empty, *Transfer Stack* of the full Stack moves the Long sword to `party` and empties the Creature's Inventory of it (post-Cleanup).

**Transfer Stack is atomic.** When the destination's *Add Item* would fail (hypothetical — Equipment has no failing path today, but the contract holds against future preconditions), the source Inventory is unchanged.

---

## Equip and Reconcile Loadout

### Equip Stack

**Equipping a Stack peels off a Quantity-1 equipped copy.** Given `creature:1` with `{Long sword, quantity: 2, equipped: false}`, *Equip Stack* against the Stack produces two Stacks: the carried copy keeps Quantity 1 at the original index, and a new `{Long sword, quantity: 1, equipped: true}` appears at the next index. *Reconcile Loadout* is then called automatically.

**Unequipping reverses the split.** *Unequip Stack* on the equipped copy flips `equipped` to false, then *Reconcile Loadout* runs. The unequipped copy merges with the carried Stack by Stack Identity, producing a single `{Long sword, quantity: 2, equipped: false}` Stack.

**Equipping a Consumable is an error.** *Equip Stack* on an `Alchemist's fire` returns an error sentinel — Stable Stack Key is undefined for Consumables.

### Reconcile Loadout

**Reconcile clears the `equipment:<owner_id>:` namespace first.** Given `creature:3` with one equipped Stack, *Reconcile Loadout* calls Conditions' *Remove Effects by Prefix* with `equipment:creature:3:` exactly once, before any *Apply Effect* call.

**Each equipped Stack posts its Guidance Bonus.** Given `creature:3` equipping `{Belt of Strength, tier: 1, guidance_bonus: 2, equipped: true, slot: belt}`, *Reconcile Loadout* calls Conditions' *Apply Effect* with `{target_key: str, bonus_type: Guidance, amount: 2, source_id: "equipment:creature:3:Belt of Strength:belt"}`.

**Multiple Properties produce indexed Source IDs.** Given an equipped Weapon Stack with two Property Effects, *Reconcile Loadout* posts Source IDs `equipment:creature:3:<key>:0` and `equipment:creature:3:<key>:1` in order. Re-applying the same Stack uses the same Source IDs — replace-by-Source-ID makes the call idempotent.

**Reconcile is idempotent.** Calling *Reconcile Loadout* twice in a row produces the same Conditions state. The second call clears the namespace and re-posts the same Effects.

**Removing the last equipped Stack clears the namespace.** Given a `creature:3` whose equipped Stack is removed (via *Remove Item* or *Unequip Stack*), the next *Reconcile Loadout* still calls *Remove Effects by Prefix* but issues no *Apply Effect* calls.

**Stable Stack Key uses the catalog Slot.** For `Belt of Strength` (slot `belt`), the Stable Stack Key is `Belt of Strength:belt`. For `Long sword` (no declared slot, Weapon), the key uses `hand:<index>` — equipping two Long swords produces keys `Long sword:hand:0` and `Long sword:hand:1`.

---

## Unit Price

**Tier 0 non-magical Weapon prices as Base Price.** A `{Long sword, tier: 0, properties: []}` Stack has Unit Price 35.

**Tier 1 Weapon adds Default Tier Surcharge.** A `{Long sword, tier: 1, properties: []}` Stack has Unit Price `35 + 250 = 285`.

**Property cost stacks into Unit Price.** A `{Long sword, tier: 1, properties: [Elemental(Fire) cost 500]}` Stack has Unit Price `35 + 250 + 500 = 785`.

**Per-Item Tier Surcharge overrides the Default.** With a homebrew config setting `tier_surcharge: {1: 100}` on `Long sword`, a Tier 1 Long sword prices at `35 + 100 = 135`.

**Guidance Items use Bonus Surcharge plus Tier Surcharge, ignoring Base Price.** A `{Belt of Strength, tier: 1, guidance_bonus: 2}` Stack has Unit Price `Default Tier Surcharge[1] + Default Bonus Surcharge[2] = 250 + 1000 = 1250`.

**Guidance Items at Tier 0 (hypothetical homebrew) price at the Bonus Surcharge alone.** Bypasses Default Tier Surcharge[0] which is undefined.

**Ammunition magical cost divides by Magical Ammunition Divisor.** A `{Arrow, tier: 1, bundle_size: 20, properties: [Elemental(Fire) cost 500]}` Stack has per-unit Unit Price `(5 / 20) + (250 + 500) / 100 = 0.25 + 7.5 = 7.75`.

**Non-ammo Consumable magical cost divides by Consumable Surcharge Divisor.** A `{Alchemist's fire, tier: 1}` Stack has Unit Price (pre-Innately-Usable) `25 + 250 / 10 = 50`.

**Innately Usable doubles the final price.** A `{Alchemist's fire, tier: 0, innately_usable: true}` Stack has Unit Price `25 × 2.0 = 50`. A `{Alchemist's fire, tier: 1}` Stack has Unit Price `(25 + 250 / 10) × 2.0 = 50 × 2 = 100`.

**Currency Unit Price is `value_in_gold`.** A Gold Stack prices at 1.0; Silver at 0.1; Copper at 0.01.

**Gem Unit Price is the Stack's own `value_in_gold`.** A `{Gem, value_in_gold: 250}` Stack prices at 250 regardless of Tier.

---

## Total Wealth and Debit Wealth

**Total Wealth sums Currencies and Gems.** Given an Inventory of `{Gold, quantity: 5}`, `{Silver, quantity: 12}`, `{Gem, value_in_gold: 50, quantity: 1}`, Total Wealth = `5 × 1.0 + 12 × 0.1 + 1 × 50 = 56.2`.

**Other Item Categories do not contribute.** A Long sword Stack does not add to Total Wealth.

### Debit Wealth ordering

**Coins spent cheapest-first.** Given `{Copper, quantity: 50}`, `{Silver, quantity: 5}`, `{Gold, quantity: 1}` (Total Wealth `0.5 + 0.5 + 1 = 2.0`), *Debit Wealth* with `amount: 0.7` consumes all 50 Copper (0.5 gp), then 2 Silver (0.2 gp), leaving `{Silver, quantity: 3}` and the Gold Stack intact.

**Gems consumed when coins are exhausted, cheapest first.** Given `{Copper, quantity: 5}` (0.05 gp), `{Gem, value_in_gold: 10}`, `{Gem, value_in_gold: 50}` — Total Wealth 60.05. *Debit Wealth* with `amount: 30` consumes all 5 Copper, then the 10-gp Gem fully (cumulative 10.05), then the 50-gp Gem fully (overpayment 30.05). A `{Gold, quantity: 30.05}` Stack is added as change via *Add Item*.

**Refund as Gold Stack.** Same setup as above — the refund is added via *Add Item*, so it merges with any existing Gold Stack.

**Atomic failure when amount > Total Wealth.** *Debit Wealth* with `amount: 100` against Total Wealth 60.05 returns an error sentinel and modifies nothing.

**Zero amount is a no-op.** *Debit Wealth* with `amount: 0` leaves the Inventory unchanged.

---

## Loot Table rolling

### Row shapes

**Guaranteed row always produces its payload.** A table whose single row is `{item: {item: Long sword}}` produces one `{Long sword, quantity: 1}` Stack on every roll.

**Independent Chance respects the probability.** A row `{chance: 0.5, item: {item: Long sword}}` produces the Stack iff the random draw `u < 0.5`. Test with seed pinning `u = 0.4` (drops) and `u = 0.6` (does not).

**Weighted Choice picks the first cumulative bucket above `u`.** Row `{options: [{chance: 0.3, item: {item: A}}, {chance: 0.5, item: {item: B}}]}`. With `u = 0.2` produces A; `u = 0.5` produces B; `u = 0.9` produces nothing (remainder).

**Gated Weighted Choice rolls `chance` first.** Row `{chance: 0.5, options: [{chance: 1.0, item: {item: A}}]}`. With outer draw < 0.5, inner Weighted Choice runs and produces A. With outer draw ≥ 0.5, nothing.

**Plural `items:` produces multiple Stacks at once.** Row `{items: [{item: Shortbow}, {item: Arrow, quantity: 20}]}` produces both Stacks in a single Row resolution.

**Row-level `equipped: true` propagates to every produced Stack.** A row `{equipped: true, items: [{item: Rapier}, {item: Studded leather}]}` produces two Stacks both with `equipped: true`.

**Dice Expression `quantity` evaluates per roll.** Row `{item: {item: Gold, quantity: "2d6 + 3"}}` produces a Gold Stack whose Quantity is the rolled expression result.

### Roll Variables

**`as:` publishes the winning `key:`.** A Weighted Choice row `{as: hand, options: [{chance: 0.5, key: one_handed, item: {item: Short sword}}, {chance: 0.4, key: two_handed, item: {item: Spear}}]}` publishes `hand = one_handed`, `hand = two_handed`, or `hand = null` (remainder), depending on the draw.

**`when:` against a matching variable allows the row.** A row `{when: {hand: one_handed}, chance: 0.5, item: {item: Light wooden shield}}` rolls normally when `hand == one_handed`. With `hand == two_handed`, the row is skipped.

**`when:` against an unset variable compares to null.** If no earlier row published `hand`, then `when: {hand: one_handed}` treats `hand == null` and skips the row. `when: {hand: null}` would allow it.

**A skipped row does not publish.** A row carrying both `when:` and `as:` whose `when:` fails does not publish its `as:` value — the variable retains whatever it held before.

**Multiple `when:` pairs are AND-ed.** `when: {hand: one_handed, armor: heavy}` skips the row unless both variables match.

**Variables are scoped to one roll.** Two consecutive *Roll Loot Table* calls do not share Roll Variables; each starts with an empty variable set.

### Option Lists

**Named Option List substitutes for inline `options:`.** A row `{options: tier_one_magical_melee}` resolves identically to a row whose `options:` literally lists every entry from `option_lists.tier_one_magical_melee`.

**Recursive `from:` follows the chain.** An Option List entry `{chance: 0.2, from: tier_two_magical}` recurses into the named list when picked.

---

## Magical Item generation

**`none` produces a propertyless tiered item.** Constraint `{category: melee, tier: [1], properties_weighted: {none: 1}}` produces `{Long sword (or weighted alternative), tier: 1, properties: []}`. Any weapon with `category` matching `melee` may be picked uniformly.

**Property filter applies `min_tier` and `applies_to`.** Constraint `{category: ammo, tier: [1], properties_weighted: {Elemental: 1, Vicious: 1}}` filters out `Vicious` (its `applies_to: [melee]` excludes ammo). The generated Stack carries `Elemental` (with a random Subtype) or — if the catalog change makes the filtered pool empty — falls back to `none`.

**Subtyped Property picks a Subtype uniformly.** With Property `Elemental` selected (subtypes `[Fire, Acid, Electricity, Cold]`), each Subtype is equally likely. Test by pinning the random draw to each quartile of `[0, 1)`.

**`items_weighted` controls Item Type choice.** Constraint `{category: melee, tier: [1], properties_weighted: {none: 1}, items_weighted: {Long sword: 3, Mace: 1}}` picks `Long sword` with probability 0.75 and `Mace` with probability 0.25.

**`tier_weights` weights the Tier draw.** Constraint `{tier: [1, 2], tier_weights: {1: 3, 2: 1}, ...}` picks Tier 1 with probability 0.75.

**No matching Property falls back to `none`.** A pool where every Property is filtered out (e.g., all Properties have `min_tier > picked_tier`) yields a propertyless item.

---

## End-of-Combat loot

**Collect Combat Loot moves non-ally Inventory and Currency into the Ground Pile.** Given:
- Combat hand-off: `[{combatant_id: 1, creature_id: pc_1, ally: true}, {combatant_id: 2, creature_id: goblin_a, ally: false}, {combatant_id: 3, creature_id: goblin_b, ally: false}]`.
- `creature:goblin_a` Inventory: `[{Short sword, quantity: 1, equipped: true}, {Gold, quantity: 3}]`.
- `creature:goblin_b` Inventory: `[{Dagger, quantity: 1, equipped: true}, {Silver, quantity: 10}]`.

*Collect Combat Loot* with `location: map_7` produces Ground Pile Owner `ground:map_7` with Inventory `[{Short sword, quantity: 1}, {Gold, quantity: 3}, {Dagger, quantity: 1}, {Silver, quantity: 10}]`. The two goblin Inventories are emptied (Stacks moved are removed via *Remove Item* and *Cleanup* ed). The player character is untouched.

**Ally entries are skipped entirely.** With the same hand-off, *Collect Combat Loot* never reads `creature:pc_1`'s Inventory and never calls the player character's Loot Table.

**Loot Table Reference is rolled in addition to Inventory.** When `creature:goblin_a` carries a `loot_table: goblin_pocket_change` reference, *Collect Combat Loot* rolls the table and appends the rolled Stacks to the Ground Pile alongside the moved Inventory.

**Empty hand-off (or all allies) produces no Ground Pile.** *Collect Combat Loot* returns `null` and writes nothing.

**Equipped Stacks have `equipped` reset.** Moved Stacks arrive in the Ground Pile with `equipped: false`. Equipment treats this as part of the move — a Ground Pile has no equipped concept.

---

## Loot Archive

**Open Loot Archive snapshots the Ground Pile.** Given `ground:combat_42` with two Stacks, *Open Loot Archive* creates an Archive Entry containing two item records, each carrying the original Stack and `claimed_by: null`. The Ground Pile remains in place.

**Claim From Loot Archive transitions one item.** *Claim From Loot Archive* with `claimer_owner_id: creature:pc_1` on item record 0 sets `claimed_by = creature:pc_1` and moves the matching Stack out of the Ground Pile into `creature:pc_1`'s Inventory.

**Claim refuses a previously claimed item.** A second *Claim From Loot Archive* on the same item record returns an error sentinel.

**Close Loot Archive removes the Ground Pile and marks the entry closed.** After *Close Loot Archive*, the Archive Entry persists with `closed: true` and the corresponding `ground:combat_42` Owner is gone.

---

## Distribute Loot Pile

**Each Stack transfers to its assigned target.** Pile `ground:combat_7` holds three Stacks: `{Rapier, 1, equipped: false}`, `{Healing Draught, 2}`, `{Gold, 30}`. *Distribute Loot Pile* with assignments `[{stack_ref: 0, target_owner_id: "character:1"}, {stack_ref: 1, target_owner_id: "party"}, {stack_ref: 2, target_owner_id: "party"}]`: the Rapier lands in `character:1`'s Inventory, the Healing Draught and Gold land in the Party Owner. The pile is empty afterward.

**Empty pile is removed via Cleanup.** Continuing from the previous case: after all transfers, the pile has no Stacks. *Cleanup* fires automatically and the `ground:combat_7` Owner is gone. *Get Inventory* on `ground:combat_7` returns an empty result (no such Owner).

**`skip` assignments leave the Stack on the pile.** Pile holds `[A, B, C]`. *Distribute Loot Pile* with assignments `[{stack_ref: 0, target_owner_id: "party"}, {stack_ref: 1, target_owner_id: "skip"}, {stack_ref: 2, target_owner_id: "character:2"}]`: Stack A goes to party, Stack C goes to character:2, Stack B remains on the pile. The pile is non-empty afterward; *Cleanup* does not fire.

**`null` target behaves like `skip`.** Same as the previous case with `target_owner_id: null` in place of `"skip"`: the Stack stays on the pile, no transfer.

**Mixed assignments produce a result list in input order.** Inputs `[party, skip, character:2]`: returned list is `[<destination Party Stack>, null, <destination character:2 Stack>]`.

**`character:<id>` to a PC who already owns a matching Stack merges.** PC `character:1` already has `{Healing Draught, quantity: 1, innately_usable: true}`. Pile has `{Healing Draught, quantity: 2, innately_usable: true}` (same identity fields). *Distribute Loot Pile* with `{stack_ref: 0, target_owner_id: "character:1"}`: per Stack Identity, the two Stacks merge — `character:1`'s Healing Draught now reads `quantity: 3`. No new Stack is created.

**`character:<id>` to an unknown Creature ID rejects.** *Distribute Loot Pile* with `{stack_ref: 0, target_owner_id: "character:99999"}`: rejected with an unknown-owner error. The pile is unchanged; no transfers run.

**Non-existent pile rejects.** *Distribute Loot Pile* with `pile_owner_id = "ground:never_existed"`: rejected. No state changes.

**`stack_ref` out of range rejects.** Pile holds two Stacks. *Distribute Loot Pile* with `{stack_ref: 5, target_owner_id: "party"}`: rejected with an out-of-range error. The pile is unchanged.

**Currency Stacks distribute alongside item Stacks.** Pile holds `{Gold, 30}` and `{Rapier, 1}`. *Distribute Loot Pile* with `{stack_ref: 0, target_owner_id: "party"}` and `{stack_ref: 1, target_owner_id: "character:1"}`: the Gold moves to the party (the Party Owner gains 30 gp; if it already held a Gold Stack, the quantity adds), the Rapier to `character:1`.

**All-`skip` assignment leaves the pile in place.** Pile holds three Stacks. *Distribute Loot Pile* with every assignment `target_owner_id: "skip"`: no transfers run. The pile is unchanged; *Cleanup* does not fire. To discard a pile wholesale the caller invokes *Cleanup* directly (or the implementation's pile-delete sentinel).

**Distribute does not touch Combat State.** Combat State has a Combatant pointing at `creature_id = "1000"` (the dead enemy whose loot is being distributed). After *Distribute Loot Pile*, the Combatant entry is unchanged — Combat removal is the caller's separate concern (typically already done by the post-combat creatures stub before this stub runs).

---

## Item Consumption

**Consume Item routes a spell's effects through Conditions.** Given `creature:1` with `{Potion of Cure Light Wounds, quantity: 2, tier: 1, innately_usable: true}` and a `cure_light_wounds` spell that produces an `{minor_damage: -10}` Effect (heal 10 Minor), *Consume Item* with `target_creature_id: creature:1`, `toxicity_threshold: 6`, `saturation_reducer: 0`:
- Calls Conditions' *Apply Heal* with `{minor: 10}` against `creature:1`.
- Calls Conditions' *Apply Magic Toxicity* with the Item-form Toxicity Cost (per the rules below).
- Decrements the Potion Stack to Quantity 1.
- Calls *Cleanup*.

### Item-Form Toxicity

**Potion at target's Tier uses Base[item_tier].** A Tier 2 Potion consumed by a Tier 2 (or higher) target with `saturation_reducer: 0`: Toxicity Cost = `max(Base[2] − 0, Minimum[2]) = max(6, 3) = 6`.

**Reducer lowers the cost down to Minimum[item_tier].** Same Tier 2 Potion on a Tier 2 target with `saturation_reducer: 5`: `max(6 − 5, 3) = 3`. The floor is `Minimum[2] = 3`; a larger reducer (e.g. 10) yields the same 3.

**Below-Tier target multiplies both Base and Minimum.** Same Tier 2 Potion on a Tier 1 target with `saturation_reducer: 0`: `Base[2] × Lower Tier Multiplier = 12`, `Minimum[2] × Lower Tier Multiplier = 6`; Toxicity Cost = `max(12 − 0, 6) = 12`.

**Reducer applies after the multiplier.** Same Tier 2 Potion on a Tier 1 target with `saturation_reducer: 4`: `max(12 − 4, 6) = 8`. With `saturation_reducer: 10`: `max(12 − 10, 6) = 6` (floor).

**Tier 0 Potion uses Base[0].** A Tier 0 Potion on a Tier 0+ target: Toxicity Cost = `max(Base[0] − 0, Minimum[0]) = max(2, 1) = 2`. On a Tier 0 target there is no below-Tier case (no Creature can be below Tier 0).

**Scroll consumption imposes no Equipment-side saturation.** *Consume Item* on a Scroll Stack returns Toxicity Cost = 0 and does not call Conditions' *Apply Magic Toxicity*. The spell's own Mana cost is the Abilities domain's concern.

**Wand consumption imposes no Equipment-side saturation.** *Consume Item* on a Wand Stack returns Toxicity Cost = 0 and does not call Conditions' *Apply Magic Toxicity*. The Mana spend is delegated to Abilities.

### Saturation Gate

**Cure / mana Effects skip when target ≥ threshold.** Given `target_creature_id` whose Conditions reports `magic_toxicity = 7` and `toxicity_threshold: 6`, *Consume Item* of a cure Potion: the Cure Effect is skipped. The Potion's saturation is still imposed.

**Ward effects bypass the gate.** A Potion granting Temporary HP applies the Ward even when toxicity is at the cap.

### Other

**Item-Only spell exposed via Is Item-Only.** When the Abilities catalog flags `dragon_breath` as `item_only: true`, *Is Item-Only?* returns true. Other spells return false.

**Non-Consumable Item Type is not decremented.** *Consume Item* on a Wand (Category `Item`, not `Consumable`) does not decrement Quantity. Consumable Items (Potions, Oils, Scrolls, Alchemist's fire, Acid jar) decrement by one.

**Alchemist's fire routes its damage Effect through Combat.** *Consume Item* on an `{Alchemist's fire, quantity: 1}` with a fire-damage Effect calls Combat's *Apply Damage* against the target. The Stack is decremented to 0; *Cleanup* removes it.

---

## Get Item / Weapon / Armor Details

**Get Item Details returns generic fields.** For `{Long sword, tier: 1, properties: [Elemental(Fire) cost 500], equipped: true}`: returns `category: Weapon`, `definition: <catalog block>`, `tier: 1`, `properties` as a list of Property Applications, `equipped: true`, `display_name: "+1 Flaming Long sword"`, `unit_price: 785`, `durability_damage: 0`, `slot: null` (Weapon — implicit slot `hand`).

**Get Weapon Details adds weapon-specific fields.** For the same Stack: `damage_formula: "str / 4 - 2"` (Category default — no Tag override), `damage_types: [Slashing, Piercing]`, `bleed: 7` (max of Slashing 7 and Piercing 3), `threshold: 4` (min of Slashing 5 and Piercing 4), `tags: []`, `ammo_type: null`.

**Tag damage_formula override wins over Category default.** A `{Great sword, tier: 0}` Stack carries Tag `heavy`. `Get Weapon Details` returns `damage_formula: "str / 2 + 2"` (from `heavy`), not `"str / 2"` (from `Two Handed`).

**Per-Weapon `base_damage` override wins over Tag and Category defaults.** A `{Whip, tier: 0}` Stack has `base_damage: 0` configured. `Get Weapon Details` returns `damage_formula: 0`, not the Category default.

**Per-Weapon `threshold: null` propagates.** `Whip` declares `threshold: null`; *Get Weapon Details* returns `threshold: null` rather than the min over Damage Type defaults.

**Get Armor Details computes Effective Hardness and Resilience.** For `{Chain mail, tier: 2, properties: []}`: `material: Metal`, `base_hardness: 10`, `effective_hardness: 14`, `damage_reduction: 3`, `resilience_increment: 2`, `resilience: 4`, `hit_points_formula: "30 * thickness"`, `thickness: 2`, `is_metal_armor: true` (Chain mail's catalog entry declares `metal: true`).

**Shields read the per-Item Metal flag.** For `{Tower shield, tier: 3}`: `damage_reduction: null`, `resilience_increment: null`, `resilience: 0` (the null guard), `is_metal_armor: true` (Tower shield declares `metal: true`). For `{Light wooden shield, tier: 0}`: `is_metal_armor: false` (no `metal` flag).

**`metal` defaults to false when omitted.** For `{Leather armor, tier: 0}` and `{Studded leather, tier: 0}` (neither declares `metal:`): `is_metal_armor: false`. A Medium-Category Armor without `metal: true` (e.g. `Hide armor`) also reports `is_metal_armor: false` — the flag is per-Item, not per-Category.

**Non-magical armor has zero Resilience.** For `{Chain mail, tier: 0}`: `resilience: 0` (`tier × increment = 0 × 2`).

---

## Generated Display Name

**Tier 0 omits the prefix.** `{Long sword, tier: 0}` → `"Long sword"`.

**Tier ≥ 1 produces a tier prefix from the format string.** `{Long sword, tier: 2}` → `"+2 Long sword"`.

**Consumable Category hides the Tier prefix.** `{Alchemist's fire, tier: 2}` → `"Alchemist's fire"` (Consumable is in Tier Hidden For).

**Property prefix Display sits between the Tier prefix and the Item Type.** `{Long sword, tier: 1, properties: [Elemental(Fire)]}` → `"+1 Flaming Long sword"`.

**Properties apply in `properties` order.** `{Long sword, tier: 1, properties: [Elemental(Fire), Keen]}` → `"+1 Flaming Keen Long sword"`. Reversing the list reverses the prefix order in the name.

**Suffix-position Property sits after the Item Type.** With a homebrew Property `Of Demonslaying` Display `{word: of Demonslaying, position: suffix}`, `{Long sword, tier: 1, properties: [Of Demonslaying]}` → `"+1 Long sword of Demonslaying"`.

**Name Override replaces the entire Generated Display Name.** `{Lute of the Wandering Bard, tier: 1, name_override: "Lute of the Wandering Bard"}` displays exactly the override — no Tier prefix, no Property affixes.

---

## Shops

### Visit Generic Shop (population model)

**First Visit scales stock by population.** A Generic Shop visited on Game Day 5 with `population: 1000` produces an Active Generic Shop Owner with `generated_at_day: 5`. A stock entry `{qty_base: 2, qty_per_kpop: 4}` materializes at Quantity `2 + floor(4 * 1000 / 1000) = 6`.

**Items below their `min_pop` are omitted.** At `population: 100`, an entry with `min_pop: 200` is not stocked.

**Budget scales with population.** *Get Total Wealth* on the Active Generic Shop equals `base_gold + floor(gold_per_sqrt_pop * sqrt(population))` (e.g. `80 + floor(18 * sqrt(1000)) = 649`), held as a Gold Stack in its materialized stock.

**Same-day re-Visit returns the existing Active Generic Shop.** A second Visit on Day 5 reads the same Active Generic Shop without re-materializing — the first visit's population stands for the day.

**Advance Time expires yesterday's Active Generic Shop.** *Advance Time* on Day 5 → Day 6 removes every Active Generic Shop with `generated_at_day < 6`. A subsequent Visit on Day 6 materializes fresh stock.

### Refresh Specific Shop

**Each Stack flips a d2.** Given a Specific Shop with three Stacks and a pinned RNG producing `[1, 2, 1]`: Stacks 0 and 2 are removed; Stack 1 has its Quantity rerolled in `[1, current]`.

**After flip-and-decay, the Shop Template is rolled and merged.** Stacks rolled from the template are added via *Add Item* — matching identities merge.

**Currency Stacks are treated the same way.** A Shop's Gold Stack is subject to the same d2 flip.

**Refresh persists.** After *Refresh Specific Shop*, the Shop's Inventory in `shops.yaml` reflects the new state.

### Shop Purchase

**Specific Shop with insufficient Wealth refuses to buy.** A Shop with Total Wealth 5 asked to buy a Stack worth 10 returns an error sentinel.

**Generic Shop refuses a buy beyond its budget.** A Generic Shop's Wealth is its finite population-scaled budget; *Shop Purchase* of a Stack priced above that budget is refused, and one within it is accepted.

---

## Restock

**Restock Cost sums understocked deltas.** Given an Inventory with `{Arrow, quantity: 5, restock_target: 20, tier: 0}` (Unit Price 0.25 per arrow) and `{Bolt, quantity: 20, restock_target: 20, tier: 0}` (fully stocked): Restock Cost = `(20 − 5) × 0.25 = 3.75`. The Bolt Stack contributes zero.

**Restock pays the cost and refills the understocked Stacks.** With Total Wealth ≥ 3.75, *Restock* debits 3.75 via *Debit Wealth* and sets the Arrow Quantity to 20. Atomic.

**Restock fails atomically when Total Wealth is insufficient.** With Total Wealth 1.0 against a Restock Cost of 3.75, *Restock* returns an error sentinel and modifies nothing.

**Stacks without Restock Target contribute zero.** A Stack with `restock_target: null` is ignored entirely.

---

## Source-file tracking and multi-file overlays

**Loading two `loot_tables-*.yaml` files merges Loot Tables by ID.** Tables from both files appear in the in-memory catalog; duplicate IDs across files raise at load time.

**Mutation writes back to the source file.** A Ground Pile loaded from `loot-arc1.yaml` and modified via *Drop Stack* re-writes `loot-arc1.yaml`, not `loot.yaml`.

**Runtime-created Owners go to the base file.** A Ground Pile created at runtime via *Collect Combat Loot* writes to `loot.yaml`.

**Adding a Loot Table writes to the base.** *Add Loot Table* persists to `loot_tables.yaml`.
