# Initiative Stub (Combat Tracker)

A table titled **Combat Tracker**, one row per Combatant in the active Combat,
ordered by Initiative String descending (ties broken by Combat ID). The Acting
Combatant's row is emphasized (yellow background, bold initiative, a `▶` in the
turn-control cell instead of `Set`). The GM uses it to track whose turn it is,
read HP and Combat Pool at a glance, and spot Combatants who need intervention.

Rendered by the Encounter page directly beneath the Timekeeping stub, with the
combat action controls (`../combat`) directly below it for the Acting Combatant.

## Columns

Left to right:

1. **Turn control** — `▶` on the acting row (read-only); `Set` on every other
   row, which makes that Combatant the Acting Combatant (the GM override for
   out-of-band turn changes).
2. **Initiative** — the Combatant's Initiative String.
3. **Name** — resolved via Creatures' *Look up Creature*, falling back to a
   stored `name`, then `Creature #<id>`.
4. **HP** — a bar with up to four proportional segments (green current, light-red
   Minor, red Moderate, dark-red Major) over the Creature's Max HP, plus a
   `<current>/<max>` line that appends `<n> Mod` / `<n> Maj` when non-zero.
5. **Mana** — `<remaining>/<max>` + bar (`max − mana_spent`).
6. **Combat Pool** — `<remaining>/<max>`; max via *Get Combat Pool*.
7. **Magic Toxicity** — Conditions' `magic_toxicity`, color-ramped toward the
   Toxicity Threshold.
8. **Conditions** — colored badges: `<n> Shock`, `<n> Pain` (the tracker's term
   for the Acid Counter), `Bleed: <potency>`, `Poison: <potency>`, `Major: <n>`,
   and any other Active Effect. Each badge has a DM-only `×` that calls the
   matching Conditions removal entry point.
9. **Ability Damage** — one chip per `(attribute, severity)` in Conditions'
   `ability_damage` (e.g. `Str Minor 2`).

A row whose Combatant returns false from Conditions' *Creature Can Act?* gets a
red background — the GM may need to act for it. The flag is presentation-only;
the tracker never mutates combat state.

## Killed Combatants

A second table beneath the tracker lists every Combatant whose Creature is Dead
(Conditions' *Dead?*), with **Name** and **Cause** (a short summary the host
supplies). Hidden when the host passes `show_killed = false`.

## PC roster panel

A DM-only panel with a checkbox per Player Character (Creatures tagged
`player_character`); checked = in combat (the inverse of `excluded_pcs`).
Toggling POSTs the new set to *Set PC Exclusions*. It persists across fights.

## Page-level controls

Below the table (page chrome, not part of the tracker proper):

- **Next Turn** — *Advance Turn*; advances to the next Combatant, rolling the
  Round over when the last one ends their turn.
- **Reroll Initiative** — *Reroll Initiative*.
- **Start Combat** / **End Combat** — shown by combat state (mutually exclusive).
- **DM Luck Points** — a read-only total of the GM's Luck pool.

## Indicators and visibility

- **Acting Combatant** — the row matching `acting_combatant_id` is emphasized;
  when there is no active Combatant (before the first Reroll Initiative, or
  after End Combat) no row carries the indicator.
- **Visibility** — rendered for the DM always; for players only while
  `combat_active?`.
- **Scene embed** — when embedded in a scene rather than the Combat page, the
  host passes a read-only flag (suppresses `Set`, badge `×`, inline edits) and
  may pass a name-masking flag that renders non-PC names as `DM` to players.

## Roster ownership

The Combatant roster is owned by the combat-state domain; the tracker only
displays it. New Combatants are added elsewhere (the roster sidebar, a Random
Encounter roll, the PC roster checkboxes); every successful add surfaces on the
next render.
