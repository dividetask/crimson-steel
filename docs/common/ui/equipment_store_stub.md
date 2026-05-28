# Equipment Store Stub

The purchase grid for a Shop. Renders one card per buyable Item; clicking Purchase debits the buyer's wealth (via Equipment's *Debit Wealth*) and adds the Item to the buyer's Inventory. Handles three families of Item: fixed Shop stock, spell Items (Potion / Oil / Scroll / Wand), and Rituals.

See `ui_conventions.md` for shared rules.

## Layout

A vertical scroll of sections:

1. **Top banner** — the buyer's Total Wealth (from Equipment's *Get Total Wealth*) and flash messages from the previous purchase (success or error).
2. **Filter sidebar** — checkboxes for Item Category and Tier. Filtering is local; the underlying Shop inventory does not refetch.
3. **Shop inventory grid** — one card per Stack in the Shop's Inventory, read via Equipment's *Get Inventory* against the Shop's Owner ID (`shop:<id>` for Specific Shops, `generic_shop:<id>` for Generic Shops — per `equipment_design.md`'s Owner ID format).
4. **Ammunition card** — a specialized card for tier-plus-Property Ammunition Stacks.
5. **Spell-Item cards** — four cards: Potion, Oil, Scroll, Wand. Each builds a spell-bearing Stack from the Abilities catalog.
6. **Rituals card** — a card for purchasing a single Ritual.

## Item card

Each card shows:

- **Name** — the Generated Display Name (via Equipment's *Get Item Details*).
- **Category line** — Item Category and any defining tags.
- **Tier badge** — when non-zero.
- **Properties** — comma-joined Property names (with Subtype where applicable).
- **Unit Price** — read from *Get Item Details*.
- **Buyer selector** — dropdown of every Creature in the roster. Defaults to the most recent buyer (persisted in `localStorage` per `ui_conventions.md`).
- **Quantity input** — defaults to 1.
- **Purchase button** — emits a `purchase` event carrying the source Owner ID (the Shop), the Stack reference, the buyer Owner ID, and the chosen Quantity. The parent page resolves through Equipment's *Debit Wealth* (against the buyer) followed by *Transfer Stack* into the buyer's Inventory.

## Ammunition card

A specialized card with two selectors:

- **Tier** dropdown — the Tiers available in the Equipment catalog for Ammunition.
- **Property** dropdown — Properties whose `applies_to` includes `ammo` and whose `min_tier ≤ chosen Tier` (per `equipment_design.md`'s Magical Item generation filter).

Plus a buyer selector, quantity input, and Purchase button. The Unit Price uses the Ammunition formula in `equipment_design.md`'s *Unit Price formula by Category*.

## Spell-Item card (Potion / Oil / Scroll / Wand)

Four cards, one per spell-bearing Item form. Each has cascading selectors:

| Item form | Cascade |
|---|---|
| Potion | Tier → Spell |
| Oil | Tier → Spell |
| Scroll | Casting Skill → Tier → Spell |
| Wand | Casting Skill → Tier → Spell |

The Spell dropdown is filtered by Equipment's *Is Item-Only?* — Item-only Spells appear only here, never as standalone Abilities. Spells are sourced from the Abilities catalog.

For Potions and Oils, the buyer-selector is expanded into a per-Creature Quantity grid: one row per Creature in the roster, each with its own Quantity input, plus a single total-cost summary at the bottom. One Submit dispatches every Creature's purchase as a batch.

For Scrolls and Wands, a single buyer selector plus Quantity input.

## Rituals card

- **Tier** — dropdown over the Tiers at which Rituals are sold.
- **Ritual** — dropdown of every Catalog Ability that is a Ritual (per the Abilities domain) at the chosen Tier. Rituals the buyer already knows render as disabled with `(already known)` suffix — the parent page reads the buyer's known Rituals via the appropriate Abilities entry point.
- **Buyer** — selector.
- **Purchase** — emits a `purchase_ritual` event. The parent page resolves it through Equipment's *Debit Wealth* and adds the Ritual to the buyer's known Rituals via the Abilities-side mutation.

## Parameters

Required:
- The Shop Owner ID — `shop:<id>` for Specific Shops, `generic_shop:<id>` for Generic Shops. For Generic Shops, the parent page calls Equipment's *Visit Generic Shop* before invoking the stub so the Active Generic Shop is materialized.
- The buyer roster — Creatures' *List Creatures*.
- The Equipment catalog — Item Types, Properties, Tier surcharges. Used by the cascading selectors and price math.
- The Abilities catalog — Spells (filtered by *Is Item-Only?* and by Casting Skill / Tier) and Rituals.
- Viewer role.

## Behavior

- Filter changes hide / show cards client-side; no event is emitted.
- Selector changes update the displayed price and Generated Display Name client-side; no event is emitted.
- Purchase events are resolved by the parent page through *Debit Wealth* + *Transfer Stack* (Items) or *Debit Wealth* + Abilities-side mutation (Rituals). On failure (insufficient wealth — *Debit Wealth* returns an error sentinel per `equipment_design.md`), the parent page surfaces an error in the top banner.

## DM-only

The store has no DM-only affordances beyond what any logged-in viewer has. Custom Item creation lives in a separate stub (`equipment_add_item_stub.md`).

## Composition

Self-contained page. Not embedded inside other stubs.

## What this stub does not do

- It does not compute Unit Price independently. *Get Item Details* is the sole source of truth.
- It does not refresh Shop stock. Specific Shop refresh and Generic Shop daily expiry are owned by Equipment (*Refresh Specific Shop*, *Visit Generic Shop*, *Advance Time*); the parent page invokes them.
- It does not validate Ritual eligibility. The parent page consults Abilities to determine which Rituals a Creature can learn.
