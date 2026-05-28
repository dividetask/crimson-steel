# Creatures Encounter Roll Result Stub

A read-only panel rendering the outcome of a single *Roll Encounter*. Lists the rolled creatures grouped by row label, with per-Creature loot (gold and item names with quantities) indented beneath each spawn.

Surfaced from the Roster Sidebar (`creatures_roster_sidebar_stub.md`) and from the Encounter Template Stub (`creatures_encounter_template_stub.md`). Both surfaces hit the same fetch path; the result is inserted into the Character Sheets page above the main sheet panel by client-side script.

See `ui_conventions.md` for shared rules.

## Layout

A single-column panel with a header, a flat content list, and a single action button.

1. **Header**
   - Encounter Table display name, large, bold.
   - Optional subtitle line in muted italic when the host page wants to flag the run (timestamp, seed, etc.). The stub itself does not show a seed.

2. **Body** — a flat list of lines, one per spawned creature with its loot indented beneath. Lines render in roll order — the order the encounter resolution returned them, which matches the Encounter Table's row order.

   Within each row group:
   - The row's **label** (when the Encounter Table row carries a human label — currently the table's `name` is used as the section header; finer per-row labeling lands when row metadata gets a `label:` field).
   - One **creature line** per Spawn Ref result: `<count>× <creature name>` in regular weight. When `count == 1` the prefix is `1×` for visual consistency.
   - Indented under each creature line, the **loot lines**:
     - **Gold** — first, as `<n> gp`. Omitted when the loot table didn't roll any gold.
     - **Items** — one per item stack the loot table produced. A stack of one shows just the name (`falcion`); a stack of more than one shows `<name> ×<count>` (`falcion ×5`). Magic items show the name verbatim (`chain shirt +1`, `Potion of Sanctuary`).
   - The loot block can be empty — when a Creature's `loot_table` is null or the table rolled nothing, no loot lines appear under that creature.

3. **Footer — single Roll button** — labeled `Roll`. Clicking emits a `reroll_encounter` event the parent resolves by fetching a fresh roll of the same Encounter Table and replacing the panel's body. The same button is also the commit affordance: every roll the result panel renders is treated as committed (i.e. the host page has already called *Add Combatant* for each rolled Creature and recorded the loot in the enemy data file). A second click rolls again — old combatants are removed and replaced by the new spawn list. The DM keeps clicking until satisfied; the last visible result is what stays in the active Combat.

## Composition

Rendered above the main panel on the Character Sheets page. The host page wires up the panel by:

1. Listening for clicks on `creatures_roster_sidebar_stub.md`'s `Roll` button (and on the Encounter Template Stub's footer `Roll` button).
2. Issuing a `GET /encounters/roll/<table_id>` request.
3. Replacing or prepending the panel's HTML in `#encounter-roll-result` with the response body.
4. On click of the panel's own `Roll` button, issuing the same fetch and replacing the panel's content.

The panel itself is purely presentational — the host owns the fetch path and the Combat / enemy-data-file side effects.

## DM-only

This panel is only ever rendered for DM viewers. Host-page guards enforce that.

## Parameters

Required:
- A `result` structure:
  - `table_id` — string. Returned echo of the rolled table id.
  - `table_name` — string. Display name.
  - `rolls` — list of rolled creatures, each `{ count, name, gold, items: [{ name, count }] }`. The list is in roll order; the panel does not regroup.

Optional:
- `subtitle` — string. Rendered in muted italic under the header when set.

## What this stub does not do

- It does not actually call Creatures' *Roll Encounter*. The host route handler does. The host also handles the Combat / enemy-data-file side effects of each roll.
- It does not preserve previous rolls. Each new roll replaces the panel's body. Earlier rolls are not undoable through this stub — by design, since every roll committed before the current one is also already off the active Combat.
- It does not let the DM tweak loot. Loot comes back already rolled from the Equipment domain; editing happens in dedicated Equipment-domain UIs.
