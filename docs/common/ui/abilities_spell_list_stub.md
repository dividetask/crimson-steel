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
2. **Spell table** — one row per **individual Spell Variant**: a Tier-axis Spell is expanded to one row per Tier (Heal → Heal Petty Wounds, Heal Lesser Wounds, …), an aspect-axis Spell to one row per aspect (Elemental Dart → Fire / Acid / Electricity / Cold Dart); a single-Variant Spell is one row. Rows are **sorted by Tier, lowest first** — there is no Tier column. Clicking a spell name opens its detail popup (`abilities_spell_detail_stub`); clicking its **School** badge opens the School's description (from `abilities_config.yaml` → `Spell Schools`).

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

Rows are ordered by Tier (lowest first); the Tier is the ordering key and has no column of its own.

| Column | Source |
|---|---|
| Name | The resolved Variant name (Heal Petty Wounds, Fire Dart, …). |
| School | The Spell's `school`, rendered as a badge; clicking it opens the School description. |
| Skills | The resolved `skills` list, comma-joined, excluding the Universal Spell Casting Skills (Evocation). |
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
