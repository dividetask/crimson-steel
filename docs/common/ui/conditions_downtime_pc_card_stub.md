# Conditions Downtime PC Card Stub

A per-Creature health card showing a player-character Creature's current Conditions State plus the Consumable Items they carry. Used on the downtime page (between Combats).

See `ui_conventions.md` for shared rules.

## Layout

A card with the following blocks, stacked:

1. **Header** — Creature name, Race + Class summary, Tier. Name uses the Tier Color per `ui_conventions.md`.
2. **HP bar** — a four-segment bar mirroring the convention used in `creatures_minimal_stub.md`: a green Current-HP segment plus three colored damage segments for Minor / Moderate / Major HP Damage (light red, red, dark red). Below the bar: `<current> / <max>`. When a Temporary HP grant is active, `+<amount> temp HP` is appended.
3. **Mana bar** — a single-segment bar showing `current / max` Mana (Current Mana derived per `conditions_design.md` as `mana_max - mana_spent`).
4. **Magic Toxicity bar** — current value relative to the Creature's Toxicity Threshold, with a green-to-red color ramp. Threshold is computed by the parent page from the Creature's Charisma and Tier per the *Toxicity Threshold* formula in `conditions_design.md`. When current Magic Toxicity is strictly above the Threshold, the bar surfaces a visual cue indicating that `positive`-kind Toxicity sources will be blocked.
5. **Active Effects** — colored badges, one per non-Modifier Active Effect targeting the Creature. Each badge shows the effect name (e.g. `Paralyzed`, `Frightened`) — looked up by the parent page from the Effect Names catalog. Modifier-shaped Active Effects are not surfaced here; they roll into the numeric attribute / derived-stat displays elsewhere on the card.
6. **Ability Damage** — flat list of `<attr> · <severity> · <count>` chips for each non-zero entry in `ability_damage` (per `conditions_design.md`). One chip per (attribute, severity) pair with positive damage.
7. **Active Afflictions** — one row per entry in `afflictions`: the Affliction name, current Potency, Inflicter Tier, and the `next_resolution_round` (rendered as `R<n>` or `—` when null). The list runs in insertion order.
8. **Consumables** — list of Equipment Stacks in the Creature's Inventory whose Item Type Category is `Consumable` (per `equipment_design.md`). Each row shows the Generated Display Name (or `name_override`), Tier, and Quantity. Clicking a row opens the Use-Item form (see below).

## Parameters

Required:
- A Creature ID. The stub reads the Creature record via Creatures' *Look up Creature*, the Conditions State via the Conditions domain (`hp_damage`, `temporary_hit_points`, `mana_spent`, `magic_toxicity`, `effects`, `afflictions`, `ability_damage`), and the Inventory via Equipment's *Get Inventory* against `creature:<id>`.
- Viewer role — `dm` or `player`.

Optional:
- `chrome` — boolean, default true. When false, the outer card framing is suppressed so the card can stack inside a parent stub's wrapper.

## Use-Item action

Clicking a Consumable opens a small inline form:

- Target dropdown — every Creature visible to the viewer.
- Submit — emits a `consume_item` event carrying the Consumer Owner ID, the Stack reference, and the chosen target Creature ID.

The parent page resolves the event by calling Equipment's *Consume Item* with a caller-computed Toxicity Threshold for the target (read by combining the target's Charisma and Tier through the formula in `conditions_design.md`). Equipment routes Heal, Mana, and Temporary HP effects through Conditions and applies Magic Toxicity per the *Item-Form Toxicity* rules in `equipment_design.md`.

## DM-only

The DM sees every PC card in a grid. Player viewers see only their own card; the parent page is responsible for filtering. The card itself does not gate on viewer role.

## Composition

The downtime page embeds one card per player-character Creature in a grid. The card has no batched-action affordance — each Use-Item form submits independently.

## What this stub does not do

- It does not apply or remove Effects. Use-Item, dismiss, and recovery flows are resolved by the parent page through Equipment and Conditions.
- It does not advance time. Natural Recovery is the parent page's responsibility via Conditions' *Apply Natural Recovery*; this card displays the post-recovery state.
- It does not roll Affliction saves. Per-Affliction resolution is surfaced by `conditions_urgent_actions_stub.md`.
