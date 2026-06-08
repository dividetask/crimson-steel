# Creature Full Stub

A reusable UI component that displays a single Creature with full detail. The compact variant is `creatures_minimal_stub.md`. The application chooses which to render based on a toggle.

See `ui_conventions.md` for shared rules.

## Layout

The sheet has a mix of full-width sections and a two-column body:

1. **Header** (full width) — Creature name, race + class summary, Tier, BAB, Player line. Tier is colored per the Tier Colors mapping in `ui_conventions.md`.
2. **Vitals strip (expanded)** (full width) — Combat Pool, Perception (with dice and bonus), Initiative, Damage Reduction, Damage Resilience, Speed, HP, Mana, Mana Regen, Temporary HP, Moderate Damage, Major Damage. Damage Reduction and Damage Resilience are equipped-Armor mitigation **plus** the Creature's active-effect Modifiers (e.g. a raging Creature's Circumstance bonuses), so a Condition the Creature is under is reflected in these totals.
3. **Combat** (full width) — table of usable actions: Name, Speed, Roll, Attack/Defense Bonus, Damage Bonus, Bleed, MT, Notes.

Below Combat the sheet splits into two side-by-side columns. The left column carries the per-Creature mechanical detail (Attributes through Item Descriptions); the right column carries the narrative / casting detail (Abilities and Spell List). The split keeps the sheet from running too tall when both halves are populated.

4. **Attributes** (left column) — table of all six Attributes: Score, Half (modifier), Check dice and bonus, Save dice and bonus. An equipped Guidance item (Belt / Headband) shows the intrinsic Score followed by a green `+X` (the bonus is folded into the Effective Attribute the Check / Save dice use). Save bonuses are broken out as signed tokens after the Save's Competency — green for a bonus, red for a penalty — with a leading `*` on conditional ones (poison / enchantment / charm resistance). Inherent bonuses stay baked into the underlying value. The Damage Reduction / Resilience vitals follow the same rule (base plus broken-out active-effect tokens, e.g. `3+2` while raging).
5. **Skills** (left column) — table of Skills the Creature has trained: Name, Ranks, Dice, Bonus. Omitted when the Creature has no trained Skills.
6. **Items** (left column) — Equipped, Consumable, Ammunition, Other. Ammunition is a separate category from Consumable because arrows, bolts, and similar quantity-tracked stacks are consumed by Combat actions rather than used as standalone consumables; the parent looks them up via the same Equipment-domain accessor as Consumable but reads from the `ammunition` slot.
7. **Item Descriptions** (left column) — descriptions of named magic items.
8. **Active Effects** (right column) — the named Conditions currently on the Creature (e.g. Rage), shown as badges. Sourced from Conditions' active named Effects. Omitted when none are active.
9. **Abilities** (right column) — granted abilities with full descriptions, **excluding known Spells** (a spell-typed granted entry appears in the Spell List below, not here).
10. **Spell List** (right column) — spells grouped by tier. Two follow-on subsections render beneath the main spell list when their lists are non-empty: **Rituals** (spells the Creature knows as rituals — same per-row format as the spell list, with the ritual's casting time and component cost shown in place of mana cost) and **Item Spells** (spells the Creature can cast from carried items such as scrolls or wands — each row names the source item alongside the spell). Both subsections share the spell list's column layout.

Sections with no content are omitted. When one side of the two-column body is much taller than the other, the shorter column simply ends earlier — sections do not flow across the split.

In the Items section, hovering an item that carries a `metadata.description` surfaces the description inline (a small text bubble or tooltip-like reveal positioned next to the row). This is an in-section hover behavior — separate from the dedicated `atlas_token_tooltip`-style tooltip widget; specs that need a richer popup use a tooltip spec instead. The Item Descriptions section below still renders the full descriptions in one place so the information is available without hovering.

## Parameters

Required:
- A Creature ID.
- Viewer role — `dm` or `player`.

Optional:
- Viewing Player ID.
- Prev / Next navigation context — when set, the header renders left and right arrow affordances that navigate to the previous and next Creature in the parent's list. The parent supplies the route prefix (e.g. the Creatures index it is iterating) and the current position; the stub emits the arrow targets but does not own the routing.
- Detail-mode toggle target — the route the toggle button posts to in order to switch between this stub and `creatures_minimal_stub.md`. The toggle reads `Show minimal` while the full sheet is active, is rendered at the **bottom-left** of the sheet, and visually sits below every other section. The application may persist the last-picked mode in `localStorage` keyed by Creature ID (see `ui_conventions.md`); the stored value is a hint only, not authoritative.

## Visibility

Same rule as the minimal stub: the parent page handles visibility. Player viewers only see Creatures tagged `player_character`.

## Data sources

In addition to everything used by the minimal stub:

- **Combat-derived values** (Combat Pool, attack rolls and bonuses, damage and bleed) — computed by the Encounter domain via Creatures' Accessor (`attribute_value`, `ranks_for("martial")`) plus Equipment's Weapon Details. BAB is `ranks_for("martial")` directly.

The expanded vitals (Damage Reduction, Damage Resilience, Mana Regen, etc.) come from formulas applied to Creature attributes, Tier, equipped Armor, and Conditions tunables (Mana Regen is `floor(Max Mana / Mana Per Recovery Tick Divisor)` per Day). The Attributes table's Check and Save columns derive from Effective Attributes plus the displayed formulas.