# Equipment Inventory Stub

The inventory-management surface shown **below the Character Sheet** on
the Creature tab (`/character-sheets`). It is keyed to the Creature
displayed above and lets any viewer move that Creature's gear around
through the Equipment domain.

See `ui_conventions.md` for shared rules.

## When it appears

Only for a **real Creature** — a Player Character, NPC, or a spawned
instance that lives in a creature data file. It is **hidden for an
`enemy_template`** stat block (templates are shared blueprints with no
inventory of their own).

## Viewer

DM + Player. Every viewer may equip, unequip, discard, and claim — there
is no per-Creature ownership restriction (a player managing the shown
Creature acts on it directly). The server still refuses to mutate a
template's inventory.

## Sections

All three sections use the same **three-column card grid** as the Store.
Each card shows the item's icon and its name, with the Quantity (when
greater than one) prefixed as `N× Name`, and the section's action
buttons at the card foot.

### Equipped

The Creature's equipped Stacks. Each card has an **Unequip** button.

### Carried

The Creature's unequipped Stacks. Each card offers:

- **Equip** — equips the Stack (peels off a single copy, per the
  Equipment domain). Shown only when the item is equippable.
- **Discard** — moves the Stack to the Sell Pile (the Party Inventory).

### Sell Pile

The shared **Party Inventory** (`party`) — every item the party holds
that is not claimed by a specific Creature. Each card offers:

- **Claim** — moves the Stack to the shown Creature.
- **Equip** — claims a single copy to the shown Creature and equips it.
  Shown only when the item is equippable.

## Equippability

Equippable Stacks are every **Weapon** and **Armor**, plus an **Item**
that declares an equipment **Slot** (e.g. Lute, the belts, Cloak of
Resistance). Slotless Items (Rations, Bedroll, Whetstone), **inscribable
books** (Ritual books — carried for their rituals, never worn), and the
non-wearable categories (Consumable, Ammunition, Currency, Gem) are
**not** equippable.

Non-equippable cards simply omit the Equip control. The server enforces
the same rule — an equip request for a slotless, book, or wrong-category
item is a no-op.

## Ritual books

An inscribable book (Ritual book) shows a **(N rituals)** link on its
card. Clicking it opens a scrollable modal (the same overlay the Chronicle
notes text uses — dismiss with Esc or a click outside) listing the
inscribed Ritual names, resolved to their Abilities catalog display names.
Every Ritual book a Creature carries contributes its inscribed Rituals to
the Creature's castable Ritual list on the Character Sheet — books are not
equipped to take effect, merely held.

The stub does **not** yet block equipping an item whose Slot is already
occupied — that one-Slot-one-Item rule is owned by Creatures and is
deferred.

## Quantity

A Stack of Quantity > 1 carries a **quantity input** on its Discard
(Carried) and Claim (Sell Pile) controls, defaulting to the full Stack
and clamped to `[1, available]`. Equip always acts on a single copy, so
it has no quantity input.

## Icons

Each card's icon comes from the **Item Icon Map**
(`docs/common/equipment/item_icons.yaml`), which maps an Item Type to a
file under `public/item_images/`. An Item Type with no map entry falls
back to the slug convention (lowercased name, non-alphanumerics collapsed
to `_`); a missing file renders an empty placeholder. The same resolution
backs the Store's item art.

## Behavior

Each action is a form POST that mutates through the Equipment domain and
redirects back to the sheet (preserving the detail mode):

| Action | Endpoint | Equipment operation |
|---|---|---|
| Equip | `POST /inventory/equip` | *Equip Stack* on the Creature |
| Unequip | `POST /inventory/unequip` | *Unequip Stack* on the Creature |
| Discard | `POST /inventory/discard` | *Transfer Stack* Creature → `party` |
| Claim | `POST /inventory/claim` | *Transfer Stack* `party` → Creature |
| Equip (Sell Pile) | `POST /inventory/claim_equip` | *Transfer Stack* one `party` → Creature, then *Equip Stack* |

Stack references are the index into the owner's Inventory at render time;
each request performs one action and re-renders fresh.

## What this stub does not do

- It does not enforce one-Item-per-Slot (deferred to Creatures).
- It does not price or sell items — the Sell Pile is a holding area; the
  actual selling flow is not part of this stub.
- It does not appear for enemy_template stat blocks.
