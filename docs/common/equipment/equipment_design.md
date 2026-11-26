@chapter 7 Equipment

# Equipment — Design

@player
What a character carries matters as much as what they can do. This chapter covers the things a Creature owns — coins and gems, weapons and armor, magical gear, and the potions, scrolls and wands that put a spell in anyone's hands. It shows how to read the equipment tables printed at the end of the chapter, what changes when you put an item on, and what an item costs. How weapon meets armor in a fight belongs to the **Combat** chapter; this one supplies the numbers Combat uses.

@implementation
Sole owner of inventory data — Items a Creature carries or wears, plus the Currency, Gem, Shop, Loot Table, Ground Pile, and Loot Archive state that surround inventory mutation. Other domains read or mutate items only through the public entry points listed below; the underlying YAML files are not touched directly.

Sibling domains:

- **Conditions** receives the Active Effects Equipment posts on equip/unequip. Equipment writes only into the `equipment:` Source ID Namespace and uses Conditions' *Apply Effect* / *Remove Effects by Prefix* to reconcile.
- **Combat** triggers *Collect Combat Loot* at *End Combat* and queries item details during Severity Calculation.
- **Creatures** owns Creature identity, the Slot-uniqueness rule at equip time, and the storage of Creature Inventories. Equipment reads Creature Inventories through a Creature accessor.
- **Abilities** owns the spell catalog. Equipment looks up spells stored in or inscribed into items at *Consume Item* time.

## What you carry

@player
Everything you own is an **Item**, and the list of your Items is your **Inventory**. Identical Items share one line with a **Quantity** — twenty arrows are one line — while an Item that differs in any way (a higher Tier, a magical Property, a different gem) gets a line of its own. An Item you carry is either **equipped** — worn or in hand, and doing its work — or packed away.

Four kinds of owner hold an Inventory: a **Creature**; the **Party**, one shared stash of common coin and unclaimed gear; a **Ground Pile**, loot lying at a particular place (dropping an Item puts it there); and a **Shop**, with its stock and the gold it has to buy with.

## Money

@player
Prices are in Gold. The `Currency` table lists the coins — Gold, Silver and Copper — with the value of each in Gold, and coins change freely into one another at those values. A **Gem** carries its own value, stone by stone. Your **Total Wealth** is the Gold value of all your coins and gems.

When you pay:

1. If the price is more than your Total Wealth, the purchase fails and nothing is spent.
2. Coins go first, least valuable first, so the most valuable are the last to leave your purse.
3. If the coins run out, gems go next, cheapest first, and a gem is always spent whole.
4. Whatever a gem overpays comes back as change in Gold.

When a player character buys something, their own wealth is spent first and the Party's purse covers the rest; the purchase fails only if the two together fall short.

You may give any line of your Inventory a **Restock Target** — the Quantity you like to keep, such as a full quiver. When you get the chance to resupply, **restocking** buys every such line back up to its target in one purchase. It is all or nothing: if you cannot pay the whole **Restock Cost**, nothing is bought.

## Wearing and wielding

@player
Worn Items occupy a **Slot** on the body: {{Slots}}. Each Slot holds one Item, so a second belt waits in your pack. Armor fills the body Slot; weapons and shields are held rather than worn; an Item that names no Slot — rations, a bedroll — is only ever carried. Ammunition, consumables, coins and gems are never equipped.

An equipped Item works for as long as it stays equipped and stops the moment it comes off: its Bonuses apply, the Abilities it grants are yours, and the spell in a Wand is yours to cast. Those Bonuses obey the stacking rule from the **Dice Resolution** chapter — two Bonuses of the same Type do not add together, only the larger counts — so check the Type before paying for a second source of the same help.

A **Tattoo** is permanent body art that grants Abilities. Tattoos have places of their own — {{Tattoo Slots}} — separate from the worn Slots: a chest Tattoo never competes with your armor, only with another chest Tattoo. A Tattoo is always in effect and can never be removed.

## Weapons

@player
The `Weapons` table has one entry per weapon. Read an entry like this:

- Its **category** — Ranged, One Handed or Two Handed — sets two figures from `Weapon Categories`: the weapon's **base damage**, a formula built on your Strength, and its **Speed**, the flat number of Combat Pool dice an attack costs on top of the dice you roll.
- Its **tags** — light, heavy, thrown and so on, described in `Weapon Tags` — are structural traits. A tag may carry its own base damage formula or Speed, which replaces the category's; if several do, the first tag listed wins.
- Its **Damage Type** — Slashing, Bludgeoning or Piercing, all of them physical damage — gives it a **Bleed** and a **Threshold** from `Damage Type Defaults`. A weapon with two Damage Types takes the higher Bleed and the lower Threshold.
- A figure written on the weapon's own entry overrides all of the above. A few entries carry extras: a throwing range, or a save the target must make when hit.
- A weapon that names an ammunition type fires that kind of `Ammunition`, sold by the bundle.

Threshold and Bleed are what make one weapon wound differently from another:

- **Threshold** decides how deep the damage goes. A hit fills the target's Minor damage up to the Threshold plus the target's Damage Resilience, then Moderate by the same amount, and the rest is Major. The lower the Threshold, the sooner a blow turns Moderate and Major.
- **Bleed** decides how freely the wound bleeds. A hit inflicts the bleeding Affliction (see **Conditions**) with a Potency of the weapon's Bleed plus the damage dealt.

**Natural weapons** — bites, claws, slams — sit in the same table. A Creature has them because of what it is; they are never carried, bought or sold. Some inject a poison: a hit also inflicts the Affliction named on the entry, with a Potency of the listed amount plus the damage dealt. Every Creature can also attack **Unarmed**.

In a fight, an attack with a weapon is a Martial Roll (the **Skills** chapter gives your Dice Cap). You pay the weapon's Speed plus one Combat Pool die per die rolled, and a hit deals the weapon's base damage, plus your Martial Competency Modifier, plus the attack's Degree of Success, before the target's armor has its say. A melee weapon in hand also lets you **Parry** at the same price. The **Combat** chapter walks through the whole exchange.

## Armor and shields

@player
The `Armor` table gives every piece a **category** — Clothing, Light, Medium, Heavy or Shield — whose figures are in `Armor Category Defaults`, and a **material**, whose figures are in `Materials`.

Armor protects in two ways, and it pays to keep them apart:

- **Damage Reduction** is subtracted from each hit before the wound is sorted into Minor, Moderate and Major. It comes from the armor's category and does not change with the armor's Tier.
- **Damage Resilience** makes each wound shallower: it is added to the attacker's Threshold, so more of a blow stays Minor. Your Damage Resilience is your own Tier (Tier 0 adds nothing), plus your armor's Tier multiplied by its category's **Resilience Increment**, plus any Bonuses to it. Mundane armor is Tier 0 and adds none of its own.

A **shield** gives neither. It lets you **Block** — a Defensive Action that answers melee, ranged and spell attacks alike (see **Combat**). No shield in hand, no Block.

A material gives the object itself a **Hardness** and **Hit Points** (the formula uses the category's Thickness), and each Tier of a magical piece adds 2 to its Hardness. This book does not yet give rules for damaging or breaking gear.

Armor marked as metal is **Metal Armor**, which matters to certain Damage Types — Electricity above all (see **Combat**).

## Magical gear

@player
Every Item has a **Tier**, the same measure of magical density the **Magical Tier** chapter applies to Creatures. Ordinary gear is Tier 0. On a magical weapon or piece of armor the Tier does four things:

- **On a weapon** it is an enhancement: a Guidance Bonus equal to the Tier on attack Rolls made with it, and the same amount added to the damage it deals.
- **On armor** it raises your Damage Resilience and hardens the piece, as above.
- It unlocks **Properties**: each has a minimum Tier, and an Item must be at least that Tier to carry it.
- It raises the price — see *What things cost*.

### Weapon Properties

@player
`Weapon Properties` lists each Property with its cost, its minimum Tier, and what it can go on — melee weapons, ranged weapons, ammunition. Most add a **Damage Rider**: extra dice, as many as the Property lists, rolled only after the attack has hit, at the attack's own Target Number. Each Success does what the Property says and a Critical Success counts double as usual, but a 1 never subtracts. Rider damage is a wound of its own, sorted by Severity separately from the weapon's damage and by the rules of its own Damage Type.

| Property | The Item is called | What it does |
|---|---|---|
| Elemental | Flaming, Corrosive, Shocking or Freezing | Rider dice deal Fire, Acid, Electricity or Cold damage. Each such Item is bound to one element. |
| Emotional | Wrathful | Rider dice deal Emotional damage. |
| Radiant | Radiant | Rider dice deal Radiant damage. |
| Subdual | Merciful | Rider dice inflict Shock rather than damage, and the weapon's Threshold is raised, so its wounds stay shallower. |
| Glory | Glorious | No rider. When you attack a Creature of a higher Tier than yours, you count as being of a higher Tier for that attack (see **Combat**). |
| Vicious | Vicious | Rider dice deal the weapon's own kind of damage, all of it Major. The weapon bites back: every hit deals Minor damage to its wielder, and more for each rider die that shows a 1. |

### Armor Properties

@player
`Armor Properties` lists them the same way.

| Property | The Item is called | What it does |
|---|---|---|
| Fortification | Fortified | Adds a Guidance Bonus to your Damage Resilience. Body armor only, never a shield. |
| Elemental Resistance | Fireproof, Acidproof, Grounded or Coldproof | Takes a fixed amount off every hit of its one element, before the wound is sorted by Severity. |

### Attribute and save items

@player
The `Items` table lists worn Items that grant a flat **Guidance Bonus** while equipped: belts for Strength, Dexterity and Constitution, headbands for Intelligence, Wisdom and Charisma, and the Cloak of Resistance for saving throws. A Bonus to an Attribute raises the Attribute itself, and with it everything worked out from it. Each entry pairs every Bonus the Item can grant with the Tier of the Item that grants it; more than one Bonus can share a Tier.

### Reading an item's name

@player
A magical Item's name is assembled from its parts: the Tier prefix, written `{{Tier Prefix Format}}`; the word for each Property (a {{Default Property Position}} unless its entry says otherwise); then the Item itself. A Tier 1 long sword with the Elemental Property bound to fire is its Tier prefix followed by *Flaming Long sword*. Three things break the pattern: Items of these categories show no Tier prefix — {{Tier Hidden For}}; an attribute or save Item shows the size of its Bonus where the Tier would be; and a one-of-a-kind Item goes by its own name.

## Spell items and consumables

@player
A spell can be put into an object. There are four **Item Forms**, and any Creature can use them — the Item supplies the spell, so you need not be a caster.

| Form | How you use it | Which spells | Mana | Magic toxicity | Used up? |
|---|---|---|---|---|---|
| **Scroll** | Read it to cast the spell once, exactly as if you had cast it yourself. | Any | None | None | Yes |
| **Wand** | While it is equipped, its spell is one you can cast. | Any | The spell's usual cost, from your own Mana | None | No |
| **Potion** | Drink it. The spell takes effect on you. | Only those that allow a Potion | None | On the drinker | Yes |
| **Oil** | Throw it at a target at range, or apply it to a target beside you. | Only those that allow an Oil | None | On the target | Yes |

The casting Check for a spell cast from an Item uses one of the Skills the spell names, or Evocation. Each spell's entry in the Spell list says which Forms it comes in, and the **Magic and Abilities** chapter covers casting. Reading a Scroll or drinking a Potion in a fight is a Main Action (see **Combat**).

Potions and Oils load the body with magic. Each dose imposes **magic toxicity**, read from `Consumable Saturation` by the Item's Tier:

1. Take the **Base** and the **Minimum** for that Tier.
2. If the Creature affected is of a lower Tier than the Item, multiply both by the **Lower Tier Multiplier**.
3. The toxicity is the Base, less any reduction one of your Abilities gives, but never less than the Minimum.

The **Conditions** chapter says what magic toxicity does. One consequence belongs here: a helpful dose is blocked once your magic toxicity is above your Toxicity Threshold. The dose is used up and neither healing nor Mana comes of it — though a Ward's Temporary Hit Points still take hold. A harmful dose is never blocked.

Three other things share the shelf:

- **Alchemical items** — Alchemist's fire and Acid jars, in the `Consumables` table — need no magical knowledge to use.
- A **Poison Vial** holds doses of one poison, a poison Affliction from **Conditions**; its Quantity is the doses left.
- A **Ritual book** holds the rituals inscribed in it (see **Magic and Abilities**).

## Tattoos and unique items

@player
The `Tattoos` table lists each Tattoo by the place it occupies and the Abilities it grants. A Tattoo can fix the level at which a granted Ability works, so that it never grows with its bearer.

`Unique Items` are one of a kind. They have no price and are never for sale — the DM places them in the world — and each grants an Ability, a spell or an effect of its own while it is worn.

## What things cost

@player
An Item's **Unit Price** — the price of one — depends on what it is:

| Item | Unit Price |
|---|---|
| Weapon, armor or other gear | Base Price + Tier Surcharge + the cost of each Property |
| Attribute or save Item | Tier Surcharge + Bonus Surcharge (there is no Base Price) |
| Ammunition, each | Base Price ÷ bundle size, plus (Tier Surcharge + Property costs) ÷ {{Magical Ammunition Divisor}} |
| Any other consumable | Base Price + (Tier Surcharge + Property costs) ÷ {{Consumable Surcharge Divisor}} |
| Coin or gem | Its value in Gold |

- The **Tier Surcharge** is the entry for the Item's Tier in `Default Tier Surcharge`; Tier 0 has none.
- The **Bonus Surcharge** is the entry for the size of the Guidance Bonus in `Default Bonus Surcharge`.
- An Item anyone can use without magical knowledge — a potion, oil, scroll or alchemical item — has its price multiplied by {{Innately Usable Price Multiplier}}.
- A Scroll costs half what a Potion or Oil of the same spell and Tier costs.
- A Tier 0 spell Item would carry no surcharge at all, so it costs half the Tier 1 price instead — Tier 0 counting as 0.5, as everywhere else.

### Worked example — pricing a potion

@player
A Tier 2 Potion of Heal is a consumable with no Base Price and no Properties.

- Start from the Tier 2 entry of `Default Tier Surcharge`.
- Divide it by {{Consumable Surcharge Divisor}}, because the potion is a consumable.
- Multiply by {{Innately Usable Price Multiplier}}, because anyone can drink it.

The Scroll of the same spell and Tier costs half as much.

## For the DM — shops

@player
A **Specific Shop** is a named place whose stock and gold persist. Trade changes them, and they stay changed until you **refresh** the shop:

1. For every line of stock, coins included, flip a coin. One face and the line is gone; the other and it stays, its Quantity re-rolled to a random number from 1 up to what it had.
2. Roll the shop's Loot Table and add the result to what is left.

A **Generic Shop** — an alchemist, a smith — has no stock until the party walks in. Its stock list is then read against the size of the settlement:

- Each entry has a minimum population; a smaller place does not carry it.
- The Quantity carried is a base amount plus a further amount per thousand inhabitants.
- The shop's gold, for buying from the party, is a base amount plus an amount that grows with the square root of the population.

That stock stands for the rest of the game day. Either kind of shop buys only what its gold can cover.

## For the DM — loot tables

@player
A **Loot Table** is a list of rows, read top to bottom, that says what a creature carries, a chest holds or a shop stocks. Each row is one of four kinds:

| Row | What you do |
|---|---|
| **Guaranteed** | The Item, or Items, are always there. |
| **Independent Chance** | Roll against the row's chance. On a success the Items are there. |
| **Weighted Choice** | Roll once and take one option from the row's list. |
| **Gated Weighted Choice** | Roll against the row's chance, and only on a success make a Weighted Choice. |

To roll a chance with real dice, read it as a percentage and roll percentile dice — two d{{Die Size}}s, one for tens and one for ones, a double zero counting as 100. A roll at or under the chance succeeds. For a Weighted Choice, roll once and walk down the options adding up their chances: the first option whose running total reaches your roll is the one you get, and a roll above the total means nothing drops.

A row can remember its result under a name, and a later row can demand a particular result before it is rolled at all — that is how a table gives arrows only to the goblin that rolled a bow. A Quantity may be a dice expression in the usual notation (how many dice, of what size, plus or minus a fixed number). A row marked as equipped is gear the creature is using, not merely carrying. An option may point to another list of options, which you then roll on in turn, and a row may call for a random magical Item instead of naming one.

## For the DM — random magical items

@player
A row that calls for a magical Item gives a recipe: the kind of gear (melee weapon, ranged weapon, ammunition, any armor, or body armor only), the Tiers allowed, and a weighted list of Properties. Build the Item in order:

1. **Tier.** Choose among the allowed Tiers — by their weights if the recipe gives any, evenly if not.
2. **Item.** Choose a piece of gear of the right kind the same way.
3. **Property.** Strike every Property whose minimum Tier is above the Tier you rolled, or that cannot go on this kind of gear, and choose from the rest by weight. The entry "none" is always allowed and gives an Item with a Tier but no Property; if nothing else survives, the result is "none".
4. **Kind.** If the Property comes in several kinds, as Elemental does, choose one evenly.

A generated Item never has more than one Property. To choose by weight, add the weights up, roll a random number from 1 to the total, and count down the list.

## For the DM — loot after a fight

@player
When a fight ends, everything carried by the creatures that were not on the party's side — coins included — goes into one **Ground Pile** where the fight took place, together with whatever each creature's Loot Table adds. The party's allies keep what is theirs.

Then divide the pile: each line goes to a character, to the Party's stash, or stays where it is. An emptied pile is gone; one the party walks away from lies there until you clear it.

For a record of the haul, open a **Loot Archive** entry for the pile: a list of everything found, each Item with a space for who claimed it. Claiming an Item moves it from the pile to the claimant, and an Item can be claimed only once. Closing the entry clears whatever is still on the pile; the record stays.

## What lives in the next chapter

@player
Gear is only numbers until someone swings it. **Combat** is next: Initiative and turns, the Combat Pool that pays for every attack and defense, how an attack Roll meets a Parry, Block or Dodge, and how the Threshold, Bleed, Damage Reduction and Damage Resilience from this chapter turn a hit into wounds.

## Common types

### Item Stack

| Field | Type | Default | Description |
|---|---|---|---|
| `item_type` | string | required | Catalog name. Free-form; not validated against the catalog at write time. |
| `quantity` | number | 1 | Per the *Quantity* glossary entry. May be fractional only for Currency Item Types. Non-negative. |
| `tier` | integer | 0 | Magical infusion level. |
| `properties` | list of Property Application | `[]` | Ordered. Each entry is `{name: string, subtype: string or null, cost: number or null}` — `cost` mirrors the catalog cost at attach time so a later catalog edit does not retroactively reprice stored Stacks. |
| `inscribed_spells` | list of string | `[]` | Spell names written into the item. Empty for items without `inscribable: true`. |
| `stored_spell` | string or null | null | Single-slot spell storage. |
| `durability_damage` | integer | 0 | Stored only. |
| `name_override` | string or null | null | Replaces the Generated Display Name when set. |
| `equipped` | boolean | false | Equipped status. Identity field. |
| `value_in_gold` | number or null | null | Per-Stack Gold value. Required for Gem and Currency Stacks; null for everything else. Identity field for Gems. |
| `gem_name` | string or null | null | Optional Gem name (e.g. `"ruby"`). Identity field for Gems. |
| `guidance_bonus` | integer or null | null | Per-Stack Guidance Bonus. Required when the Item Type lists `guidance_bonus`. Identity field for guidance Items. |
| `restock_target` | integer or null | null | When non-null, the Quantity the Restock Operation brings the Stack to. |

### Item Type catalog entry

An Item Type lives in `equipment_config.yaml` under one of the catalog blocks (`Weapons`, `Armor`, `Items`, `Consumables`, `Books`, `Misc Items`, `Tattoos`, `Currency`, `Ammunition`). Beyond the per-category fields documented in the config file's comments, two cross-category fields are standardized:

| Field | Type | When used | Description |
|---|---|---|---|
| `spell` | string or null | Items whose magical effect derives from a known spell — chiefly Potions / Oils / Scrolls / Wands (where the spell is invoked at *Consume Item* or, for Wands, granted while equipped) and guidance Items like Cloak of Resistance (where the connection is documentary, naming the spell whose effect the item embodies). Identifies the spell by its catalog name from `abilities/spells.yaml`. For tier-array items the same `spell` covers every tier, with the spell's own tier resolution producing the variant name. |
| `grants` | list | Tattoos, Unique Items, and any Item Type conferring Abilities while borne. Each entry is either a plain Ability catalog name (from `abilities/`), or a mapping `{ ability:, class_level: }` that pins the Class Level the Ability is granted at (e.g. the Tattoo of the Viper grants `Sneak Attack` at `class_level: 1`, so its bonus never scales with the wearer). Granted while the Item is equipped; for Tattoos — always equipped — the grant is permanent. |
| `no_store` | bool | Unique Items. When true the Item Type is excluded from Store provisioning (the DM places it; it is never bought or sold). Such items typically also omit `base_price` (no gold value). |
| `description` | string | Generic catalog items. Authoritative single source of truth for the Item Type's description. Inventory Stacks must not carry a `description` override unless the Stack is a unique item whose flavor isn't captured by Type + Properties (e.g. a named magic Lute). |

### Property Application

Carried on every Property entry of a Stack:

| Field | Type | Description |
|---|---|---|
| `name` | string | The Property's catalog key. |
| `subtype` | string or null | Required iff the catalog entry has `has_subtype: true`. |
| `cost` | number | Gold cost copied from the catalog at attach time; used by Unit Price math. |

### Owner ID

A string with a kind prefix plus an identifier. Format by Owner kind:

| Kind | Form |
|---|---|
| Creature | `creature:<creature_id>` — the Creature ID owned by Creatures, never the display name. |
| Party | `party` — reserved single-instance string, no body. |
| Ground Pile | `ground:<location>` — `<location>` is a free-form string chosen by the caller. |
| Specific Shop | `shop:<shop_id>` |
| Generic Shop | `generic_shop:<shop_id>` |

Equipment never validates the body of the prefix — `creature:99999` is syntactically valid even if no such Creature exists. The prefix governs which loader services the Owner.

### Owner Record

| Field | Type | Description |
|---|---|---|
| `owner_id` | string | Per *Owner ID* above. |
| `source_file` | string | Path of the YAML file the Owner was loaded from. Mutations are written back to the same file. Runtime-created Owners default to the base file for their kind. |
| `inventory` | list of Item Stack | Append order preserved across mutations. |

Creature Owners are not stored in Equipment's own files — the `inventory` is read through the Creature accessor. The Owner Record for a Creature Owner is materialized on demand from the accessor's response; `source_file` is the Creatures-owned file path the accessor reports.

### Creature accessor

The interface a caller (typically Creatures) supplies so Equipment can read and write per-Creature Inventories:

| Method | Returns | Description |
|---|---|---|
| `get_inventory(creature_id)` | list of Item Stack | The Creature's Stacks. Empty list when the Creature has no Inventory yet. |
| `set_inventory(creature_id, stacks)` | nothing | Replaces the Creature's Inventory with the supplied list. Equipment always passes a fully reconciled list — partial updates are not part of the contract. |
| `source_file_for(creature_id)` | string | The YAML file Equipment should report as `source_file` for this Creature Owner. |

Equipment never mutates the accessor and never caches values across calls.

### Magical Item Constraint

The dict passed to *Generate Magical Item* and embedded in Inline Magical Rows:

| Field | Type | Default | Description |
|---|---|---|---|
| `category` | one of `melee`, `ranged`, `ammo`, `all_armor`, `all_body` | required | Restricts eligible Item Types and Properties. |
| `tier` | list of integer | required | Allowed Tiers. |
| `tier_weights` | map of integer → number | uniform | Optional per-Tier weight. |
| `properties_weighted` | map of name → number | required | Property→weight. The reserved name `none` yields a tiered but propertyless item. |
| `items_weighted` | map of Item Type → number | uniform | Optional per-Item-Type weight inside the chosen Category. |

### Loot Roll Row

| Field | Type | Default | Description |
|---|---|---|---|
| `chance` | number ∈ [0, 1] | absent on Guaranteed rows | Bernoulli probability for Independent Chance and Gated Weighted Choice. |
| `item` | dict or null | null | Single payload. Mutually exclusive with `items`. |
| `items` | list of dict | null | Multi payload. |
| `options` | list of Option Entry, or named Option List | null | Weighted Choice list. |
| `equipped` | boolean | false | Row-level flag applied to every produced Stack. |
| `as` | string | absent | Roll Variable name to publish. |
| `key` | string | absent | Value to publish under `as`. |
| `when` | map of name → value | empty | AND-ed gating; row is skipped when any pair mismatches. |

## Public entry points

### Get Inventory

Input: `owner_id`.

Returns: the Owner Record's `inventory`, with positions preserved.

Looks up the Owner Record by Owner ID. For Creature Owners, delegates to the Creature accessor; for all other Owners, reads from the loaded Inventory File Set.

### Add Item

Inputs: `owner_id`, an Item Stack.

Behavior: Append the Stack to the Owner's Inventory if no existing Stack matches by Stack Identity. Otherwise *Stack Merge* into the matching Stack in place. Persist to the Owner's `source_file`.

Returns: the resulting Stack (post-merge or freshly appended).

### Remove Item

Inputs: `owner_id`, a Stack reference (either index into the Owner's Inventory or a full Stack Identity), `quantity` (number, optional; default = all).

Behavior: Decrement the matching Stack's Quantity by `quantity`. The Stack itself is not deleted — see *Cleanup*. Refuses negative `quantity` and amounts that would drop Quantity below 0 (returns an error sentinel; no persistence).

Returns: the remaining Quantity, or an error sentinel.

### Adjust Stack Quantity

Inputs: `owner_id`, Stack reference, `new_quantity` (number, ≥ 0).

Behavior: Set the matching Stack's Quantity to `new_quantity` exactly. Bypasses the per-unit decrement of *Remove Item*. Persist.

Returns: the new Quantity.

### Transfer Stack

Inputs: `from_owner_id`, `to_owner_id`, Stack reference, `quantity` (number, optional; default = full Stack).

Behavior: *Remove Item* on the source Owner, *Add Item* on the destination Owner with a Stack copy carrying the transferred Quantity and every identity field intact. Atomic: if either half fails, neither half persists.

Returns: the resulting destination Stack.

### Cleanup

Input: `owner_id`.

Behavior: Remove every zero-Quantity Stack from the Owner that does not carry a Restock Target. Persist.

Delayed cleanup lets "spend last copper, immediately gain one" stay on the same Stack across a sequence of *Remove Item* / *Add Item* calls. Callers invoke *Cleanup* when they want the Inventory tidy — typical times are end-of-turn, end-of-Combat loot transfer, and after a Restock Operation.

### Equip Stack / Unequip Stack

Inputs: `owner_id`, Stack reference.

Behavior: Flip the Stack's `equipped` flag. Because `equipped` is part of Stack Identity, this may split the Stack (equipped copy peels off as a new Stack of Quantity 1; the remainder keeps the original index). After the flip, call *Reconcile Loadout* for the Owner.

Returns: the resulting equipped (or unequipped) Stack.

### Reconcile Loadout

Input: `owner_id`.

Behavior:
1. Call Conditions' *Remove Effects by Prefix* with `equipment:<owner_id>:`.
2. For each equipped Stack in the Owner's Inventory, apply every Active Effect the Stack should post. Each Active Effect's `source_id` is `equipment:<owner_id>:<stable_stack_key>` (with a Property index suffix when the Stack posts more than one Effect — `:0`, `:1`, …).

Effects are derived from:
- The Item Type's declared Guidance Bonus, if any (Bonus Type `Guidance`, Target Key `guidance_attribute`, Amount `guidance_bonus`). For weapons, a `+N` enhancement contributes `+N Guidance` to both the attack Roll and the damage Roll — the dual application is handled by Combat at resolution time using the same Guidance entry; Equipment posts one Active Effect that Combat reads in both pipelines.
- Each Property's declared static effects (see *Property Effects* in Operations).

The mundane portion of an Item (the base armor's damage reduction, etc.) is conventionally a `Circumstance` Bonus on top of which the magical enhancement layers as `Guidance`. See the Bonus Types List in `abilities/abilities_config.yaml` for the canonical list and the per-Type descriptions.

Returns: the list of `source_id`s posted, in order.

Reconcile Loadout is idempotent. Callers invoke it after every Equip / Unequip / Add Item / Remove Item that touches equipped Stacks; the cost is one Conditions sweep plus one *Apply Effect* per equipped Stack-Effect pair.

### Get Item Details

Input: a Stack (or `owner_id` plus Stack reference).

Returns a dict with: `category`, `item_type`, `definition` (the catalog block), `tier`, `properties` (list of Property Application), `equipped`, `durability_damage`, `display_name` (the Generated Display Name or `name_override`), `unit_price` (per Unit Price formula), `slot` (when applicable), `value_in_gold` (Currency / Gem), `guidance_attribute` and `guidance_bonus` (guidance Items), `inscribed_spells`, `stored_spell`, `innately_usable`.

### Get Weapon Details

Input: a Stack with `category == Weapon`.

Returns *Get Item Details* extended with: `damage_formula` (per-weapon override → first Tag with `damage_formula` → Category default), `damage_types` (list), `bleed` (max over the Damage Types' defaults, or per-weapon override), `threshold` (min over the Damage Types' defaults, or per-weapon override, plus the sum of every equipped Property's `weapon_modifiers.threshold_delta`; `null` when explicitly null on the Weapon), `tags` (list), `ammo_type` (string or null), `affliction` (the key of a Conditions Affliction the weapon injects on a hit — e.g. a spider's `spider_venom` Bite — or `null`; Combat offers a Poison input alongside Damage / Bleed when present), `damage_riders` (the resolved `damage_rider` of every magical Property on the Stack — sentinel Damage Types `from_subtype` / `from_weapon` already resolved to a concrete type — for Combat to roll at attack time), `tier_advantage` (summed `tier_advantage.amount` across the Stack's Properties — the Glory Tier bump; 0 for a mundane weapon).

A Weapon's `base_damage` is its **damage field** — the amount the weapon adds to an attack; `base_damage: 0` (e.g. the Bola) means the Weapon contributes no extra damage, not that the attack deals nothing. Two further per-weapon catalog fields are **declarative** (surfaced for Combat but not yet acted on): `range_feet` (a thrown Weapon's range in feet) and `on_hit_save` (a `{ attribute, fail, success }` save the target makes when hit — the Bola's Dexterity-save-or-`prone`).

### Get Armor Details

Input: a Stack with `category == Armor`.

Returns *Get Item Details* extended with: `damage_reduction`, `material`, `base_hardness`, `effective_hardness` (`base + 2 × tier`), `hit_points_formula`, `thickness`, `resilience_increment`, `resilience` (`tier × increment`; 0 for Shields and Armor with null increment), `is_metal_armor` (the catalog entry's `metal` flag; default false).

### Is Item-Only?

Input: a spell name (string).

Returns: boolean. Delegates to the Abilities catalog. Exposed by Equipment so UI surfaces can suppress non-item invocation paths without a direct dependency on Abilities.

### Item Forms (Scroll / Potion / Oil / Wand)

A spell may be packaged into a consumable or held item. Which forms a spell
permits is declared on the spell itself, by the `items:` list in
`abilities/spells.yaml`:

- **Scroll** — every spell can be made into a Scroll, regardless of `items:`.
  Consuming a Scroll casts its spell once and destroys the Scroll.
- **Wand** — every spell can be made into a Wand. While a Wand is equipped it
  adds its `spell` to the wielder's castable list (the wielder casts it as if
  they knew it, channelling their own Mana); unequipping the Wand removes the
  spell. A Wand is not consumed by casting and imposes no Magic Toxicity.
- **Potion** — permitted only when the spell's `items:` list contains `potion`.
  Anyone may drink a Potion to cast its spell on **themselves** (the drinker is
  the target).
- **Oil** — permitted only when the spell's `items:` list contains `oil`. An Oil
  is either **thrown** to cast its spell at a target at range, or **applied** to
  an adjacent target.

`items:` therefore restricts only the Potion and Oil forms; Scroll and Wand are
universal. For example `Heal` and `Ward` carry `items: [potion, oil]` (both
forms), `Grease` carries `items: [oil]` (Oil only), and a spell with no `items:`
list can still be a Scroll or Wand but never a Potion or Oil.

**Casting skill.** When a spell is cast from an item — drinking a Potion,
throwing/applying an Oil, reading a Scroll, or casting through a Wand — the
casting check uses the skill defined on the spell (or evocation): the spell's
`skills:` list in `abilities/spells.yaml`. The consumer need not be a caster;
the item supplies the spell and the spell supplies the skill.

**Autogeneration.** These forms are not enumerated in `equipment_config.yaml`.
The Catalog generates them from the Abilities Spell catalog at load: for each
Spell it synthesizes the Item Types named `Scroll of <Spell>`, `Wand of
<Spell>`, and — gated by the Spell's `items:` — `Potion of <Spell>` /
`Oil of <Spell>`, each keyed by the Spell's base name and carrying that Spell's
`spell` and `tier`. Scroll / Potion / Oil are `Consumable` and `innately_usable`
(anyone may use them); a Wand is a held `Item` (`slot: hands`) flagged
`grants_spell`. A handwritten catalog entry of the same name always wins over
the generated one. (Generated forms currently price through the standard Unit
Price formula from their Tier; a per-form price model is not yet defined.)

### Poison Vials

A Poison Vial (Category `Consumable`) holds doses of one specific poison, bound
through a `poison` field — a Conditions Affliction of category `poison` (e.g.
`spider_venom`) from `conditions/conditions_afflictions.yaml`. The number of
doses a Vial holds is its Stack `quantity`.

Like the Spell-Form Items, Poison Vials are **autogenerated**: the Catalog
synthesizes one `Vial of <Poison>` per poison-category Affliction in the
Conditions catalog (the display name title-cases the Affliction key, so
`spider_venom` → `Vial of Spider Venom`). A project may still author an explicit
entry under a `Poison Vials:` block to override a generated one. This is
**structure only**: applying a dose (coating a Weapon, or throwing / applying
the vial to a target) is not yet wired into Combat, and a Poison Vial carries no
`spell`, so *Consume Item* does not act on it.

### Consume Item

Inputs: `owner_id`, Stack reference, `target_creature_id`, `toxicity_threshold` (integer), optional `saturation_reducer` (integer, default 0).

Behavior:
1. Look up the spell carried by the Stack via Abilities (`stored_spell` for Spell Storing items, `spell` field on the catalog Item Type for Potion / Oil / Scroll, etc.).
2. Resolve the spell's Effects at the Stack's Tier.
3. For each Effect:
   - `minor_damage` / `moderate_damage` / `major_damage` — route through Combat's Severity Calculation if the Effect is an attack, otherwise call Conditions' *Apply Heal* (worst-first cascade keyed by the Severity).
   - `mana` — call the Creatures domain to restore the supplied amount of Mana.
   - `temp_hp` — call Conditions' Temporary HP grant.
   - explicit Damage Effects — route through Combat's *Apply Damage*.
4. Impose Magic Toxicity per Item-form rules (see *Item-Form Toxicity* in Operations). Scrolls and Wands skip this step.
5. Decrement Quantity by one when the Item Type's Category is `Consumable`.
6. Call *Cleanup* on the Owner.

Returns: a result struct with the resolved spell name, the per-Effect outcomes, and the Toxicity Cost imposed (0 for Scrolls and Wands).

The *Saturation Gate* applies before steps 3 and 4: when the caller-supplied `toxicity_threshold` is non-null and the target's Magic Toxicity (read through Conditions) is at or above it, Cure and Mana Effects are skipped; Ward Effects (Temporary HP) are applied regardless. Equipment does not compute the Threshold — the caller passes it in.

### Get Total Wealth

Input: `owner_id`.

Returns: number. Sum of `quantity × value_in_gold` across every Currency and Gem Stack in the Owner's Inventory.

### Debit Wealth

Inputs: `owner_id`, `amount` (number, ≥ 0).

Behavior:
1. If `amount > Total Wealth`, return an error sentinel without modifying state.
2. Sort Currency Stacks ascending by `value_in_gold`. Spend Quantity from the cheapest first until `amount` is consumed; any partial consumption decrements the Stack's Quantity. The "cheapest first" rule means Copper drains before Silver before Gold, so the densest denominations remain available longest.
3. If `amount` still positive after Currencies are exhausted, sort Gem Stacks ascending by `value_in_gold` and consume Gems whole, cheapest first. Each consumed Gem may overpay; the overpayment accumulates.
4. After Gems are exhausted, refund any accumulated overpayment as a Gold Currency Stack (added via *Add Item*).
5. Persist.

Returns: the resulting Gold change refunded (number, ≥ 0).

### Roll Loot Table

Inputs: `table_id`, optional Random Seed (for deterministic testing).

Behavior:
1. Read the Loot Table by ID.
2. Iterate the table's `rolls` list in order. For each Row:
   - Evaluate `when` against the current Roll Variables; skip if any pair mismatches.
   - Resolve the Row by its shape (Guaranteed / Independent Chance / Weighted Choice / Gated Weighted Choice).
   - If the Row publishes via `as`, store the resulting `key:` in Roll Variables. A skipped Row does not publish.
3. Collect every produced Item Stack in order.

Returns: the list of produced Item Stacks. Persistence is the caller's responsibility — *Roll Loot Table* does not place the Stacks anywhere.

### Generate Magical Item

Input: a Magical Item Constraint.

Behavior:
1. Pick a Tier from `tier` weighted by `tier_weights` (uniform default).
2. Pick an Item Type from the catalog matching `category`, weighted by `items_weighted` (uniform default).
3. Pick a Property from `properties_weighted` filtered by `min_tier ≤ picked_tier` AND `applies_to includes category`. The reserved name `none` always passes the filter and yields a propertyless item.
4. If the Property has `has_subtype: true`, pick a Subtype uniformly from the Property's `subtypes`.
5. Build the Stack: Quantity 1, Tier as picked, Properties = `[picked]` (or empty if `none`), `equipped` per the constraint (default false).

Returns: the generated Item Stack.

### Collect Combat Loot

Inputs: a list of Combat Loot Entries — `{combatant_id, creature_id, ally}` — plus a `location` (the Ground Pile location to gather into).

Behavior:
1. For each entry with `ally: false`:
   a. Read the Combatant's Inventory via *Get Inventory* against `creature:<creature_id>`.
   b. If the Creature Reference declares a `loot_table`, *Roll Loot Table* against it and collect the resulting Stacks.
   c. Move every Stack from the Combatant's Inventory plus the rolled Stacks into a Ground Pile Owner with `owner_id = "ground:<location>"`. Stack Identity governs merging on the destination side. Currency Stacks are moved too.
   d. Empty the source Inventory of every moved Stack (via *Remove Item*).
2. Persist the Ground Pile to `loot.yaml`.
3. Entries with `ally: true` are skipped entirely — no Inventory read, no Loot Table roll.

Returns: the Ground Pile Owner ID. When no non-ally entries exist, no Ground Pile is created and the result is `null`.

The `location` is supplied by the caller — Crimson Steel's Encounter passes the active Map (`map_<map_id>`), so loot the party leaves behind when it moves to a new Map is no longer surfaced (the next Map has its own pile).

### Drop Stack

Inputs: `owner_id`, Stack reference, `location` (string), `quantity` (number, optional; default = full Stack).

Behavior: *Transfer Stack* the Quantity into the Ground Pile Owner `ground:<location>`. Creates the Ground Pile if missing.

Returns: the destination Stack.

### Distribute Loot Pile

Inputs: `pile_owner_id` (a Ground Pile), `assignments` (a list of `{stack_ref, target_owner_id}` — `target_owner_id` is `null` for "leave on pile", `"party"` for the General Sell Pile, `"character:<id>"` for a specific PC, or `"skip"` to mark the Stack as ignored and leave it on the pile).

Behavior:
1. For each assignment, look up the Stack on the source pile by `stack_ref` (index or identity match).
2. Resolve the target:
   - `"party"` → *Transfer Stack* into the Party Owner.
   - `"character:<id>"` → *Transfer Stack* into that Owner's Inventory.
   - `"skip"` / `null` → leave the Stack on the pile (no transfer).
3. After all transfers, if the pile is empty, call *Cleanup* to remove the Ground Pile Owner entirely.

Returns: a list of the resulting destination Stacks (one entry per non-skipped assignment, `null` for skipped ones).

The pile is also removed explicitly when the DM "deletes" it from the post-combat loot stub — *Distribute Loot Pile* called with every Stack assigned to `"skip"` will leave the pile in place; an explicit *Cleanup* call (or a single `{stack_ref: "*", target_owner_id: "delete_pile"}` sentinel — implementation choice) discards the pile and its remaining contents.

### Open Loot Archive

Inputs: `ground_id` (an existing Ground Pile Owner ID), optional `label`, optional `notes_ref`.

Behavior: Create an Archive Entry. Snapshot the Ground Pile's Inventory; each item record carries the original Stack and `claimed_by: null`. The Ground Pile remains in place; the Archive Entry coexists.

Returns: the Archive Entry ID.

### Claim From Loot Archive

Inputs: `archive_id`, item record reference (index or matching identity), `claimer_owner_id`.

Behavior: Atomically — set the item record's `claimed_by` to `claimer_owner_id` AND *Transfer Stack* the matching Stack from the Ground Pile into the claimer's Inventory. Refuses claims when `claimed_by` is already non-null.

Returns: the resulting destination Stack.

### Close Loot Archive

Input: `archive_id`.

Behavior: Mark the Archive Entry `closed: true` and remove the corresponding Ground Pile from `loot.yaml`. Archive Entry persists.

Returns: nothing.

### Restock

Inputs: `owner_id`.

Behavior: Compute the Restock Cost across understocked Stacks. If `Total Wealth < Restock Cost`, return an error sentinel without modifying state. Otherwise, *Debit Wealth* the Restock Cost and increment every understocked Stack's Quantity to its Restock Target. Atomic.

Returns: the Restock Cost paid, or an error sentinel.

### Refresh Specific Shop

Input: `shop_id`.

Behavior:
1. For each Stack in the Shop's Inventory: roll a d2. On 1, remove the Stack entirely. On 2, set its Quantity to a uniform random integer in `[1, current Quantity]`. Currency Stacks are treated the same way.
2. *Roll Loot Table* against the Shop's `shop_template`.
3. *Add Item* each rolled Stack into the Shop (Stack Identity governs merging).
4. *Cleanup* the Shop.

Returns: the resulting Inventory.

### Visit Generic Shop

Inputs: `shop_id`, `population`.

Behavior:
1. Look up the Active Generic Shop for `shop_id` and the current Game Day. If one exists, return it (the first visit's `population` stands for the rest of the day).
2. Otherwise, materialize fresh stock from the Generic Shop's population-scaled stocking rules (see *Generic Shop stocking*) and persist it as an Active Generic Shop with `generated_at_day = current_day`.

Returns: the Active Generic Shop Owner ID.

### Generic Shop stocking

A Generic Shop in `shops.yaml` is **not** backed by a Loot Table. It declares a `name`, a purchasing-budget formula (`base_gold`, `gold_per_sqrt_pop`), and a `stock` list. Each stock entry carries `item`, `min_pop`, `qty_base`, `qty_per_kpop`, and an optional `tier` (selecting the variant for tier-array Item Types). Given a `population`:

- **Budget** — the Shop's purchasing Gold, materialized as a Gold Stack in its Inventory:
  `base_gold + floor(gold_per_sqrt_pop * sqrt(population))`.
- **Per-item Quantity** — an entry is stocked only when `population >= min_pop`; its Quantity is
  `qty_base + floor(qty_per_kpop * population / 1000)`.

Population is the load-bearing variable: larger settlements stock deeper and carry more buying Gold. The result is a fully materialized Inventory (Gold Stack first, then one Stack per stockable entry).

### Advance Time

Input: none.

Behavior: Increment `state.current_day` in `shops.yaml`. Expire every Active Generic Shop with `generated_at_day < state.current_day`. Persist.

Returns: the new Game Day.

### Add Loot Table / Remove Loot Table

Inputs: Loot Table definition (Add); Loot Table ID (Remove).

Behavior: Add appends a Loot Table to the base `loot_tables.yaml` and validates that the ID is unique across every loaded `loot_tables*.yaml`. Remove deletes the named Loot Table from the file it was loaded from. Both persist immediately.

Returns: nothing.

## Operations

### Stack Identity matching

Two Stacks match for *Stack Merge* iff **every** identity field is equal under the listed comparison:

- `item_type`, `tier`, `stored_spell`, `durability_damage`, `name_override`, `equipped`: equality.
- `properties`: list equality, order-sensitive. Two Property Applications match when `name`, `subtype`, and `cost` are all equal.
- `inscribed_spells`: list equality, order-sensitive.
- `value_in_gold`, `gem_name`: equality, only when `item_type` is `Gem`. Ignored on non-Gem Stacks (always equal across non-Gem Stacks).
- `guidance_bonus`: equality, only when the Item Type lists `guidance_bonus`. Ignored otherwise.
- `restock_target`: NOT part of identity. A `restock_target` conflict is resolved by keeping the earlier Stack's value and logging a warning.

### Unit Price formula by Category

| Category | Formula |
|---|---|
| Weapon, Armor | `Base Price + Tier Surcharge[tier] + sum(Property.cost)` |
| Guidance Item | `Default Tier Surcharge[tier] + Default Bonus Surcharge[guidance_bonus]` (no Base Price; per-Item `tier_surcharge` not used for guidance Items) |
| Ammunition | `(Base Price / bundle_size) + (Tier Surcharge[tier] + sum(Property.cost)) / Magical Ammunition Divisor` |
| Non-ammo Consumable | `Base Price + (Tier Surcharge[tier] + sum(Property.cost)) / Consumable Surcharge Divisor` |
| Currency | `value_in_gold` |
| Gem | `value_in_gold` |

Tier 0 contributes 0 surcharge. Tier Surcharge is the Per-Item map when the Item Type declares one; otherwise the Default. When `innately_usable: true`, the final formula result is multiplied by *Innately Usable Price Multiplier*.

### Property Effects

A Property catalog entry may declare any combination of three effect-shape fields. Combat consumes them at the relevant moment (equip time, attack time, damage time).

**`effects:`** — Static on-equip Active Effects. Each entry uses the same fields Conditions consumes (`target_key`, `bonus_type`, `amount`, optional `ends_on_round`, optional `metadata`). At *Reconcile Loadout* time, every equipped Stack's Property effects are posted to Conditions with `source_id = equipment:<owner_id>:<stable_stack_key>:<effect_index>`. Subtyped Properties may declare per-Subtype Effects; the Subtype on the Stack picks which list is posted. Each `bonus_type` value must name an entry in the canonical Bonus Types List in `abilities/abilities_config.yaml`. Equipment does not validate the name itself — Modifiers / Conditions reject unknown names downstream.

**`damage_rider:`** — Per-hit dice the weapon adds when an attack lands. Read by Combat during attack resolution. Schema:

| Field | Type | Default | Description |
|---|---|---|---|
| `dice` | non-neg int | required | Number of extra dice rolled when the attack hits. Not rolled to determine attack success — only when the attack has already landed. |
| `on_success` | dict | required | What each rider die that comes up Success contributes. See below. |
| `on_failure` | dict | null | What each rider die that comes up Failure (value 1) does. Optional. See below. |

`on_success` dict:
- `kind`: `damage` or `named_effect`.
- For `damage`: `damage_type` is either a literal Damage Type name (`radiant`, `emotional`) or the sentinel `from_subtype` (use the Stack's Subtype as the Damage Type) or `from_weapon` (use the wielded weapon's normal Damage Type). `amount` is the damage per Success (default 1). Optional `severity` (`minor` / `moderate` / `major`) forces the Severity of the rider damage rather than deriving it from the Damage Type — Vicious uses `major` so every Success lands as Major damage.
- For `named_effect`: `name` is the Effect Name from Conditions' catalog (e.g. `shock`). `amount` is the magnitude per Success (e.g. 2).

The rider damage is applied as its **own** Severity Calculation, separate from the weapon's base damage — fire damage from a Flaming weapon buckets independently of the slashing damage the blade deals.

`on_failure` dict (optional):
- `kind`: `self_damage` is the only case in current data.
- For `self_damage`: `severity` (`minor`, `moderate`, `major`) and `amount` per rider die that came up a Failure (a `1`). Optional `minimum` adds a flat floor applied once whenever the attack hits (even with zero `1`s) — Vicious deals `minimum: 1` plus `amount: 1` per `1` rolled to the wielder.

**`weapon_modifiers:`** — Per-weapon stat adjustments the Property applies. Schema:

| Field | Type | Default | Description |
|---|---|---|---|
| `threshold_delta` | integer | 0 | Added to the weapon's Threshold (for damage-bucketing rules in Combat). |

**`tier_advantage:`** — A weapon-attack-only modifier (the Glory Property) that treats the wielder as that many Tiers higher when attacking a higher-Tier opponent, shrinking the Tier gap Combat applies before the per-step damage reduction. Single-target weapon attacks only — never a spell or area effect. Schema:

| Field | Type | Default | Description |
|---|---|---|---|
| `amount` | non-neg integer | required | Tiers added to the wielder's effective Tier for the attack's Tier-gap math. |

*Get Weapon Details* surfaces the summed `tier_advantage` across the Stack's Properties; Combat reads it at attack time (it is not posted to Conditions).

**`damage_resistance:`** — Incoming-damage filter the Property applies when the wearer is hit by damage of a matching type. Schema:

| Field | Type | Default | Description |
|---|---|---|---|
| `damage_type` | string | required | Literal Damage Type name (`fire`, `radiant`, etc.) or the sentinel `from_subtype` (use the Stack's Subtype). |
| `amount` | non-neg integer | required | Damage of the matching type to eliminate from each incoming attack, before Severity bucketing. |

Combat consults `damage_resistance` during the Severity Calculation pipeline: for each equipped Property whose `damage_type` matches the incoming attack's type, subtract `amount` from the raw damage (clamped at zero) before bucketing.

`damage_rider`, `weapon_modifiers`, and `damage_resistance` are not posted to Conditions as Active Effects — they are consumed by Combat at attack / damage time. Equipment's role is to surface them through *Get Item Details*; Combat reads the relevant Property entries when building the attacker's Roll or resolving incoming damage.

### Stable Stack Key

Computed at *Reconcile Loadout* time:

- Armor / Item: `<item_type>:<slot>` (slot resolved from the catalog `slot:`; defaults to `body` when absent).
- Weapon: `<item_type>:hand:<index>` where `index` disambiguates two-weapon configurations (0 for the first equipped copy, 1 for the second). Index is recomputed each Reconcile; callers should not depend on it across calls beyond the lifetime of one equipped state.
- Tattoo: `<item_type>:tattoo:<slot>` — the `tattoo:` infix keeps Tattoo keys in their own namespace, so a Tattoo and a worn Item may occupy the same body location without colliding.
- Ammunition / Consumable / Currency / Gem: never equipped. *Equip Stack* on these is an error.

### Tattoos

A Tattoo is permanent body art (catalog `category: Tattoo`) that confers the
Abilities in its `grants` list. Tattoos differ from worn Items in three ways:

- **Parallel slots.** A Tattoo occupies a Tattoo Slot (the `Tattoo Slots`
  namespace in `equipment_config.yaml`), not a worn-Item Slot. A `chest` Tattoo
  does not conflict with chest Armor — only with another `chest` Tattoo.
  Creatures enforces "one Tattoo per Tattoo Slot" independently of the worn-Item
  one-per-Slot rule.
- **Always equipped.** A Tattoo has no un-equipped state and carries no
  `equipped` field; it is treated as equipped at all times, so its `grants`
  Abilities are always active.
- **Permanent.** A Tattoo cannot be removed or unequipped. *Equip Stack* and
  *Unequip Stack* are errors on a Tattoo; it is conferred (and its Abilities
  granted) for as long as the Creature carries it.

### Generated Display Name

When `name_override` is null:

```
<tier_prefix> <property_prefixes...> <item_name> <property_suffixes...>
```

- `tier_prefix`: substituted from *Tier Prefix Format* with `{tier}`. Omitted for Tier 0 and for Item Types whose Category appears in *Tier Hidden For*.
- `property_prefixes` / `property_suffixes`: each Property's Display block declares a `word` and an optional `position` (`prefix` or `suffix`; default = *Default Property Position*). For subtyped Properties, the Display block is keyed by Subtype.
- Properties apply in `properties` order. Prefix Properties stack left-to-right ahead of the Item Type; Suffix Properties stack right-to-left after it.

### Item-Form Toxicity

Imposed at step 4 of *Consume Item*. Only **Potions** and **Oils** route through this step; Scrolls and Wands impose no Equipment-side saturation (Wands channel Mana from themselves; Scrolls do not load saturation at all — both are the Abilities domain's concern).

For Potions and Oils, given the item's Tier `T`, the target Creature's Tier `target_tier`, and the caller-supplied `saturation_reducer`:

1. Read `base = Consumable Saturation.Base[T]` and `minimum = Consumable Saturation.Minimum[T]`.
2. When `target_tier < T`, multiply both `base` and `minimum` by *Lower Tier Multiplier*.
3. `saturation_cost = max(base − saturation_reducer, minimum)`.

The saturation is keyed entirely off the *item's* Tier; the spell's own `effect_saturation` (if any) is not consulted at this step. The `saturation_reducer` argument exists so caller abilities (e.g. a "tolerance" trait on the consumer) can lower the imposed cost without bypassing the per-Tier floor.

Equipment calls Conditions' *Apply Magic Toxicity* with the computed `saturation_cost` and `Toxicity Source Kind = positive` for cure / buff effects and `Toxicity Source Kind = forced` for damage effects. The classification follows the spell's polarity, read from the Abilities catalog.

### Loot Roll Row resolution

For each Row shape:

- **Guaranteed**: `item` or `items` always becomes a Stack.
- **Independent Chance**: draw `u ∈ [0, 1)`; if `u < chance`, the payload becomes a Stack. Otherwise nothing.
- **Weighted Choice**: draw `u ∈ [0, 1)`; walk the options in declared order accumulating `chance` values. The first option whose cumulative sum exceeds `u` wins. If `u` exceeds the cumulative total, nothing drops — this is the "remainder when `sum(chance) < 1`" behavior.
- **Gated Weighted Choice**: roll Independent Chance against `chance`. On success, do a Weighted Choice across `options`. On failure, nothing.

Roll Variables flow:

- A Row with `as: var_name` publishes its outcome's `key:`. Weighted Choice rows publish the winning option's `key`; other shapes publish the Row's own `key`. A Row that produces no Stack publishes `null`.
- A Row with `when: {var_name: expected_value}` is evaluated *before* its own roll. If any pair mismatches (including comparing an unset variable against a non-null expected value), the Row is skipped without rolling. A skipped Row does not publish.

### Magical Item generation filter

The Property filter at step 3 of *Generate Magical Item*:

- `min_tier ≤ picked_tier`.
- `applies_to includes category` (literal containment; `melee`, `ranged`, `ammo` only match Weapon Categories; `all_armor` and `all_body` only match Armor — the latter excluding Shields).
- The reserved name `none` is always eligible and bypasses both filters.

If no Property passes the filter, *Generate Magical Item* falls back to `none` (the catalog must always permit propertyless results).

### Source-file tracking

Every Owner Record carries `source_file`. Mutations rewrite the owning file in place. Runtime-created Owners default to:

- Ground Piles → `loot.yaml`.
- Specific Shops → `shops.yaml`.
- Active Generic Shops → `shops.yaml` (under `active_generic_shops`).
- Loot Archive Entries → `notes_loot.yaml`.

Creature Owners write through the Creature accessor's `source_file_for` reply.

Multi-file overlays (`loot-arc1.yaml`, `loot-arc2.yaml`, etc.) are supported by reading every matching `loot*.yaml`. Writes go back to whichever file the Owner came from.

## Cross-domain interactions

- **Conditions.** Equipment posts Active Effects via Conditions' *Apply Effect* and clears them via *Remove Effects by Prefix*. The `equipment:` Source ID Namespace is Equipment-exclusive — no other domain writes into it. Equipment never reads Effects back; *Reconcile Loadout* is the sole reconciliation primitive.
- **Combat.** Combat calls *Collect Combat Loot* at *End Combat*. Combat reads *Get Weapon Details* during attack-resolution (damage formula, Damage Types, Bleed, Threshold) and *Get Armor Details* during Severity Calculation (Damage Reduction, Resilience, Metal Armor classification).
- **Creatures.** The Creature accessor is the sole path to Creature Inventories. Equipment never persists Creature Inventories itself. The one-Slot-one-Item rule at equip time belongs to Creatures.
- **Abilities.** Spell catalogs (Effects, Effect Saturation, polarity, `item_only`) are owned by Abilities. Equipment passes spell names through opaquely and lets Abilities raise when a name does not match.
- **Modifiers / Abilities.** Property catalog entries declare Bonus Types by name. Equipment passes them through to Conditions; the canonical list lives in `abilities/abilities_config.yaml` under `Bonus Types List`. The mundane portion of armor is conventionally `Circumstance`; magical enhancements (a +N item) are `Guidance`. Per-Property catalog entries may declare additional Bonus Types as needed.

## Responsibilities

### Owned

- Loading `equipment_config.yaml` and every `loot_tables*.yaml`, `loot.yaml`, `shops.yaml`, `notes_loot.yaml` file.
- Per-Owner Inventory state with Source File tracking.
- Stack Identity, Stack Merge, Cleanup.
- Owner ID conventions and the five Owner kinds.
- Item add / remove / adjust / transfer.
- Unit Price per Category, including Per-Item Tier Surcharge override and Innately Usable multiplier.
- Total Wealth, Debit Wealth (cheapest-first with refund).
- Loot Tables: four Row shapes, Roll Variables (`as:` / `key:` / `when:`), Option Lists, inline Magical Item generation.
- Magical Item generation including the `none` propertyless option.
- Specific Shop refresh and Generic Shop visit.
- Game Day counter and Active Generic Shop expiry.
- Atomic Restock Operation.
- Collect Combat Loot end-of-Combat hand-off and Ground Pile bookkeeping.
- Loot Archive open / claim / close.
- Detail-fetchers (*Get Item Details*, *Get Weapon Details*, *Get Armor Details*).
- Generated Display Name composition.
- Equip-time wiring via *Reconcile Loadout* into the `equipment:` Source ID Namespace.
- Item Consumption: spell lookup, Effect routing, per-form Magic Toxicity, Saturation Gate, Quantity decrement.
- Inscribed Spells: storage, add/remove on books, identity matching.
- Metal Armor classification (per-Item-Type `metal: true`; consumed by Combat via *Get Armor Details*).

### Not owned

- **One-item-per-Slot enforcement.** Creatures.
- **Damage formula evaluation.** Combat (Equipment supplies the formula string).
- **Hit Points formula evaluation for armor.** Combat (Equipment supplies the formula string).
- **Mana storage and Mana Max.** Creatures / Conditions.
- **Magic Toxicity storage.** Conditions (Equipment posts, never reads).
- **Spell mechanics (effects, saves, durations).** Abilities.
- **Encumbrance.** No current owner; `weight` is stored on Currencies but not acted on.
- **Per-name Gem pricing.** Gems carry their own `value_in_gold`.
- **Chronicle Timestamp.** Equipment's Game Day counter is independent.

### Unassigned

- **Encumbrance computation.** `weight` is stored on Currencies but the rule is not designed.
- **Validation that Loot Table `item:` references resolve to a real Item Type.** The loader does not cross-check.
- **Validation that Property references on Loot Table rows exist in the Properties catalog.**
- **Cross-config validation** (`tier_hidden_for` Categories real, Material names declared, etc.).
- **Migration if a future Property is named `none`.** The reserved key in `properties_weighted` collides.
- **Combat-driven Durability Damage.** The counter is stored; nothing currently writes it.
