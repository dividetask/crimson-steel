# Check Resolution Overview

# Checks

Whenever you attempt something that could fail, you make a [[check]].
Pushing a boulder, picking a lock, recalling a rumor, swinging a blade,
shrugging off a poison — each is resolved the same way: you gather a handful
of dice and roll them against a [[target number]].

## Rolls

Each [[check]] is made up of one or more [[rolls]]. Some [[checks]]
only involve one creature and thus only involve one [[roll]], while others
involve multiple creatures, each with its own [[roll]].

Every die has **{{Die Size}}** sides, and a die *succeeds* when it rolls at or
above the [[target number]]. A die can also crit when it rolls a **{{Die Size}}**,
and fails when it rolls a 1.

There are several kinds of Check, and the later sections of this chapter spell
each one out:

- [[attribute check]] — a raw test of an ability that does not benefit from training, such as pushing something heavy or recalling something you heard earlier.
- [[aptitude check]] — a test of an activity that does benefit from training, such as picking a lock, lying, or identifying a monster.
- [[opposed aptitude check]] — an aptitude check between two or more creatures opposing each other, such as seeing through a lie, winning a board game, or noticing a creature trying to hide.
- [[single-target magic check]] — an attempt to impose a negative condition on another creature with a magic spell or ability. It always involves a casting roll and a saving throw, and may add supporting rolls that aid the casting roll and opposing rolls that aid the saving throw.
- [[multi-target magic check]] — an attempt to impose a negative condition on one or more creatures with a magic spell or ability. It always involves a casting roll and a saving throw for each targeted creature, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[area magic check]] — an attempt to impose a negative condition on all creatures in a defined area with a magic spell or ability. It always involves a casting roll and a saving throw for each creature in the area, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[combat check]] — an attempt to hit another creature in combat with a melee or ranged weapon. It always involves an attack roll and may include a defense roll, and may add supporting rolls that aid the attack roll and opposing rolls that hamper it.
- [[magic combat check]] — an attempt to hit another creature in combat with a magic spell or ability. It always involves a casting roll and may include a defense roll, and may add supporting rolls that aid the casting roll and opposing rolls that hamper it.

What changes between them is mostly *how the bonuses and penalties are shared*
among the creatures involved. The rest of the machinery is the same, so we
cover it first.

## Dice Cap

@function Dice Cap

Each [[roll]] rolls between **{{Minimum Dice}}** and **{{Maximum Dice Formula}}**
dice. The exact number is calculated using the most relevant [[attribute]] for the
task together with the creature's [[prowess]]:

> **Dice Cap** = {{Dice Cap Formula}}

A higher attribute or more Prowess will earn you more dice until you hit the
[[maximum dice]], at which point it resets back to the [[minimum dice]] and
continues to bounce between those two values. More dice means more successes
you are likely to roll. Whenever a rise in [[prowess]] or attribute pushes your
[[dice cap]] back down, your [[check]] is compensated with a lower
[[target number]] or additional [[starting successes]].

```test
global:
  Minimum Dice: 3
  Dice Range: 5
cases:
  - where: { Attribute: 0,  Prowess: 10 }
    expect: { Dice Cap: 3 }
  - where: { Attribute: 10, Prowess: 0  }
    expect: { Dice Cap: 3 }
  - where: { Attribute: 2,  Prowess: 10 }
    expect: { Dice Cap: 4 }
  - where: { Attribute: 10, Prowess: 2  }
    expect: { Dice Cap: 5 }
  - where: { Attribute: 10, Prowess: 4  }
    expect: { Dice Cap: 7 }
```

## Dice Modifier

@function Dice Modifier

A [[check]]'s [[target number]] is rarely the bare base. Circumstances,
equipment, and spells shift it: a [[bonus]] lowers the [[target number]]
(making the check easier), and a [[penalty]] raises it (making the
[[check]] harder).

Every bonus and penalty has a [[bonus type]] — circumstance, guidance,
inherent, morale, and ascendancy. **Bonuses and penalties of the same type do
not stack.** Only the single largest bonus of each type and the single harshest
penalty of each type are counted; the rest are ignored.

Once same-type stacking is settled, add up the surviving bonuses and subtract
the surviving penalties. That total is the [[dice modifier]].

```test
cases:
  - where:  { bonuses: { Circumstance: [4, 2] }, penalties: {} }
    expect: { Dice Modifier: +4 }
  - where:  { bonuses: {}, penalties: { Circumstance: [4, 2] } }
    expect: { Dice Modifier: -4 }
  - where:  { bonuses: {}, penalties: {} }
    expect: { Dice Modifier: 0 }
  - where:  { bonuses: { Circumstance: [2], Guidance: [1] }, penalties: { Circumstance: [4], Guidance: [2] } }
    expect: { Dice Modifier: -3 }
  - where:  { bonuses: { Circumstance: [5], Guidance: [1] }, penalties: { Circumstance: [4, 2] } }
    expect: { Dice Modifier: +2 }
```

## Starting Value

@function Starting Value

A [[target number]] can never drop below the [[minimum target number]]
({{Minimum Target Number}}) or climb above the [[maximum target number]]
({{Maximum Target Number}}). When the [[dice modifier]] is large enough to
push it past one of those limits, the leftover becomes the [[starting value]]
that is carried into your score.

> **Starting Value** = {{Starting Value Formula}}

```test
global:
  Minimum Target Number: 3
  Maximum Target Number: 9
cases:
  - where:  { Dice Modifier: 10 }
    expect: { Starting Value: -1 }
  - where:  { Dice Modifier: -2 }
    expect: { Starting Value: +5 }
  - where:  { Dice Modifier: 5 }
    expect: { Starting Value: 0 }
```

# Roll Target Number

@function Roll Target Number

With the Dice Modifier in hand, a [[roll]]'s [[target number]] is the
[[base target number]] ({{Base Target Number}}) shifted by the dice
modifier, then clamped to its allowed range:

> **Roll Target Number** = {{Roll Target Number Formula}}

If the shifted value would fall below {{Minimum Target Number}} it is set to
{{Minimum Target Number}}; if it would rise above {{Maximum Target Number}} it
is set to {{Maximum Target Number}}. (Any overflow becomes the Starting Value
described above.)

# Degree of Success and Check Outcome

Roll your dice against the Roll Target Number and count the successes. The
[[degree of success]] is the supporting side's total minus the opposing
side's total; when it is negative, its size is the [[degree of failure]].

The [[check outcome]] is then read from the degree of success:

- [[success]] if it reaches the success threshold.
- [[fumble]] if it sinks to the fumble threshold below zero.
- [[failure]] otherwise — including a degree of success of exactly zero.

Unlike a single roll, a check **can always fumble**, no matter how its
individual rolls are protected.

# Competency Bonus

When a creature attempts something it is genuinely trained in, it adds a
[[competency bonus]] reflecting its skill and [[tier]]. The exact size is set
per check by the acting creature's proficiency.

> *(Drafting note: the Competency Bonus formula is not yet pinned down in the
> config — say the word and I'll add it as a named formula and tag this as a
> function section.)*

# Sharing Bonuses Between Creatures

Most checks involve more than one creature, and the interesting question is how
one creature's bonuses and penalties affect the others. The sections below give
the exact rule for each kind of check. Two ideas recur:

- **Inversion.** On a contested check, a bonus that helps one side is felt as a
  penalty by the other. This lets a single set of dice settle the contest — no
  separate "attacker rolls, then defender rolls, then subtract" step.
- [[ascendancy]] — some bonuses come from training; the [[inherent]] bonus
  comes from raw [[tier]] power. When the two sides are badly mismatched in
  Tier, ascendancy amplifies the gap — helping the stronger creature twice over
  and hurting the weaker one just as much. Ascendancy only ever looks at
  inherent bonuses and penalties; it ignores everything else.

# Attribute Checks

The most basic check, for tasks that training doesn't help with — heaving a
portcullis, holding your breath, noticing a draft. Compute the dice cap from
the relevant attribute using **0 for Prowess**, then apply your Tier's inherent
bonus and any competency bonus.

Attribute checks are usually unopposed, and they are **not affected by
ascendancy** — raw Tier power does not tip a test of pure attribute.

# Aptitude Checks

A check for a trained skill, where know-how improves your odds. It works like
an attribute check but draws on the relevant skill's prowess for its dice cap
and adds the skill's competency bonus.

Like attribute checks, an aptitude check is **not affected by ascendancy**.

# Opposed Aptitude Checks

Two or more creatures pit the same skill directly against each other — an
arm-wrestle, a staring contest, a chase. Each creature rolls, and **a copy of
each creature's bonuses is turned into a penalty of the same type against its
opponent.** The highest combined result wins.

Opposed aptitude checks measure skill, not Tier, so they carry no inherent
entries and **ascendancy does not apply**.

# Single-Target Magic Checks

A spell aimed at one creature pits the caster's casting roll against the
target's [[saving throw]]. Supporting rolls aid the casting roll; opposing
rolls aid the saving throw. The two sides' bonuses and penalties **invert
across the gap** — the caster's casting bonuses are felt as penalties by the
target, and the target's defenses are felt as penalties by the caster.

Both sides carry their [[inherent]] bonus (the spell's own Tier rides along as
a guidance bonus, *not* an inherent, so it stays out of the comparison), so
**ascendancy applies** between caster and target.

# Multi-Target Magic Checks

Some spells name several specific targets. The caster makes a single casting
roll; each target makes its own [[saving throw]]. The caster's bonuses invert
onto **every** target's save, and each target's defenses invert back onto the
caster — but the targets do not affect one another. Opposing rolls aid every
saving throw.

The casting side resolves once, then nets against each target's save in turn,
producing one [[check outcome]] per target. **Ascendancy applies** between the
caster and each target independently.

# Area Magic Checks

An area spell — a fireball, a cloud of gas — is a [[spread check]]: one caster
against everyone caught in the area, with no single defender. It is prepared
like a multi-target magic check (the caster's bonuses invert onto each caught
creature's save, and each caught creature's defenses invert back onto the
caster), but every caught creature is a peer of the others.

The casting side resolves once into a single total; each caught creature then
nets against that total independently, so the spell yields **one outcome per
creature in the area**. **Ascendancy applies** between the caster and each
caught creature.

# Combat Checks

A combat check pits an attack roll against an optional defense roll. Supporting
rolls aid the attack roll; opposing rolls hamper it. Every participant's
bonuses and penalties invert across the sides:

- The attacker (the [[initiating roll]]) receives the inverted entries of
  **every** defender.
- The primary defender (the [[defending roll]]) receives the inverted entries
  of **every** attacker.
- Supporting allies receive only the primary defender's inverted entries.
- Other defenders receive only the attacker's inverted entries.

Each creature carries its own Tier as an [[inherent]] entry, so **ascendancy
applies**: a higher-Tier combatant presses its advantage, and a lower-Tier one
feels the gap.

### Worked example — a bonus on the attacker becomes a penalty on the defender

The attacker has a +2 Circumstance bonus; the defender has a +1 Equipment
bonus. After inversion:

| Roll | Carries |
|---|---|
| Attacker | +2 Circumstance, and the defender's −1 Equipment |
| Defender | +1 Equipment, and the attacker's −2 Circumstance |

The attacker now faces an easier target number and the defender a harder one —
the contest settled with a single exchange of dice.

# Magic Combat Checks

A magic combat check is a combat check whose action is a spell or magical
ability rather than a weapon: the caster's casting roll against an optional
defense roll. Supporting rolls aid the casting roll; opposing rolls hamper it,
and bonuses invert across the sides exactly as in a weapon [[combat check]].

Both combatants carry their Tier as an [[inherent]] entry (the spell's own Tier
rides along as a guidance bonus, not an inherent), so **ascendancy applies**.
