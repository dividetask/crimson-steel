# Combat Encounter Stub

The controls that let the Acting Combatant **take an action** — attack, move,
cast a spell, use an item, use a special ability, or end the turn. It is the
**Turn Action panel** plus the **Action Builder** it mounts to compose and roll
each action.

It owns the *action flow* and the *action economy*; it owns no rules math. Every
roll goes through the Check Resolution roll table, every point of damage through
the Damage domain, and every change to a Creature through Conditions. The exact
calls are pinned in [`required_interfaces.md`](required_interfaces.md).

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

The turn opens with one **Save Resolution** sub-stub per Affliction the
**Afflictions** domain reports as due, built from the save data it supplies
(the Creature, the Affliction rule + Potency, the Dice Cap, the Target Number).
The DM rolls and confirms; the result goes back to Afflictions' *Resolve
Affliction*. See [`required_interfaces.md`](required_interfaces.md) →
*Afflictions*.

---

## How a step works

The panel builds an action **one step at a time**. Every step behaves the same
way, so the behavior is stated once here and never repeated per step.

A step is a set of buttons. Picking one:

1. **collapses the step to a summary row** — the step's label, a colon, the
   chosen value, and a **Change** button (preceded by a change icon) on the
   right, e.g. `Action: Attack   ⟳ Change`; and
2. **advances to the next step** (determined per *The action flow* below).

Two automatic cases never prompt: a step with a single forced outcome (a
Potion's target is always the drinker) resolves itself and shows its row, and a
step that does not apply to the current action is skipped.

Pressing **Change** on any summary row re-opens that step's buttons, **discards
its choice and any dice or modifiers it contributed**, and **rewinds every later
step — and the final roll — back to unmade**; the DM re-walks from that step.
Nothing touches the game until the final **Commit** (or, for a no-roll action,
**Confirm**).

---

## The action flow

**Action Choice** is always the first step. The action chosen there decides
which steps follow. The *Steps* catalog below defines each step's buttons once;
this section defines, per action, the order they appear in and how the **next**
step is chosen.

- **Attack** — Target → Weapon & Dice → Defence → *[Reactions]* → Luck → Roll → Commit.
- **Active Spells** — identical to Attack, over the conjured strikes; the strike
  is **free** (no Combat Pool) and does not consume its Reservoir.
- **Cast** — Spell → Dice → *target* → *defence* → *[Reactions]* → *luck* → Roll → Commit, where:
  - *target* is **Target** for a single-target spell, **Area Placement** for an
    area spell, or **Multi-Target** for a multi-target spell; a `self` spell
    auto-targets the caster.
  - *defence* is **Defence** for an attack-roll (magic combat) spell; for a
    save spell each target's **saving throw** is added automatically at its full
    Dice Cap (no Defence step); a utility spell has neither.
  - *luck*, **Roll**, and **Dice** appear only when the cast rolls dice. A
    **no-roll buff** (a fixed-cost spell that rolls nothing) skips Dice, Luck,
    and Roll and ends at **Confirm**.
- **Item** — Item → Dice → *target* → *defence* → *[Reactions]* → *luck* → Roll → Commit:
  the Cast flow exactly, except a **Potion** auto-targets the drinker, **Dice**
  offers one row per usable casting skill, and no Mana is spent.
- **Move** — a single **Confirm Move** (spends the Move Cost; no roll).
- **Special** — one of:
  - *channeled* (e.g. Bardic Performance): *[pick Performance, if several]* →
    Dice → Roll → **Confirm** (which shows the Luck the Reservoir will gain);
  - *named-effect* (e.g. Rage): **Confirm** (applies the named Effect);
  - *other* (e.g. Turn Undead): **Confirm** (spends the action; the DM
    adjudicates targets / saves manually).
- **End Turn** — a single **Confirm**, then *Advance Turn*.

*[Reactions]* is the optional Supporting / Opposing Actions step — see the
catalog.

## Steps

Each step's panel, defined once.

- **Action Choice** — buttons: `Attack`, `Cast`, `Move`, `Item`,
  `Active Spells`, `Special`, `End Turn`. A button is **hidden** when it has
  nothing to offer: `Cast` (the Combatant knows no spell and holds no
  spell-granting item), `Item` (no usable consumable), `Active Spells` (no usable
  active persistent spell), `Special` (no usable special ability). When the
  Combatant cannot act (Conditions' *Creature Can Act?* false) only `End Turn`
  shows and the header reads `(Incapacitated)`.
- **Target** — every other Combatant, with a quick-pick for the nearest enemy.
  For an attack the attack kind (`melee` / `ranged` / `spell`) follows the
  weapon chosen next.
- **Weapon & Dice** — one row per equipped weapon (Active Spells: per conjured
  strike), each with dice buttons `2…Dice Cap`. The Combat Pool cost to roll `n`
  dice is `Speed + n`; counts the pool can't afford are greyed.
- **Spell** — the Combatant's known spells plus any spell an equipped Wand / Ring
  grants, grouped by Tier under a `Tier <n> (<cost> mana)` header. A spell the
  Combatant can't afford the Mana for is shown greyed.
- **Dice** — how many dice to roll on the casting check: buttons from the spell's
  **Action Minimum** up to the casting-skill **Dice Cap**, bounded by the Combat
  Pool. For an **Item**, one such row per usable casting skill. The step is
  **auto-applied (no buttons)** when the spell's dice are fixed (a no-roll buff).
- **Item** — one button per usable consumable, `<item> ×<quantity>`, grouped by
  Tier.
- **Area Placement** — drop the spell's footprint on the Map; every caught
  creature becomes a defender that rolls its own saving throw.
- **Multi-Target** — pick the spell's named targets; each becomes a defender that
  rolls its own saving throw.
- **Defence** — the target's reaction: `No defense`, `Dodge` (any attack kind),
  `Block` (any attack kind), or `Parry` (melee weapon attacks only). Each costs
  Combat Pool, so the DM picks the dice (Reaction minimum up to the pool, capped
  by the Dice Cap). A target that cannot act is **Helpless** and is offered only
  `No defense`.
- **Reactions** *(optional)* — ally **Supporting** rolls and foe **Opposing**
  rolls offered when available (e.g. a caster's Shield-of-Faith block of an
  ally, a Roll-Table Reaction). Each is its own pool-costed roll added to the
  Check; inserted before Luck.
- **Luck** *(only when the action rolls dice)* — one step per source able to
  spend Luck as a reaction: each *other* Combatant holding a Bardic Inspiration
  Reservoir, plus the **DM** when it holds DM Luck. Per in-play roll it offers a
  Bardic Inspiration bonus (reroll low dice) and/or an Unsettling Words penalty
  (reroll high dice), each bounded by `min(the source's Luck, that roll's dice)`.
- **Roll** — the embedded **Check Resolution roll table** (`Roll All` + `Confirm`
  + the dice table). The DM rolls, may reroll / nudge or type a manual result,
  then Confirms. Mounted only when a step actually rolled dice.
- **Commit** — applies the action (see below). For an attack whose hit lands and
  whose weapon carries magical **Damage Riders**, a **rider roll** phase runs
  first (the rider dice at the attack's Target Number); then the editable
  **Damage / Bleed / Poison** (plus a box per rider) appear before Commit.

## Commit — what each action applies

On Commit the stub spends the Combat Pool (`Speed + dice`; saving throws and
no-roll buffs cost none) and routes the outcome — never computing rules itself:

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
  lives on the tracker (see [`../initiative`](../initiative/initiative_stub.md)).

## Behavior notes

- Each step is client-side until Commit; only Commit / Confirm POSTs back.
- **DM Luck Points** are a Combat-level pool, persisting until *End Combat*.

## Under the hood — the Action Builder

The wizard is the reusable, **domain-agnostic** Action Builder: it owns only the
step flow and the embedded Check Resolution roll table, and knows nothing about
Combat, Damage, or Conditions. The host (Combat) precomputes the option blob —
each option carrying a **patch** that mutates the seed rolls (set dice / target
number / name / exclusion / reroll / nudge) — and listens for the single
`action:confirmed` event (`{ choices, rolls: [{ id, side, successes, crits,
dice_count }] }`) to apply the result. The same wizard serves Affliction saves,
attacks, casts, and any future Check.

## Required interfaces

Everything above that reaches outside this stub is enumerated, per domain, in
[`required_interfaces.md`](required_interfaces.md). The Combat Tracker's own
dependencies live in [`../initiative/required_interfaces.md`](../initiative/required_interfaces.md).
