# Combat Encounter Stub

The Game Master's surface for **taking actions** in a fight on `/encounter` —
attack, move, cast a spell, use an item or special ability, end the turn. It is
**DM-only** and is split into two stubs:

1. **Combat Encounter Stub** (`combat_encounter_stub.md`) — drives the Acting
   Combatant's **turn**: header resources, automatic start-of-turn bookkeeping,
   and start-of-turn Affliction saves. When the DM acts, it **calls the Action
   Builder** (passing the current Combatant and the active Combatant list) and
   **applies the confirmed action** by routing the outcome through the other
   domains.
2. **Action Builder** (`action_builder_stub.md`) — a **domain-agnostic,
   parameter-driven** wizard (`public/js/ui/actionBuilder.js`) that composes one
   action (target, dice, defence, luck) and mounts the Check Resolution roll
   table to roll it. It walks a precomputed `{ rolls, steps }` blob, applies each
   option's `patch` to the seed rolls, computes no rules, and emits a single
   `action:confirmed` for its host to apply. The same wizard serves Affliction
   saves, attacks, casts, and any future Check.

The Combat Encounter Stub renders directly below the **Combat Tracker** (the
Initiative Stub, which shows turn order and vitals) and acts on whichever
Combatant that tracker marks as acting. The tracker is documented separately
with its own stub.

## Why this lives in `website_design`

The combat stub is the **integration point** where the rules domains meet. It
does almost no rules math itself — it gathers the GM's choices, asks the
**Check Resolution** roll to resolve them, routes the result through **Damage**,
and writes the outcome through **Conditions**. This folder pins down **exactly
what the combat stub expects from each other domain** so the domains stay
compatible.

Those expectations are the partial stubs in
[`required_interfaces.md`](required_interfaces.md): one section per domain
(Check Resolution, Damage, Conditions, Afflictions, Creatures, Proficiencies,
Equipment, Abilities). Each section is the slice of that domain the combat stub
calls — the contract the domain must satisfy.

## Contents

The files below are each surfaced as a **DM-only Compendium entry** (see
[`../../project/compendium.md`](../../project/compendium.md)):

- [`combat_encounter_stub.md`](combat_encounter_stub.md) — the turn lifecycle:
  header resources, start-of-turn bookkeeping, Affliction saves, calling the
  Action Builder, and applying the confirmed action. *(Compendium: **Combat**.)*
- [`action_builder_stub.md`](action_builder_stub.md) — the domain-agnostic
  action-composition wizard (`public/js/ui/actionBuilder.js`): the
  `{ rolls, steps }` blob it reads, how a step applies its `patch`, what it defers
  to Check Resolution, and the `action:confirmed` contract.
  *(Compendium: **Action Builder**.)*
- [`required_interfaces.md`](required_interfaces.md) — the partial stub the
  combat feature requires from each other domain. *(Compendium: **Combat —
  Interfaces**.)*
- [`test_data.md`](test_data.md) — a worked example of the Action Builder blob
  (built live by the `*_builder_blob` helpers, not a standalone dummy file).
  *(Compendium: **Combat — Test Data**.)*

## Cross-references

- Player-facing rules live under [`../../common`](../../common) — Check
  Resolution and Conditions in particular. In the Compendium, the player-facing
  Check Resolution and Conditions chapters are the canonical companions.
- This is a design document, not player content — it is **DM-only** (see
  [`../README.md`](../README.md)).
