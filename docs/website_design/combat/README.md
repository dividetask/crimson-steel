# Combat Encounter Stub

The Combat Encounter Stub is the Game Master's surface for **taking actions** in
a fight on `/encounter` — attack, move, cast a spell, use an item or special
ability, end the turn. It is **DM-only** and composes two pieces:

1. **Turn Action panel** — drives the Acting Combatant's turn: start-of-turn
   saves, then the action menu (Attack, Move, Cast, Item, Special, End Turn).
   (`combat_encounter_stub.md` → *Turn Action panel*)
2. **Action Builder** — a domain-agnostic wizard that composes one action
   (target, dice, defense, luck) and then mounts the Check Resolution roll
   table to roll it. (`combat_encounter_stub.md` → *Action Builder*)

It renders directly below the **Initiative Stub** (the Combat Tracker, which
shows turn order and vitals) and acts on whichever Combatant that tracker marks
as acting. The tracker is documented separately in
[`../initiative`](../initiative/README.md).

## Why this lives in `website_design`

The combat stub is the **integration point** where the rules domains meet. It
does almost no rules math itself — it gathers the GM's choices, asks the
**Check Resolution** roll to resolve them, routes the result through
**Damage**, and writes the outcome through **Conditions**. As the project
splits into one branch per domain, this folder pins down **exactly what the
combat stub expects from each other domain** so the branches stay compatible.

Those expectations are the partial stubs in
[`required_interfaces.md`](required_interfaces.md): one section per domain
(Check Resolution, Damage, Conditions, Afflictions, Creatures, Proficiencies,
Equipment, Abilities). Each section is the slice of that domain the combat stub
calls — the contract the domain's own branch must satisfy.

## Contents

- [`combat_encounter_stub.md`](combat_encounter_stub.md) — the stub's UI and
  behavior: the Combat Tracker, the Turn Action panel and its action panes,
  and the Action Builder wizard.
- [`required_interfaces.md`](required_interfaces.md) — the partial stub the
  combat stub requires from each other domain.

## Cross-references

- Player-facing rules: [`../../game_rules/check_resolution`](../../game_rules/check_resolution/check_resolution_overview.md)
  and [`../../game_rules/damage`](../../game_rules/damage/damage_overview.md).
- This is a design document, not player content — it is **not** rendered in the
  Compendium (see [`../README.md`](../README.md)).
