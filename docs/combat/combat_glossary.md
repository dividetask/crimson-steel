# Combat — Glossary

Defines the vocabulary used by `combat_design.md` and `combat_tests.md`. Covers the in-progress fight, its Combatants, Initiative, the Time Tick subdivision of a Round, the Action Economy, Combat Pool, Attacker Bonuses, Concentration, Damage Types and Severity Calculation. *(configurable)* values come from `combat_config.yaml`.

## Combat

**Combat**: An in-progress fight. At most one Combat is active at a time.

**Combat Anchor**: The point in time at which a Combat began.

**Stale Combat**: A Combat whose view of time disagrees with Chronicle's.

## Combatant

**Combatant**: A Creature taking part in the active Combat.

**Acting Combatant**: The Combatant whose turn it currently is.

## Time

(Round and Day: see common glossary.)

**Time Tick**: A subdivision of a Round used during Combat. Outside Combat the concept does not exist; Round is the finest time unit.

**Time Ticks Per Round**: The number of Time Ticks a Round is divided into during a Combat. Equal to the highest Turns Per Round across present Combatants.

**Turns Per Round**: The number of turns a Combatant of a given Tier gets per Round. *(configurable)*

## Time Tick Scheduling

**Time Tick Schedule**: The Time Ticks during a Round on which a Combatant acts. One entry per turn that Combatant gets in the Round.

## Initiative

**Initiative**: An ordering of Combatants that determines who acts first within a Time Tick.

**Initiative Attribute**: The attribute consulted to determine a Combatant's number of initiative dice. *(configurable)*

**Initiative Divisor**: The divisor applied to Initiative Attribute when determining a Combatant's number of initiative dice. *(configurable)*

**Initiative String**: A Combatant's initiative result, recorded in a form that can be compared directly against another Combatant's.

**Initiative Luck**: A modifier applied to a Combatant's initiative roll that re-rolls extreme dice. Combat-specific because initiative has no Target Number.

**Initiative Insight**: A modifier applied to a Combatant's initiative roll that nudges a single die. Combat-specific because initiative has no Target Number.

## Action Economy

**Action**: Anything a Combatant does during the active Combat. Every Action is categorized as Main, Bonus, or Free.

**Main Action**: An Action with a minimum dice cost. A Combatant gets two Main Actions per turn and may take them only on their own turn. *(configurable: Main Action Minimum)*

**Bonus Action**: An Action with a minimum dice cost. Unlimited in count but limited in practice by the Combatant's remaining Combat Pool. *(configurable: Bonus Action Minimum)*

**Free Action**: An Action with a fixed cost. Unlimited in count and timing. *(configurable: Free Action Cost)*

**Reaction**: An action triggered in response to another Combatant's Main Action. Each Main Action a Combatant takes grants one Reaction allowance, spendable only against that Main Action or another Combatant's Reaction to it. Distinct from a Bonus Action.

**Move**: A Main Action.

**Granted Action**: An Action made available to a Combatant by another domain (Spells, Abilities, Equipment), to be presented as part of that Combatant's action options.

## Attacker Bonuses

Modifiers granted to the attacker based on the defender's state. Despite the defender-side trigger, the modifier accrues to the attacker.

**Flatfooted Bonus**: An Attacker Bonus that applies when the defender takes no Defensive Action against the incoming attack. *(configurable)*

**Unaware Bonus**: An Attacker Bonus that applies when the defender has not yet acted in the active Combat. *(configurable)*

**Hidden**: A relationship between an attacker and a defender that exists when the defender cannot perceive the attacker. Defender Blind, attacker Invisible, or otherwise visually concealed all qualify. Hidden is asymmetric and per-pair: the same attacker may be Hidden from one defender and not from another. When the attacker is Hidden from the defender, the attacker's incoming attack receives the Unaware Bonus against that defender.

## Defensive Actions

**Defensive Action**: An Action declared by a defender on the attacker's turn — Parry, Block, or Dodge. Resolved as an Opposed Roll against the attacker's to-hit.

## Combat Pool

**Combat Pool Attribute**: The attribute used in the Budget formula. *(configurable)*

**Combat Pool Divisor**: The divisor applied to Combat Pool Attribute in the Budget formula. *(configurable)*

**Combat Pool Step**: The size of each cost tier and the guaranteed minimum pool. *(configurable)*

**Combat Pool Budget**: An intermediate value used when computing a Combatant's Combat Pool.

**Combat Pool**: A Combatant's maximum spendable dice on one of their turns.

**Combat Pool (Remaining)**: The portion of a Combatant's Combat Pool still available during the current turn.

## Set-Value Spend

**Set-Value Spend**: A general dice-spend option in which a Combatant pays extra dice from their Combat Pool to fix the value of dice on a Roll they would otherwise have rolled randomly.

**Set Value**: The value each Set-Value-Spent die takes — Dice Resolution's Die Size, so every set die is a Critical.

**Set Value Spend Ratio**: The number of extra dice paid per set die. *(configurable)*

**Dice Cap**: The maximum number of dice a Combatant may spend on a Roll due to their Proficiency in the relevant track. The Set-Value Spend cannot set more dice than Dice Cap allows. *(owned by Proficiencies — pending.)*

## Channeling and Concentration

**Concentration**: The state of maintaining a spell whose effect persists only while the caster continues to commit effort. Covers Channeled spells (every-turn Main Action) and any spell with a long activation time still in progress.

**Channeled Spell**: A spell whose persistence depends on the caster spending a Main Action on it each of their turns. The cast itself counts as the first such Main Action. See `abilities_glossary.md` for the modes (fire, reservoir, maintain, auto) and Reservoir mechanics.

**Channel Action**: The Main Action a Combatant spends to maintain a Channeled spell on their turn. For fire and reservoir modes the Combatant chooses how many dice to spend, from Main Action Minimum up to Combat Pool Remaining; for maintain mode the cost is always exactly Main Action Minimum. Auto-mode spells require no Channel Action after the cast.

**Reservoir**: For reservoir-mode and auto-mode Channeled spells, the pool of dice held by the spell. Defined in `abilities_glossary.md`. Combat tracks the per-entry Reservoir count.

**Concentration Save**: A Check a Combatant makes to keep a Concentration alive when they take damage. Failure ends the spell (Channeled spells lose their Reservoir as well).

**Ended Concentration**: A Concentration that has been removed from the Combatant — either by a failed Concentration Save, by skipping the Channel Action on the Combatant's turn, or by direct end-of-spell.

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
