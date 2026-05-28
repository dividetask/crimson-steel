# Combat Initiative Stub

A widget that shows the Combatants in the active Combat in initiative order, with the Acting Combatant highlighted. The Game Master uses it to track whose turn it is, see at-a-glance HP and Combat Pool, and spot Combatants who need intervention.

See `ui_conventions.md` for shared rules.

## Layout

A table titled **Combat Tracker** with one row per Combatant in the active Combat. The row order is by Initiative String, descending — ties broken by Combat ID, as in Combat's *Advance Turn*.

Columns, left to right:

1. **Turn control** — a single-cell button.
   - The Acting Combatant row shows a `▶` indicator (read-only; advancing the turn happens via the page-level Advance Turn control).
   - Every other row shows a `Set` button. Clicking it makes that Combatant the Acting Combatant (i.e. sets `acting_combatant_id` directly). This is the GM override for out-of-band turn changes.
2. **Initiative** — the Combatant's Initiative String. The acting row's value is bolded and tinted to make the current turn obvious.
3. **Name** — the Combatant's display name. Looked up via `creature_lookup(creature_id)`; falls back to any stored `name` override, then to the Creature ID as a last resort.
4. **HP** — a horizontal HP bar plus a numeric breakdown line.
   - The bar has up to four colored segments rendered left-to-right: **green** (current HP), **light red** (Minor damage), **red** (Moderate damage), **dark red** (Major damage). Widths are proportional to the Creature's Max HP.
   - The numeric line reads `<current>/<max>` and, when non-zero, appends `<n> Mod` for Moderate damage and `<n> Maj` for Major damage. Minor damage is folded into the bar only — no numeric annotation — because it heals out fastest.
5. **Mana** — `<remaining>/<max>` plus a thin horizontal bar. Max is the Creature's Max Mana from the Creatures domain; remaining is `max − mana_spent` from Conditions.
6. **Combat Pool** — `<remaining>/<max>`. Max is computed on demand via Combat's *Get Combat Pool*; remaining is the stored `combat_pool_remaining`.
7. **Magic Toxicity** — the Creature's `magic_toxicity` counter from Conditions, displayed with a color ramp (green at zero, ramping toward red as the value approaches and exceeds the Toxicity Threshold). The threshold itself is computed via the Conditions formula using the Creature's Charisma and Tier.
8. **Conditions** — colored badges, one per active effect or counter, in a horizontal row.
   - **Shock**: `<n> Shock` — blue badge.
   - **Pain / Acid**: `<n> Pain` — solid red badge (the project's term for Acid Counter on the tracker; the underlying counter is Conditions' `acid_counter`).
   - **Bleed**: `Bleed: <potency>` — pink badge. (Bleeding is an Active Affliction; the badge reads the Affliction's Potency.)
   - **Poison**: `Poison: <potency>` — green badge. (Affliction badge — any catalog entry tagged as poison.)
   - **Major**: `Major: <n>` — dark red badge. (Appears when major HP damage is non-zero; mirrors the bar's dark-red segment textually for quick scanning.)
   - Other Active Effects from Conditions may render as additional badges; color choice is documented per badge type in the project's CSS rather than hard-coded here.
   - Each badge carries a small `×` dismiss affordance (DM-only). Clicking it emits a remove-effect event the parent handles by calling the appropriate Conditions entry point (e.g. *Remove Active Effect*, *Remove Active Affliction*, or the counter-clearing call).
9. **Ability Damage** — a flat row of small chips, one per `(attribute, severity)` entry in the Creature's `ability_damage` map from Conditions. Each chip reads `<attr> <severity> <n>` (e.g. `Str Minor 2`). Chips for the same attribute across Severities render side by side. Empty when the Creature has no Ability Damage.

A row whose Combatant returns false from *Creature Can Act?* is rendered with a red row background — the GM may need to act on their behalf.

### Killed combatants

A second table titled **Killed Combatants** renders directly beneath the main tracker. It lists every Combatant whose Creature is Dead (per Conditions' *Dead?*), with two columns: **Name** and **Cause** (a short string summarizing how the Combatant died — typically the last damage entry from the Combatant's log, supplied by the parent). The killed-combatants table is hidden when the parent passes `show_killed = false`.

## Below the table — page-level controls

The page that hosts this stub places these controls below the table (they are page chrome, not part of the stub):

- **Advance Turn** — POSTs to `/combat/advance_turn`.
- **Reroll Initiative** — POSTs to `/combat/reroll_initiative`.
- **End Combat** — POSTs to `/combat/end`.
- **DM Luck Points** — a read-only display of the GM's current Luck Points pool (read from Combat State's `dm_luck_points`). Shown only to the GM. Spent via the Luck stage of the turn action panel; this control surfaces only the running total.

The turn-action panel (see `turn_action_stub.md`) renders directly below the Combat Tracker when a turn is active.

## PC roster panel

A second small panel beneath the tracker — visible only to the GM — lists every Player Character on the roster (every Creature whose `tags` include `player_character`) with a checkbox per PC. The checkbox state is the inverse of `excluded_pcs` membership: checked = "in combat", unchecked = "sitting out".

Toggling a checkbox POSTs the new exclusion set to `/combat/set_pc_exclusions`, which calls Combat's *Set PC Exclusions*. When unchecking a PC who is currently a Combatant, the entry point also removes them from the roster; when checking a previously-excluded PC, the consuming page's render-time reconciliation re-adds them via *Add Combatant* on the next render.

The panel persists between fights — it shows the same set whether a Combat is active or not — because `excluded_pcs` itself survives *End Combat*.

## Parameters

Required:
- The Combat State — list of Combatants, `acting_combatant_id`, `time_tick`, `time_ticks_per_round`.

Optional:
- `creature_lookup` — defaults to the Creatures domain's *Look up Creature*.
- `conditions_lookup` — defaults to the Conditions domain. Used to populate the HP segments and the condition badges.

## Cannot-act highlight

A Combatant whose turn has been skipped by *Advance Turn* — i.e., one for whom *Creature Can Act?* returns false (Dead, Dying, or affected by a "cannot act" condition) — is shown with a red row background. The row is still listed in initiative order; the highlight signals to the GM that the Combatant's turn was skipped automatically and that they may need to act on the Combatant's behalf.

The stub queries *Creature Can Act?* for each Combatant when rendering. The result is presentation-only — the stub does not call *Advance Turn* or otherwise mutate Combat state.

## Embedded in a scene

When the Combat Tracker is embedded inside a scene page (rather than rendered on its own Combat page), the parent passes a flag that makes the table read-only — the `Set` buttons, badge dismiss affordances, and any inline-edit inputs are suppressed. The GM still uses the dedicated Combat page for actual management; the scene embed is informational.

In the embedded scene context the parent may also pass a name-masking flag. When set and the viewer role is `player`, non-`player_character` Combatant names render as `DM` in the Name column so the player cannot see hidden Combatants' identities. The GM viewer always sees the real names regardless of the flag.

## Acting Combatant indicator

The row whose `combat_id` matches `acting_combatant_id` is visually emphasized — yellow row background, `▶` instead of `Set` in the Turn Control column, and a bold Initiative String. When the Combat State has no active Combatant (e.g. before the first *Reroll Initiative*, or after *End Combat*), no row carries the indicator.
