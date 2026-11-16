# Android App

A native Android client for Crimson Steel DM Tools. It has its own GUI (not a WebView) and will talk to the Ruby server; for now it runs entirely on built-in dummy data and needs no server.

The Gradle project lives in `android/` and is built by `build_branches.sh` (see the claude-basics repository). Built APKs are committed to `android/versions/`.

## Layout

- The **character name** is always shown at the top of the screen.
- A tab row under it selects one of four screens:
  - **Sheet** — the character sheet.
  - **Initiative** — the current Combat's turn order, the round number, whose turn it is, and which entry is the viewer.
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

The full Dice Cap is always rolled.

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

## Not yet decided

- How the app finds and connects to the server.
- How a device is assigned to a character, or to the DM (see [device_assignment.md](device_assignment.md)).
- Rerolls, Nudges, and choosing to roll fewer dice than the Dice Cap.
