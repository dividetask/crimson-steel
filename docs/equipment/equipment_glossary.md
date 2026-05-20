# Equipment — Glossary

Defines the vocabulary used by `equipment_design.md` and `equipment_tests.md`. Equipment is the sole owner of inventory data — every other domain reads or mutates items through Equipment rather than touching the underlying storage. *(configurable)* values come from `equipment_config.yaml`. Field shapes, formulas, prefixes, and file paths belong in the design file; this glossary describes terms in domain language only.

## Core Concepts

**Item**: Anything that can exist in an Inventory.

**Item Type**: The catalog name of an Item, drawn from the Equipment configuration. Equipment treats the name as opaque text.

**Item Stack**: An Inventory entry recording a Quantity of one Item Type sharing every per-instance characteristic. Stacks with identical Stack Identity merge.

**Inventory**: The ordered list of Item Stacks belonging to one Owner. Order is preserved across mutations; new Stacks append.

**Owner**: An entity that holds an Inventory. Five kinds: Creature, Party, Ground Pile, Specific Shop, Generic Shop.

**Tier**: A non-negative integer representing how magically infused an Item is. Tier 0 is non-magical.

## Inventory Stack Fields

**Quantity**: How many of the Item Type are in the Stack. Defaults to 1; may be fractional only for Currencies; never negative. Zero-Quantity Stacks persist until a Cleanup pass removes them.

**Stack Identity**: The characteristics that must all match for two Stacks to merge — Item Type, Tier, ordered Properties, Stored Spell, ordered Inscribed Spells, Durability Damage, Name Override, equipped status, and category-specific characteristics (a Gem's Value in Gold and name; a Guidance Item's Guidance Bonus). Property and Inscribed Spell *order* is part of identity even though the contents are conceptually unordered — this keeps merges predictable across loaded Loot Tables.

**Stack Merge**: Combining two matching-identity Stacks into one. Quantity is summed; identity is preserved.

**Durability Damage**: A counter recording damage an Item has taken. Mechanical consequences are deferred to a later pass — Equipment stores the counter without acting on it.

**Stored Spell**: The single spell currently held in a Spell Storing or Spell Crystal Item. Absent or blank means expended.

**Inscribed Spells**: The ordered list of spell names written into a Ritual book. Equipment stores the list without inspecting the names. The set of Item Types that may carry Inscribed Spells is declared per-Item-Type.

**Name Override**: A string that replaces the Generated Display Name. When present, the Tier prefix and Property affixes are suppressed.

**Restock Target**: An optional per-Stack target Quantity used by the Restock Operation. A Stack without a Restock Target is never restocked; a zero-Quantity Stack that carries one survives Cleanup.

**Equipped**: A per-Stack flag indicating that the wearer has the Item active. Part of Stack Identity, so equipped and unequipped copies of the same Item Type do not merge.

## Item Definitions

**Item Category**: The top-level grouping of an Item Type. The defined Categories are Weapon, Armor, Ammunition, Currency, Gem, Item (slot-equippable accessories), and Consumable. Further Categories may be added without code changes — unrecognized Categories are inert for Category-specific logic.

**Slot**: The body location an Item or piece of Armor occupies. Held weapons and worn armor use implicit Slots and are not enumerated. Equipment stores the Slot string; the Creatures domain enforces the "one Item per Slot" rule at equip time.

**Material**: An Armor property pairing a base Hardness with a Hit Points formula. **Effective Hardness** scales with Tier; non-magical armor uses the base.

**Weapon Tag**: A mundane structural attribute of a Weapon — distinct from a magical Weapon Property. Standard Tags include `thrown`, `light`, `heavy`, `exotic`, `double_weapon`, and `lesslethal`. A Tag may override the Weapon's Category-default damage formula.

**Metal Armor**: A per-Armor classification declared on the Armor's catalog entry. Wearers of Metal Armor are flagged for Damage Type interactions (notably Electricity) by Combat. The classification is per-Item-Type, not per-Category — a magical alloy that is Heavy but not metallic is not Metal Armor, and vice versa.

**Base Price**: Price in Gold of one non-magical unit. Inherently magical Items carry a Base Price of zero.

**Default Tier Surcharge**: The flat per-Tier surcharge in Gold added for being magical. *(configurable)*

**Per-Item Tier Surcharge**: An optional per-Item-Type override that replaces the Default Tier Surcharge for that Item Type.

**Tier Surcharge**: The effective per-Tier surcharge — Per-Item when declared, otherwise Default. *(indirectly configurable)*

**Default Bonus Surcharge**: The flat per-Guidance-Bonus surcharge in Gold, used together with the Default Tier Surcharge to price Guidance Items. *(configurable)*

**Magical Ammunition Divisor**: The divisor that scales a magical Ammunition Stack's magical cost down per unit. *(configurable)*

**Consumable Surcharge Divisor**: The divisor that scales a non-ammo Consumable's magical cost. *(configurable)*

**Innately Usable Price Multiplier**: The multiplier applied to any Item Type that anyone may activate without magical knowledge (notably potions and oils). *(configurable)*

**Unit Price**: The Gold cost of a single copy of a specific Stack configuration.

**Magical Property**: A named effect attachable to a Weapon or Armor. A Property declares its minimum Tier, Gold cost, applicable Item Categories, and display words.

**Property Subtype**: A variant of a Magical Property — for example the elemental kinds (Fire, Acid, Electricity, Cold) of an Elemental Property.

**Generated Display Name**: The Item name composed from the Tier prefix, Property affixes, and Item Type when no Name Override is set. The Tier prefix is omitted at Tier 0 and for any Item Category listed under Tier Hidden For.

**Tier Prefix Format**: The pattern used to render the Tier prefix in a Generated Display Name. *(configurable)*

**Tier Hidden For**: The Item Categories that suppress the Tier prefix in their Generated Display Names. *(configurable)*

**Default Property Position**: Whether a Property word defaults to prefix or suffix when its Display block does not declare a position. *(configurable)*

**Guidance Bonus**: A flat numeric bonus a Guidance Item grants to a specific Attribute. The Bonus value is primary; the Item's Tier is secondary, since multiple Bonus values may map to the same Tier.

**Guidance Attribute**: The Attribute a Guidance Item's Bonus targets. Equipment passes the Attribute name through opaquely.

## Currency and Gems

**Currency**: An Item Type with a fixed Value in Gold. Currency Stacks merge by Item Type alone and admit fractional Quantities.

**Gem**: An Item Type whose individual Stacks carry their own Value in Gold and optional name. Gem Stacks merge only when both match.

**Value in Gold**: The Gold-equivalent value of one unit of a Currency or Gem.

**Total Wealth**: An Owner's combined Gold-equivalent buying power, summed across every Currency and Gem Stack.

**Debit Wealth**: Spending Gold to cover a cost. Coins are spent cheapest-first so that heavier denominations last longest; if insufficient, Gems are consumed cheapest-first, with any overpayment refunded as a Gold Stack. A Debit exceeding Total Wealth fails atomically.

## Loot Tables

**Loot Table**: A named, rollable definition of what Items a creature, chest, or Shop carries.

**Roll Row**: One entry in a Loot Table. A Row has one of four shapes: Guaranteed (always drops), Independent Chance (a single probability check), Weighted Choice (one of several options picked by cumulative-probability sample), or Gated Weighted Choice (a probability check followed by a Weighted Choice on success).

**Roll Variable**: A named, table-scoped value set by one Row and read by later Rows in the same table to gate themselves. Roll Variables live for one Loot Table Roll and never persist.

**Option List**: A named, reusable Weighted Choice list defined alongside Loot Tables. A Row may pull from an Option List by name; an Option List entry may recurse into another Option List.

**Dice Expression**: A small expression like `2d6 + 3` used for Loot Table quantities. Equipment's evaluator handles dice notation and integer arithmetic; it is unrelated to the Dice Resolution domain's success-counting dice.

**Loot Table Roll**: Applying a Loot Table to produce Item Stacks. Currencies appear as ordinary Stacks with a Dice Expression Quantity; there is no separate gold payload.

## Magical Item Generation

**Magical Item Constraint**: The configuration handed to the magical-item generator — an Item Category restriction, an allowed Tier list with optional weights, a weighted Property pool, and an optional weighted Item Type pool. At most one Property is applied to a generated Item. A reserved name in the Property pool produces a tiered but propertyless result.

**Inline Magical Row**: A Roll Row whose payload is a Magical Item Constraint rather than a literal Item Type, resolved at roll time.

## Shops

**Shop**: An Owner that buys from and sells to the party. Two kinds: Specific and Generic.

**Specific Shop**: A named Shop with persistent Inventory and Wealth. Trades mutate Shop state between DM-initiated Refreshes.

**Shop Template**: The Loot Table reference a Shop draws from on first stock and on every Refresh.

**Refresh Specific Shop**: A DM-initiated refresh. Each existing Stack independently flips between removal and a reduced-Quantity carry-over; afterward the Shop Template is rolled and merged in.

**Generic Shop**: A reusable Shop with no persistent Inventory. Visiting one generates fresh stock from the Shop Template that lasts for one Game Day.

**Active Generic Shop**: The transient stock generated by a Visit to a Generic Shop. Cleared by Advance Time.

**Game Day**: An integer counter Equipment maintains independently of Chronicle's Timestamp. Advance Time increments it and expires Active Generic Shops generated on earlier days.

**Shop Purchase**: A Specific Shop refuses to buy when its Total Wealth would not cover the price; Generic Shops have unlimited Wealth. Partial purchases (fewer units than offered) are the caller's choice.

## Restock

**Restock Cost**: The Gold required to bring every Stack in an Inventory up to its Restock Target. Stacks without a Restock Target contribute zero.

**Restock Operation**: A manual, caller-initiated, atomic refill — the full Restock Cost is debited and every understocked Stack is brought to target, or nothing changes. Fails when Total Wealth is below Restock Cost.

## End-of-Combat Loot

**Ground Pile**: A loot pile sitting at a location in the world. A kind of Owner.

**Collect Combat Loot**: The end-of-Combat hand-off invoked by Combat. For each non-ally Combatant supplied, Equipment moves the Combatant's Inventory and Currency into a Ground Pile keyed by the Combat, optionally rolling the Combatant's death Loot Table for additional drops. Ally Combatants are skipped.

**Ally Flag**: A per-Combatant boolean supplied by Combat at end-of-Combat hand-off. Marks a Combatant as untouched by Collect Combat Loot.

**Loot Table Reference**: An optional Loot Table named on a Creature Reference that Collect Combat Loot rolls in addition to taking the Combatant's existing Inventory.

## Loot Archive

**Loot Archive**: The persistent record of every Ground Pile the party has formally encountered, who claimed what, and what remains on the floor.

**Archive Entry**: One record in the Loot Archive. Carries a reference to the corresponding Ground Pile, an optional label, an optional notes reference, a closed flag, and the snapshotted item records.

**Pickup**: A single transition of one Archive item record from unclaimed to a specific Owner. Records the claim and transfers the matching Stack out of the Ground Pile in the same step.

**Open Loot Archive**: Creating a new Archive Entry from an existing Ground Pile. The Ground Pile remains in place; the Archive coexists with it until Close.

**Close Loot Archive**: Finalizing an Archive Entry. The Entry is marked closed and the corresponding Ground Pile is removed.

## Item Detail Lookups

The Equipment domain exposes three detail-fetcher entry points so other domains can read everything about an Item from a single call.

**Get Item Details**: Returns the generic Item information: Category, Item Type definition, Tier, Properties, equipped status, Durability Damage, Display Name, Unit Price, Slot when applicable, Value in Gold for Currencies and Gems, and Guidance fields.

**Get Weapon Details**: Get Item Details extended with weapon-specific information: resolved damage formula, Damage Type list, effective Bleed and Threshold, Tags, and ammo type.

**Get Armor Details**: Get Item Details extended with armor-specific information: Damage Reduction, Material, base Hardness, Effective Hardness, Hit Points formula, Thickness, Resilience Increment, computed Resilience, and the Metal Armor flag.

## Item Consumption

**Item Consumption**: Invoking a spell held by a Potion, Oil, Scroll, Wand, or other spell-storing Item. Consume Item applies the spell's effects to the target's Conditions, imposes Magic Toxicity per Item-form rules (Potion and Oil only), and decrements the Stack's Quantity by one for Consumables.

**Consumable Saturation Base**: The per-Tier saturation imposed by Potions and Oils, indexed by the Item's Tier. *(configurable)*

**Consumable Saturation Minimum**: The per-Tier floor below which caller-supplied reducers cannot push the imposed saturation. *(configurable)*

**Lower Tier Multiplier**: The multiplier applied to both Consumable Saturation Base and Consumable Saturation Minimum when the target Creature's Tier is strictly lower than the Item's Tier. *(configurable)*

**Saturation Gate**: The rule by which Cure and Mana-restore effects refuse to land when the target is at or above the Toxicity Threshold supplied by the caller. Ward effects bypass the gate.

**Innately Usable**: An Item Type classification marking the Item as usable without magical knowledge. Multiplies Unit Price by the Innately Usable Price Multiplier.

**Item-Only Spell**: A spell that can be invoked only through Item Consumption — never as a standalone Ability.

## Equip-Time Wiring

**Equipment Source ID Namespace**: The reserved namespace into which Equipment writes Active Effects when posting equipped Items to Conditions. Equipment is the sole writer to this namespace.

**Stable Stack Key**: A deterministic identifier for an equipped Stack, derived from the Item Type and its Slot. Combined with the Owner to form the per-Stack Source ID used in the Equipment Source ID Namespace.

**Reconcile Loadout**: The equip-time operation that clears every Active Effect Equipment has posted for an Owner and re-applies the current loadout's effects. Idempotent — Equipment never reads Conditions back to verify state.

## Interactions with other domains

- **Conditions** receives the Active Effects Equipment posts on equip. Equipment owns the Equipment Source ID Namespace; Conditions never validates Source IDs.
- **Combat** notifies Equipment at End Combat via Collect Combat Loot, supplying the list of Combatants and their Ally Flags. Combat queries Equipment through Get Weapon Details and Get Armor Details during Severity Calculation.
- **Creatures** owns Creature identity and the one-Slot-one-Item enforcement at equip time. Equipment stores Slot strings but does not enforce.
- **Abilities** owns spell catalogs. Equipment looks up Inscribed Spells, Stored Spells, and Item-form Effect data through Abilities at Consume Item time.
- **Modifiers** owns the canonical Bonus Types List. Property catalog entries declare Bonus Type names by reference; Equipment carries them through opaquely.
- **Chronicle** is not consulted. Equipment's Game Day counter is independent.
