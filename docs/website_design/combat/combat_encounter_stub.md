# Combat Encounter Stub

The DM's surface for running a fight on `/encounter`. It owns the **turn** —
the header resources, the automatic start-of-turn bookkeeping, and the
start-of-turn Affliction saves — and it is the **host** that lets the Acting
Combatant take an action by mounting the [Action Builder](/compendium?view=action_builder).

The Combat Encounter stub does almost no rules math itself. It drives the turn,
hands action-building off to the Action Builder, and **applies the confirmed
action** by routing the outcome through the other domains. Those cross-domain
calls are listed in [Combat — Interfaces](/compendium?view=combat_interfaces);
the dummy data that drives this page is in
[Combat — Test Data](/compendium?view=combat_test_data).

---

## The turn

### Header and resources

`<Combatant Name>'s Turn`, with an optional `(Incapacitated)` / `(Dead)` suffix
from Conditions' *Creature Can Act?* / *Dead?*. Beside it: **Mana** remaining,
**Combat Pool** remaining (`Get Combat Pool − combat_pool_spent`), and **Main
Actions** left this turn.

### Turn start (automatic)

When the turn passes to a Combatant, its turn begins server-side with no DM
input: the **Combat Pool refills** to full, **two Main Actions** are granted
(`MAIN_ACTIONS_PER_TURN`; the cap is tracked, not enforced), **expired Active
Effects** clear (Conditions) and the Combatant's timed spell Zones expire.

### Afflictions due this round

The turn opens with one **Save Resolution** per Affliction the **Afflictions**
domain reports as due, built from the save data it supplies (the Creature, the
Affliction rule + Potency, the Dice Cap, the Target Number). Each save is itself
an [Action Builder](/compendium?view=action_builder) invocation — a one-step
roll — so the DM rolls and confirms it the same way as any other action; the
result goes back to Afflictions' *Resolve Affliction*. See
[Combat — Interfaces](/compendium?view=combat_interfaces) → *Afflictions*.

---

## Taking an action — the Action Builder

The Action Builder is a **domain-agnostic** wizard: it renders whatever blob it
is handed and computes no rules (see
[Action Builder](/compendium?view=action_builder)). Combat is the **host** that
does the combat-specific work on both sides of it.

**Building the blob.** When the DM picks an action, the `/encounter` route builds
the wizard's blob from live combat state via a `*_builder_blob` helper — one per
action kind: `attack_builder_blob`, `cast_builder_blob`, `item_builder_blob`,
`special_builder_blob`, `roll_table_builder_blob` (in `lib/routes/encounter.rb`
with the step machinery in `encounter_attack_ui.rb` / `encounter_cast_ui.rb` /
`encounter_special.rb` / `encounter_reactions.rb`). This is where every combat
rule is resolved into the wizard's plain `steps` + `rolls` + option `patch`es:
the seed rolls (attacker vs target), the weapon / dice options and their pool
costs, each target's eligible defenses, the Luck sources, and the typed
bonus/penalty lists (`set_bpl`) that Check Resolution later stacks.

**Applying the result.** The client-side host (`turnAttack.js`, `turnCast.js`,
`turnItem.js`, `turnSpecial.js`, `turnRollTable.js`) listens for the single
`action:confirmed` event the wizard emits (`{ choices, rolls: [{ id, side,
successes, crits, dice_count, speed }], noRoll, auto }`) and applies the result
below. Confirm is multi-stage — a first Confirm previews (and, for a weapon with
Damage Riders, runs the rider roll), a final Confirm commits — so nothing touches
the game until the DM commits. A worked example of an actual blob is in
[Combat — Test Data](/compendium?view=combat_test_data).

## Applying a confirmed action

On a confirmed action the stub spends the Combat Pool (`Speed + dice`; saving
throws and no-roll buffs cost none) and routes the outcome — never computing
rules itself:

- **Attack / Active Spells** — net Supporting − Opposing successes, recompute the
  weapon damage, apply **Ascendancy Damage Reduction**, and route positive
  damage through the Damage domain's *Apply Damage*; Bleed / Poison inflict
  through Afflictions.
- **Cast / Item** — the **Abilities** domain resolves the spell's Effects;
  Conditions takes Mana (*Apply Mana Cost*; Item spends none), Magic Toxicity
  (*Apply Magic Toxicity*, gated by the Toxicity Threshold; a Potion adds
  Item-Form Toxicity), and any heal / Temporary HP / mana / Active Effect; damage
  routes through the Damage domain; a sustained spell registers a Concentration /
  Long Cast entry and an area spell drops a Zone on the Map. An Item decrements
  its charge.
- **Move** — spends the Move Cost and one Main Action.
- **Special** — debits `mana_cost`; a named-effect applies via Conditions' *Apply
  Named Effect*, a channel fills its Reservoir, anything else is reported for the
  DM to adjudicate.
- **End Turn** — *Advance Turn* (per-turn cleanup on the outgoing Combatant, then
  the next Combatant's automatic turn start; a Round wrap also runs per-round
  cleanup and advances the Chronicle timestamp). The **Next Turn** button itself
  lives on the Combat Tracker (the Initiative Stub), documented separately.

## Behavior notes

- Only a confirmed action POSTs back; everything up to Commit is client-side.
- **DM Luck Points** are a Combat-level pool, persisting until *End Combat*.

## Required interfaces

Everything above that reaches outside this stub is enumerated, per domain, in
[Combat — Interfaces](/compendium?view=combat_interfaces). The Combat Tracker's
own dependencies live with the Initiative Stub, documented separately.

```test
# Developer note (stripped from the rendered page, kept in source):
# The Combat host is the ONLY place that interprets action:confirmed and routes
# to Damage / Conditions. The Action Builder must stay unaware of those domains.
todo:
  - wire action:confirmed → outcome routing
  - assert Combat Pool never goes negative after a committed spend
```
