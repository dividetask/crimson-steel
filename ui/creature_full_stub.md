# Creature Full Stub

A reusable UI component that displays a single Creature with full detail. The compact variant is `creature_minimal_stub.md`. The application chooses which to render based on a toggle.

See `ui_conventions.md` for shared rules.

## Layout

A single-column sheet with these sections, top to bottom:

1. **Header** — Creature name, race + class summary, Tier, BAB, Player line. Tier is colored per the Tier Colors mapping in `ui_conventions.md`.
2. **Vitals strip (expanded)** — Combat Pool, Perception (with dice and bonus), Initiative, Damage Reduction, Damage Resilience, Speed, HP, Mana, Mana Regen, Temporary HP, Moderate Damage, Major Damage.
3. **Combat** — table of usable actions: Name, Speed, Roll, Attack/Defense Bonus, Damage Bonus, Bleed, MT (major-threshold), Notes. Footer note explains MT.
4. **Attributes** — table of all six Attributes: Score, Half (modifier), Check dice and bonus, Save dice and bonus. Footer shows the formula used.
5. **Skills** — table of Skills the Creature has ranks in: Name, Ranks, Dice, Bonus. Footer shows the formula used.
6. **Items** — Equipped, Consumable, Other.
7. **Item Descriptions** — descriptions of named magic items.
8. **Abilities** — granted abilities with full descriptions.
9. **Spell List** — spells grouped by tier.
10. **Notes** — free-form per-Creature notes.

Sections with no content are omitted.

## Parameters

Required:
- A Creature ID.
- Viewer role — `dm` or `player`.

Optional:
- Viewing Player ID.

## Visibility

Same rule as the minimal stub: the parent page handles visibility. Player viewers only see Creatures tagged `player_character`.

## Data sources

In addition to everything used by the minimal stub:

- **Combat-derived values** (Combat Pool, attack rolls and bonuses, damage and bleed, BAB) — currently derived by the application from creature data and orphan_data values. Will migrate to the Combat domain when designed.
- **Per-Creature notes** — free-form text. Source TBD; likely a future Chronicle reference or its own orphan file.

The expanded vitals (Damage Reduction, Damage Resilience, Mana Regen, etc.) come from formulas applied to Creature attributes and Tier. The Attributes table's Check and Save columns derive from Effective Attributes plus the displayed formulas.