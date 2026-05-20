# Combat Initiative Stub

A widget that shows the Combatants in the active Combat in initiative order, with the Acting Combatant highlighted. The Game Master uses it to track whose turn it is and to spot Combatants who need intervention (those who cannot act on their own).

See `ui_conventions.md` for shared rules.

## Layout

A vertical list of rows, one per Combatant in the active Combat. Each row is keyed by Combat ID. The list is ordered by Initiative String, descending — ties broken by Combat ID as in Combat's *Advance Turn*.

Each row displays:

- The Combatant's display name.
- The Combatant's Initiative String.
- A turn indicator on the row whose `combat_id` matches `acting_combatant_id`.
- A status indicator when the Combatant cannot act (see **Cannot-act highlight** below).

The list has no interactive elements by default — clicking a row may open the Combatant's full stub, but that's the parent application's choice.

## Parameters

Required:
- The Combat State — the list of Combatants and the current `acting_combatant_id`.
- A `creature_lookup` callback so the stub can resolve display names from each Combatant's `creature_id` when not already on the Combatant record.

## Cannot-act highlight

A Combatant whose turn has been skipped by *Advance Turn* — i.e., one for whom *Creature Can Act?* returns false (Dead, Dying, or affected by a "cannot act" condition) — is shown with a red row background. The row is still listed in initiative order; the highlight signals to the GM that the Combatant's turn was skipped automatically and that they may need to act on the Combatant's behalf (drag the body, stabilize them, etc.).

The stub queries *Creature Can Act?* for each Combatant when rendering. The result is presentation-only — the stub does not call *Advance Turn* or otherwise mutate Combat state.

## Acting Combatant indicator

The row whose `combat_id` matches `acting_combatant_id` is visually emphasized — for example a left-edge arrow, a brighter background, or a bold label. The exact treatment is an implementation choice; the convention is only that the indicator is unmistakable at a glance.

When the Combat State has no active Combatant (e.g., before the first *Reroll Initiative*, or after *End Combat*), no row carries the Acting Combatant indicator.
