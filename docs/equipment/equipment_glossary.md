# Equipment System — Glossary

> **Note on conventions**: Defined terms are capitalized throughout this document. Entries marked *(configurable)* have their values defined in `equipment_config.yaml`. This module is the sole owner of inventory data: other modules that need to read or mutate items go through the `Equipment` class rather than touching the yaml files directly.

## Core Concepts

**Item**: Anything that can exist in an Inventory. Every Item has an Item Type (see below), a Quantity, and optional per-instance fields (Tier, Properties, durability damage, stored spell, name override, value_in_gold for Gems, Restock Target).

**Item Type**: The name of an item as defined in `equipment_config.yaml` — e.g., `Long sword`, `Arrow`, `Leather armor`, `Gold`, `Gem`. Item Types are the catalog of what items CAN exist; Item Stacks are the runtime instances.

**Item Stack**: An entry in an Inventory recording ownership of some Quantity of a specific Item Type with a specific combination of per-instance fields. Two stacks with identical identity fields may be merged into one (see Stack Identity).

**Inventory**: The ordered list of Item Stacks belonging to a single Owner.

**Owner**: An entity that can hold an Inventory. Four Owner kinds: Character, Party, Ground Pile, and Shop. Each is addressed by an Owner ID.

**Owner ID**: A string that identifies an Owner, formatted as a kind prefix plus an id. Characters use `"character:<id>"`, where `<id>` is the immutable character id assigned by the character module (NOT the character's display name — names may collide between characters or change over time). The party uses the reserved string `"party"` (no id; there is exactly one). Ground Piles use `"ground:<location>"` where `<location>` is a free-form string. Specific Shops use `"shop:<id>"`. Generic Shop instances use `"generic_shop:<id>"`.

**Tier**: A non-negative integer representing how magically infused an item is. Tier 0 is non-magical. There are no half-Tier items — every Item Stack carries an integer Tier. Some formulas in other modules treat a Tier 0 input as 0.5 for calculation purposes (avoiding multiply-by-zero, etc.), but that is a calculation convention, not a Tier value: the item itself is still Tier 0.

**Source File**: The yaml file an Owner was loaded from. Tracked per-Owner so that writes go back to the same file. Owners created at runtime are written to the base file for their Owner kind (`loot.yaml`, `shops.yaml`).

## Inventory Stack Fields

**Quantity**: How many of the Item Type are in the Stack. Defaults to 1. May be fractional for Currencies (e.g., 147.5 gp). Never negative. Zero-Quantity Stacks persist until a Cleanup pass removes them.

**Stack Identity**: The set of fields that must all match exactly for two Stacks to merge. These are: Item Type, Tier, Properties (in order), stored_spell, durability_damage, name override, and — for Gems — value_in_gold. If any identity field differs, the Stacks remain separate.

**Stack Merge**: The operation of combining two Stacks with matching Stack Identity into a single Stack. The merged Stack's Quantity is the sum of the inputs' Quantities; every identity field stays the same (the inputs were already equal on those fields, by definition of Stack Identity).

**Durability Damage**: An integer recording damage an item has taken. Defaults to 0. Mechanical effects are deferred to a later pass.

**Stored Spell**: The name of a spell currently held in a Spell Storing or Spell Crystal item. Absent or blank means expended.

**Name Override**: A string that fully replaces the Generated Display Name of an item instance.

**Restock Target**: An optional per-Stack integer. When the Restock operation runs for the Owner, every understocked Stack (Quantity below its Restock Target) is brought back up to target. A Stack without a Restock Target is never restocked.

## Item Definitions

**Item Category**: The top-level grouping an Item Type belongs to. Defined categories: Weapon, Armor, Ammunition, Currency, Gem, Item (slot-equippable accessories like cloaks, belts, headbands), Consumable (potions, oils, scrolls; ammo is a separate category despite also being consumed). Further categories (Tool, etc.) may be added without code changes — the module dispatches on category where necessary and treats unrecognized categories as inert for category-specific logic.

**Slot**: The body location an Item or Armor occupies when worn or carried. Slot strings are listed in `equipment_config.yaml` under `Slots:` (e.g., `back`, `bag`, `belt`, `body`, `head`, `neck`, …). The Item Type's `slot` field selects one. Held weapons and worn armor have implicit slots (hand / body) and do not appear in the `Slots:` list. The character module enforces the "one item per slot" rule at equip time; this module just stores the slot string.

**Material**: A property of Armor specifying its baseline `hardness` and `hit_points` formula. Defined under `Materials:` in `equipment_config.yaml`. Effective hardness scales with Tier as `hardness = base_hardness + 2 × Tier`; non-magical armor uses the base value. Hit-point formulas are evaluated by the combat module.

**Weapon Tag**: A mundane structural tag attached to a Weapon definition (distinct from the magical Weapon Properties catalog used on inventory stacks). Tags live under `Weapon Tags:` in `equipment_config.yaml`. A tag may declare a `damage_formula` override or a `damage_offset`; multiple tags compose. Standard tags include `thrown` (overrides damage to `str / 4 - 2`), `light`, `heavy`, `exotic`, and `double_weapon`.

**Base Price**: The price in Gold of one non-magical (Tier 0) unit of the Item Type. Items that are inherently magical (e.g., Cloak of Resistance, which has no mundane Tier 0 form) declare `base_price: 0`.

**Default Tier Surcharge**: The default flat additional cost in Gold added to an item's Unit Price when it is made magical, keyed by Tier. Defined under `Tier Pricing.default_surcharges` in `equipment_config.yaml`. Applies to every Item Type that does not declare its own `tier_surcharge` override. *(configurable)*

**Per-Item Tier Surcharge**: An optional `tier_surcharge` map on an individual Item Type that REPLACES the Default Tier Surcharge for that type's magical pricing. Used by items whose magical pricing follows a different curve (e.g., Cloak of Resistance grows quadratically rather than the default ×4 per tier).

**Tier Surcharge**: The effective per-tier flat additional cost for an Item Type — the Per-Item Tier Surcharge if declared, otherwise the Default Tier Surcharge. Used directly by Unit Price math and divided by category-specific divisors for Ammunition and non-ammo Consumables.

**Magical Ammunition Divisor**: The number of units of Magical Ammunition whose combined magical cost equals the magical surcharge of one equivalent Magical Weapon. Per-unit magical ammunition cost is `(Tier Surcharge + sum of Property costs) / Magical Ammunition Divisor`. Defined under `Tier Pricing.ammunition_divisor`. Defaults to 100. *(configurable)*

**Consumable Surcharge Divisor**: The analogue of the Magical Ammunition Divisor for non-ammo Consumables (potions, oils, scrolls, …). Per-unit magical consumable cost is `(Tier Surcharge + sum of Property costs) / Consumable Surcharge Divisor`. Magical Ammunition uses its own divisor; the two are independent. Defined under `Tier Pricing.consumable_divisor`. Defaults to 10. *(configurable)*

**Innately Usable Price Multiplier**: A multiplier applied to the Unit Price of any Item Type flagged with `innately_usable: true`. Models the premium charged for items that anyone can activate without magical knowledge — most notably potions and oils. Defined under `Tier Pricing.innately_usable_price_multiplier`. Defaults to 2.0. *(configurable)*

**Unit Price**: The Gold cost of a single copy of a specific item configuration (Item Type plus Tier plus Properties).

- For Weapons, Armor, and Items: `Unit Price = Base Price + Tier Surcharge + sum of Property costs`.
- For Ammunition: `Unit Price = (Base Price / bundle size) + (Tier Surcharge + sum of Property costs) / Magical Ammunition Divisor`.
- For non-ammo Consumables: `Unit Price = Base Price + (Tier Surcharge + sum of Property costs) / Consumable Surcharge Divisor`.
- For Currencies: `Unit Price = value_in_gold`.
- For Gems: `Unit Price = the Gem's value_in_gold`.

When the Item Type is flagged `innately_usable: true`, the result of the formula above is then multiplied by the Innately Usable Price Multiplier.

**Magical Property**: A named effect that can be attached to a Weapon or Armor. Each Property specifies a minimum Tier, a cost in Gold, which Item Categories it applies to, whether it takes a Subtype (e.g., Elemental Fire vs. Elemental Cold), and a Display block used by the Name Generator.

**Property Subtype**: A variant of a Property (e.g., Fire, Acid, Electricity, Cold for Elemental). Subtyped Properties have one Display entry per Subtype.

**Generated Display Name**: The item name produced from `<tier_prefix> <property_prefixes...> <item_name> <property_suffixes...>` when no Name Override is set. The tier prefix is omitted for Tier 0 items and for any category listed in `tier_hidden_for` (e.g., Potion).

**Enhancement Bonus**: A flat numeric bonus an Item grants to a specific Attribute on the wearer, equal to the Item's Tier. A Tier 3 Cloak of Resistance grants +3 to all saves; a Tier 5 Belt of Strength grants +5 to Strength. The character module applies the bonus; this module just records the target attribute.

**Enhancement Attribute**: The attribute affected by an Item's Enhancement Bonus. Stored on the Item Type as `enhancement_attribute` (e.g., `saves`, `str`, `dex`, `con`, `int`, `wis`, `cha`). The character module interprets the string; this module just records it.

## Currency and Gems

**Currency**: An Item Type with a fixed `value_in_gold` — Gold (1.0), Silver (0.1), Copper (0.01). Currencies stack by Item Type alone; fractional Quantities are permitted. Each Currency may optionally declare a `weight` (e.g., grams or pounds per unit) for use by an outside encumbrance calculation; this module stores the field but does not act on it.

**Gem**: An Item Type (`Gem`) whose instances carry their own `value_in_gold` field and optional `name` (e.g., "Ruby", "Emerald"). Two Gem Stacks merge only if both `value_in_gold` and `name` match. Gems do not have fixed types defined up-front; any Gem instance with a value_in_gold is a valid Gem.

**Value in Gold**: The Gold-equivalent value of one unit of a Currency or Gem. Used by Total Wealth and Debit Wealth.

**Total Wealth**: An Owner's combined Gold-equivalent buying power, computed by summing `Quantity × value_in_gold` across every Currency Stack and every Gem Stack in the Inventory.

**Debit Wealth**: Spending Gold from an Inventory to cover a cost. Coins are spent cheapest-first (Copper, then Silver, then Gold). If coins are insufficient, Gems are consumed next, cheapest-first by `value_in_gold`. A Debit that would exceed Total Wealth fails without modifying the Inventory.

## Loot Tables

**Loot Table**: A named, rollable definition of what Items a creature, chest, or Shop carries. Loot Tables are stored in `loot_tables.yaml` and any `loot_tables-*.yaml`.

**Roll Row**: One entry in a Loot Table's `rolls` list. Four row shapes are recognized:

- **Guaranteed**: `{slot, item}` — the item always drops.
- **Independent Chance**: `{slot, chance, item}` — the item drops with probability `chance` ∈ `[0, 1]`.
- **Weighted Choice**: `{slot, options: [{chance, item}, ...]}` — exactly one of the options is picked by cumulative-probability sample; the remainder (when `sum(chance) < 1`) means nothing drops.
- **Gated Weighted Choice**: `{slot, chance, options: [...]}` — first roll `chance` to decide whether to enter the table; on success, do a Weighted Choice.

**Option List**: A named, reusable weighted-choice list stored under `option_lists:` in a loot table file. A Roll Row may set `options: "<list_name>"` (string) to pull options from the registry instead of inlining them. Option entries may also recurse via `{chance, from: "<other_list>"}`.

**Dice Expression**: A string like `"2d6 + 3"` resolved by a simple expression evaluator. Accepts `NdM`, integer constants, and `+`/`−` joiners. Used anywhere a Loot Table wants a variable Quantity (e.g., `quantity: "1d6"` on a currency drop). Distinct from the `DiceSystem` module — this is a utility evaluator for arbitrary dice, not the success-counting d10 system.

**Loot Table Roll**: Applying a Loot Table's rolls to produce a list of Item Stacks. Gold and other Currencies show up in the table as ordinary Item Stacks with a Dice Expression `quantity` field; there is no separate "gold" field on a table.

## Magical Item Generation

**Magical Item Constraint**: The configuration passed to the magical-item generator. Shape: `{category, tier, tier_weights?, properties_weighted}`. `category` restricts the pool of eligible Item Types (e.g., `melee`, `ranged`, `ammo`, `all_armor`, `all_body`). `tier` is a list of allowed Tiers. `tier_weights` is an optional map from Tier to weight; if absent, Tiers are picked uniformly from the list. `properties_weighted` is a map from Property name to weight; a Property is eligible only if its `min_tier` is ≤ the picked Tier and its `applies_to` includes the constraint's `category`. Exactly one Property is applied per generated item.

**Inline Magical Row**: A Roll Row where `item` is a Magical Item Constraint rather than a literal Item Stack. Resolved at roll time by invoking the magical-item generator.

## Shops

**Shop**: An Owner that sells to the party and buys from them. Two kinds: Specific and Generic.

**Specific Shop**: A named shop with a persistent Inventory and persistent gold. The party's trades mutate its state between DM-initiated Refreshes. The shop references a Loot Table Template used only when the DM refreshes it. Defined in `shops.yaml` under `specific_shops:`.

**Shop Template**: A Loot Table reference used to generate a shop's initial stock and to reroll it on Refresh. Both Specific and Generic Shops have a Template.

**Refresh Specific Shop**: The DM-initiated refresh operation on a Specific Shop. Each existing Stack in the shop's Inventory is processed in turn: flip a d2; on a 1, remove the Stack; on a 2, keep it but roll a new Quantity uniformly in `[1, current Quantity]`. The shop's gold Stacks are treated the same way (50% fully removed; otherwise a uniform amount in `[0, current]` is removed). Then the shop's Template is rolled and the results are merged into the Inventory via Stack identity.

**Generic Shop**: A reusable shop definition with no persistent Inventory. A Visit generates fresh stock from the Template; the generated stock persists as an Active Generic Shop for one Game Day, after which it is discarded. Defined in `shops.yaml` under `generic_shop_templates:`.

**Active Generic Shop**: The transient generated-stock record for a Generic Shop that has been visited today. Stored under `active_generic_shops:` and cleaned out by Advance Time.

**Game Day**: An integer counter tracked by the `Equipment` class. Advance Time increments it; any Active Generic Shop whose `generated_at_day` is strictly less than the new current day is expired and removed. Persisting the counter lives in `shops.yaml` under `state.current_day`.

**Shop Purchase**: A Specific Shop refuses to buy an item from the party if the shop's Total Wealth is below the purchase price. A shop may buy only what it can afford; partial purchases (fewer units than offered) are the caller's choice, not the module's.

## Restock

**Restock Target**: See under Inventory Stack Fields.

**Restock Cost**: The total Gold cost of bringing every Stack on an Owner's Inventory up to its Restock Target. Computed as `sum over understocked stacks of (Restock Target − Quantity) × Unit Price`. Stacks without a Restock Target contribute zero.

**Restock Operation**: Manual, caller-initiated. Atomic: the operation either debits the full Restock Cost from the Owner's wealth AND increments every understocked Stack's Quantity up to its target, or it makes no changes at all. Fails when the Owner's Total Wealth is below the Restock Cost.

## Combat Attributes (second pass)

Placeholder entries — full definitions land in the Attack Roll / Combat modules. Listed here so that consumers know the `Equipment` class will own the per-item lookup surface.

**Weapon Damage**: Gold formula that converts an attacker's Strength into damage for a specific Weapon. *(pseudocode body TBD — second pass)*

**Damage Reduction (DR)**: The flat damage an Armor subtracts from incoming damage. *(TBD)*

**Bleed**: A Weapon's Bleed value, used by the combat module's ongoing-damage rule. *(TBD)*

**Threshold**: A Weapon's Threshold value, used by the combat module's minimum-damage rule. *(TBD)*

**Resilience**: A magical Armor's effective HP against damage, equal to `Tier × resilience_increment`. *(TBD)*

**Shock**: A non-lethal stunning effect applied by Weapons carrying the `shock` tag (currently the Whip). The magnitude of Shock applied on a successful hit equals the damage the weapon would otherwise deal — physical damage is not applied. Shock recovery, accumulation, and interaction with hit points belong to the combat module. *(TBD)*

## Time

**Advance Time**: The function the caller invokes to notify the `Equipment` class that game-time has elapsed. Increments the Game Day counter and triggers Active Generic Shop expiry. No other time-sensitive state lives in the Equipment module today; a future shared "time-aware module" interface may generalize this across other systems.
