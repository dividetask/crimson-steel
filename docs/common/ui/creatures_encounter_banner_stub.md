# Creatures Encounter Banner Stub

A banner shown after an encounter has been rolled, describing the Creatures that were just added to the active Combat and any loot rolled alongside them. Renders above the main content on pages that surface combat or roster state.

See `ui_conventions.md` for shared rules.

## Layout

A horizontal panel with:

1. **Title** — the encounter's name as supplied by the parent page.
2. **Outcome description** — body text describing the encounter outcome. Uses the show-more truncation pattern (per `ui_conventions.md`).
3. **Spawn list** — one row per spawn entry:
   - `<count> × <Creature name>` on the left — the Creatures added to the active Combat (via Combat's *Add Combatant*), grouped by Creature record.
   - Gold rolled in the middle — the total Gold-equivalent from any Currency Stacks in the rolled Loot Table result (per Equipment's *Roll Loot Table*).
   - Items rolled on the right — a comma-joined list of `<Generated Display Name>` or `<Generated Display Name> × N` tallies. The names come from Equipment's *Get Item Details* applied to each rolled Stack.
4. **Dismiss button** — a `×` button on the right. DM-only. Emits a `dismiss_banner` event the parent page resolves by clearing the encounter message from its scene state.

## Parameters

Required:
- Encounter Name — string. Supplied by the parent page.
- Outcome Description — string. May be empty.
- Spawn list — a list of `{creature_id, count}` entries. Each `creature_id` is resolved through Creatures' *Look up Creature* for the display name.
- Loot list — the Item Stacks produced by Equipment's *Roll Loot Table* call that accompanied the encounter (may be empty).
- Viewer role — `dm` or `player`. Determines whether the Dismiss button renders.

## When it renders

The parent page renders the banner only when an encounter has been rolled since the last dismissal. The encounter message is scene-level state owned by the parent page; this stub does not persist it.

## Dismiss

The Dismiss button is DM-only. Players see the banner but cannot dismiss it; it remains visible until the DM clears it.

## Composition

The banner is a partial included by parent pages above their main content when an encounter is active. Not embedded inside other stubs.

## What this stub does not do

- It does not roll encounters. Encounter rolling is the parent page's responsibility — typically via Creatures' *Roll Encounter* (which spawns the new Creature records via *Spawn Creature From Template* and returns their IDs); the parent then adds each via Combat's *Add Combatant* and may roll accompanying loot via Equipment's *Roll Loot Table*.
- It does not place rolled Loot into an Owner. The Loot list is displayed only; the parent page decides whether the Stacks land in a Ground Pile (via Equipment's *Collect Combat Loot* at end of Combat, then surfaced via `equipment_loot_pile_stub`) or elsewhere.
- It does not validate Creature IDs. Unknown IDs render as `—` for the display name.
