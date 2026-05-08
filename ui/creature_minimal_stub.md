# Creature Minimal Stub

A reusable UI component that displays a single Creature in compact form. The full sheet variant is `creature_full_stub.md`. The application chooses which to render based on a toggle; switching between them displays opposite-named buttons (`Show full sheet` while minimal is active, `Show minimal` while full is active).

See `ui_conventions.md` for shared rules.

## Layout

A single-column card with these sections, top to bottom:

1. **Header** — Creature name (large), race + class summary (e.g., `Human Bard 3`), Tier, Player line. Tier is colored per the Tier Colors mapping in `ui_conventions.md`.
2. **Vitals strip** — HP, Mana, Toxicity, Initiative, Perception, Speed.
3. **Actions** — a small table of usable actions: Name, Speed, Roll, Bonus, Damage, Notes.
4. **Spells** — grouped by tier (`Tier 0. Mending`, `Tier 1. Charm Person, Healing Word`, etc.). Each tier on its own line.
5. **Rituals** — same format as Spells. Omitted when no rituals.
6. **Items** — grouped into Equipped, Consumable, Other. Each group on its own line.
7. **Abilities** — list of granted abilities with full descriptions.
8. **Item Descriptions** — descriptions of named magic items the Creature carries.

Sections that have no content are omitted entirely.

## Parameters

Required:
- A Creature ID. The stub looks up the Creature from the roster.
- Viewer role — `dm` or `player`.

Optional:
- Viewing Player ID. Used by the application to determine the player's identity for visibility filtering done at the parent level.

## Visibility

The stub itself does not filter. The parent page is responsible for ensuring the requested Creature is visible to the viewer. When viewer role is `player`, the parent page only renders the stub for Creatures whose `tags` include `player_character`.

## Data sources

The stub composes data from:

- **Creatures domain** — identity, race, classes, Tier, Effective Attributes, Speed, Initiative, abilities (names), proficiency ranks (for Perception display).
- **Conditions orphan data** — current HP / Mana / Toxicity, current condition flags. (When the Conditions domain exists, this moves to that domain.)
- **Equipment orphan data** — equipped/consumable/other items, prepared spells, rituals, item descriptions. (Will move to Equipment.)
- **Abilities orphan data** — ability description text. (Will move to Abilities.)

Computed values (HP max, Mana max, Initiative, Perception bonus, attack rolls, etc.) come from the Creatures domain and the formulas in its config files. They are not stored anywhere.