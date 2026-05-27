# Conditions Downtime PC Card Stub

A per-Creature health card showing a player-character Creature's current Conditions State plus the Consumable Items they carry. Used on the downtime page (between Combats).

See `ui_conventions.md` for shared rules. Cross-domain terms (Magic Toxicity, Toxicity Threshold, Tier) are defined in `../common_glossary.md`.

## Layout

A compact card. Cards arrange in a grid three across; each card holds approximately a third of the page's content width. The card's blocks stack top to bottom:

1. **Header** — Creature name styled in the Tier Color per `ui_conventions.md`, then a small subtitle line of `Race Class · Tier N`.

2. **HP bar** — a four-segment bar: a green Current-HP segment plus three damage segments for Minor / Moderate / Major HP Damage (light red, red, crimson). The bar is followed by `<current> / <max>`.

3. **Mana bar** — a single-segment bar showing `current / max` Mana (Current Mana derived per `conditions_design.md` as `mana_max - mana_spent`).

4. **Toxicity bar** — current Magic Toxicity relative to the Creature's Toxicity Threshold, with a green-to-red rainbow color ramp (green → yellow → orange → red). Threshold is computed by the parent page from the Creature's Charisma and Tier per the *Toxicity Threshold* formula in `conditions_design.md`. When current Magic Toxicity is strictly above the Threshold, the bar carries a visual cue indicating that `positive`-kind Toxicity sources will be blocked.

5. **Inline numeric rows** — `Temp HP`, `Moderate Dmg`, `Major Dmg`. Each row appears only when its value is positive. The Moderate Dmg row is tinted red; the Major Dmg row is tinted crimson. Minor HP Damage is **not** surfaced as a row — it is already visible as the light-red segment of the HP bar.

6. **Ability Damage** — a tinted row per non-zero entry in `ability_damage` (`<Severity> <ATTR> Damage`). Tinted by Severity (Minor = yellow, Moderate = red, Major = crimson). The block is omitted when there is no Ability Damage.

7. **Active effects** — colored badges, one per distinct non-Modifier Active Effect targeting the Creature. Each badge shows the effect name (e.g. `paralyzed`, `frightened`). Modifier-shaped Active Effects are not surfaced here. The block is omitted when there are no non-Modifier Effects.

8. **Afflictions** — a small table with the header row `Affliction | Potency`. One row per Active Affliction in insertion order. The Affliction name is plain text; the Potency cell is styled in the Tier Color of the Inflicter Tier (Tier Color mapping per `ui_conventions.md`). The Inflicter Tier number itself is not written out — the Potency cell's color carries it. The block is omitted when the Creature carries no Afflictions.

9. **Healing items** — a bulleted list of Equipment Stacks in the Creature's Inventory whose Item Type Category is `Consumable` (per `equipment_design.md`). Each row shows the Generated Display Name (or `name_override`) and Quantity; the item text is styled in the Tier Color of the item's Tier. Clicking a row opens the Use-Item form (see below). The block is omitted when the Creature carries no Consumables.

Empty blocks are not rendered — a Creature at full health with no Afflictions, no Effects, and no Consumables shows only the header and the three bars.

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

The downtime page embeds one card per player-character Creature in a three-column grid. The card has no batched-action affordance — each Use-Item form submits independently.

## What this stub does not do

- It does not apply or remove Effects. Use-Item, dismiss, and recovery flows are resolved by the parent page through Equipment and Conditions.
- It does not advance time. Natural Recovery is the parent page's responsibility via Conditions' *Apply Natural Recovery*; this card displays the post-recovery state.
- It does not roll Affliction saves. Pending Affliction resolution is owned by the parent page; this card displays the current Conditions state only.
