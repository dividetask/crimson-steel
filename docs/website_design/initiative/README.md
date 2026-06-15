# Initiative Stub

The **Initiative Stub** (the *Combat Tracker*) shows every Combatant in the
active Combat in initiative order, with at-a-glance vitals and the turn
indicator. On `/encounter` it sits **above** the combat action controls
(`../combat`), which drive whichever Combatant the tracker marks as acting.

The DM sees it at all times; player viewers see it only while a Combat is
active. It is read-only display plus the turn-management controls (Next Turn,
Reroll Initiative, Start / End Combat, PC roster).

## Contents

- [`initiative_stub.md`](initiative_stub.md) — the tracker's layout, columns,
  killed-combatants table, PC roster, page controls, and indicators.
- [`required_interfaces.md`](required_interfaces.md) — the partial stub the
  tracker needs from each other domain (Creatures, Conditions, and the combat
  state / turn order).

Design document; not rendered in the Compendium.
