# Check Resolution Overview

# Checks

Whenever you attempt something that could fail, you make a [[check]]. Pushing a boulder, picking a lock, recalling a rumor, swinging a blade, shrugging off a poison — each is resolved the same way: you gather a handful of dice and roll them against a [[target number]].

## Rolls

Each [[check]] is made up of one or more [[rolls]]. Some [[checks]] only involve one creature and thus only involve one [[roll]], while others involve multiple creatures, each with its own [[roll]].

Every die has **{{Die Size}}** sides, and a die *succeeds* when it rolls at or above the [[target number]]. A die can also crit when it rolls a **{{Die Size}}**, and fails when it rolls a 1.

There are several kinds of Check, and the later sections of this chapter spell each one out:

- [[attribute check]] — a raw test of an ability that does not benefit from training, such as pushing something heavy or recalling something you heard earlier.
- [[aptitude check]] — a test of an activity that does benefit from training, such as picking a lock, lying, or identifying a monster.
- [[opposed aptitude check]] — an aptitude check between two or more creatures opposing each other, such as seeing through a lie, winning a board game, or noticing a creature trying to hide.
- [[single-target magic check]] — an attempt to impose a negative condition on another creature with a magic spell or ability. It always involves a casting roll and a saving throw, and may add supporting rolls that aid the casting roll and opposing rolls that aid the saving throw.
- [[multi-target magic check]] — an attempt to impose a negative condition on one or more creatures with a magic spell or ability. It always involves a casting roll and a saving throw for each targeted creature, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[area magic check]] — an attempt to impose a negative condition on all creatures in a defined area with a magic spell or ability. It always involves a casting roll and a saving throw for each creature in the area, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[combat check]] — an attempt to hit another creature in combat with a melee or ranged weapon. It always involves an attack roll and may include a defense roll, and may add supporting rolls that aid the attack roll and opposing rolls that hamper it.
- [[magic combat check]] — an attempt to hit another creature in combat with a magic spell or ability. It always involves a casting roll and may include a defense roll, and may add supporting rolls that aid the casting roll and opposing rolls that hamper it.

What changes between them is mostly *how the bonuses and penalties are shared* among the creatures involved. The rest of the machinery is the same, so we cover it first.

## Dice Cap

@function Dice Cap

Each [[roll]] rolls between **{{Minimum Dice}}** and **{{Maximum Dice Formula}}** dice. The exact number is calculated from the most relevant [[attribute]] for the task together with the creature's [[prowess]]:

> **Dice Cap** = {{Dice Cap Formula}}

A higher attribute or more Prowess earns you more dice until you hit the [[maximum dice]], at which point it resets to the [[minimum dice]] and keeps bouncing between those two values. Whenever a reset pushes your [[dice cap]] back down, your [[check]] is compensated with a lower [[target number]] or additional [[starting successes]].

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

A [[check]]'s [[target number]] is rarely the bare base. Circumstances, equipment, and spells shift it: a [[bonus]] lowers the [[target number]] (making the check easier), and a [[penalty]] raises it (making the check harder).

Every bonus and penalty has a [[bonus type]] — circumstance, guidance, inherent, morale, and ascendancy. **Bonuses and penalties of the same type do not stack.** Only the single largest bonus of each type and the single harshest penalty of each type are counted; the rest are ignored.

Once same-type stacking is settled, add up the surviving bonuses and subtract the surviving penalties. That total is the [[dice modifier]].

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

A [[target number]] can never drop below the [[minimum target number]] ({{Minimum Target Number}}) or climb above the [[maximum target number]] ({{Maximum Target Number}}). When the [[dice modifier]] is large enough to push it past one of those limits, the leftover becomes the [[starting value]] carried into your score.

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

With the Dice Modifier in hand, a [[roll]]'s [[target number]] is the [[base target number]] ({{Base Target Number}}) shifted by the dice modifier, then clamped to its allowed range:

> **Roll Target Number** = {{Roll Target Number Formula}}

If the shifted value would fall below {{Minimum Target Number}} it is set to {{Minimum Target Number}}; if it would rise above {{Maximum Target Number}} it is set to {{Maximum Target Number}}. Any overflow becomes the Starting Value described above.

# Degree of Success and Check Outcome

Roll your dice against the Roll Target Number and count the successes. The [[degree of success]] is the supporting side's total minus the opposing side's total; when it is negative, its size is the [[degree of failure]].

The [[check outcome]] is read from the degree of success:

- [[success]] if it reaches the success threshold.
- [[fumble]] if it sinks to the fumble threshold below zero.
- [[failure]] otherwise — including a degree of success of exactly zero.

Unlike a single roll, a check **can always fumble**, no matter how its individual rolls are protected.

# Competency Bonus

When a creature attempts something it is genuinely trained in, it adds a [[competency bonus]] reflecting its skill and [[tier]]. The exact size is set per check by the acting creature's proficiency.

# Sharing Bonuses Between Creatures

Most checks involve more than one creature, and the interesting question is how one creature's bonuses and penalties affect the others. The sections below give the exact rule for each kind of check. Two ideas recur:

- **Inversion.** On a contested check, a bonus that helps one side is felt as a same-type penalty by the other, so a single set of dice settles the contest.
- [[ascendancy]] — when the two sides are mismatched in Tier, it amplifies the gap, helping the higher-Tier creature and hurting the lower. It looks only at [[inherent]] bonuses and penalties.

# Attribute Checks

The most basic check, for tasks training doesn't help with. Compute the [[dice cap]] from the relevant attribute using **0 for Prowess**, then add your Tier's [[inherent]] bonus and any [[competency bonus]]. Attribute checks are usually unopposed and are **not affected by [[ascendancy]]**.

# Aptitude Checks

Like an attribute check, but the [[dice cap]] uses the relevant skill's [[prowess]] and you add that skill's [[competency bonus]]. Also **not affected by [[ascendancy]]**.

# Opposed Aptitude Checks

Two or more creatures pit the same skill directly against each other — an arm-wrestle, a staring contest, a chase. **A copy of each creature's bonuses becomes a same-type penalty against its opponent**, and the highest result wins. These carry no [[inherent]] entries, so **[[ascendancy]] does not apply**.

# Single-Target Magic Checks

The caster's casting roll opposes the target's [[saving throw]]; supporting rolls aid the cast and opposing rolls aid the save. The two sides' bonuses **invert** onto each other as same-type penalties. Both carry an [[inherent]] bonus (the spell's Tier rides along as a guidance bonus, not an inherent), so **[[ascendancy]] applies**.

# Multi-Target Magic Checks

One casting roll faces each named target's own [[saving throw]]. The caster's bonuses invert onto every save and each target's defenses invert back onto the caster, but the targets do not affect one another. The cast resolves once and nets against each save in turn, giving one [[check outcome]] per target, with **[[ascendancy]]** judged against each target separately.

# Area Magic Checks

An area spell is a [[spread check]]: one caster against everyone in the area, with no single defender. It is prepared like a multi-target check, but every caught creature is a peer. The cast resolves once and each caught creature nets against it independently, giving **one outcome per creature**, with **[[ascendancy]]** judged against each.

# Combat Checks

An attack roll faces an optional defense roll; supporting rolls aid the attack and opposing rolls hamper it. Bonuses invert across the sides: the attacker (the [[initiating roll]]) takes every defender's inverted entries, the primary defender (the [[defending roll]]) takes every attacker's, and any extra roll on a side takes only the lead opponent's. Each creature carries its Tier as an [[inherent]] entry, so **[[ascendancy]] applies**.

A short example: the attacker has a +2 Circumstance bonus and the defender a +1 Morale bonus. After inversion the attacker carries +2 Circumstance and the defender's inverted −1 Morale, while the defender carries +1 Morale and the attacker's inverted −2 Circumstance — so the attacker faces an easier target number and the defender a harder one.

# Magic Combat Checks

A combat check whose attack is a spell or ability: a casting roll against an optional defense roll, with bonuses inverting across the sides exactly as in a weapon [[combat check]]. The spell's Tier rides along as a guidance bonus and both combatants carry an [[inherent]] entry, so **[[ascendancy]] applies**.
