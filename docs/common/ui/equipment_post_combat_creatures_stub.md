# Equipment Post-Combat Creatures Stub

A DM-only side menu that runs after a fight to clear non-PC Combatants from the active Combat — looting their gear into a pile and deleting their Creature records. Composes Equipment's *Collect Combat Loot* + *Distribute Loot Pile*, Combat's *Remove Combatant*, and Creatures' *Delete Creature* into a single confirm-driven flow.

This stub is **never shown to players.** Player Characters do not appear in the list at all.

See `ui_conventions.md` for shared rules.

## When it appears

After the DM ends a Combat. The host page reads the participating Combatants from the parent's End Combat notification (see `combat_design.md` — *End Combat* "notify the post-combat consumer"), filters out PCs, and renders this stub against the remaining roster. The stub is the entire post-combat creature-management surface — Combat itself does not remove creatures and does not loot them; Equipment owns both.

## Layout

A right-side panel titled **Post-Combat Cleanup**. One row per non-PC Combatant that participated in the just-ended Combat. Each row has, left to right:

1. **Name** — the Combatant's display name (read through `creature_lookup`).
2. **Source** — short label: "Spawned", "Template", or "NPC". Spawned (per Creatures' *Spawn Creature From Template*) is the common case.
3. **Loot toggle** — a two-state button. `Loot` (default, highlighted) means "move this Creature's Inventory plus any rolled Loot Table contents into the combat pile". `Ignore` means "leave the Inventory in place".
4. **Delete toggle** — a two-state button. `Delete` (default, highlighted) means "remove the Creature record after looting via Creatures' *Delete Creature*". `Keep` means "leave the Creature record in the dataset so it can be referenced later" (e.g., for a recurring named villain who escaped).

Below the rows, a single **Confirm** button.

## Confirm behavior

When the DM presses Confirm, the stub:

1. Composes the Combat Loot Entries for every row whose Loot toggle is `Loot` and calls Equipment's *Collect Combat Loot* once. The resulting Ground Pile Owner ID (`ground:combat_<combat_id>`) is the destination pile.
2. For every row whose Delete toggle is `Delete`, calls Combat's *Remove Combatant* followed by Creatures' *Delete Creature*. (Combat removal first so any concentration/casting references unwind cleanly; then the Creature record is gone.)
3. Persists. The stub disappears from the page.
4. The host page reroutes the GM to the loot pile, which renders via `equipment_loot_pile_stub.md`.

Rows where both toggles are off (`Ignore` + `Keep`) are a no-op — the Creature stays in the dataset with its gear, available for the DM to revisit later.

## Defaults

Every row arrives with `Loot` and `Delete` selected. This is the common case (the Combatants are dead, the party takes their stuff, the records get cleaned up). The DM toggles individual rows for exceptions.

## Empty state

When no non-PC Combatants participated, the stub renders the message "No creatures to clean up — End Combat removed PC-only state directly." and shows no rows or Confirm button.

## Parameters

Required:
- The list of just-ended Combat participants (Combat ID + Creature ID per entry) supplied by the host page from the End Combat notification.

Optional:
- `creature_lookup` — defaults to Creatures' *Look up Creature*.
- `combat_id` — the just-ended Combat's ID, used to construct the pile owner key `ground:combat_<combat_id>`.

## Viewer role

DM-only. The host page must enforce — a player viewer requesting this URL gets a 403.
