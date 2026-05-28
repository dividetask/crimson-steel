# Abilities Spell Detail Stub

A read-only reference page for a single Spell — either the full multi-Tier reference or one resolved Variant.

See `ui_conventions.md` for shared rules.

## Layout

A single panel with these blocks, stacked top to bottom:

1. **Header**
   - Spell name. When a specific Variant was requested, the resolved Variant name (with `prefix` / `suffix` applied). Otherwise the base Catalog Ability name.
   - School badge — the Spell's `school`.
   - Tier(s) — a single Tier for single-Tier Spells; a list or range for Tier-axis Variants.
2. **Stats table** — Range, Duration, Activation Time, Save. Each value comes from the resolved Catalog Ability.
3. **Casting Skills** — the resolved `skills` list, comma-joined. (Includes Universal Spell Casting Skills appended at lookup time.)
4. **Description** — see *Description* below.
5. **Effects by Tier** — table form of the resolved Effect Hash across Tiers, shown only for Tier-axis Variants whose Effect Hash carries Variant values.
6. **Duration by Tier** — table form of `duration` across Tiers, shown only when `duration` is itself a parallel list across the Variant Axis.
7. **Available as** — the resolved `items` list (Item Forms), one badge per form. Includes Universal Item Forms unless the Spell is `item_only`.
8. **Back link** — to the `abilities_spell_list_stub` page.

## Parameters

Required:
- Spell name — the base name or a Variant name. The stub looks the Ability up via the Abilities domain's *Look up a Catalog Ability by name* entry point.
- Viewer role — `dm` or `player`. Player and DM see the same content; viewer role is carried for consistency with other UI specs.

Optional:
- Variant index — when the caller arrived at a specific Variant (e.g. a `prefix`-decorated name), the resolved `axis_index`. When omitted, the page renders the full multi-Tier reference.

## Header

When a Variant index is supplied, the header shows just that Variant's name and Tier. When omitted, the header shows the base name and the full Tier list (or range, for contiguous Tiers).

## Description

For Tier-axis Variants with a Variant index supplied: one resolved description block, with `{name}` and `{aspect}` substitution already applied by the Abilities domain.

For Tier-axis Variants with no Variant index: one block per Tier, headed by that Tier's Variant name (e.g. `Lesser Cure`, `Cure`, `Greater Cure`). The Abilities domain resolves each Variant separately; this stub renders the resolved descriptions side by side.

For single-Tier Spells: one description block; no Tier heading.

## Effects-by-Tier table

Shown only when the Catalog Ability declares an `effect_hash` and is a Tier-axis Variant. Columns are the keys of the Effect Hash (e.g. `minor_damage`, `temp_hp`, `mana`); rows are the Tiers. Each cell shows the resolved value for that Tier, computed by the Abilities domain.

## Available as

Lists each Item Form from the resolved `items` list as a badge. The list always includes the Universal Item Forms (`scroll`, `wand`) unless the Spell carries `item_only: true`.

## Composition

Self-contained read-only page. Not embedded inside other stubs. Reached from `abilities_spell_list_stub` rows and from any other UI that links to a Spell by name.

## What this stub does not do

- It does not roll dice. The page is descriptive only; casting is owned by Combat.
- It does not evaluate Damage Objects. Severity and damage Formulas are surfaced as declared on the Catalog Ability; evaluation happens at cast time with caller-supplied `success`, `critical`, and `attribute`.
- It does not interpret Triggers. A Spell with a Trigger Spec lists it as part of the description; the Trigger is evaluated by Combat / Conditions, not here.
