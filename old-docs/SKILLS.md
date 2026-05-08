# Crimson Steel Online — Skills

### Skill Proficiency Formula

Every skill has a **skill aptitude value** calculated as:

```
Skill Aptitude Value = floor(Associated Attribute / attribute_divider) + Skill Ranks
```

Where `attribute_divider` is defined in `data/rules.json` (`skill.attribute_divider`).

From the total skill value, two derived values are calculated:

- **Skill Proficiency Bonus** = proficiency_bonus_base + floor(Skill Aptitude Value / dice_count_range)
- **Untrained Skill Proficiency Bonus** = proficiency_bonus_base + floor(Skill Aptitude Value / dice_count_range) + untrained_proficiency_penalty
- **Skill Dice Maximum** = dice_count_minimum + (Total Skill Value % dice_count_range)

Where `dice_count_minimum`, `dice_count_range`, and `proficiency_bonus_base` are defined in `data/rules.json` 


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

