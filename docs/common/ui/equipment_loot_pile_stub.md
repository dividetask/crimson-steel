# Equipment Loot Pile Stub

A table showing every Stack in a single Ground Pile (typically the combat pile produced by `equipment_post_combat_creatures_stub.md`), with a per-row dropdown letting each item be assigned to the Party's General Sell Pile, to a specific Player Character, or skipped. The DM confirms with a single button that distributes everything via Equipment's *Distribute Loot Pile*.

See `ui_conventions.md` for shared rules.

## When players see it

The DM controls whether the pile is visible to players. The post-combat creatures stub (DM-only) creates the pile and is hidden from players; this loot-pile stub is shown to everyone *after* the DM finishes the cleanup step. Until then, players see no loot UI for the just-ended Combat.

## Layout

A table titled with the pile's name (default: `Combat <id> loot pile`). One row per Stack on the pile, in pile order. Columns, left to right:

1. **Item** — the Stack's display name (`name` override if set, else the generated name from `equipment_config.yaml`). Magical items show their Tier and Properties inline.
2. **Quantity** — the Stack's `quantity`.
3. **Assignment** — a dropdown with these options, in this order:
   - **General Sell Pile** (default) — the Stack will be transferred to the Party Owner. The party converts pool to Gold during downtime; no specific PC takes possession.
   - One option per Player Character on the roster — labeled `<PC Name>` — assigns the Stack to that PC's Inventory.
   - **Skip** — the Stack stays on the pile after Confirm. Use this to defer a decision (e.g., the magic sword nobody can identify yet).

Below the rows, two controls:

- **Confirm Distribution** (primary button) — runs *Distribute Loot Pile* with the assignment map. Stacks marked **Skip** stay on the pile; everything else transfers. If the pile is empty after, Equipment's *Cleanup* removes it automatically.
- **Delete Pile** (secondary button, DM-only) — removes the pile and its remaining contents wholesale. The host page confirms first (the contents are unrecoverable).

## Per-row assignment defaults

Every row starts on **General Sell Pile**. Players adjust their own row assignments; the DM can adjust any row. The current selection is persisted on the page (LocalStorage key per the conventions document) so a player who reloads doesn't lose their picks.

## Empty state

When the pile has no Stacks, render the message "Pile is empty." and offer only the **Delete Pile** button (DM-only).

## Auto-removal

After a successful Confirm Distribution, if the pile has no remaining Stacks the host page's next render will not show this stub for that pile (it's gone). The host page typically redirects back to the Combat or party page.

## Parameters

Required:
- `pile_owner_id` — the Ground Pile Owner ID (e.g., `ground:combat_42`).

Optional:
- `pc_roster` — list of PC `{id, name}` used to populate the assignment dropdown. Defaults to every Creature whose `tags` include `player_character`.
- `pile_label` — display title override. Defaults to the pile owner's location string.

## Viewer role

Both — DM and player. The host page enforces that the pile is "ready for distribution" before exposing this stub to players (the DM's post-combat creatures stub gates that transition).
