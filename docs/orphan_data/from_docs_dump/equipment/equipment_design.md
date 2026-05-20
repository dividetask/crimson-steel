# Equipment — Design

Sole owner of inventory data — other modules read or mutate items only through the `Equipment` class. Also owns loot tables, magical-item generation, shops, the loot archive, and pricing math.

## Key Operations

### Stack identity and merging

Two Item Stacks merge when **every identity field matches exactly**: Item Type, Tier, Properties (in order — `[fire, keen]` ≠ `[keen, fire]`), `stored_spell`, `durability_damage`, name override, equipped status, and category-specific fields (Gem `value_in_gold` + `name`; guidance Item `guidance_bonus`).

Property *order* is part of identity even though stacking is conceptually a set operation — keeps merges predictable across loaded loot tables. **Equipped and unequipped copies don't merge** because the wearer can distinguish them.

### Stack cleanup

Quantity-0 Stacks persist until a `Cleanup` pass removes them. Delayed cleanup lets "spend last copper, immediately gain one" stay on the same Stack.

### Owner ID conventions

Owners are addressed by string keys with a kind prefix:

- `"character:<id>"` — uses the immutable Character ID (names collide and change).
- `"party"` — reserved single-instance party owner.
- `"ground:<location>"` — Ground Pile at a free-form location.
- `"shop:<id>"` — Specific Shop.
- `"generic_shop:<id>"` — Generic Shop instance.

Equipment never validates the body of the prefix — `"character:99999"` is syntactically valid even if no such Character exists.

### Source-file tracking

Owners tagged with their YAML file so writes go back to the same file. Runtime-created Owners fall through to the base file for their kind (`loot.yaml` for ground piles, `shops.yaml` for shops). Lets campaigns keep multi-file overlays (`loot-arc1.yaml`, `loot-arc2.yaml`).

### Unit Price formula by category

| Category | Formula |
|---|---|
| Weapon / Armor | `Base + Tier Surcharge + sum(Property cost)` |
| Guidance Item | `Default Tier Surcharge[Tier] + Default Bonus Surcharge[Bonus]` (no mundane base) |
| Ammunition | `(Base / bundle) + (Tier Surcharge + sum(Property cost)) / Magical Ammunition Divisor` |
| Non-ammo Consumable | `Base + (Tier Surcharge + sum(Property cost)) / Consumable Surcharge Divisor` |
| Currency | `value_in_gold` |
| Gem | The Gem's own `value_in_gold` |

Items flagged `innately_usable: true` get the result multiplied by **Innately Usable Price Multiplier** (default 2.0). The **Tier Surcharge** is the per-Item-Type override if declared, otherwise the **Default Tier Surcharge**.

### Wealth and debit ordering

`Total Wealth` sums `Quantity × value_in_gold` across Currency and Gem Stacks. `Debit Wealth`:

1. Coins cheapest-first (Copper → Silver → Gold) — heaviest denominations last longest.
2. Gems cheapest-first when coins run out; overpayment returns Gold change.
3. Exceeds Total Wealth → fails atomically.

### Loot Roll Row shapes

A Loot Table's `rolls:` list contains one of four row shapes:

- **Guaranteed** — `{item}` or `{items}`. Always drops.
- **Independent Chance** — `{chance, item|items}`. Single Bernoulli trial.
- **Weighted Choice** — `{options: [{chance, item|items}, ...]}`. Cumulative-probability sample picks **at most one**; remainder when `sum(chance) < 1` means nothing drops.
- **Gated Weighted Choice** — `{chance, options: [...]}`. Roll `chance` first; on success, do a Weighted Choice.

Each row may carry `equipped: true`, `as: <var_name>` (publish a Roll Variable), `key: <value>`, and `when: {var: expected, …}` (gate on previously-published variables).

### Roll Variables

Table-scoped: live for one `ROLL_LOOT_TABLE` call. A row publishes via `as:`; the published value is the winning option's `key:` (Weighted Choice) or the row's own `key:` (other shapes); a row that drops nothing publishes `null`.

A consumer's `when:` is AND-ed across pairs. `when:` against an unset variable compares to `null`. A skipped `when:`-gated row does not advance variables.

### Magical Item generation

`Magical Item Constraint` configures the generator: category restriction, tier list, optional tier weights, weighted property pool. The reserved key `none` in `properties_weighted` produces a tiered but propertyless result. **At most one Property per generated item.**

Property eligibility = `min_tier ≤ picked_tier` AND `applies_to includes constraint.category`. Intentionally restrictive — tier and category bound the result, then sample within.

### Specific vs Generic Shops

- **Specific Shop**: persistent inventory and gold; trades mutate state. Refresh is DM-initiated, applies a per-Stack flip-and-decay rule (50% removal, otherwise quantity uniformly scaled to `[1, current]`); then the Template rolls and merges in via Stack Identity.
- **Generic Shop**: stateless template. Visiting creates an Active Generic Shop (one per visit per Game Day); `Advance Time` cleans up entries with `generated_at_day` strictly less than the new day.

### Game Day

`Advance Time` increments the Game Day counter (persisted under `state.current_day` in `shops.yaml`) and triggers Active Generic Shop expiry. Currently the only time-driven behavior in Equipment.

### Restock as an atomic operation

`Restock Operation` is **all-or-nothing**: full Restock Cost debited and every understocked Stack brought to target, or no changes. `Restock Cost = sum over understocked Stacks of (Restock Target − Quantity) × Unit Price`; Stacks without a Restock Target contribute zero.

### Loot Archive

Persistent narrative record of who claimed what, kept in `notes-loot.yaml`:

1. **`OPEN_LOOT_ARCHIVE`** snapshots a Ground Pile into a new Archive Entry with each item's `claimed_by` set to `null`. The pile and the archive coexist.
2. **`CLAIM_FROM_LOOT_ARCHIVE`** atomically transitions one item's `claimed_by` to a specific Owner ID and transfers the Stack out of the pile.
3. **`CLOSE_LOOT_ARCHIVE`** marks the entry `closed: true` and removes the pile. Archive entry persists indefinitely.

### Detail-fetchers

- **`GET_ITEM_DETAILS`** — generic fields (category, definition, tier, properties, equipped, durability, display name, unit price, slot, value_in_gold, guidance fields). No combat values.
- **`GET_WEAPON_DETAILS`** — extends with weapon fields including the **resolved damage formula** (per-weapon override → first tag with `damage_formula` → category default), damage type list, effective Bleed and Threshold, ammo type. Combat evaluates the formula.
- **`GET_ARMOR_DETAILS`** — extends with armor fields: damage reduction, material, base hardness, **effective hardness** (`base + 2 × Tier`), HP formula, thickness, resilience increment, computed resilience (`Tier × increment`).

One call returns everything so callers don't walk property catalogs themselves.

### Generated Display Name

Without a Name Override: `<tier_prefix> <property_prefixes...> <item_name> <property_suffixes...>`. Tier prefix is omitted for Tier 0 and for categories listed in `tier_hidden_for` (e.g. Potion). Property prefix vs. suffix is per-Property in its Display block.

### Equip-time wiring to Conditions

Items granting ongoing effects (Belt of Strength, Cloak of Resistance, anything with Guidance) post effects to Conditions via an **equipment-only Source ID Namespace**:

- Equipment generates a deterministic `source_id` per equipped Stack: `equipment:<owner_id>:<stable_stack_key>` (e.g. `equipment:character:42:belt_str:body`).
- For each effect, calls `APPLY_EFFECT` (or `APPLY_NAMED_EFFECT`) with that source_id. Conditions' replacement-by-source-id makes re-applies idempotent.
- On unequip, calls `REMOVE_EFFECTS_BY_PREFIX('equipment:<owner_id>:<stable_stack_key>')`.
- For loadout swap or Character reset: `REMOVE_EFFECTS_BY_PREFIX('equipment:<owner_id>:')` then re-apply current loadout.

Equipment is the sole writer to the `equipment:*` namespace; never queries Conditions to verify state, just re-applies on every relevant change. If anything else removed an effect, the next equipment-driven re-apply restores it.

### Item consumption

Items containing a spell (potions, oils, scrolls, wands, spell-storing) invoke that spell when used:

1. Look up the spell entry through abilities at the item's tier.
2. Read the resolved Effect Hash for conventional keys: `minor_damage`/`moderate_damage`/`major_damage` → cure cascade, `mana` → mana restoration, `temp_hp` → ward, explicit damage Effects → damage routing through Combat's Severity Calculation.
3. Apply effects to target's Conditions (or mana through the character module).
4. Impose Magic Toxicity per item form:
   - **Potion / Oil**: `effect_saturation - target_tier`, floored at `effect_minimum_saturation`, plus potion overhead `floor(2 * tier_value * 2^max(item_tier - user_tier, 0))` (tier-0 = 0.5).
   - **Scroll**: same base; `improved_healing` ability reduces saturation by `2 * user_tier` for cure scrolls; no potion overhead.
   - **Wand**: deferred — wands channel mana from themselves rather than imposing per-use toxicity.
5. Decrement quantity by one for consumable forms.

**Saturation gate**: cure and mana effects refuse to land if target is at or above their Magic Toxicity cap (typically `target.cha`). Ward effects bypass. Cap is supplied as input — Equipment doesn't reach into Character.

**Item-only entries** (`item_only: true`, e.g. Dragon Breath) can only be invoked through this consumption flow; `is_item_only?` exposes the check.

## Responsibilities

### Owned

- Load `equipment_config.yaml` and loot/shop YAML files.
- Per-Owner Inventory state with Source File tracking.
- Stack Identity, Stack Merge, Cleanup.
- All four Owner kinds with Owner ID conventions.
- Item add / remove / adjust / transfer.
- Unit Price per category, including Tier Surcharge override and Innately Usable multiplier.
- Total Wealth, Debit Wealth (cheapest-first with refund).
- Loot Tables: four Roll Row shapes, Roll Variables (`as:` / `key:` / `when:`), Option Lists.
- Magical Item generation including the `none` propertyless option.
- Specific Shop refresh and Generic Shop visit.
- Game Day counter and Active Generic Shop expiry.
- Atomic Restock Operation.
- Loot Archive open / claim / close.
- Detail-fetchers (`GET_ITEM_DETAILS`, `GET_WEAPON_DETAILS`, `GET_ARMOR_DETAILS`).
- Generated Display Name composition.
- Equip-time wiring to Conditions via `equipment:*` Source ID Namespace (sole writer).
- Item consumption: spell lookup, Effect Hash routing, per-form Magic Toxicity, saturation gate, quantity decrement.

### Not owned

- One-item-per-slot enforcement (Character module).
- Damage formula evaluation (Combat).
- HP formula evaluation for armor (Combat).
- Encumbrance (no current owner).
- Attribute bonuses from worn items (Conditions stores; Equipment posts).
- Magic Toxicity tracking (Conditions).
- Per-name Gem pricing — Gems carry their own `value_in_gold`.

### Unassigned

- Encumbrance computation — `weight` exists only on Currencies today.
- Validation that loot-table `item:` references resolve to a real Item Type.
- Validation that loot-table property references exist in the catalog.
- Cross-config validation (`tier_hidden_for` categories real, Material names defined, etc.).
- Migration if a future Property is named `none` (today's reserved key in `properties_weighted`).
