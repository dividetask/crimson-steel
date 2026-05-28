# Creatures Encounter Template Stub

A read-only viewer for a single Encounter Table from `encounter_tables.yaml`. Shows the table's name plus a row-by-row breakdown of what the table could roll — the row probability (`Always`, `60%`, etc.), any `when` gate, the spawn list (template name and count), and any name/loot overrides per Spawn Ref.

Surfaced from the Roster Sidebar (`creatures_roster_sidebar_stub.md`): clicking an Encounter Table's name in the sidebar opens this stub in the page's main panel, in place of the character sheet. The `Roll` button next to the name in the sidebar is a separate path that produces a `creatures_encounter_roll_result_stub.md` panel above the sheet instead.

See `ui_conventions.md` for shared rules.

## Layout

A single-column panel:

1. **Header** — Encounter Table display name. A short subtitle line below shows the table's snake_case id in parens for cross-reference.

2. **Rows** — one row per entry in the Encounter Table's `rolls` list, in the order they would resolve. Each row groups:
   - **Row chance** — `Always` when no `chance` is declared (Guaranteed), `<percent>%` for an Independent Chance row, or `Weighted` / `Gated Weighted` for the other two variants once those land.
   - **`when` gate** — when present, rendered as `When <var> = <value>` on a small line above the spawn list. Omitted when the row has no `when`.
   - **`as` publication** — when the row publishes a Roll Variable via `as`, rendered as `Publishes <var>` on the same small line as `when`.
   - **Spawn list** — one line per Spawn Ref, in the row's payload order. Each line shows `<count>× <template name>` where `count` mirrors the field on disk (an integer or a dice expression like `2d4`). When the Spawn Ref carries `name_override`, the rendered name uses the override followed by `(<template name>)` in muted italic so the source template stays visible. When the Spawn Ref carries `loot_table`, an italic `loot: <table>` suffix appears.

3. **Footer** — single `Roll` button that emits a `roll_encounter` event identical to the sidebar's per-row Roll button (the parent handles it by rendering a `creatures_encounter_roll_result_stub.md` panel; both paths share the same fetch).

## DM-only

Encounter Tables are DM operational data. Player viewers should never reach this stub — the host route guards by viewer role.

## Parameters

Required:
- The Encounter Table entry — usually the result of looking it up in `Creatures::Encounter.tables` by id. The stub does not call into Creatures itself.
- A name resolver — given a Creature template id, returns the template's display name. Sourced from `Creatures.lookup(id).name` (or the equivalent SampleCreatures shape on the Status / Character Sheet pages).

Optional:
- `id` (table key) — when supplied, rendered as the subtitle line under the table name.

## What this stub does not do

- It does not roll the encounter. The Roll button emits an event the parent resolves (typically by fetching a roll-result fragment and inserting `creatures_encounter_roll_result_stub.md` above the page's main panel).
- It does not show the loot the table would produce. Per-Creature loot is rolled at the time of *Roll Encounter*; only the resulting `creatures_encounter_roll_result_stub.md` shows it. The template viewer stays static.
- It does not edit the Encounter Table. Editing is the responsibility of a dedicated Encounter Tables editor (not yet designed).
