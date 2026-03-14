# Crimson Steel Online — Skills

### Skill Proficiency Formula

Every skill has a **skill aptitude value** calculated as:

```
Skill Aptitude Value = floor(Associated Attribute / attributeDivider) + Skill Ranks
```

Where `attributeDivider` is defined in `data/rules.json` (`skill.attributeDivider`).

From the total skill value, two derived values are calculated:

- **Skill Proficiency Bonus** = proficiencyBonusBase + floor(Skill Aptitude Value / diceCountRange) + proficiency_bonus_base + p
- **Untrained Skill Proficiency Bonus** = proficiencyBonusBase + floor(Skill Aptitude Value / diceCountRange) — proficiency_bonus_base + untrained_skill_proficiency_penalty
- **Skill Dice Maximum** = diceCountMinimum + (Total Skill Value % diceCountRange)

Where `diceCountMinimum`, `diceCountRange`, and `proficiencyBonusBase` are defined in `data\rules.json` 


## Skill Categories

### Combat Skill

bab is the main combat skill used. When making a weapon attack you must spend additional dice based upon the speed of the weapon used, and additional dice to ammunition if it is a ranged attack. 

### Saving Throws

Saving throws aren't listed in the skill list but each attribute has one saving throw. Saving throws do not expend dice from the combat pool.

### Other Skills

Using skills in combat only requires dice from the combat pool when it is used as a main action. When you use a skill in reaction to another's action it is free. Skills can sometimes be used instead of saving throws.

---

## Primary Skill List

### Combat

| Property | Value |
|----------|-------|
| **Attribute** | Dexterity |
| **Advancement** | Class level (same rate as combat pool) |

The Combat skill represents overall fighting ability. It is used as the baseline for all weapon attacks. If a character's Combat skill is higher than their specific weapon skill, Combat is used instead.

### Saving Throws

Each attribute has an associated saving throw skill. Saving throws **do not cost combat pool dice**.

