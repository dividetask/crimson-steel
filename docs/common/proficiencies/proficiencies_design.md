@chapter 6 Skills

# Proficiencies — Design

@player
A **Skill** is something a Creature has trained to do — pick a lock, read a liar, shape a spell. The **Characters** chapter says how many **ranks** your Classes give you in each one. This chapter turns those ranks into the two numbers every Roll needs — how many dice you may throw, and how far your training moves the Target Number — and then walks through making a Skill Check at the table.

@implementation
Owns the Skill catalog, the Prowess formula, and the ability-driven substitutions (Floor Ability, Substitution Ability) that may produce a higher Prowess than the queried key alone. Pure calculation — Proficiencies holds no state. Per-Creature ranks, attributes, and ability membership are read through a Creature accessor the caller supplies.

Rank accumulation across class levels, Class skill lists, and the rule that every Class trains every Save are not Proficiencies concerns; those live in `creatures/creatures_design.md` (see *Ranks Computation* under that domain's Operations).

## What a Skill is

@player
Every Skill in the **Skill catalog** carries two things: a short description of what it covers, and a **driving Attribute** — the one Attribute that feeds it. Climbing and swimming run on Strength, sneaking and lock-work on Dexterity, lore on Intelligence, noticing and reading people on Wisdom, and talking your way through on Charisma.

A few entries deserve a second look:

- **Set Skills** are families rather than single Skills — crafts, professions, performances, games. You never train the family itself. You train one member of it (a particular craft, a particular instrument), and that member is a Skill in its own right, with the family's driving Attribute. A rule that names the family applies to every member of it.
- **Casting Skills** are the Skills spells are cast with. Each tradition of magic has its own; the **Magic and Abilities** chapter says which Skill a given Spell uses.
- **Martial** is general combat training. It is rolled for weapon attacks and for parrying and blocking, but you do not pick it as a trained Skill — your Classes hand out its ranks automatically (see *Saves and Martial* below).

## From ranks to Prowess

@player
Your **Prowess** in a Skill is your training plus your raw talent:

> **Prowess = ranks + floor(driving Attribute ÷ {{Attribute Contribution Divisor}})**

Use the Attribute's *Effective* value — after Race, Tier, anything you are wearing, and any effect currently raising or lowering it. Nothing else goes into Prowess. A Bonus or Penalty on a Roll never changes it; only ranks and the Attribute do. That is why an item that raises an *Attribute* can give you more dice, while a Bonus to the *Roll* only moves the Target Number.

## From Prowess to dice

@player
Prowess is spent in blocks of {{Dice Count Range}} — the **Dice Count Range**.

- Every **full block** becomes one point of **Competency**: a Bonus, of the Competency Type, on every Roll you make with the Skill.
- The **leftover** points raise your **Dice Cap** — the most dice you may throw on one Roll with that Skill — above the minimum of {{Minimum Dice Count}}.

> **Competency = floor(Prowess ÷ {{Dice Count Range}})**
>
> **Dice Cap = {{Minimum Dice Count}} + (Prowess − Competency × {{Dice Count Range}})**

| Prowess | Competency | Dice Cap |
|---|---|---|
| 0 | none | {{Minimum Dice Count}} |
| 1 | none | {{Minimum Dice Count + 1}} |
| {{Dice Count Range - 1}} | none | {{Minimum Dice Count}} + {{Dice Count Range - 1}} — the largest Dice Cap there is |
| {{Dice Count Range}} | +1 | {{Minimum Dice Count}} |
| {{Dice Count Range + 1}} | +1 | {{Minimum Dice Count + 1}} |

The Dice Cap climbs to its maximum, then drops back to {{Minimum Dice Count}} as the next point of Competency arrives, and starts climbing again. Each block trades a handful of dice for a Target Number that is one point easier on every die you do roll.

If something drives your Prowess below zero, the same arithmetic runs in reverse: a Prowess of −1 is a Competency *Penalty* of 1 with the Dice Cap at its maximum.

The Dice Cap is a ceiling, not an order. You may always roll fewer dice — and in a fight you often will, because every die is paid for (see the **Combat** chapter).

### Worked example — reading a Skill off the sheet

@player
You have 3 ranks in a Skill, and its driving Attribute contributes {{Dice Count Range - 1}} more. Your Prowess is {{Dice Count Range + 2}}.

- One full block of {{Dice Count Range}} gives **+1 Competency**.
- The 2 points left over give a **Dice Cap of {{Minimum Dice Count + 2}}**.

On a Check with that Skill you roll up to {{Minimum Dice Count + 2}} dice, and the +1 Competency Bonus lowers the Target Number from {{Base Target Number}} to {{Base Target Number - 1}} before any other modifier is counted.

## Acting untrained

@player
A Skill you have no ranks in is **untrained**. You may still attempt it: your Prowess is just the Attribute's contribution, so you still get dice. But the attempt carries the **Non-Proficiency Penalty** — a Competency modifier of {{Non-Proficiency Penalty Value}}, added to whatever Competency your Prowess produced.

- The penalty moves the **Target Number only**. It never takes dice away.
- **Saving Throws never take it**, however few ranks you have.

## Abilities that change your ranks

@player
Two abilities, named in the configuration table at the end of this chapter, bend the arithmetic above.

**The Floor Ability** (`{{Floor Ability}}`). A Creature with it counts as having at least `floor(level ÷ 2)` ranks in every Skill, where *level* is its level in the Class that granted the ability. If the Creature's real ranks are higher, the real ranks are used. The floor does not reach the **Restricted Skills** (`{{Restricted Skills}}`), and it never changes a Skill's driving Attribute.

**The Substitution Ability** (`{{Substitution Ability}}`). A Creature with it may answer certain Checks with a different Skill altogether. The **Substitution Map** lists, for each *source* Skill, the Skills it can stand in for. When a Check calls for one of those, work out your Prowess both ways — the called-for Skill, and the source Skill with *its own* ranks and *its own* driving Attribute — and use the higher. On a tie, use the Skill that was called for.

## Saves and Martial

@player
**Saving Throws** run on the same arithmetic. Each of the six Attributes has a save; its Prowess is your ranks in that save plus the contribution of that same Attribute, and Competency and Dice Cap follow as above. Every Class trains every save, at a rate the Class sets, so you always have save ranks to count. Two things set a save apart from a Skill Check: it is never untrained, and you do not choose its dice — a save always rolls its full Dice Cap, and costs nothing to roll.

**Martial** also runs on the same arithmetic, with Dexterity as its driving Attribute. Its ranks come from each Class's Martial rate rather than from a trained-Skill pick. Martial ranks do double duty: they set the dice and Competency of your attacks, parries and blocks, and they also feed your Combat Pool (see the **Combat** chapter).

## Making a Skill Check

@player
When the outcome of something you attempt is in doubt, the DM calls for a Check and names the Skill.

1. **Find your numbers.** Look up the Skill's Dice Cap and Competency. They change only when your ranks or the Attribute change, so write them next to the Skill once and reuse them.
2. **Gather modifiers.** Start with your Competency. Add any Bonus or Penalty in play — a condition you are suffering, an item's magical Guidance, a modifier the DM assigns for the circumstances. Modifiers of the same Type do not stack; see the **Dice Resolution** chapter.
3. **Set the Target Number.** Start from {{Base Target Number}}, subtract the net modifier, and keep the result between {{Minimum Target Number}} and {{Maximum Target Number}}. Anything that would push past those limits becomes Starting Successes or Starting Failures instead.
4. **Roll.** Throw up to your Dice Cap. Apply any Rerolls, then any Nudge, and count your Degree of Individual Success.
5. **Read the result.** With nobody opposing you, {{Default Success Threshold}} or more is a Success, −{{Default Fumble Threshold}} or less is a Fumble, and anything in between is a Failure.

Many effects do not stop at yes or no — they count your Successes, and each one buys a little more. The effect's own text says what a Success is worth.

### How the DM sets difficulty

@player
There is no difficulty number to roll against. The bar never moves: a Check needs {{Default Success Threshold}} net Successes. To make a task easier or harder, the DM gives the Roll a **Circumstance** Bonus or Penalty, and that moves the Target Number. A Roll takes only its largest Circumstance Bonus and its largest Circumstance Penalty, so the DM sizes up the whole situation and assigns one of each at most.

### Opposed Skill Checks

@player
When someone is actively working against you, both sides roll and the Check is resolved as in the **Check Resolution** chapter: your Bonuses become their Penalties and theirs become yours, and their Degree of Individual Success is subtracted from yours. The DM names the Skill the other side answers with. Two pairings are fixed:

- **Deception** is opposed by the listener's **Sense Motive**.
- **Persuasion** is opposed by the listener's **Persuasion** or **Sense Motive**, whichever serves the listener better.

A Skill Roll carries no Inherent Bonus, so a difference in Tier is *not* amplified in an opposed Skill Check the way it is in an attack. A higher Tier still tells, through the higher Attributes it brings.

### Working together

@player
Allies who can genuinely contribute add their own Rolls to your side of the Check as Supporting Rolls. Each helper rolls their own Skill with their own numbers, and their Degree of Individual Success — good or bad — is added to the side's total. A clumsy helper can sink the attempt.

## What lives in the next chapter

@player
The next chapter, **Equipment**, covers what a Creature carries: coin, weapons, armor, and the magical items whose Bonuses feed the Rolls described here.

## Common types

### Skill catalog entry

| Field | Type | Default | Description |
|---|---|---|---|
| `attribute` | one of `str`, `dex`, `con`, `int`, `wis`, `cha` | required | The driving attribute for this Skill. |
| `description` | string | required | Human-readable description, displayed by UI surfaces. |

The catalog lives in `skills.yaml`. A Skill is a Set Skill iff its catalog key ends with `_`; there is no separate flag.

### Creature accessor

The interface the caller supplies so Proficiencies can read per-Creature data. Methods:

| Method | Returns | Description |
|---|---|---|
| `ranks_for(key)` | integer | The Creature's ranks in the given concrete key. Zero when the Creature has no entry. The key must not end in `_`. |
| `attribute_value(attr)` | integer | The Creature's value for the given attribute key. |
| `has_ability(ability_name)` | boolean | Whether the Creature has the named ability. The names Proficiencies passes are the configured Floor Ability and Substitution Ability values. |
| `level_for_ability(ability_name)` | integer | The Creature's level in the Class (or other source) that granted the named ability. Used by the Floor Ability; not the Creature's total level. |

Proficiencies never mutates the accessor and never caches values across calls.

## Public entry points

### Compute Roll inputs for a Proficiency

The main entry point. Computes Direct Prowess and (when applicable) Substituted Prowess, picks the higher Prowess, translates through dice resolution.

Inputs:

| Field | Type | Default | Description |
|---|---|---|---|
| `key` | string | required | The proficiency key being resolved. May be a catalog key, a Set Instance key, or an unknown key. The key must not end in `_`. |
| `creature` | Creature accessor | required | See common types. |
| `attribute_override` | attribute key or null | null | When non-null, used as the driving attribute and the catalog lookup is skipped for attribute purposes. Required when the key has no catalog entry. |

Pipeline:

1. **Resolve the catalog entry.** Look up `key` in the catalog. If no exact entry exists, apply Prefix Match. The result is either a catalog entry or null. If the result is null and `attribute_override` is null, the call is invalid.
2. **Determine the queried key's driving attribute.** `attribute_override` if provided; otherwise the resolved entry's `attribute`.
3. **Compute Direct Prowess.** See **Direct Prowess** below.
4. **Compute Substituted Prowess.** See **Substituted Prowess** below. Skipped entirely when not applicable.
5. **Proficiency Prowess.** `max(Direct Prowess, Substituted Prowess)`. Direct Prowess wins ties. Prowess is built from **ranks + attribute only** — it carries no bonus or penalty, because a bonus/penalty must never change the dice count (only ranks and attribute do).
6. **Translate.** Call dice resolution's *Translate Skill Prowess into Roll inputs* with the Proficiency Prowess, yielding `dice_cap` and a base `bonus_penalty`.
7. **Apply the Non-Proficiency Penalty.** When the winning Prowess source is untrained (its effective ranks are 0) **and** the queried key is **not** a Saving Throw (`*_save`), add the Non-Proficiency Penalty to `bonus_penalty`. This is a Target-Number penalty only — it never changes `dice_cap`. A Saving Throw never takes the penalty, trained or not.
8. **Return.** `{dice_cap, competency_modifier}`. The modifier is `("Competency", bonus_penalty)` when `bonus_penalty != 0`; otherwise null.

Returns:

| Field | Type | Description |
|---|---|---|
| `dice_cap` | integer | The dice count returned by dice resolution's Prowess translator. The maximum dice the Creature can spend on a roll for this proficiency. |
| `competency_modifier` | `(type_name, signed_value)` pair or null | Tagged Competency entry to be added to the Roll's `bonus_penalty_list`. Null when zero. |

### Break down the Roll inputs for a Proficiency

Same inputs and pipeline as *Compute Roll inputs for a Proficiency*, but returns every step, for a caller that shows the math. *Compute Roll inputs* is built from this, so the two cannot disagree.

Returns:

| Field | Type | Description |
|---|---|---|
| `key` | string | The queried key. |
| `source_key` | string | The key whose Prowess won: `key` itself for Direct Prowess, the Substitution Map source for Substituted Prowess. |
| `attribute`, `attribute_value`, `attribute_contribution` | attribute key, integer, integer | The winning source's driving attribute, its value, and `floor(value / Attribute Contribution Divisor)`. |
| `base_ranks`, `floor_ranks`, `ranks` | integer | The source's ranks from the Creature accessor, the Floor Ability lift (zero when it does not apply), and the effective ranks — the higher of the two. |
| `prowess` | integer | `ranks + attribute_contribution`. |
| `trained` | boolean | `ranks > 0`. |
| `dice_cap`, `bonus` | integer | The Prowess translated through dice resolution. |
| `penalty` | integer | The Non-Proficiency Penalty when it applies (pipeline step 7), otherwise zero. The Competency Modifier's value is `bonus + penalty`. |

### Look up a Skill

Pure conversion. Resolves a key against the catalog using Prefix Match.

Input: `key` — string. Must not end in `_`.

Returns: a Skill catalog entry, or null when the key matches nothing in the catalog.

Used by callers (e.g., UI sheets) that want a Skill's attribute or description without computing Prowess.

### List Skills

Returns the catalog as a map of key → entry. Set Skills are included; Set Instances are not (they aren't enumerated).

## Operations

### Prefix Match

Reads the Skill catalog and a queried key. Produces a catalog entry or null.

Rules:

- If the catalog has an exact match for `key`, return it.
- Otherwise, find every catalog entry whose key ends in `_` and is a prefix of `key`. Among those, the entry with the longest key wins. Return it.
- If no such entry exists, return null.

### Direct Prowess

Reads the queried key, the resolved catalog entry, the queried key's driving attribute, the Creature accessor, and the Floor Ability configuration.

- `base_ranks = creature.ranks_for(key)`.
- `floor_ranks`: when **all** of the following hold, the floor lift is `floor(creature.level_for_ability(Floor Ability) / 2)`; otherwise zero.
  - `creature.has_ability(Floor Ability)` is true.
  - The resolved catalog entry is not null (the call did not use `attribute_override` against an unknown key).
  - The resolved entry's key does not appear in `Restricted Skills`.
- `effective_ranks = max(base_ranks, floor_ranks)`.
- `Direct Prowess = effective_ranks + floor(creature.attribute_value(driving_attribute) / Attribute Contribution Divisor)`. The Non-Proficiency Penalty is **not** part of Prowess — it is a Target-Number penalty applied after translation (pipeline step 7). The Skill is **trained** when `effective_ranks > 0`; that flag (not the penalty) flows out so the caller can decide the penalty.

The Floor Ability never changes the driving attribute. It is purely a ranks lift on the queried key; the higher of (actual ranks, floor ranks) is used.

### Substituted Prowess

Reads the queried key, the Substitution Map, the Creature accessor, and the catalog.

- Skipped entirely (no Substituted Prowess produced) when **either** of these holds:
  - `creature.has_ability(Substitution Ability)` is false.
  - No entry of the Substitution Map lists the queried key as a target.
- Otherwise, for each source key in the map whose target list contains the queried key:
  - `source_ranks = creature.ranks_for(source_key)`.
  - `source_attribute = the catalog attribute of source_key`. Source keys must resolve to a catalog entry (exact match or via Prefix Match for Set Instances). A source key with no catalog match is a configuration error.
  - `source_prowess = source_ranks + floor(creature.attribute_value(source_attribute) / Attribute Contribution Divisor)`. As with Direct Prowess, no penalty is folded in; the source is **trained** when `source_ranks > 0`.
- `Substituted Prowess = max(source_prowess across all matching sources)`, carrying the winning source's trained flag.

The Floor Ability never lifts a source's ranks. The substitution operates on the source key's actual stored ranks and its catalog attribute.

The Substitution Map's source keys do not have to be Set Instances. Concrete catalog keys (e.g., `cooking`) are valid, as are Set Instances (e.g., `perform_dance`). The default config uses Set Instances because Versatile Performance is the seed use case.

### Proficiency Prowess

Compares Direct Prowess and (if produced) Substituted Prowess. The higher value is the Proficiency Prowess. Direct Prowess wins ties.

The Proficiency Prowess is fed to dice resolution's translator. *Compute Roll inputs* returns only the translated `dice_cap` and `competency_modifier`; the intermediate ranks and attribute are returned by *Break down the Roll inputs*.

### Non-Proficiency Penalty

A flat penalty (default `-2`) for acting **untrained** — using a Skill in which the winning Prowess source has zero effective ranks. Two rules govern it:

- **It adjusts the Target Number, never the dice.** The penalty is added to the translated `bonus_penalty` (the Competency Modifier), *after* Prowess has set the dice count. Dice come only from ranks + attribute, so being untrained costs you accuracy, not dice. (This is the general rule for every bonus and penalty: only ranks and attribute move dice. A bonus *to an attribute* — a Belt of Strength, say — does change dice because it raises the attribute; a bonus *to the roll* never does.)
- **Saving Throws never take it.** A Saving Throw key (`*_save`) is exempt regardless of ranks: an untrained Save rolls its full ranks-plus-attribute Prowess with no Competency penalty. The penalty applies only to untrained Skill checks (including the Floor Ability's *untrained Skill* row).

## Cross-domain interactions

- **Dice resolution.** Proficiencies calls *Translate Skill Prowess into Roll inputs* and labels the resulting bonus/penalty with the Type Name `Competency`. Proficiencies never assembles full Rolls; that is the caller's responsibility.
- **Modifiers.** Proficiencies emits exactly one Bonus/Penalty Type — `Competency`. Other Types come from other producers and are aggregated into the Roll's `bonus_penalty_list` outside this domain.
- **Creatures.** Proficiencies depends on the Creature accessor. Concrete rank storage, level-per-class computation, and ability membership are Creatures concerns.
- **Abilities.** Two abilities are referenced by configured name: the Floor Ability (default `jack_of_all_trades`) and the Substitution Ability (default `versatile_performance`). Proficiencies queries `creature.has_ability` rather than parsing ability data directly. When the Abilities domain lands, the Substitution Map may move there; Proficiencies will read it from the new location.
- **Configuration.** Loaded from `proficiencies_config.yaml` and `skills.yaml` at boot.
