# Equipment Loot Pile Stub

A card grid of every Stack in a single Ground Pile (the pile produced by `equipment_post_combat_creatures_stub.md`), styled like the Character Sheet Inventory stub — each item has an icon, a name, and per-item actions. Players claim items for themselves or give them to a teammate; a single **Loot** button sweeps everything left marked **Sell Pile** into the Party's shared Sell Pile.

See `ui_conventions.md` for shared rules.

## When players see it

Both DM and players see this stub while the Encounter is in the **Looting** Phase (the DM's menu Phase selector — see `menu_layout.md`). The DM moves loot onto the pile with the DM-only post-combat creatures stub; in any other Phase no loot UI is shown.

## Layout

A section titled with the pile's name (default: `Map <id> loot pile`), then a card grid — one card per Stack, in pile order, mirroring the Inventory stub (`equipment_inventory_stub.md`):

- **Icon** — the item's icon (same source as the Inventory / Store stubs).
- **Name** — the Stack's display name, prefixed with `N×` when `quantity > 1`.
- **Actions**, left to right:
  1. **Sell Pile / Discard** — a per-item toggle (default **Sell Pile**). It is only a flag; nothing moves until the **Loot** button is pressed.
  2. **Quantity** — an input defaulting to the full Stack `quantity`, shared by Claim and Give.
  3. **Claim** (players only) — moves that quantity from the pile to the viewing player's own Creature.
  4. **Give** — a dropdown of the Creatures involved in this combat plus a **Give** button; moves that quantity to the chosen Creature. Uses the same quantity input.

Below the grid:

- **Loot** (primary button) — transfers every Stack still flagged **Sell Pile** to the Party Owner and leaves the **Discard**-flagged Stacks on the pile. Runs via Equipment's *Distribute Loot Pile* (Sell Pile → Party, Discard → skip); if the pile empties, *Cleanup* removes it.
- **Delete Pile** (secondary button, DM-only) — removes the pile and its remaining contents wholesale, confirmed first (the contents are unrecoverable).

## Defaults

Every item starts flagged **Sell Pile**, and each quantity box defaults to the full Stack. Claim and Give act immediately (like the Inventory stub's per-item actions); the Sell Pile / Discard flag is applied in bulk by the **Loot** button.

## Viewer role

Both — DM and player. The Looting Phase is what exposes this stub to players; the DM controls the Phase from the menu. The DM has no viewing Creature, so the DM sees **Give** (and **Delete Pile**) but not **Claim**.

## Parameters

Required:
- `pile_owner_id` — the Ground Pile Owner ID (e.g., `ground:map_3`).

Optional:
- `give_options` — list of `{id, name}` (the combat participants) for the Give dropdown. Defaults to the current Combatant roster.
- `claim_creature_id` — the viewing player's Creature id; `nil` (the DM) hides the Claim button.
