# Equipment — Design

Companion to `equipment_glossary.md`. Glossary defines *what* the terms mean; this doc records the non-obvious *how* and locks down ownership.

The Equipment module is the **sole owner of inventory data**. Other modules read or mutate items only through the `Equipment` class — never by touching the YAML files directly. Equipment also owns loot tables, magical-item generation, shops (specific and generic), the loot archive, and pricing math.

## Key Operations

### Stack identity and merging

Two Item Stacks merge into one when **every identity field matches exactly**. Identity fields:

- Item Type
- Tier
- Properties (in order — `[fire, keen]` ≠ `[keen, fire]`)
- `stored_spell`
- `durability_damage`
- Name override
- Equipped status
- For Gems: `value_in_gold` and `name`
- For guidance Items: `guidance_bonus`

Property *order* is part of identity even though stacking is conceptually a set operation. This is deliberate — it keeps the merge predictable when partial matches show up across loaded loot tables and avoids implicit re-ordering at load time.

`Stack Merge` sums quantities; every identity field stays the same by definition of the match. **Equipped and unequipped copies don't merge** — the wearer can distinguish them, and grouping them would lose information.

### Stack cleanup

Stacks with quantity 0 persist until a `Cleanup` pass removes them. This delayed cleanup lets sequences like "spend last copper, immediately gain one" stay on the same stack rather than churn through entry creation and deletion.

### Owner ID conventions

Owners are addressed by string keys with a kind prefix:

- `"character:<id>"` — uses the immutable Character ID, never the display name (names collide and change).
- `"party"` — the reserved single-instance party owner.
- `"ground:<location>"` — a Ground Pile at a free-form location string.
- `"shop:<id>"` — a Specific Shop.
- `"generic_shop:<id>"` — a Generic Shop instance generated from a template.

The Equipment module never validates the body of the prefix — `"character:99999"` is a syntactically valid Owner ID even if no such Character exists.

### Source-file tracking

Every Owner is tagged with the YAML file it was loaded from so that writes go back to the same file. Owners created at runtime fall through to a base file for their kind: characters → `loot.yaml` (for ground piles), shops → `shops.yaml`. This split lets a campaign keep multi-file overlays (`loot-arc1.yaml`, `loot-arc2.yaml`, …) where each file ships independently.

### Unit Price formula by category

Each Item Category has its own formula. The rules and the rationale:

| Category | Formula | Why |
|---|---|---|
| Weapon / Armor | `Base + Tier Surcharge + sum(Property cost)` | Magical weapons price the surcharge as a flat per-tier addition on top of the mundane base. |
| Guidance Item | `Default Tier Surcharge[Tier] + Default Bonus Surcharge[Bonus]` | No mundane base exists (a Cloak of Resistance has no Tier-0 form). Both surcharges come from the global `Tier Pricing` table. |
| Ammunition | `(Base / bundle size) + (Tier Surcharge + sum(Property cost)) / Magical Ammunition Divisor` | A magical arrow's surcharge is a tiny fraction of a magical weapon's because you fire arrows in volume. The divisor (default 100) anchors the ratio. |
| Non-ammo Consumable | `Base + (Tier Surcharge + sum(Property cost)) / Consumable Surcharge Divisor` | Same idea, different divisor (default 10) — potions and oils are consumed once but priced higher per-unit than ammo. |
| Currency | `value_in_gold` | Direct. |
| Gem | The Gem's own `value_in_gold` | Per-instance value rather than per-type. |

After the per-category formula, items flagged `innately_usable: true` get the result multiplied by the **Innately Usable Price Multiplier** (default 2.0). Models the premium for items anyone can activate without magical knowledge.

The **Tier Surcharge** itself is per-Item-Type if the type declares its own `tier_surcharge` map, otherwise the **Default Tier Surcharge**. This lets exotic items follow a different magical curve without introducing a new pricing category.

### Wealth and debit ordering

`Total Wealth` sums `Quantity × value_in_gold` across every Currency Stack and every Gem Stack. `Debit Wealth` spends:

1. Coins cheapest-first (Copper → Silver → Gold). This keeps the heaviest, most generic denominations as the longest-lasting reserve.
2. Gems cheapest-first when coins run out. Overpayment from a Gem returns the difference as Gold.
3. A Debit that would exceed Total Wealth fails atomically — no partial spend.

### Loot Roll Row shapes

A Loot Table's `rolls:` list contains one of four row shapes:

- **Guaranteed** — `{item}` or `{items}`. Always drops.
- **Independent Chance** — `{chance, item|items}`. Single Bernoulli trial.
- **Weighted Choice** — `{options: [{chance, item|items}, ...]}`. Cumulative-probability sample picks **at most one** option; remainder (when `sum(chance) < 1`) means nothing drops.
- **Gated Weighted Choice** — `{chance, options: [...]}`. Roll `chance` first; on success, do a Weighted Choice; on failure, drop nothing.

Each row may also carry `equipped: true` (every produced Stack arrives equipped), `as: <var_name>` (publish a Roll Variable), `key: <value>` (named outcome for variable publishing), and `when: {var: expected, …}` (gate this row on previously-published variables).

### Roll Variables

Roll Variables are a **table-scoped** dependency mechanism — they live for the duration of one `ROLL_LOOT_TABLE` call and disappear after. A row publishes via `as:`; the published value is the `key:` of whichever option won (for Weighted Choice) or the row's own `key:` (for non-Weighted shapes). A row that drops nothing publishes `null`.

A consuming row's `when:` is AND-ed: every `(var, expected)` pair must match the current variable state. A `when:` against an unset variable is treated as comparison against `null`.

A row that's gated `when:` and skipped does **not** advance any Roll Variables — it's as if the row didn't exist on this roll. Subsequent rows still see whatever was published before.

### Magical Item generation

`Magical Item Constraint` configures the generator: a category restriction (`melee`, `ranged`, `ammo`, `all_armor`, `all_body`, …), a tier list, optional tier weights, and a weighted property pool. The reserved key `none` in `properties_weighted` lets propertyless magical items show up — when `none` wins, the generated Stack is tiered but has no Property applied. **At most one Property per generated item.**

Property eligibility is the intersection of `min_tier ≤ picked_tier` and `applies_to includes constraint.category`. Generation is intentionally restrictive — the design favors a "tier and category bound the result, then sample within" model rather than bolting on multiple properties.

### Specific vs Generic Shops

Two shop kinds, one persistence model each:

- **Specific Shop** — persistent inventory and gold. Trades mutate state. Refresh is DM-initiated and applies a per-stack flip-and-decay rule (50% removal, otherwise quantity uniformly scaled down to a value in `[1, current]`); then the shop's Template is rolled and the new stock merges in via Stack Identity.
- **Generic Shop** — stateless template. Visiting generates fresh stock (one Active Generic Shop per visit per Game Day); the Active Generic Shop persists for one Game Day and is cleaned up by `Advance Time`.

`Active Generic Shop` records carry their `generated_at_day` so `Advance Time` knows what's expired (anything strictly less than the new current day).

### Game Day

`Advance Time` increments the Game Day counter and triggers Active Generic Shop expiry. The counter persists in `shops.yaml` under `state.current_day`. Today this is the only time-driven behavior in Equipment; future modules with time-aware state may share an interface.

### Restock as an atomic operation

`Restock Operation` is **all-or-nothing**: either the full Restock Cost is debited and every understocked Stack is brought up to its target, or no changes are made. A partial restock is not exposed — callers that want gradual restocking iterate explicit `ADD_ITEM` calls.

`Restock Cost` is `sum over understocked stacks of (Restock Target − Quantity) × Unit Price`; Stacks without a Restock Target contribute zero.

### Loot Archive

The Loot Archive is a **persistent narrative record** of who claimed what, kept in `notes-loot.yaml` and consumed by the notes module. The flow:

1. **`OPEN_LOOT_ARCHIVE`** snapshots an existing Ground Pile into a new Archive Entry, with each item's `claimed_by` set to `null`. The pile stays in `loot.yaml`; both copies coexist.
2. **`CLAIM_FROM_LOOT_ARCHIVE`** transitions one item's `claimed_by` from `null` to a specific Owner ID and simultaneously transfers the matching Stack out of the Ground Pile in `loot.yaml`. The two writes happen together so the archive can't drift from the pile.
3. **`CLOSE_LOOT_ARCHIVE`** marks the entry `closed: true` and removes the Ground Pile from `loot.yaml`. The archive entry persists indefinitely.

### Detail-fetcher fan-out

Three detail-fetchers expose item information to other modules:

- **`GET_ITEM_DETAILS`** — generic fields any UI or rules system might want: category, definition, tier, properties, equipped status, durability damage, display name, unit price, slot, value_in_gold, guidance fields. Does not compute combat values.
- **`GET_WEAPON_DETAILS`** — extends `GET_ITEM_DETAILS` with weapon-specific fields, including the **resolved damage formula** (per-weapon override → first tag with `damage_formula` → category default), the damage type list, the effective Bleed and Threshold (per-weapon override → max/min over the damage types' defaults), and ammo type. The combat module evaluates the damage formula against the attacker's Strength.
- **`GET_ARMOR_DETAILS`** — extends `GET_ITEM_DETAILS` with armor-specific fields: damage reduction, material, base hardness, **effective hardness** (`base + 2 × Tier`), hit-points formula, thickness, resilience increment, and computed resilience (`Tier × increment`).

The fan-out exists so callers don't have to know how to walk the property catalogs themselves; one call returns everything.

### Generated Display Name

When no Name Override is set, the display name is `<tier_prefix> <property_prefixes...> <item_name> <property_suffixes...>`. The tier prefix is omitted for Tier 0 items and for any category listed in `tier_hidden_for` (e.g. Potion — "Tier 2 Potion of Healing" reads worse than "Potion of Greater Healing"). Property prefix vs. suffix is per-Property and lives in the Property's Display block.

## Responsibilities

### Owned by the equipment domain

- Loading `equipment_config.yaml` (item definitions, properties, materials, slots, tier pricing) and the loot/shop YAML files.
- Per-Owner Inventory state with Source File tracking.
- Stack Identity matching, Stack Merge, and Cleanup.
- All four Owner kinds (Character, Party, Ground Pile, Shop) with their Owner ID conventions.
- Item add / remove / adjust / transfer.
- Unit Price computation per category (Weapon, Armor, Ammunition, Consumable, Guidance, Currency, Gem) including Tier Surcharge override and Innately Usable multiplier.
- Total Wealth and Debit Wealth (cheapest-first coins, then gems, with overpayment refund).
- Loot Tables: loading, the four Roll Row shapes, Roll Variables (`as:` / `key:` / `when:`), Option Lists.
- Magical Item generation under a Magical Item Constraint, with the `none` weight for propertyless results.
- Specific Shop refresh (flip-and-decay + Template merge) and Generic Shop visit (Active Generic Shop creation).
- Game Day counter and Active Generic Shop expiry on `Advance Time`.
- Atomic Restock Operation (debit cost + raise quantities, or no changes).
- Loot Archive open / claim / close, kept consistent with `loot.yaml`.
- Detail-fetchers (`GET_ITEM_DETAILS`, `GET_WEAPON_DETAILS`, `GET_ARMOR_DETAILS`).
- Generated Display Name composition.

### Explicitly *not* owned here

- **One-item-per-slot enforcement.** Equipment stores the slot string; the character module enforces "you can't equip two cloaks" at equip time.
- **Damage formula evaluation.** `GET_WEAPON_DETAILS` returns the formula string; combat evaluates it against the attacker's Strength.
- **Hit-point formula evaluation for armor.** `GET_ARMOR_DETAILS` returns the formula; combat or another consumer evaluates.
- **Encumbrance.** Currencies record `weight` if the type declares it; nothing here computes total weight.
- **Attribute bonuses from worn items.** A Belt of Strength's `+2 str` is captured by the conditions module's Effect storage; equipping an item is the trigger that posts the Effect, but Equipment doesn't own that wiring.
- **Magic Toxicity from worn magic items.** Conditions module.
- **Pricing of Gems by their `name`** (e.g. ruby vs emerald). Gems carry their own `value_in_gold`; the type catalog has no per-name price table.

### Unassigned (no current owner)

- **Equip-time wiring** — when a Character equips a Belt of Strength, who posts the `+2 str` Effect to the conditions module? The equipment module owns the Equipped flag; the conditions module owns the Effect; the bridge isn't pinned to a class.
- **Encumbrance computation.** `weight` lives on Currencies; armor and weapons have no weight field today. A future encumbrance system needs both inputs and a home.
- **Validation that loot table item references resolve.** A typo in an `item:` field of a loot row produces a Stack of an unknown Item Type at roll time. Today the failure surfaces only when display or pricing tries to read the missing definition.
- **Validation that property references in loot tables exist** in the property catalog. Same shape as the item-typo issue.
- **Cross-config validation that `tier_hidden_for` categories are real categories**, that Material names referenced from Armor entries are defined under `Materials`, etc.
- **A migration story for the `none` weight in `properties_weighted`.** Today the key is reserved at runtime by the generator; if a future Property is named `none` it'll silently become the propertyless option.
