# Encounter — Glossary

Defines the vocabulary used by `encounter_design.md` and `encounter_tests.md`. Currently covers Combat — the in-progress fight, its Combatants, Initiative, the Time Tick subdivision of a Round, the Action Economy, Combat Pool, Attacker Bonuses, Concentration, Damage Types and Severity Calculation. *(configurable)* values come from `encounter_config.yaml`. Downtime and Travel vocabulary will be added when those modes are designed.

## Combat

**Combat**: An in-progress fight. At most one Combat is active at a time.

**Combat Anchor**: The point in time at which a Combat began.

**Stale Combat**: A Combat whose view of time disagrees with Chronicle's.

## Combatant

**Combatant**: A Creature taking part in the active Combat.

**Acting Combatant**: The Combatant whose turn it currently is.

**Excluded PC**: A Player Character whose Creature ID appears in the Combat's `excluded_pcs` list. Excluded PCs are *not* Combatants — they are not in the roster, do not roll initiative, and do not receive turns. The exclusion is a scheduling concern (the player is sitting out the session) rather than an in-combat status; the list persists across End/Start cycles and is mutated via *Set PC Exclusions*.

## Time

(Round and Day: see common glossary.)

**Time Tick**: A subdivision of a Round used during Combat.

**Time Ticks Per Round**: The number of Time Ticks every Round is divided into during this Combat.

**Turns Per Round**: The number of turns a Combatant of a given Tier gets per Round. *(configurable)*

## Time Tick Scheduling

**Time Tick Schedule**: The Time Ticks during a Round on which a Combatant acts. One entry per turn that Combatant gets in the Round.

## Initiative

**Initiative**: An ordering of Combatants that determines who acts first within a Time Tick.

**Initiative Attribute**: The attribute consulted to determine a Combatant's number of initiative dice. *(configurable)*

**Initiative Divisor**: The divisor applied to Initiative Attribute when determining a Combatant's number of initiative dice. *(configurable)*

**Initiative String**: A Combatant's initiative result, recorded in a form that can be compared directly against another Combatant's.

**Initiative Luck**: A modifier applied to a Combatant's initiative roll that re-rolls extreme dice.

**Initiative Insight**: A modifier applied to a Combatant's initiative roll that nudges a single die.

## Action Economy

**Action**: Anything a Combatant does during the active Combat. Every Action is categorized as Main, Bonus, or Free.

**Main Action**: An Action with a minimum dice cost. A Combatant gets two Main Actions per turn and may take them only on their own turn. *(configurable: Main Action Minimum)*

**Bonus Action**: An Action with a minimum dice cost. Unlimited in count but limited in practice by the Combatant's remaining Combat Pool. *(configurable: Bonus Action Minimum)*

**Free Action**: An Action with a fixed cost. Unlimited in count and timing. *(configurable: Free Action Cost)*

**Reaction**: An action triggered during another Combatant's Main Action in response to that Main Action or another Combatant's Reaction to that Main Action. Each Main Action allows each Combatant only one Reaction during the resolution of that Main Action.

**Move**: A Main Action where a Combatant moves to another square.

**Small Step**: A Free Action a Combatant can take during their turn to move a single square. This can only be taken once per Turn and only on Turns where they did not take a Move Action.

**Granted Action**: An Action made available to a Combatant by another domain (Spells, Abilities, Equipment), to be presented as part of that Combatant's action options.

**Ended Concentration**: An maintained Ability that the Combatant stopped maintaining — either by a failed Concentration Save, by skipping the Channel Action on the Combatant's turn, or by direct end-of-ability.

## Attacker Bonuses

Modifiers granted to the attacker based on the defender's state. Despite the defender-side trigger, the modifier accrues to the attacker.

**Flatfooted**: The condition a Creature is in when they are unable to respond to an attack.

**Unaware**: The condition a Creature is in when they are stationary and not engaged in combat.

**Flatfooted Bonus**: An Attacker Bonus that applies when the defender is Flatfooted against the incoming attack. *(configurable)*

**Unaware Bonus**: An Attacker Bonus that applies when the defender has not yet acted in the active Combat. *(configurable)*

**Hidden**: A relationship between an attacker and a defender that exists when the defender cannot perceive the attacker.

## Defensive Actions

**Defensive Action**: A Reaction declared by a defender on the attacker's turn — Parry, Block, or Dodge.

**Parry**: A Defensive Action involving swinging a weapon to deflect an Attack.

**Block**: A Defensive Action involving interposing a shield to defend against an Attack.

**Dodge**: A Defensive Action involving moving out of the way of an Attack.

## Falling Damage

**Falling Damage**: Damage taken when a Creature falls. *(configurable)*

## Zones

**Zone Event**: A trigger that may occur when a Combatant enters, exits, or ends a turn in a Zone.

## Combat Pool

**Combat Pool Attribute**: The Attribute used to calculate a Creature's Combat Pool. *(configurable)*

**Combat Pool**: A Combatant's maximum spendable dice on one of their turns.

**Remaining Combat Pool**: The unused portion of a Combatant's Combat Pool still available.

## Luck Points

**Luck Points**: A per-Combatant pool of bonuses generated by certain abilities, spendable for single-die rerolls.

**DM Luck Points**: A Combat-level pool symmetric to Luck Points but for DM-aligned use.

## Damage Types

**Damage Type**: A category of damage. Each Damage Type determines how its damage maps to Severity and what side effects, if any, it produces.

**Damage Type Parent**: A Damage Type referenced by another. The referencing Damage Type inherits the parent's rules, or — when the parent has no rules of its own — simply belongs to the parent's group.

**Damage Type Mechanic**: A side-effect or modification specific to one Damage Type.

**Severity**: A category that determines which Hit Point pool a damage point fills. Three values, ordered least to most serious: Minor, Moderate, Major.

**Severity Calculation**: The process by which Combat routes a damage total through its Severity buckets before handing the result to Conditions.

**Runtime Bucketing**: A Severity Calculation rule used for physical damage; it spreads incoming damage across Severity categories using Threshold and Damage Resilience.

**Threshold**: A value used by Runtime Bucketing.

**Bleed Value**: A weapon property that drives bleed effects on physical damage.

**Damage Resilience**: A Creature property added to Threshold during Runtime Bucketing.

**Metal Armor**: A classification used by certain Damage Type Mechanics (notably Electricity). *(configurable)*
