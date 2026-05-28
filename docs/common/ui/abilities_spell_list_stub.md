# Abilities Spell List Stub

A filterable table of every Spell in the Abilities catalog. Renders the full Spell reference as a standalone page.

See `ui_conventions.md` for shared rules.

## Layout

A two-region card:

1. **Filter row** — three dropdowns plus a Clear button.
   - **School** — every Spell School from `abilities_config.yaml`'s `Spell Schools`.
   - **Tier** — `0` through `5` (the Tiers the Abilities domain recognizes).
   - **Skill** — every Casting Skill that appears on at least one Spell.
   - **Clear** — resets all three dropdowns.
2. **Spell table** — one row per Catalog Ability whose `type` is `spell`. The base name is shown; Variants are not listed separately. Clicking a row navigates to that Spell's detail page (`abilities_spell_detail_stub`).

DM-only affordance: an **Add Spell** form below the table. Hidden for player viewers.

## Parameters

Required:
- Viewer role — `dm` or `player`. Determines whether the Add Spell form is shown.

Optional:
- Initial filter selection — pre-populated School / Tier / Skill values from the URL or a navigation context. When omitted the dropdowns start empty (no filter active).

## Filter behavior

- Filtering is applied locally to the rendered table; the underlying Spell list does not refetch.
- **School filter**: a Spell matches when its `school` equals the chosen value.
- **Tier filter**: a Spell with a single integer `tier` matches when the chosen Tier equals it. A Spell with a list `tier` (a Tier-axis Variant) matches when the chosen Tier is in the list.
- **Skill filter**: a Spell matches when the chosen Skill appears in its resolved `skills` list (which includes Universal Spell Casting Skills appended at lookup time).

Multiple filters compose with AND.

## Spell table columns

| Column | Source |
|---|---|
| Name | The Catalog Ability's base name. |
| School | The Spell's `school`, rendered as a badge. |
| Tier(s) | A single integer for single-Tier Spells; a range (e.g. `0–2`) for Tier-axis Variants. |
| Skills | The resolved `skills` list, comma-joined. |
| Save | The Save Spec's Save Attribute, or `—` when `save` is empty. |
| Range | The named Range or feet from the Catalog Ability's `range` field. |
| Duration | The `duration` field as a string. For Channeled Abilities the field is the maximum sustained duration. |
| Activation Time | The resolved Activation Time (Action Alias, Real-Time Alias, turn count, or minutes). |

## DM-only — Add Spell form

Visible only when the viewer role is `dm`. Fields mirror the Catalog Ability schema (see `abilities_design.md`):

- `name`, `school`, `tier` (single value or list), `save` attribute, `range`, `duration`, `activation_time`, `skills`, `items`, `description`.

Submitting the form is the parent page's responsibility — the stub emits the structured Spell payload and an `add` event.

## Composition

Self-contained page. The stub is not embedded inside other stubs. Each row links to the matching `abilities_spell_detail_stub`.

## What this stub does not do

- It does not resolve Variants. The table shows base Spells; Variant resolution happens on the detail page.
- It does not validate Add Spell input against the schema. Validation is owned by the Abilities domain at load time.
- It does not interpret Effect strings or Damage Objects. Those are surfaced on the detail page.
