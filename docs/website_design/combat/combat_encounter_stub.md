# Combat Encounter Stub

The controls that let the Acting Combatant **take an action** — attack, move,
cast a spell, use an item, use a special ability, or end the turn. It is the
**Turn Action panel** plus the **Action Builder** it mounts to compose and roll
each action.

It renders on `/encounter` directly below the Initiative Stub (the Combat
Tracker, documented in [`../initiative`](../initiative/initiative_stub.md)) and
acts on whichever Combatant the tracker marks as acting (`acting_combatant_id`).
It is **DM-only**.

It owns the *action flow* and the *action economy*; it owns no rules math. Every
roll goes through the Check Resolution roll table, every point of damage through
the Damage domain, and every change to a Creature through Conditions. The exact
calls are pinned in [`required_interfaces.md`](required_interfaces.md).

---

## Turn Action panel

Drives the Acting Combatant.

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

### Afflictions due this Round

The turn opens with one **Save Resolution** sub-stub per Affliction due this
Round (Next Resolution Round arrived, or active-but-unscheduled). Each is built
from a `save` blob (the Creature, the Affliction rule + Potency, the save's Dice
Cap and Target Number). The DM rolls the save and confirms; the net DoIS is
applied through Conditions' *Resolve Affliction*. See
[`required_interfaces.md`](required_interfaces.md) → *Conditions* and *Check
Resolution*.

### Action menu

The Combatant's actions as buttons grouped under **Main Action**, **Bonus
Action**, and **Free Action**:

- **Main Action** — `Attack`, `Move`, `Cast`, `Item`, `Active Spells` (only
  while channeling a usable persistent Spell), and any `main`-activation Special
  Ability.
- **Bonus Action** — any `bonus`-activation Special Ability.
- **Free Action** — `End Turn`, and any `free`-activation Special Ability.

An empty category is skipped. When the Combatant cannot act (Conditions'
*Creature Can Act?* false), it is offered only **End Turn** and the header gains
`(Incapacitated)`. Picking an action collapses the menu to a **selected-action
row** (`<action> [Change]`) carrying a **confirm slot** where a ready Attack /
Cast surfaces its **Commit** button.

### Action panes

#### Attack

Mounts the **Action Builder**. Combat precomputes the builder blob and, on the
builder's confirm, applies the result. Builder steps:

1. **Target** — every other Combatant, with an enemy quick-pick. Attack kind
   (`melee` / `ranged` / `spell`) follows the chosen weapon.
2. **Weapon & dice** — one row per equipped weapon (details from Equipment),
   with dice buttons `2…Dice Cap`. Pool cost to roll `n` dice is `Speed + n`;
   unaffordable counts are greyed.
3. **Target's defense** — `No defense` or an eligible Defensive Action: `Dodge`
   (borrows `dex_save`, any kind), `Block` (Martial, any kind), `Parry`
   (Martial, melee only). All three are pool-costed; the DM picks the dice.
4. **Luck** — one step per source able to spend Luck as a Reaction (each other
   Combatant's Bardic Inspiration Reservoir, plus the DM's DM Luck): Bardic
   Inspiration (reroll low) and Unsettling Words (reroll high) per in-play Roll.

Each option carries a **patch** mutating the seed Rolls. Combat folds in the
attacker Bonuses (Flatfooted / Unaware / Helpless) and each side's **Inherent**
entry, then Check Resolution's cross-side propagation and Ascendancy resolve the
Tier mismatch (see [`required_interfaces.md`](required_interfaces.md) → *Check
Resolution*). When every step is resolved the embedded Check Resolution roll
table appears (`Roll All` / `Confirm` + the dice table); on confirm Combat nets
Supporting − Opposing Successes, recomputes weapon damage, applies **Ascendancy
Damage Reduction**, and routes positive damage through the Damage domain's
*Apply Damage*. A magical weapon's **Damage Riders** roll as a second phase of
the same builder, each applying as its own Severity Calculation. The DM may edit
**Damage / Bleed / Poison** before the final Commit.

#### Move

Spends the **Move Cost** in Combat Pool dice and one Main Action — no other
effect. A `Confirm Move` button (disabled when unaffordable).

#### Cast

Steps: **Spell** (known spells + any granted by an equipped Wand/Ring, grouped
by Tier, mana-unaffordable ones disabled) → **Dice** (variable count from the
spell's Action Minimum up to the casting-skill Dice Cap; a no-roll buff is
auto-applied with no button and skips the roll) → **Target(s)** (driven by the
spell's `target` / `area` / `save`) → **Defense** (the target's Saving Throw at
full Dice Cap for a Save spell, Dodge / Block for an attack-roll spell). On
submit the **Abilities** domain resolves the spell's Effects; Combat routes
them — Mana via Conditions' *Apply Mana Cost*, **magic toxicity** via *Apply
Magic Toxicity* (gated by the Toxicity Threshold), damage via the Damage
domain, heal / Temporary HP / mana / Active Effects via Conditions — and
registers a Concentration / Long Cast entry for a sustained spell. An area spell
drops a Zone on the Map.

#### Item

Reuses the Cast flow: a **Potion** casts its spell on the drinker (self), a
**Scroll** exactly as casting the spell. Costs **no Mana** (the item supplied
it); a Potion imposes Item-Form Magic Toxicity, a Scroll none; the charge
decrements on commit and a Main Action is spent. Wands / Rings are not consumed
here — their spell lives in the Cast list.

#### Active Spells

Strikes with an active persistent Spell (e.g. Spiritual Weapon). Reuses the
Attack flow verbatim; the strike is **free** (no Combat Pool) and does **not**
consume the Reservoir.

#### Special

Uses a non-Spell Ability that needs no Reaction (Bardic Performance, Rage, Turn
Undead, …), each a button under its activation category. Resolving it debits its
`mana_cost`; a channeled Performance mounts the Action Builder to roll the
skill check, a self-target named Effect (Rage) applies via Conditions' *Apply
Named Effect*, and anything else spends the Action Minimum and reports it for the
DM to adjudicate. Definitions come from the **Abilities** domain.

#### End Turn

Invokes *Advance Turn*: applies per-turn cleanup to the outgoing Combatant
(clearing `luck_points`; the pool is **not** refilled), skips Combatants who
cannot act, and **begins the incoming Combatant's turn** (Turn start, above). A
Round wrap also runs per-round cleanup and advances the Chronicle timestamp.
(The **Next Turn** button itself lives on the tracker — see `../initiative`.)

### Behavior notes

- Each pane is client-side until submit; only submit POSTs back.
- The Combat Pool is spent on submit as `Speed + dice`. Saving Throws never cost
  Combat Pool; Defensive Actions do.
- **DM Luck Points** are a Combat-level pool, persisting until *End Combat*.

---

## Action Builder

A reusable, **domain-agnostic** wizard for composing an action — an Attack, a
Cast, a Special — from DM choices, then rolling it. It owns the *step flow* and
**composes the Check Resolution roll table** as its terminal step, mounting the
*Roll All* affordance **only when a step actually rolls dice** (a no-roll buff
just confirms). It knows nothing about Combat, Damage, or Conditions: the host
precomputes the blob and acts on the confirmed result.

### Parameters

A blob of DM-pickable options; a null/empty list omits its step.

| Parameter | Shape | Purpose |
|---|---|---|
| `target_options` | `[{creature_ref, name}]` | Target picker. |
| `action_options` | `[{name, min_dice, max_dice, speed?, damage?}]` | The actor's action; `min_dice == max_dice` locks the dice and omits the step. |
| `actor_pool` / `defender_pool` | integer | Caps dice the actor / defender may spend. |
| `defense_options` | `[{name, min_dice, max_dice, speed?}]` | The defender's reaction. |
| `supporting_actions` / `opposing_actions` | `[{creature_ref, action_name, min_dice, max_dice, pool}]` | Ally / foe reactions. |
| `reroll_sources` / `mass_reroll_sources` / `nudge_sources` | `[{creature_ref, creature_name, source_name, direction, pool?}]` | Luck-step sources. |
| `rolls` | `[{creature_name, roll_name, dice_count, tn, die_size, starting_value, side}]` | The seed Rolls for the embedded dice table; `side` is `:supporting` / `:opposing`. |

### Step model and lifecycle

Steps walk in order, each skipped if its list is null/empty: **Target →
Action → Defense → Supporting Actions → Opposing Actions → Rerolls → Mass
Rerolls → Nudges**, then the Check Resolution roll table (Roll All + Confirm).
Each step is **pending** (hidden), **active** (its controls occupy the shared
`.rolls-actions` slot), or **complete** (a `<Label>: <choice> [Change]` summary
row). Each pick carries a **patch** that mutates the seed Rolls (`set_dice`,
`set_tn`, `set_name`, `set_excluded`, `set_reroll`, `set_nudge`); `Change`
re-opens a step and rewinds every later step (and the dice table) to pending.
The **Luck** step is dynamic: a per-source table whose amounts are bounded by
`min(source Luck, that Roll's dice)`, composed onto each Roll's reroll slots
(max of each sign — Check Resolution applies them).

### Output

The builder runs entirely client-side and emits one `action:confirmed` event:
`{ choices, rolls: [{ id, side, successes, crits, dice_count }] }`. The host
(Combat) reads it and applies the result. The builder does **not** validate
legality (the host pre-validates) and does **not** understand saves, attacks,
or any domain concept — the same wizard serves Affliction saves, attacks, casts,
and any future Check.

---

## Required interfaces

Everything above that reaches outside this stub is enumerated, per domain, in
[`required_interfaces.md`](required_interfaces.md). The Combat Tracker's own
dependencies live in [`../initiative/required_interfaces.md`](../initiative/required_interfaces.md).
