# Equipment Provision Stub

The provisioning surface for the Store page (`/store`). Hands gear to
Creatures: each section lists Item Types and a quantity input, and a
**Buy** button drops the chosen quantity into a client-side **Shopping
Cart**. Nothing hits the server until the cart's **Purchase** button is
pressed, at which point the whole cart is sent at once and the Items land
in each recipient's Inventory (via Equipment's *Add Item*).

**Give (DM only).** Beside each **Buy** button, the DM (and only the DM)
sees a **Give** button. Give adds the same line to the cart but marks it as
a free gift: at checkout a gifted line is handed to its recipient without
spending any gold, even when the recipient is a Player Character. The gift
flag is honored only on a DM (loopback) request — a player's line is always
charged normally.

See `ui_conventions.md` for shared rules.

The page header shows the **Store** title on the left and the shared
**Party** wallet total (`Party gold: N gp`) on the right, so the DM can see
the party's purse while provisioning.

## Charging

- A recipient that is a **Player Character** is charged for what it
  receives: its own wealth is spent first (Equipment's *Debit Wealth*),
  and the shared **Party** wallet (`party`) covers any remainder. If the
  combined PC + Party wealth can't cover the cost, that recipient is
  skipped and reported.
- A recipient that is **not** a Player Character (NPC or enemy) is
  provisioned for free — no wealth is spent.

## Viewer

DM + Player. The Recipient dropdowns list every Creature for the DM;
**enemies are hidden when a player views the page**.

## Sections

### Weapons

A **Recipient** dropdown (the Creature roster) sits under the title.
Below it, every mundane (Tier 0) Weapon is laid out in **three columns**.
Each Item shows a picture slot, its name and Unit Price, a quantity
input, and a **Buy** button. Buy places the chosen quantity into the
cart for the Creature currently selected in the dropdown.

**Natural attacks** (Bite, claws, Unarmed — Weapons flagged `natural` in
the catalog) are **never listed**. They are innate Creature abilities, not
gear that can be owned, bought, or sold.

### Armor

Identical to Weapons, over every mundane Armor Item Type (Shields are in
the Armor Category, so they appear here too).

### Alchemy

Acid jar and Alchemist's fire, laid out in the same **three-column** grid
as Weapons and Armor. A **Recipient** dropdown sits under the title as
before, but each Item card carries several quantity boxes stacked
vertically (one per line): one labelled **selected** (the dropdown
Creature — which may be an enemy) and one per **Player Character**, each
labelled with that PC's name. A single **Buy** drops the *selected* box
plus every per-PC box into the cart together. The Party is charged only
for Items that go to Player Characters; the *selected* box is free when it
targets a non-PC.

### Magical Items

The Guidance Items — Cloak of Resistance, Belt of Strength, Belt of
Dexterity, Headband of Intelligence — laid out in the same three-column
grid. Each card adds a **+N Bonus** dropdown above the recipient boxes,
listing the Bonus values the catalog defines for that Item. Selecting a
Bonus updates the card's shown price client-side. Recipients use the same
Alchemy-style model (a **selected** box plus one box per Player
Character), since a wearer is bought one at a time but may be any
Creature.

Each Item's **Tier follows its catalog `tier` array** for the chosen Bonus
(e.g. a +5 Cloak of Resistance is Tier 5; a +6 Belt of Strength is Tier
3). The client sends only the Bonus at checkout; the server re-derives the
Tier from the catalog and reprices — the client cart is never trusted for
Tier or cost. Because Guidance Bonus is a Stack-identity field, two
Bonuses of the same Item are distinct Stacks and never merge.

### Magical Weapons

A builder card for enchanted weapons: three dropdowns — **Weapon** (any
buyable Weapon, no natural attacks), **Property** (the Weapon Properties —
Elemental flattened per Subtype, Emotional, Radiant, Subdual, Vicious,
Glory) and **Tier** (1–5). One enchanted weapon is bought per **Buy**, for
the section's **Recipient** dropdown (there is no quantity box — a magic
weapon is bought one at a time). The shown price updates client-side as
`base weapon + Tier Surcharge + Property cost`. The card validates the
combination live: a Property below its `min_tier`, or one whose
`applies_to` excludes the weapon's melee/ranged category (e.g. Vicious on a
bow), shows a note and disables **Buy**.

At checkout the client sends the chosen `properties` (name + subtype) and
`tier`; the server (`StoreMagicWeapons.fields`) revalidates eligibility and
reprices from the catalog — the cart is never trusted for cost. Because
`properties` and `tier` are Stack-identity fields, different enchantments
of the same Weapon are distinct Stacks and never merge.

### Magical Armor

A builder card for enchanted armor, following the **Magical Weapons**
layout **without the Property dimension** — a magical Armor's only
enchantment is its Tier. Two dropdowns: **Armor** (any buyable Armor,
Shields included) and **Tier** (1–5). One enchanted Armor is bought per
**Buy**, for the section's **Recipient** dropdown (no quantity box). The
shown price updates client-side as `base armor + Tier Surcharge`; there is
no Property to validate, so **Buy** is always enabled.

At checkout the client sends the chosen `tier` (and no `properties`); the
server (`StoreMagicalArmor.fields`) revalidates that the Item is an Armor
and reprices from the catalog — the cart is never trusted for cost. Because
`tier` is a Stack-identity field, different Tiers of the same Armor are
distinct Stacks and never merge.

### Scrolls, Potions & Oils

A builder card for spell-form Consumables. Three dropdowns, **Form first**:
**Form** (Scroll / Potion / Oil) drives the **Spell** list — every Spell
offers a Scroll, but only Spells whose `items:` list includes `potion` / `oil`
appear when that Form is chosen — then **Tier** (the Spell's own Tiers: a
single-Tier Spell has one, a Tier-axis Spell lists each). One item is bought
per **Buy** (or **Give**), for the section's **Recipient** dropdown (no
quantity box). Because the Spell list is already filtered to the Form, every
combination is buyable (no option is disabled).

**Pricing.** A Potion or Oil costs the full Consumable price; a **Scroll is
half** that. **Tier 0** has no Tier Surcharge, so — per the project's "Tier 0
is treated as 0.5" rule — a Tier-0 Consumable costs **half the Tier-1 price**
rather than nothing. The card's shown price updates client-side from the
per-Spell/Tier/Form prices embedded on it.

At checkout the client sends the chosen `item` (`Scroll of X` / `Potion of X`
/ `Oil of X`) and `tier`; the server (`StoreSpellItems`) revalidates the form
and Tier and reprices with the same Scroll-half / Tier-0 rule, so the charge
always equals the shown price. Different Tiers (and Scroll / Potion / Oil) are
distinct Stacks and never merge.

This section shares the top row with **Weapons** and **Armor** (the three sit
side by side).

## Shopping Cart

A cart rail sits on the **right** of the page. It is shown only when it
holds at least one line, and its body can be **collapsed / expanded** from
the header. Each line reads `qty× Item → Recipient (cost)` — the cost is
`free` for non-PC recipients and `gift` for a DM give — with a remove (×) control; lines for the
same Item + Recipient merge by summing quantity. A running **Total** sums
only the paid (Player-Character) lines. **Clear** empties the cart;
**Purchase** sends it.

The cart is entirely client-side: adding, removing, collapsing, and
totalling happen in the browser with no server round-trip. Only
**Purchase** contacts the server.

## Behavior

- **Buy** is a pure client action — it never contacts the server. There
  is no confirm popup.
- **Purchase** POSTs the whole cart to `/store/checkout` as JSON
  (`{ lines: [{ item, recipient_id, quantity, guidance_bonus?, properties?,
  tier?, gift? }, …] }` — `guidance_bonus` present only on magical-item
  lines, `properties` + `tier` on magical-weapon lines, `tier` alone on
  magical-armor and scroll/potion lines, and `gift` on a DM give). The
  server recomputes every Unit Price and PC-status, re-derives a magical
  item's Tier from its catalog Bonus→Tier array, revalidates magical
  weapons / armor / scrolls / potions and reprices them (the client cart is
  never trusted for Tier or cost), honors `gift` only on a DM request (free
  even for a PC), resolves each line through *Debit Wealth* (PCs) then *Add
  Item*, and returns a JSON `{ ok, type, message }` summary the page shows
  as a flash. On success the cart is emptied.

## What this stub does not do

- It does not price Items independently — Unit Price comes from the
  Equipment catalog (*Unit Price formula by Category*).
- It does not refresh or deplete any Shop stock; provisioning adds Items
  outright rather than moving them out of a Shop Inventory.
