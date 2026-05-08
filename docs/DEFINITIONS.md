# Crimson Steel Online — Game Definitions

*This document defines the terms used throughout all design documents.*

## Creature

All entities that can take actions are called **creatures**. This includes the player's character, other players' characters, monsters, DM controlled characters, and animals.

## Player Character (PC)

All creatures directly controlled by a player are referred to as **player characters** or **PCs**. This does not include familiars and animal companions.

## Non Player Character (NPC)

All creatures not directly controlled by a player are **non player characters** or **NPCs**. These are creatures controlled by the DM.

## Acting Creature

The creature making a check. Used to refer to the creature who initiated the check.

## Supporting Creature

A creature aiding a check. Used to refer to a specific creature who is rolling to help the acting creature succeed.

## Opposing Creature

A creature opposing a check. Used to refer to a specific creature who is rolling to prevent the acting creature from succeeding.

---

## Attribute

One of the six core stats: **Strength**, **Dexterity**, **Constitution**, **Intelligence**, **Wisdom**, **Charisma**. Each attribute affects derived stats and is associated with specific skills and saving throws. See [GAME_DESIGN.md](GAME_DESIGN.md) for attribute effects.

## Skill

A measurable ability that determines a creature's effectiveness at specific tasks. Skills are organized into three categories: **primary skills**, and **Saves**. All skills share the same proficiency formula. See [SKILLS.md](SKILLS.md) for skill lists and advancement.

## Skill Attribute Modifier

The contribution of a skill's associated attribute to the total skill value:

```
Skill Attribute Modifier = floor(attribute / attribute_divider)
```

## Skill Ranks

The number of ranks a creature has in a skill. Primary skills gain ranks from class levels. Secondary skills and sub-skills gain ranks through use. See [SKILLS.md](SKILLS.md) and [CLASSES.md](CLASSES.md).

## Total Skill Value

The sum of a creature's skill attribute modifier and skill ranks for a given skill:

```
Total Skill Value = Skill Attribute Modifier + Skill Ranks
                  = floor(attribute / attribute_divider) + Skill Ranks
```

## Skill Dice Maximum

The maximum number of dice a creature can spend when using a skill, depending upon the creature's attributes and skill:

```
Skill Dice Maximum = dice_count_minimum + (Total Skill Value % dice_count_range)
```

## Skill Proficiency Bonus

The bonus to target number adjustments from a creature's skill level:

```
Skill Proficiency Bonus = proficiency_bonus_base + floor(Total Skill Value / dice_count_range)
```

The `proficiency_bonus_base` is defined in `data/rules.json` (`skill.proficiency_bonus_base`). Default: **-1**. This means untrained creatures start with a penalty to their TN.

## Skill Item Bonuses / Penalties

Some items may affect the outcome of checks due to their magical properties. These items apply their bonus or penalty to the TN of all affected checks made by the creature wearing, wielding, or possessing the item.

## Check Dice Count

The actual number of dice a creature uses for a check. By default this equals the skill dice maximum, but the creature may choose to use fewer dice (minimum 2). When the check requires spending dice from the combat pool, the check dice count is limited by available pool dice.

---

## Check

An action with a chance of failure that must be resolved with a roll of dice. 

## Individual Roll

All checks involve rolling a number of dice, and some checks involve multiple creatures rolling their own dice towards that check. An **individual roll** is the dice rolled by a single creature towards a check. 

## Net Successes

The result of a check calculated by adding and subtracting the results of all dice involved in the check as well as starting failures and starting successes related to the check. 

## Individual Net Successes

The partial result of a check calculated by adding and subtracting the results of the dice from one creature involved in the check as well as starting failures and starting successes from that creature. This term is only needed when two or more creatures are involved in a check. 

## Target Number (TN)

Each check has a target number that must be met or exceeded in order for a specific die to be considered successful. Target numbers start with a value of BTN and are adjusted by a creature's skill and circumstances of the check. TNs have upper and lower bounds defined 

## Base Target Number (BTN)

The initial TN for all checks before any adjustments. 

## Opposed Checks and Supported Checks

**Opposed checks** are checks where one or more creatures are rolling against the acting creature attempting to prevent the check from succeeding. **Supported checks** are checks where one or more creatures are rolling to help the acting creature succeed.

The total net result of such checks is the acting creature's individual net successes plus the sum of any supporting creatures' individual net successes, minus the sum of any opposing creatures' individual net successes. Opposing creatures can aid the success of a check with poor rolls, and supporting creatures may harm the success of a check with poor rolls. It is uncommon for more than two creatures to be involved in a check, but not impossible. 

## Fumble

A check fumbles if net successes <= -`default_fumble_threshold` OR any individual net successes <= -`default_fumble_threshold`. Fumbles may have additional negative consequences depending on the check type.

## Starting Successes and Starting Failures

When a TN is adjusted below `tn_minimum`, each point below the minimum becomes one **starting success**. When a TN is adjusted above `tn_maximum`, each point above the maximum becomes one **starting failure**. The TN is then clamped to the nearest bound. 

## Circumstantial Bonuses and Circumstantial Penalties

Situational modifiers applied to the TN of a check based on environmental conditions, positioning, or other factors. These follow the bonus stacking rules 

---

## Combat Pool

Each creature has a dice resource that refreshes at the start of their turn. Some checks require using dice from this resource, while other checks do not. 
