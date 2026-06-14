# Check Resolution Overview

# Checks

Whenever you attempt something that could fail, you make a [[check]]. Pushing a boulder, picking a lock, recalling a rumor, swinging a blade, shrugging off a poison — each is resolved the same way: you gather a handful of dice and roll them against a [[target number]].

## Rolls

Each [[check]] is made up of one or more [[rolls]]. Some [[checks]] only involve one creature and thus only involve one [[roll]], while others involve multiple creatures, each with its own [[roll]].

Every die has **{{Die Size}}** sides, and a die *succeeds* when it rolls at or above the [[target number]]. A die can also crit when it rolls a **{{Die Size}}**, and fails when it rolls a 1.

- [[attribute check]] — a raw test of an ability that does not benefit from training, such as pushing something heavy or recalling something you heard earlier.
- [[aptitude check]] — a test of an activity that does benefit from training, such as picking a lock, lying, or identifying a monster.
- [[opposed aptitude check]] — an aptitude check between two or more creatures opposing each other, such as seeing through a lie, winning a board game, or noticing a creature trying to hide.
- [[single-target magic check]] — an attempt to impose a negative condition on another creature with a magic spell or ability. It always involves a casting roll and a saving throw, and may add supporting rolls that aid the casting roll and opposing rolls that aid the saving throw.
- [[multi-target magic check]] — an attempt to impose a negative condition on one or more creatures with a magic spell or ability. It always involves a casting roll and a saving throw for each targeted creature, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[area magic check]] — an attempt to impose a negative condition on all creatures in a defined area with a magic spell or ability. It always involves a casting roll and a saving throw for each creature in the area, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[combat check]] — an attempt to hit another creature in combat with a melee or ranged weapon. It always involves an attack roll and may include a defense roll, and may add supporting rolls that aid the attack roll and opposing rolls that hamper it.
- [[magic combat check]] — an attempt to hit another creature in combat with a magic spell or ability. It always involves a casting roll and may include a defense roll, and may add supporting rolls that aid the casting roll and opposing rolls that hamper it.

What changes between them is how bonuses and penalties are shared among the creatures involved, and how each reads its result. The shared machinery comes first.

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

# Competency Bonus

@function Attribute Competency Bonus
@function Aptitude Competency Bonus

Competency bonuses come from natural ability ([[attributes]]) or aptitude from training ([[prowess]]). Some spells or abilities might artificially raise or lower this bonus, but typically it only increases as you gain levels or equip items that grant bonuses to your character's attributes. For attributes this value starts at {{Competency Bonus Base}} and increases every time the [[dice cap]] rolls over to the [[minimum dice]]. For aptitude this value is adjusted by {{Unskilled Penalty Value}} when a creature is untrained.

> **Attribute Competency Bonus** = {{Attribute Competency Bonus Formula}}
> **Aptitude Competency Bonus** = {{Aptitude Competency Bonus Formula}}

```test
global:
	Attribute Contribution Formula: "<Attribute> / 2"
	Dice Range: 5
	Competency Bonus Base: -1
	Attribute Competency Bonus Formula: "floor((<Attribute Contribution Formula> + <Prowess>) / <Dice Range>)"
	Aptitude Competency Bonus Formula: "<Attribute Competency Bonus Formula> - (min(Prowess, 1) * <Unskilled Penalty Value>)"
	Unskilled Penalty Value: -2
cases:
  - where: { Attribute: 0,  Prowess: 10 }
    expect: { Attribute Competency Bonus: 1 }
    expect: { Aptitude Competency Bonus: 1 }
  - where: { Attribute: 10, Prowess: 0  }
    expect: { Attribute Competency Bonus: 0 }
    expect: { Aptitude Competency Bonus: -1 }
  - where: { Attribute: 2,  Prowess: 10 }
    expect: { Attribute Competency Bonus: 1 }
    expect: { Aptitude Competency Bonus: 1 }
  - where: { Attribute: 10, Prowess: 2  }
    expect: { Attribute Competency Bonus: 0 }
    expect: { Aptitude Competency Bonus: 0 }
  - where: { Attribute: 10, Prowess: 4  }
    expect: { Attribute Competency Bonus: 0 }
    expect: { Aptitude Competency Bonus: 0 }
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

A [[target number]] can never drop below {{Minimum Target Number}} (the [[minimum target number]]) or climb above {{Maximum Target Number}} (the [[maximum target number]]). When the [[dice modifier]] is large enough to push it past one of those limits, the leftover increases or decreases the [[starting value]] affecting your result before the dice are rolled.

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

# Sharing Bonuses Between Creatures

When a check involves more than one creature, one creature's bonuses and penalties affect the others. The sections below give the exact rule for each kind of check. Two ideas recur:

- **Inversion.** On a contested check, a bonus that helps one side is felt as a same-type penalty by the other, so a single set of dice settles the contest.
- [[ascendancy]] — when the two sides are mismatched in Tier, it amplifies the gap, helping the higher-Tier creature and hurting the lower. It looks only at [[inherent]] bonuses and penalties.

# Roll Target Number

@function Roll Target Number

With the Dice Modifier in hand, a [[roll]]'s [[target number]] is the [[base target number]] ({{Base Target Number}}) shifted by the dice modifier, then clamped to its allowed range:

> **Roll Target Number** = {{Roll Target Number Formula}}

If the shifted value would fall below {{Minimum Target Number}} it is set to {{Minimum Target Number}}; if it would rise above {{Maximum Target Number}} it is set to {{Maximum Target Number}}. Any overflow becomes the Starting Value described above.

# Degree of Individual Success

Roll your dice against the Roll Target Number and add up their contributions. By default a die at or above the target number is a [[success]] worth +1, a die rolling a {{Die Size}} (a [[critical success|critical]]) is worth +2, and a die rolling a 1 is worth −1. Some rolls don't count 1s, and some count a critical as much as +4 or +5. A roll's [[degree of individual success]] is the sum of its dice plus its [[starting value]].

# Degree of Success

A check with one [[roll]] uses that roll's [[degree of individual success]] directly. When a check has rolls on opposing sides, its [[degree of success]] is the supporting side's total minus the opposing side's; a negative degree of success is a [[degree of failure]] of the same size.

What a degree of success means depends on the kind of check — each type below says how it reads its result.

# Attribute Checks

The simplest check, for tasks training doesn't help with. Its [[dice cap]] comes from the relevant attribute with **0 for Prowess**, plus your Tier's [[inherent]] bonus and your attribute [[competency bonus]]. An attribute check is unopposed: its [[degree of success]] is a [[success]] if it reaches the success threshold, a [[fumble]] if it sinks to the fumble threshold below zero, or a [[failure]] in between (a degree of success of zero is a failure). A check can always fumble. Attribute checks are **not affected by [[ascendancy]]**.

# Aptitude Checks

Like an attribute check, but the [[dice cap]] uses the relevant skill's [[prowess]] and it adds that skill's aptitude [[competency bonus]]. Its [[degree of success]] is classified into [[success]], [[failure]], or [[fumble]] the same way, and it is **not affected by [[ascendancy]]**.

# Opposed Aptitude Checks

Two or more creatures pit the same skill directly against each other — an arm-wrestle, a staring contest, a chase. **A copy of each creature's bonuses becomes a same-type penalty against its opponent.** There is no threshold: the creature with the highest [[degree of individual success]] wins. These carry no [[inherent]] entries, so **[[ascendancy]] does not apply**.

# Single-Target Magic Checks

The caster's casting roll opposes the target's [[saving throw]]; supporting rolls aid the cast and opposing rolls aid the save. The two sides' bonuses **invert** onto each other as same-type penalties. The condition takes hold when the [[degree of success]] (casting minus save) is positive, and a larger margin makes it take hold more strongly. Both sides carry an [[inherent]] bonus (the spell's Tier rides along as a guidance bonus, not an inherent), so **[[ascendancy]] applies**.

# Multi-Target Magic Checks

One casting roll faces each named target's own [[saving throw]]. The caster's bonuses invert onto every save and each target's defenses invert back onto the caster, but the targets do not affect one another. The cast resolves once and nets against each save in turn — one result per target, each read as in a single-target magic check — with **[[ascendancy]]** judged against each target separately.

# Area Magic Checks

An area spell is a [[spread check]]: one caster against everyone in the area, with no single defender. It is prepared like a multi-target check, but every caught creature is a peer. The cast resolves once and each caught creature nets against it independently, giving **one result per creature** (each read as in a single-target magic check), with **[[ascendancy]]** judged against each.

# Combat Checks

An attack roll faces an optional defense roll; supporting rolls aid the attack and opposing rolls hamper it. Bonuses invert across the sides: the attacker (the [[initiating roll]]) takes every defender's inverted entries, the primary defender (the [[defending roll]]) takes every attacker's, and any extra roll on a side takes only the lead opponent's. A positive [[degree of success]] is a hit, and its size sets how much damage gets through. Each creature carries its Tier as an [[inherent]] entry, so **[[ascendancy]] applies**.

A short example: the attacker has a +2 Circumstance bonus and the defender a +1 Morale bonus. After inversion the attacker carries +2 Circumstance and the defender's inverted −1 Morale, while the defender carries +1 Morale and the attacker's inverted −2 Circumstance — so the attacker faces an easier target number and the defender a harder one.

# Magic Combat Checks

A combat check whose attack is a spell or ability: a casting roll against an optional defense roll, with bonuses inverting across the sides exactly as in a weapon [[combat check]], and its result read the same way — a positive [[degree of success]] lands the spell and its size scales the effect. The spell's Tier rides along as a guidance bonus and both combatants carry an [[inherent]] entry, so **[[ascendancy]] applies**.

# Additional Damage

@function Additional Damage

When an attack hits, a damage source may grant extra dice — an elemental weapon grants four. Roll them against the attack's [[target number]]: each [[success]] deals 1 point of the source's damage and a [[critical success|crit]] deals 2, while 1s do nothing.

> **Additional Damage** = {{Additional Damage Formula}}
