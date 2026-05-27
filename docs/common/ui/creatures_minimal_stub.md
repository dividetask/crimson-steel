# Creature Minimal Stub

A reusable UI component that displays a single Creature in compact form. The full sheet variant is `creatures_full_stub.md`. The application chooses which to render based on a toggle; switching between them displays opposite-named buttons (`Show full sheet` while minimal is active, `Show minimal` while full is active).

See `ui_conventions.md` for shared rules.

## Card chrome

- Cream / parchment-tinted card background.
- A solid top border in the Creature's Tier Color. The border is the strongest visual cue of Tier; the same color also tints the Creature's name.
- Section heads use small-caps maroon with a thin underline rule.
- Major regions (header / vitals / actions / spells+rituals / items+abilities / item descriptions) are separated by a slightly heavier maroon rule.

## Layout

The card has full-width regions at the top, a two-column body in the middle, and full-width regions at the bottom.

1. **Header** (full width)
   - Creature name, large, bold, in the Creature's Tier Color. Left-aligned.
   - `Player: <name>` right-aligned on the same baseline. Omitted when the Creature has no Player.
   - Subtitle line below: `Human Bard 3, Tier 3` — italic, small, muted color. The Tier number in the subtitle picks up the Creature's Tier Color.

2. **Attribute + vital block** (full width, two halves side by side)
   - **Left half**: 3×2 grid of attributes. Each cell shows the attribute key in small-caps maroon (`STR`, `DEX`, ...) followed by the Effective Attribute value. Order is the project's `Attributes` config order — typically str, dex, con on the first row; int, wis, cha on the second.
   - **Right half**: two lines.
     - Line 1: `HP <current>/<max>`. `HP` label maroon, bold.
     - Line 2: `Mana <current>/<max>, Toxicity <current>/<threshold>`. The Toxicity portion uses a muted color (it's secondary information).

3. **Initiative · Perception · Speed row** (full width, three equal columns)
   - `Initiative <dice_count>` — the dice count Combat would roll on a fresh initiative roll. No `d` suffix.
   - `Perception +<modifier>` — the Competency Modifier returned by Proficiencies for the `perception` key. Show the sign explicitly.
   - `Speed <feet>` — Effective Speed in feet, no unit suffix beyond the integer.

Below the Initiative · Perception · Speed row the sheet splits into two columns. The split runs through the Actions/Skills (left) and Spells/Rituals/Items (right) sections; Abilities and Item Descriptions render in their own two-column row below.

4. **Actions** (left column) — section heading `ACTIONS`. A table with columns `Name`, `Spd`, `Roll`, `Bonus`, `Dmg`, `Notes`. One row per usable action. The four numeric columns are center-aligned; `Bonus` shows an explicit sign on positive values; `Dmg` shows `—` when the action deals no damage. Always rendered — empty actions table is still allowed; the stub renders a single default `Dodge` row when no equipped weapons are found.

5. **Skills** (left column) — section heading `SKILLS`. A table with columns `Name`, `Ranks`, `Dice`, `Bonus`. One row per Skill the Creature has trained. The `Bonus` column shows an explicit sign on positive values. Omitted when the Creature has no trained Skills. The number of trained Skills a Creature is expected to have is derived from the `Skill Pick Formula` in `creatures_config.yaml` against the Creature's Effective Intelligence and the Class's `bonus_skills` field; the section reflects whatever Skills the Creature actually trains.

6. **Spells** (right column) — `SPELLS`. One line per spell tier the Creature has at least one spell in: `Tier <n>. <names, comma-separated>`. The `Tier <n>.` label is italic and uses the Tier Color **of that spell tier** (not the Creature's Tier). Omitted when the Creature has no spells.

7. **Rituals** (right column) — `RITUALS`. Same line format as Spells. Omitted when the Creature has no rituals.

Below the Actions / Skills / Spells / Rituals / Items two-column body the sheet renders a second two-column row holding Abilities and Item Descriptions side by side.

9. **Abilities** (left half of the lower row) — `ABILITIES`. Each granted Ability renders as a collapsible row. By default each row shows only the Ability name (italic, with a trailing affordance such as a chevron or `▸` marker indicating expandability). Clicking the row reveals the description; clicking again hides it. The starting state is **collapsed** for every Ability. State is per-Ability, not section-wide; expanding one row leaves the others alone. The list runs in the order Creatures returns from `get_granted_abilities` (Race → Classes → free abilities). Implementations should use semantic HTML (e.g. `<details>/<summary>`) so the behavior works without JavaScript and is accessible to screen readers.

10. **Item Descriptions** (right half of the lower row) — lists named magic items the Creature carries that have a `metadata.description` set. Format mirrors Abilities: `<Item Name>. <description>` with the item name italic. Omitted when no inventory item carries a `metadata.description`.

## Section visibility

- Skills, Spells, Rituals, Items, Abilities, and Item Descriptions are each omitted when they have no content.
- Actions always renders (a single Dodge row at minimum).
- When the upper-right column is empty (no Spells, no Rituals, no Items) the upper two-column body collapses to single-column for Actions + Skills.
- When the lower row has only one of Abilities or Item Descriptions, that section takes the full width.

## Parameters

Required:
- A Creature ID (or a Creature Accessor). The stub looks up the Creature from the roster.
- Viewer role — `dm` or `player`.

Optional:
- Viewing Player ID. Used by the application to determine the player's identity for visibility filtering done at the parent level.
- `chrome` — boolean, default true. When false, the outer card framing (parchment background, top Tier-Color border, section rules) is suppressed and the stub renders as a bare block suitable for embedding inside a parent stub's wrapper. Parents that compose multiple creature blocks under a shared header pass `chrome = false` to avoid stacked card chrome.
- Detail-mode toggle target — the route the toggle button posts to in order to switch between this stub and `creatures_full_stub.md`. The toggle reads `Show full sheet` while the minimal view is active, is rendered at the **bottom-left** of the card, and visually sits below every other section. The application may persist the last-picked mode in `localStorage` keyed by Creature ID (see `ui_conventions.md`); a `?detail=full` or `?detail=minimal` query parameter on the page URL overrides the stored value when present.

## Visibility

The stub itself does not filter. The parent page is responsible for ensuring the requested Creature is visible to the viewer. When viewer role is `player`, the parent page only renders the stub for Creatures whose `tags` include `player_character`.

## Data sources

The stub composes data from:

- **Creatures domain** — identity, race, classes, Tier, Effective Attributes, Speed, abilities (names), proficiency ranks.
- **Conditions domain** — current HP / Mana / Toxicity.
- **Equipment domain** — equipped / consumable / other items by owner ID `creature:<id>`; item descriptions read from each Stack's `metadata.description`.
- **Abilities domain** — Ability description text. The stub looks each granted-ability name up via `lookup_catalog_ability`; unrecognized names fall back to a Title-Case rendering of the snake_case key with no description body.
- **Proficiencies domain** — Perception's Competency Modifier.
- **Combat config** — Initiative Attribute and Initiative Divisor for the dice count display. The stub does not roll initiative; it shows what the dice count would be on a fresh roll.

Computed values (HP max, Mana max, Toxicity threshold, Initiative, Perception, attack rolls) come from the domain modules and the formulas in their config files. They are not stored anywhere.
