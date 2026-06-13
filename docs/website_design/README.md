# Website Design

Developer-facing design notes for the Crimson Steel DM Tools site: UI details,
page and route behavior, JavaScript, and the Ruby classes behind each feature.

These documents describe **how the site implements the rules** — they reference
the player-facing rules in [`../game_rules`](../game_rules) rather than
restating them. In particular:

- They **do not rewrite** formulas that already live in a chapter's
  `<chapter>_config.yaml` (e.g. Dice Cap, Starting Value, Check Target Number).
  They point at the canonical definition and say which files implement it.
- They **may define formulas that `game_rules` does not specify** — internal
  computations that never surface to players (for example, the same-type
  stacking that produces the Dice Modifier).

Unlike the chapters under `game_rules`, these documents are **not** rendered in
the Compendium; they are reference material for whoever is building the site.

## Contents

- [`compendium.md`](compendium.md) — the Compendium rules browser: nav,
  markup, keyword popups, formula/variable injection, and the renderer.
- [`check_resolution.md`](check_resolution.md) — where the Check Resolution
  formulas are implemented, plus the internal formulas `game_rules` leaves out.
