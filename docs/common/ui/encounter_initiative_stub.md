# Encounter Initiative Stub

A widget that surfaces the Combatant roster on the Encounter page. First-pass version of the Combat Tracker described in `combat_initiative_stub.md`; renders only the columns whose data is available today (Initiative, Name) and grows as the Conditions, Creatures (vitals), and Combat-mode accessors land.

See `ui_conventions.md` for shared rules.

## Layout

A section titled **Combat Tracker** that sits beneath the Timekeeping Stub on `/encounter`.

The header carries a single DM-only control on its right edge:

- When Combat is **not active**, a `Start Combat` button. Submitting it POSTs `/encounter/start_combat`, which calls *Start Combat* on the Encounter domain and reloads the page.
- When Combat is **active**, an `End Combat` button. Submitting it POSTs `/encounter/end_combat`, which calls *End Combat* on the Encounter domain and reloads the page.

Below the header, a table with one row per Combatant in the active Encounter, in roster order (the eventual order will be by Initiative String descending, ties broken by Combat ID — initiative rolling lands in a later pass).

Columns:

1. **Initiative** — the Combatant's Initiative String. Currently always `—` until Reroll Initiative is wired in.
2. **Name** — the Combatant's display name. Looked up via `Creatures.lookup(creature_id)`; falls back to the stored `name` override on the Combatant, then to `Creature #<id>`.

The row representing the Acting Combatant carries an `initiative-row-acting` class for the host's CSS to highlight.

When the Combatant roster is empty, the table is replaced with the inline message **No combatants in the encounter yet.**

## Visibility

The stub is rendered for the DM at all times. Player viewers see the stub only when Combat is active (`Encounter.state.combat_active?` is true). The Encounter page's host template guards rendering accordingly.

## Parameters

Required:
- `rows` — list of `{ combatant_id, creature_id, name, initiative, acting }`.
- `combat_active` — boolean. Drives the Start/End Combat button label and the `data-combat-active` attribute on the section.
- `viewer` — `:dm` or `:player`. Determines whether the Start/End Combat button renders.

## Composition

Embedded by `views/encounter.erb` directly below the Timekeeping Stub. Not embedded in other stubs.

## Mutations and the roster

- The Combatant roster is owned by the Encounter domain. New Combatants are added through `creatures_roster_sidebar_stub.md`'s `+` button, the `Roll` button on a Random Encounter Table row, or the Active/Absent toggles for Players and NPCs. Every successful add immediately surfaces in the next render of this stub.
- The stub does not mutate the roster itself. Removing a Combatant happens from the Roster Sidebar (`−` button) or from Player/NPC Active/Absent toggles, not from this widget.
- Initiative rolling, per-turn HP/Mana/Combat Pool readouts, and Condition badges are deferred; the columns describing them in `combat_initiative_stub.md` will land here as their owning domains expose the needed reads.

## What this stub does not do

- It does not roll Initiative — the `Initiative` column is a placeholder until Encounter's *Reroll Initiative* entry point lands.
- It does not advance the turn or set the Acting Combatant directly.
- It does not show HP, Mana, Combat Pool, Toxicity, Conditions, or Ability Damage — those columns ship when their owning domains are wired up. See `combat_initiative_stub.md` for the eventual full layout.
- It does not handle the post-combat Killed Combatants table; that lands with Conditions' *Dead?* surfacing and the loot pipeline.
