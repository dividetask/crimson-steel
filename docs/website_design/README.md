# Website Design

Developer-facing design notes for the Crimson Steel DM Tools site: UI details,
page and route behavior, JavaScript, and the Ruby classes behind each feature.

These documents describe **how the site implements the rules** — they reference
the player-facing rules under [`../common`](../common) rather than restating
them. In particular:

- They **do not rewrite** formulas that already live in a domain's design docs
  or config. They point at the canonical definition and say which files
  implement it.
- They **may define computations that the rule docs do not specify** — internal
  values that never surface to players.

## DM-only, surfaced in the Compendium

Unlike the player-facing chapters under `docs/common/**`, these documents are
**DM-only**. A subset of them is surfaced in the Compendium as DM-only entries
(see [`../project/compendium.md`](../project/compendium.md)): the DM sees them in
the left nav while playing so they can inspect how a stub is defined and what it
relies on; players never see them, and a player who requests one of these
`?view=` keys is treated as if the page did not exist.

Because these pages are DM-only reference material, they may carry **developer
directives and notes** that are stripped from the rendered page but kept in the
source file — `@function` declaration lines and fenced ` ```test ` blocks (worked
sample data / cases). See the renderer notes in
[`../project/compendium.md`](../project/compendium.md).

## Contents

- [`combat/`](combat/README.md) — the combat feature, split into the **Combat
  Encounter Stub** (the turn) and the domain-agnostic **Action Builder** it
  calls, plus the cross-domain interfaces they rely on and a worked example of
  the Action Builder blob.
