# Check Resolution Overview

# Checks

Whenever you attempt something that could fail, you make a [[check]]. Pushing a boulder, picking a lock, recalling a rumor, swinging a blade, shrugging off a poison — each is resolved the same way: you gather a handful of dice and roll them against a [[target number]].

## Rolls

Each [[check]] is made up of one or more [[rolls]]. Some [[checks]] only involve one creature and thus only involve one [[roll]], while others involve multiple creatures, each with its own [[roll]].

Every die has **{{Die Size}}** sides, and a die *succeeds* when it rolls at or above the [[target number]]. A die can also crit when it rolls a **{{Die Size}}**, and fails when it rolls a 1. Typically a critical counts as two succesess, while a failure subtracts a success.

- [[primary roll]] — the creature initiating the check makes the primary roll.
- [[defending roll]] — when the check negatively affects one or more creatures, then the defending roll is a roll made by one or more of those creatures. This could be a defence check such as blocking a weapon, or a saving throw check such as resisting a mental influence.
- [[saving throw roll]] — This is a defending roll involving resisting, or dodging a spell or magical ability. Against illusions this might instead be recognizing an illusionary effect.
- [[supporting rolls]] — some [[checks]] may allow an ally to support the check in some way typically through the use of a spell or ability. The results of supporting rolls are added to the results of the primary roll.
- [[opposing rolls]] — some [[checks]] may allow an opponent to disrupt the check in some way typically through the use of a spell or ability. Depending on the check, the results of opposing rolls may be subtracted from the primary roll, or added to the results of the defending roll.

- [[attribute check]] — a raw test of an ability that does not benefit from training, such as pushing something heavy or recalling something you heard earlier.
- [[aptitude check]] — a test of an activity that does benefit from training, such as picking a lock, lying, or identifying a monster.
- [[opposed aptitude check]] — an aptitude check between two or more creatures opposing each other, such as seeing through a lie, winning a board game, or noticing a creature trying to hide.
- [[single-target magic check]] — an attempt to impose a negative condition on another creature with a magic spell or ability. It always involves a casting roll and a saving throw roll, and may add supporting rolls that aid the casting roll and opposing rolls that aid the saving throw.
- [[multi-target magic check]] — an attempt to impose a negative condition on one or more creatures with a magic spell or ability. It always involves a casting roll and a saving throw for each targeted creature, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[area magic check]] — an attempt to impose a negative condition on all creatures in a defined area with a magic spell or ability. It always involves a casting roll and a saving throw for each creature in the area, and may add supporting rolls that aid the casting roll and opposing rolls that aid every saving throw.
- [[combat check]] — an attempt to hit another creature in combat with a melee or ranged weapon. It always involves an attack roll and may include a defense roll, and may add supporting rolls that aid the attack roll and opposing rolls that hamper it.
- [[magic combat check]] — an attempt to hit another creature in combat with a magic spell or ability. It always involves a casting roll and may include a defense roll, and may add supporting rolls that aid the casting roll and opposing rolls that hamper it.

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

## Competency Bonus

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

## Rerolling Mechanics

Some spells or abilities might grant luck, unluck, minor advantage, minor disadvantage, great advantage, or great disadvantage to a [[roll]]. These abilites allow (or force) a creature to reroll a number of dice. **Dice cannot be rerolled more then once**. 

### Luck and Unluck

Luck and Unluck have are measured in points with a roll having a number of luck or unluck points. A roll with both luck and unluck will cancel each other out leaving a number of remaining points in either luck or unluck. For example if a [[roll]] had one point of luck and five points of unluck then it will lose the luck point and end up with four points of unluck. Each point allows (or forces) one die to be rerolled. Luck will be used to reroll failures first, and any remaining points will be used to reroll non successes favoring the lower results. Unluck will do the opposite rerolling criticals first, and any remaining points will be used to reroll successes. Dice cannot be rerolled more then once and the creature is stuck with the final roll even if it is worse.

### Advantage and Disadvantage

Advantage and disadvantage are the more powerful versions of luck and unluck. Minor advantage allows all of the failures for a roll to be rerolled, whereas minor disadvantage forces all of the criticals to be rerolled. Dice cannot be rerolled more then once even if the reroll came from a different source such as from luck and advantage. Dice always use the results of the last roll. Great advantage and great disadvantage allow all non successes (including failures) to be rerolled, or all succeses (including criticals) to be rerolled respectively. A roll cannot have both advantage and disadvantage, or great advantage and great disadvantage. If a roll had both then they would cancel each other out. A roll could have great advantage and luck but the luck would be superfluous.

## Nudge Mechanics

Some spells or abilities might nudge a die or an entire roll. This will increase or decrease the value of a single die, or every die in a roll. A die cannot be nudged above the **[[die size]]** or below 1, and any effect that would move it out of bounds simply moves it to **[[die size]]** or 1. When a nudge effects a single die it will have the following priorities from highest to lowest: chooses the die whose nudge will have the highest delta, prefer to make a crit (or remove a crit), and to remove a failure (or create a failure).

## Opposed Aptitude Checks

Opposed Aptitude [[checks]] involve a [[primary roll]] and a [[defending roll]]. The primary roll is rolled by the creature initiating the check, but it doesn't matter which is which for aptitude checks. Both sides calculate their bonuses and penalties then share the inverse of their bonuses and penalties with the other creature. For example if creature A has a +5 competency bonus, then creature B will gain a +5 competency penalty. After these are applied the TN and starting value is caluclated for both creatures and they roll. Each critical counts as two successes and each failure subtracts a success. Whichever creature has more successes succeeds on the check whereas the other failed. If the creature who failed the check also rolled more failures then [[fumble threshold]] then they fumbled the [[check]]. Starting value is counted towards this so a creature who has a starting value of negative -5 is almost guarenteeded to fumble the check. The exact effects of a fumble are entirely up to the DM and sometimes have no additional effects.

## Combat Checks

Whenever you attempt to hit another creature in combat that creature may attempt to block, dodge, or parry the attack. The attacker makes an attack roll, and the defender decides whether they will make a defense roll. The defense roll is subtracted from the attack roll and the attack roll requires a minimum sum of 2 to hit. The defense roll, if they roll more failures then successes, may aid the attack roll turning a miss into a hit. Some spells or abilities may allow other creatures to interfere with this check. Creatures able to aid the defender can roll an opposed check, and creatures aiding the attacker can roll a supporting check. Supporting checks add their results to the attacker's results while opposing rolls subtract their results from the attacker's results.

Each creature involved in the roll not only adds or subtracts their results from the attacker's results but also applies their bonuses and penalities to other rolls. The attacker applies their bonuses as penalities (and penalities as bonuses) to the defender and each opposing roll (not to the supporting rolls). The defender applies their bonuses as penalties (and penalties as bonuses) to the attacker and each supporting roll (not to the opposing rolls).

Each creature involved in the roll gains an ascendancy bonus or penalty depending upon the inherent bonuses and inherent penalties they have for the roll. If their highest inherent bonus is higher then their most severe inherent penalty, then they gain an ascendancy bonus based upon the difference between the bonus and penalty, otherwise they gain an ascendancy penalty based upon the difference between the same two numbers.

## Magic Combat Checks

A combat check whose attack is a spell or ability: a casting roll against an optional defense roll, with bonuses inverting across the sides exactly as in a weapon [[combat check]], and its result read the same way — a positive [[degree of success]] lands the spell and its size scales the effect. The spell's Tier rides along as a guidance bonus and both combatants carry an [[inherent]] entry, so **[[ascendancy]] applies**.

## Single-Target Magic Checks

Single target magic checks are for spells or abilities that grant a saving throw, as opposed to spells that require

The caster's casting roll opposes the target's [[saving throw]]; supporting rolls aid the cast and opposing rolls aid the save. The two sides' bonuses **invert** onto each other as same-type penalties. All casting rolls grant the caster gains a guidance bonus equal to the [[tier]] of the spell

- [[primary roll]] — the creature initiating the check makes the primary roll.
- [[defending roll]] — when the check negatively affects one or more creatures, then the defending roll is a roll made by one or more of those creatures. This could be a defence check such as blocking a weapon, or a saving throw check such as resisting a mental influence.
- [[saving throw roll]] — This is a defending roll involving resisting, or dodging a spell or magical ability. Against illusions this might instead be recognizing an illusionary effect.
- [[supporting rolls]] — some [[checks]] may allow an ally to support the check in some way typically through the use of a spell or ability. The results of supporting rolls are added to the results of the primary roll.
- [[opposing rolls]] — some [[checks]] may allow an opponent to disrupt the check in some way typically through the use of a spell or ability. Depending on the check, the results of opposing rolls may be subtracted from the primary roll, or added to the results of the defending roll.

Like an attribute check, but the [[dice cap]] uses the relevant skill's [[prowess]] and it adds that skill's aptitude [[competency bonus]]. Its [[degree of success]] is classified into [[success]], [[failure]], or [[fumble]] the same way, and it is **not affected by [[ascendancy]]**.

## Multi-Target Magic Checks

One casting roll faces each named target's own [[saving throw]]. The caster's bonuses invert onto every save and each target's defenses invert back onto the caster, but the targets do not affect one another. The cast resolves once and nets against each save in turn — one result per target, each read as in a single-target magic check — with **[[ascendancy]]** judged against each target separately.

## Area Magic Checks

An area spell is a [[spread check]]: one caster against everyone in the area, with no single defender. It is prepared like a multi-target check, but every caught creature is a peer. The cast resolves once and each caught creature nets against it independently, giving **one result per creature** (each read as in a single-target magic check), with **[[ascendancy]]** judged against each.


## Sharing Bonuses Between Creatures

When a check involves more than one creature, one creature's bonuses and penalties affect the others. The sections below give the exact rule for each kind of check. Two ideas recur:

- **Inversion.** On a contested check, a bonus that helps one side is felt as a same-type penalty by the other, so a single set of dice settles the contest.
- [[ascendancy]] — when the two sides are mismatched in Tier, it amplifies the gap, helping the higher-Tier creature and hurting the lower. It looks only at [[inherent]] bonuses and penalties.

## Roll Target Number

@function Roll Target Number

With the Dice Modifier in hand, a [[roll]]'s [[target number]] is the [[base target number]] ({{Base Target Number}}) shifted by the dice modifier, then clamped to its allowed range:

> **Roll Target Number** = {{Roll Target Number Formula}}

If the shifted value would fall below {{Minimum Target Number}} it is set to {{Minimum Target Number}}; if it would rise above {{Maximum Target Number}} it is set to {{Maximum Target Number}}. Any overflow becomes the Starting Value described above.

## Degree of Individual Success

Roll your dice against the Roll Target Number and add up their contributions. By default a die at or above the target number is a [[success]] worth +1, a die rolling a {{Die Size}} (a [[critical success|critical]]) is worth +2, and a die rolling a 1 is worth −1. Some rolls don't count 1s, and some count a critical as much as +4 or +5. A roll's [[degree of individual success]] is the sum of its dice plus its [[starting value]].

## Degree of Success

A check with one [[roll]] uses that roll's [[degree of individual success]] directly. When a check has rolls on opposing sides, its [[degree of success]] is the supporting side's total minus the opposing side's; a negative degree of success is a [[degree of failure]] of the same size.

What a degree of success means depends on the kind of check — each type below says how it reads its result.
