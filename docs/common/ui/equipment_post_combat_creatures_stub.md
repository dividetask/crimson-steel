# Equipment Post-Combat Creatures Stub

A DM-only side menu that runs after a fight to clear non-PC Combatants from the active Combat — looting their gear into a pile and deleting their Creature records. Composes Equipment's *Collect Combat Loot* + *Distribute Loot Pile*, Combat's *Remove Combatant*, and Creatures' *Delete Creature* into a single confirm-driven flow.

This stub is **never shown to players.** Player Characters do not appear in the list at all.

See `ui_conventions.md` for shared rules.

## When it appears

While the Encounter is in the **Looting** Phase (the DM's menu Phase selector — see `menu_layout.md`). The host page reads the current Combatants, filters out PCs, and renders this stub against the remaining non-PC roster (the just-defeated enemies). The stub is the entire post-combat creature-management surface — Combat itself does not remove creatures and does not loot them; Equipment owns both.

## Layout

A panel titled **Post-Combat Cleanup**, then a **list** — one row per non-PC Combatant — beside a single combined loot preview. Each row reads, left to right:

1. **Name** — the Combatant's display name (read through `creature_lookup`).
2. **Loot toggle** — a single two-state button. `Loot` (default, crimson) means "move this Creature's Inventory plus any rolled Loot Table contents into the pile"; clicking flips it to the muted `Ignore` ("leave the Inventory in place").
3. **Delete toggle** — a single two-state button. `Delete` (default, crimson) means "remove the Creature record after looting via Creatures' *Delete Creature*"; clicking flips it to `Keep` ("leave the Creature record in the dataset" — e.g., a recurring named villain who escaped).
4. **→ NPC toggle** — enemy rows only (an existing NPC ally row omits it). A two-state button that promotes a generated monster into a named NPC ally. Toggling it on reveals a **rename field** (pre-filled with the current name); on Confirm the Creature is renamed and its group set to `npc`, and it is **kept** — neither looted nor deleted — regardless of the other two toggles.

On the **right side**, a single combined preview of the loot the current selection will gather: the Inventories of every row still set to `Loot`, aggregated into one list (Stack names, quantities summed, with `N×` for quantities > 1), plus a muted "+ random loot" line when any of those Creatures has a Loot Table. It updates as the DM toggles rows between `Loot` and `Ignore`.

Below the list, a single **Confirm** button.

## Confirm behavior

When the DM presses Confirm, the stub:

0. For every row whose **→ NPC** toggle is on, promotes the Creature via Creatures' *Promote to NPC* (rename + group `npc`). These rows are then skipped by the loot and delete steps below — a new ally keeps its gear and its record.
1. Composes the Combat Loot Entries for every row whose Loot toggle is `Loot` and calls Equipment's *Collect Combat Loot* once, gathering into the active Map's Ground Pile (`ground:map_<map_id>`). That pile is the destination, and it is what the loot-pile stub then distributes. Loot left unlooted when the party moves to a different Map is no longer surfaced (the next Map has its own pile).
2. For every row whose Delete toggle is `Delete`, calls Combat's *Remove Combatant* followed by Creatures' *Delete Creature*. (Combat removal first so any concentration/casting references unwind cleanly; then the Creature record is gone.)
3. Persists. The looted-and-deleted rows disappear from the page.
4. The active Map's loot pile (now holding the gathered gear) renders below via `equipment_loot_pile_stub.md` for distribution.

Rows where both toggles are off (`Ignore` + `Keep`) are a no-op — the Creature stays in the dataset with its gear, available for the DM to revisit later.

## Defaults

Every row arrives with `Loot` and `Delete` selected. This is the common case (the Combatants are dead, the party takes their stuff, the records get cleaned up). The DM toggles individual rows for exceptions.

## Empty state

When no non-PC Combatants remain on the roster, the stub renders the message "No creatures to clean up." and shows no rows or Confirm button.

## Parameters

Required:
- The list of non-PC Combatants to clean up (Combatant ID + Creature ID per entry), supplied by the host page from the current roster.

Optional:
- `creature_lookup` — defaults to Creatures' *Look up Creature*.
- `location` — the Ground Pile location to gather loot into, used to construct the pile owner key `ground:<location>`. The Crimson Steel host uses the active Map (`map_<map_id>`).

## Viewer role

DM-only. The host page must enforce — a player viewer requesting this URL gets a 403.
