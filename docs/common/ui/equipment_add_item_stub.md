# Equipment Add Item Stub

A form for adding a custom Item Stack to a Creature's Inventory outside the Shop flow.

See `ui_conventions.md` for shared rules.

## Layout

A single form with the following fields:

| Field | Type | Description |
|---|---|---|
| Owner | dropdown | Every Creature in the roster (Creatures' *List Creatures*). The selection is converted to the Owner ID `creature:<id>` per `equipment_design.md`'s Owner ID format. |
| Item Category | dropdown | The Item Categories declared in `equipment_config.yaml`. Drives the Item Type cascade. |
| Item Type | dropdown | Item Types in the chosen Category, fed from the Equipment catalog. Re-populates client-side when Item Category changes. |
| Tier | integer | Magical infusion level. Defaults to 0. |
| Name Override | text | Optional. Replaces the Generated Display Name when set. |
| Quantity | number | Defaults to 1. Fractional values are accepted only for Currency Item Types per `equipment_design.md`. |
| Properties | repeatable group | Zero or more Property Applications. Each entry has a Property name (dropdown over the catalog) and — when the Property has `has_subtype: true` — a Subtype dropdown. Cost is copied from the catalog at submit time. |
| Equipped | checkbox | Initial `equipped` flag. Defaults to false. |
| Description | textarea | Free-form text stored in the Stack's `metadata.description`. Surfaced by `creatures_minimal_stub` and `creatures_full_stub` in their Item Descriptions section. |

Below: Submit button.

## Parameters

Required:
- The Creature roster — Creatures' *List Creatures*.
- The Equipment catalog — Item Categories, Item Types per Category, Properties (with Subtypes where applicable), per-Item Tier surcharge tables. The parent page supplies these from the loaded `equipment_config.yaml`.
- Viewer role — `dm` or `player`. Players may add items only to Creatures they control (the parent page enforces this; the form itself does not gate selection).

## Behavior

- Changing the Item Category re-populates the Item Type dropdown client-side from the catalog.
- Submitting emits an `add_item` event carrying the chosen Owner ID and a fully-shaped Item Stack (per the schema in `equipment_design.md`). The parent page resolves the event by calling Equipment's *Add Item*; Stack Merge applies on the destination side per Stack Identity.
- Successful submission clears the form so the user can add another.

## Ownership

Player viewers may submit only when the chosen Owner is a Creature they control. The parent page is responsible for validating ownership before resolving the *Add Item* call — the form itself surfaces every Creature in the dropdown.

## Composition

Self-contained page. Not embedded inside other stubs.

## What this stub does not do

- It does not validate Item Stack shape. Stack Identity matching, Property Application schema, and per-Item-Type field requirements (e.g. `value_in_gold` for Gems) are enforced by Equipment at *Add Item* time.
- It does not compute Unit Price. The Generated Display Name and Unit Price are produced by Equipment's detail-fetchers (*Get Item Details*) once the Stack is in an Inventory.
- It does not reconcile equipped Stacks. When `equipped = true`, the parent page calls Equipment's *Reconcile Loadout* after *Add Item* to post the Stack's Active Effects through Conditions.
