# Android App

A native Android client for Crimson Steel DM Tools. It has its own GUI (not a WebView) and will talk to the Ruby server; for now it runs entirely on built-in dummy data and needs no server.

The Gradle project lives in `android/` and is built by `build_branches.sh` (see the claude-basics repository). Built APKs are committed to `android/versions/`.

## Layout

- The **character name** is always shown at the top of the screen.
- A tab row under it selects one of four screens:
  - **Sheet** — the character sheet.
  - **Initiative** — the Combat Pool, the turn order, and on the player's turn their action options (see *Initiative screen*).
  - **Notes** — game notes; tap a note to expand it.
  - **Scene** — the current scene: title, location, in-game time, description, and who is present.

## Character sheet

Shows vitals (HP, Mana, magic toxicity, Damage Reduction, Damage Resilience), the six Attributes, every Skill, and the character's Abilities.

Rollable entries:

- Each Attribute has a **Check** and a **Save**.
- Each **Skill**.

Dice Count and Bonus are computed with the same rules as the server (see [proficiencies_design.md](../common/proficiencies/proficiencies_design.md) and [dice_resolution_design.md](../common/dice_resolution/dice_resolution_design.md)):

- Attribute Check: Prowess = `floor(attribute / 2)`.
- Save: Prowess = `ranks + floor(attribute / 2)`; never takes the Non-Proficiency Penalty.
- Skill: Prowess = `ranks + floor(attribute / 2)`; an untrained Skill adds the Non-Proficiency Penalty to the bonus (never to the dice).

The full Dice Cap is always rolled from the sheet; only combat actions let the player commit fewer dice.

Abilities are descriptive only (tap to expand) and are not rollable.

## Rolling

1. Tapping a rollable entry asks whether this is a **Public roll** or a **Test roll**.
2. The roll dialog shows d10s tumbling onto the screen and settling on their values, colored by state (Failure red, Success green, Critical Success blue, Neutral plain — the web sheet's colors).
3. The result line shows the Degree of Individual Success, the Roll Outcome, and the Critical Count.

| | Public roll | Test roll |
|---|---|---|
| Sent to the DM's Roll Log | Yes (once connected; offline it is only kept on the device) | Never |
| Can be rolled again from the dialog | No — one roll, like the web sheet's compact roll | Yes |

Once connected, a public roll is sent the same way the web sheet sends one (`POST /dm/roll`).

## Initiative screen

This is the player's half of the web app's Turn Action Stub ([turn_action_stub.md](../common/ui/turn_action_stub.md)): the player picks an action and how many dice to commit. Targets, defenses, rolling and applying the result stay with the DM.

Top to bottom:

1. **Combat Pool** — one small d10 per Combat Pool die. Remaining dice are filled, spent dice are hollow. The fill color depends on how much of the pool is left: more than half green, a quarter to a half amber, under a quarter red. Below it: Main Actions left this turn and Mana.
2. **Initiative order** — the round number and every combatant, with the acting one highlighted. On the player's turn the list compacts to a single row, `<name> (you) — Your turn`; tapping it shows the full list, and *Hide initiative* compacts it again.
3. **Action options** (player's turn only) — grouped under **Main Action**, **Bonus Action** and **Free Action**; an empty group is not shown.

| Option | Group | Dice | Combat Pool cost | Mana |
|---|---|---|---|---|
| Attack: `<weapon>` (one per equipped weapon, plus Unarmed) | Main | 2 up to the Martial Dice Cap | weapon Speed + dice | — |
| Move | Main | — | Move Cost (4) | — |
| Cast: `<spell>` (one per known spell) | Main (or the spell's activation) | Action Minimum (Main 4 / Bonus 2) up to the casting skill's Dice Cap | dice | Mana Cost Per Tier |
| `<Ability>` with a free / bonus / main activation (e.g. Rage) | its activation | — | Action Minimum (Free 0, Bonus 2, Main 4) | the Ability's `mana_cost` |
| End Turn | Free | — | — | — |

Tapping an option opens it: a dice-count picker (counts the pool can't afford are disabled), then **Declare**. Declaring spends the Combat Pool, Mana and (for a Main Action) one of the two Main Actions, and lists the action under *Declared this turn* with an **Undo last** button. An option the player can't currently afford (no Main Actions left, not enough Mana or Combat Pool) is shown dimmed with the reason. **End Turn** asks for confirmation and passes initiative to the next combatant; the Combat Pool is not refilled until the player's next turn begins.

Combat Pool size follows *Combat Pool computation* in [encounter_design.md](../common/encounter/encounter_design.md).

Offline, declared actions stay on the device, and an *Offline test: start my turn* button jumps the initiative back to the player.

## Not yet decided

- How the app finds and connects to the server.
- How a device is assigned to a character, or to the DM (see [device_assignment.md](device_assignment.md)).
- Rerolls and Nudges.
- What the player sees after declaring an action (for example the DM's result).
