# Equipment System — Glossary

Sole owner of inventory data: other modules go through the `Equipment` class rather than touching the yaml files directly. *(configurable)* values come from `equipment_config.yaml`.

## Core Concepts

**Item**: Anything that can exist in an Inventory. Has an Item Type, a Quantity, and optional per-instance fields (Tier, Properties, durability damage, stored spell, name override, value_in_gold for Gems, Restock Target).

**Item Type**: The catalog name of an item from `equipment_config.yaml` (e.g. `Long sword`, `Arrow`, `Leather armor`, `Gold`, `Gem`).

**Item Stack**: An Inventory entry recording a Quantity of a specific Item Type with specific per-instance fields. Stacks with identical identity fields may merge.

**Inventory**: The ordered list of Item Stacks belonging to one Owner.

**Owner**: An entity that holds an Inventory. Four kinds: Character, Party, Ground Pile, Shop. Each is addressed by an Owner ID.

**Owner ID**: A string with kind prefix plus id. Characters use `"character:<id>"` (the immutable character id, never the display name); the party uses the reserved `"party"`; Ground Piles use `"ground:<location>"`; Specific Shops `"shop:<id>"`; Generic Shops `"generic_shop:<id>"`.

**Tier**: Non-negative integer representing how magically infused an item is; Tier 0 is non-magical. Item Stacks always carry an integer Tier — the project-wide "Tier 0 → 0.5" rule is a calculation convention applied by other modules, not a Tier value here.

**Source File**: The yaml file an Owner was loaded from. Tracked per-Owner so writes go back to the same file. Owners created at runtime are written to the base file for their kind (`loot.yaml`, `shops.yaml`).

## Inventory Stack Fields

**Quantity**: How many of the Item Type are in the Stack. Defaults to 1; may be fractional for Currencies; never negative. Zero-Quantity Stacks persist until a Cleanup pass removes them.

**Stack Identity**: The fields that must all match for two Stacks to merge: Item Type, Tier, Properties (in order), `stored_spell`, `durability_damage`, name override, equipped status, and — for Gems — `value_in_gold`; for guidance Items, `guidance_bonus`. Equipped and unequipped copies do not merge.

**Stack Merge**: Combining two matching-identity Stacks into one. Quantity is summed; identity fields stay the same.

**Durability Damage**: Integer recording damage an item has taken; defaults to 0. Mechanical effects deferred to a later pass.

**Stored Spell**: Name of a spell currently held in a Spell Storing or Spell Crystal item. Absent or blank means expended.

**Name Override**: A string that fully replaces the Generated Display Name.

**Restock Target**: Optional per-Stack integer. When the Restock operation runs, every understocked Stack (Quantity < Restock Target) is brought up to target. A Stack without a Restock Target is never restocked.

**Equipped**: Optional boolean on a Stack. `true` means the wearer has the item active. Part of Stack Identity, so equipped vs. unequipped copies do not merge. Loot tables may set `equipped: true` row-level so creature-loadout drops arrive pre-equipped.

## Item Definitions

**Item Category**: The top-level grouping. Defined: Weapon, Armor, Ammunition, Currency, Gem, Item (slot-equippable accessories), Consumable. Further categories may be added without code changes — unrecognized categories are inert for category-specific logic.

**Slot**: The body location an Item or Armor occupies. Strings live under `Slots:` in `equipment_config.yaml`. Held weapons and worn armor have implicit slots (hand / body) and don't appear in the list. The character module enforces the "one item per slot" rule at equip time; this module just stores the string.

**Material**: An Armor property specifying baseline `hardness` and `hit_points` formula. Effective hardness scales with Tier as `base_hardness + 2 × Tier`; non-magical armor uses the base. Hit-point formulas are evaluated by combat.

**Weapon Tag**: A mundane structural tag on a Weapon definition (distinct from magical Weapon Properties). Tags live under `Weapon Tags:`. May declare a `damage_formula` override or `damage_offset`; multiple tags compose. Standard tags: `thrown` (overrides damage to `str / 4 - 2`), `light`, `heavy`, `exotic`, `double_weapon`.

**Base Price**: Price in Gold of one non-magical (Tier 0) unit. Inherently magical items (e.g. Cloak of Resistance) declare `base_price: 0`.

**Default Tier Surcharge**: Default flat per-Tier surcharge in Gold added for being magical. Lives under `Tier Pricing.default_tier_surcharges`. *(configurable)*

**Per-Item Tier Surcharge**: Optional `tier_surcharge` map on an Item Type that REPLACES the default for that type.

**Tier Surcharge**: Effective per-tier surcharge — Per-Item if declared, otherwise Default. Used by Unit Price math and divided by category-specific divisors for Ammunition and non-ammo Consumables.

**Default Bonus Surcharge**: Flat per-Guidance-Bonus surcharge in Gold, keyed by Bonus value. Under `Tier Pricing.default_bonus_surcharges`. Used with Default Tier Surcharge to price guidance Items: `default_tier_surcharges[T] + default_bonus_surcharges[N]`. *(configurable)*

**Magical Ammunition Divisor**: Number of magical ammunition units whose combined magical cost equals one Magical Weapon's surcharge. Per-unit magical cost = `(Tier Surcharge + Property costs) / divisor`. Default 100. *(configurable)*

**Consumable Surcharge Divisor**: Same idea for non-ammo Consumables. Default 10. *(configurable)*

**Innately Usable Price Multiplier**: Multiplier applied to any Item Type flagged `innately_usable: true` (premium for items anyone can activate, e.g. potions, oils). Default 2.0. *(configurable)*

**Unit Price**: Gold cost of a single copy of a specific configuration:

- Weapons / Armor: `Base Price + Tier Surcharge + sum of Property costs`.
- Guidance Items: `Default Tier Surcharge[Tier] + Default Bonus Surcharge[Guidance Bonus]` (no Base Price, no per-item `tier_surcharge` map).
- Ammunition: `(Base Price / bundle size) + (Tier Surcharge + Property costs) / Magical Ammunition Divisor`.
- Non-ammo Consumables: `Base Price + (Tier Surcharge + Property costs) / Consumable Surcharge Divisor`.
- Currencies: `value_in_gold`.
- Gems: the Gem's `value_in_gold`.

When `innately_usable: true`, the formula result is multiplied by the Innately Usable Price Multiplier.

**Magical Property**: A named effect attachable to a Weapon or Armor. Specifies minimum Tier, Gold cost, applicable Item Categories, whether it takes a Subtype, and a Display block for the Name Generator.

**Property Subtype**: A variant of a Property (e.g. Fire / Acid / Electricity / Cold for Elemental). Subtyped Properties have one Display entry per Subtype.

**Generated Display Name**: Item name produced from `<tier_prefix> <property_prefixes...> <item_name> <property_suffixes...>` when no Name Override is set. Tier prefix is omitted for Tier 0 and for any category in `tier_hidden_for`.

**Guidance Bonus**: A flat numeric bonus an Item grants to a specific Attribute. Bonus value is primary; the Item's Tier is secondary (the same Tier may correspond to multiple bonus values). Each guidance Item Type lists `guidance_bonus` and parallel `tier` arrays. Same modifier type as the dice resolution Bonus Types List — stacks and clamps per those rules.

**Guidance Attribute**: The attribute affected by an Item's Guidance Bonus. Stored as `guidance_attribute`; the character module interprets the string.

## Currency and Gems

**Currency**: An Item Type with a fixed `value_in_gold` — Gold (1.0), Silver (0.1), Copper (0.01). Stacks by Item Type alone; fractional Quantities permitted. Optional `weight` field stored but not acted on.

**Gem**: An Item Type (`Gem`) whose instances carry their own `value_in_gold` and optional `name`. Two Gem Stacks merge only if both match. Gem types are not configured up-front — any instance with a `value_in_gold` is valid. Spent last when paying a cost; overpayment returned as Gold. *(4 sentences — flagged: spend ordering, identity rules, and config absence are each load-bearing for spend logic and serializer)*

**Value in Gold**: Gold-equivalent value of one unit of a Currency or Gem. Used by Total Wealth and Debit Wealth.

**Total Wealth**: An Owner's combined Gold-equivalent buying power — sum of `Quantity × value_in_gold` across every Currency and Gem Stack.

**Debit Wealth**: Spending Gold to cover a cost. Coins spent cheapest-first (Copper → Silver → Gold); if insufficient, Gems are consumed cheapest-first by `value_in_gold`. A Debit exceeding Total Wealth fails without modifying the Inventory.

## Loot Tables

**Loot Table**: A named, rollable definition of what Items a creature, chest, or Shop carries. Stored in `loot_tables.yaml` and any `loot_tables-*.yaml`.

**Roll Row**: One entry in a Loot Table's `rolls` list. Four shapes:

- **Guaranteed**: `{item}` or `{items}` — always drops.
- **Independent Chance**: `{chance, item}` or `{chance, items}` — drops with probability `chance` ∈ `[0, 1]`.
- **Weighted Choice**: `{options: [{chance, item}, ...]}` — exactly one option picked by cumulative-probability sample; remainder (when `sum(chance) < 1`) means nothing drops.
- **Gated Weighted Choice**: `{chance, options: [...]}` — first roll `chance`, then on success do a Weighted Choice.

A row's payload is `item: <single>` or `items: <list>`; the plural form produces multiple Stacks at once. Any row may declare row-level `equipped: true` (applies uniformly to all stacks). Rows may participate in Roll Variables via `as:`, `key:`, `when:`.

**Roll Variable**: A named, table-scoped value set by one row and consumed by later rows in the same table to gate themselves. A row publishes via `as: <var_name>` (value is the winning outcome's `key:`, or `null` if nothing dropped). A row consumes via `when: { <var_name>: <expected_value> }` — multiple pairs are AND-ed; mismatch skips the row entirely. Variables only live for one `ROLL_LOOT_TABLE` call; `when:` against an unset variable compares to `null`. *(4 sentences — flagged: publish syntax, consume syntax, AND semantics, and lifetime are each separate rules)*

**Option List**: A named, reusable weighted-choice list under `option_lists:` in a loot table file. A row may set `options: "<list_name>"` to pull from the registry; entries may also recurse via `{chance, from: "<other_list>"}`.

**Dice Expression**: A string like `"2d6 + 3"` resolved by a simple expression evaluator. Accepts `NdM`, integer constants, and `+`/`−`. Distinct from `DiceSystem` — this is a utility evaluator, not the success-counting d10 system.

**Loot Table Roll**: Applying a Loot Table's rolls to produce Item Stacks. Gold and other Currencies appear as ordinary Stacks with a Dice Expression `quantity` field; there is no separate "gold" field.

## Magical Item Generation

**Magical Item Constraint**: Configuration passed to the magical-item generator: `{category, tier, tier_weights?, properties_weighted}`. `category` restricts the eligible Item Types; `tier` is a list of allowed Tiers; `tier_weights` optionally weights them (else uniform); `properties_weighted` is a Property→weight map filtered by `min_tier` and `applies_to`. The reserved key `none` lets propertyless magical items win the draw. At most one Property is applied per generated item. *(4 sentences — flagged: each field's role is part of the call contract)*

**Inline Magical Row**: A Roll Row where `item` is a Magical Item Constraint rather than a literal Stack. Resolved at roll time by the magical-item generator.

## Shops

**Shop**: An Owner that sells to and buys from the party. Two kinds: Specific and Generic.

**Specific Shop**: A named shop with persistent Inventory and gold. The party's trades mutate state between DM-initiated Refreshes. References a Loot Table Template used only on Refresh.

**Shop Template**: A Loot Table reference used to generate a shop's initial stock and reroll on Refresh. Both Shop kinds have one.

**Refresh Specific Shop**: DM-initiated refresh on a Specific Shop. Each existing Stack: flip a d2 — on 1 remove the Stack; on 2 keep it but roll a new Quantity uniformly in `[1, current Quantity]`. Gold Stacks treated the same way. Then the Template is rolled and merged in via Stack identity.

**Generic Shop**: A reusable shop definition with no persistent Inventory. A Visit generates fresh stock from the Template; the stock persists as an Active Generic Shop for one Game Day, then is discarded.

**Active Generic Shop**: The transient generated-stock record for a Generic Shop visited today. Stored under `active_generic_shops:` and cleaned out by Advance Time.

**Game Day**: An integer counter tracked by `Equipment`. Advance Time increments it; any Active Generic Shop with `generated_at_day` strictly less than the new day is expired. Persisted under `shops.yaml` `state.current_day`.

**Shop Purchase**: A Specific Shop refuses to buy from the party if its Total Wealth is below the price. Partial purchases (fewer units than offered) are the caller's choice.

## Restock

**Restock Target**: See under Inventory Stack Fields.

**Restock Cost**: Total Gold to bring every Stack up to its Restock Target. `sum over understocked of (target − Quantity) × Unit Price`. Stacks without a Restock Target contribute zero.

**Restock Operation**: Manual, caller-initiated, atomic — debits the full Restock Cost AND increments every understocked Stack, or makes no changes. Fails when Total Wealth is below Restock Cost.

## Item Detail Lookups

The Equipment class exposes three detail-fetcher functions so other modules can read everything about an item from a single call.

**Get Item Details**: Returns a generic dict for any Stack — category, definition block, tier, properties, equipped status, durability damage, display name, unit price, slot (when applicable), value_in_gold (Currency / Gem), guidance fields. Does not compute combat values.

**Get Weapon Details**: Get Item Details extended with weapon-specific fields: resolved damage formula (per-weapon override → first tag with `damage_formula` → category default), damage type list, effective Bleed and Threshold (per-weapon override → max/min over damage types' defaults), tags, and ammo type for projectiles. Combat evaluates the damage formula against the attacker's Strength.

**Get Armor Details**: Get Item Details extended with armor-specific fields: damage reduction, material, base hardness, effective hardness (`base + 2 × Tier`), HP formula string, thickness, resilience increment, computed resilience (`Tier × increment`, with shield/null guards).

## Loot Archive

**Loot Archive**: Persistent record of every Ground Pile the party has formally encountered, who took what, and what is still on the floor. Stored in `notes-loot.yaml`. The notes module reads this for "who got the magical sword" recaps.

**Archive Entry**: One record in the Archive. Carries `id`, `ground_id` of the corresponding Ground Pile, optional `label`, optional `notes_ref`, `closed` boolean, and a list of `items`. Each item record holds the original Stack as it appeared at archive-open time and a `claimed_by` field (an Owner ID or `null`).

**Pickup**: A single `claimed_by` transition on an Archive Entry's item record from `null` to an Owner ID. Recorded by `CLAIM_FROM_LOOT_ARCHIVE`, which simultaneously transfers the matching stack out of the Ground Pile in `loot.yaml`.

**Open Loot Archive**: DM-initiated function creating a new Archive Entry from an existing Ground Pile. Snapshots the pile's items (each `claimed_by: null`) and links via `ground_id`. The pile stays in `loot.yaml`; both copies coexist until Close.

**Close Loot Archive**: DM-initiated function finalizing an Archive Entry. Marks it `closed: true` and removes the corresponding Ground Pile from `loot.yaml`.

## Time

**Advance Time**: Function the caller invokes to notify `Equipment` that game-time has elapsed. Increments the Game Day counter and triggers Active Generic Shop expiry.
