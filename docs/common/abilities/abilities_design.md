@chapter 9 Magic and Abilities

# Abilities — Design

@player
Everything a Creature can do beyond swinging a weapon or testing a Skill is an **Ability**: a wizard's Spells, a barbarian's rage, a rogue's sneak attack, the venom in a spider's bite. This chapter gives the rules they all share. The Spells themselves are on the Spell list, and each Class's Abilities are on the Class list.

@implementation
The Abilities module is a strict **reference**: it answers "what does this Ability do?" in a form other modules can consume. It rolls no dice, tracks no active effects, and consumes no resources.

Sibling domains:
- **Conditions** owns the per-Creature state of Stateful Abilities (Rage timer, Bardic Inspiration luck pool, etc.) and the Effect Names catalog. Conditions validates the named-effect strings Abilities emits.
- **Combat** owns the action paths that Triggers fire during, and the geometry of `area`. Combat also computes implicit damage from attack rolls when no damage Effect is declared. Combat reads Bonus Type stacking rules when summing modifier totals on a Combatant.
- **Dice Resolution** owns Roll mechanics; this module's deferred-damage Formulas are evaluated by callers after the relevant Roll.
- **Creatures** aggregates `modifiers:` entries across earned Abilities into the Creature's effective bonus totals.

## What an Ability is

@player
An Ability is either a **Spell** — shaped magic with a Tier and a School, paid for in Mana and cast with a casting Skill — or a **Talent**, which is everything else: a Class feature, a racial gift, a monster's natural weapon.

Abilities work in four ways. An **active** Ability takes an action, and usually Mana or dice. A **passive** one is always on — a standing Bonus to Speed, a Skill or damage reduction. A **triggered** one fires by itself during another action when its Trigger is met. A **Reaction** answers someone else's action, on their turn.

A Creature's Abilities come from its **Race** (some wake only at a higher Tier), its **Class levels**, the **Spells it has chosen** through a Class's spellcasting, a Cleric's **deity and domains**, and its **items**: a Wand lends its Spell while held, and some rings and tattoos grant an Ability outright.

## Reading a Spell

@player
Every Spell on the Spell list is described by the same entries.

| Entry | What it tells you |
|---|---|
| **Tier** | The Spell's magical density ({{Tiers}}). It sets the Mana cost and adds to the casting check. Tier 0 counts as 0.5 in formulas. |
| **School** | Its discipline — see the Schools below. |
| **Casting Skills** | The Skills that can cast it — Arcana if none is named — plus the universal casting Skill ({{Universal Spell Casting Skills}}), which can cast anything. |
| **Activation time** | A Main Action unless stated; otherwise Bonus, Reaction, Free, a full turn, several turns, or minutes and more. |
| **Range** | Self, Touch, Close, Medium, Long, or a distance in feet. |
| **Target** | Yourself, an object, or a number of creatures. A *willing* Spell does nothing to a creature that refuses it. |
| **Area** | A shape and a size on the map, for Spells that fill a space. |
| **Duration** | Instant, a length of time, permanent, or "concentration". |
| **Save** | The Attribute the target saves with, and the result of a failed, a successful and sometimes a fumbled save. |
| **Attack roll** | The Spell is aimed like a weapon and answered with a Defensive Action, not a save. |
| **Damage Type** | Sets the Severity of its damage and any side effects (see **Combat**). |

Some Spells add a **prerequisite** (a lower Spell you may need to know first), a **property** such as *language-dependent* (a target that cannot understand you is unaffected), or the **item forms** the Spell may take.

The Schools:

{{table: Spell Schools | label: School | value: What it covers}}

The casting Skills:

{{table: Casting Skills List | label: Casting Skill | value: Tradition}}

### Rank and Variants

@player
Many entries scale with your **Rank**: your Proficiency Ranks in the Skill you cast with (see **Skills**). "Rank turns" is one turn per Rank, and "1 + Rank" targets grows as you train. Ranges scale too. **Touch** is your reach ({{Default Reach Feet}} feet unless something lengthens it), while **Close**, **Medium** and **Long** each add a set distance per Rank to a base. The **Range Formulas**, in feet:

{{table: Range Formulas | label: Range | value: Feet}}

A Spell may come in **Variants**. One with a Tier axis is a ladder of Spells: Heal exists at every Tier, each version stronger and separately named. One with an **Aspect** axis is a single Spell in several flavours: Elemental Dart as fire, acid, electricity or cold. Each Variant has its own line on the Spell list, and you learn and cast the Variant, not the family.

## Learning Spells

@player
How you gain Spells depends on your Class, and the Class list has the numbers. A Class uses one of five patterns: a pool of **points** that grows with level, each Spell costing points by its Tier; a **count** of Spells known; a count **for each Spell Tier**; a **deity and domains** that bring their own Spells; or **every** Spell of the Class's tradition, automatically. A Class may also limit which Spells qualify and fix the Skill they are cast with — a Cleric's domain Spells always use Invocation, a Bard's a Perform Skill.

## Casting a Spell

@player
A cast is a Check (see **Check Resolution**): your casting Roll is the Initiating Roll, and the target's resistance is the Defending Roll.

1. **Pay the Mana.** A Spell costs Mana by its Tier — the **Mana Cost Per Tier** table under this list. Without the Mana you cannot cast.
2. **Choose the casting Skill** from those the Spell allows. It supplies your Dice Cap, Competency and Rank for this cast.
3. **Commit dice.** Roll at least the Action Minimum for the Spell's activation — {{Main Action Minimum}} dice for a Main Action, {{Bonus Action Minimum}} for a Bonus Action, {{Reaction Action Minimum}} for a Reaction — and at most the Skill's Dice Cap. In a fight, every die committed is spent from your Combat Pool.
4. **Find your Target Number.** Start at the Base TN of {{Base Target Number}} and apply the Skill's **Competency**, your **Inherent** Bonus, and a **Guidance** Bonus equal to the Spell's Tier (none at Tier 0).
5. **The target answers** with a Saving Throw or a Defensive Action, as the Spell dictates.
6. **Roll.** Your DoIS minus the target's is the Degree of Success. The cast succeeds when it reaches the Default Success Threshold of {{Default Success Threshold}}.

{{table: Mana Cost Per Tier | label: Spell Tier | value: Mana}}

The Mana and the dice are spent whether or not the Spell takes hold.

Not every Spell is rolled. One with no save, no attack roll and no damage simply works, and costs exactly its Action Minimum in Combat Pool dice. One that stores its dice in a Reservoir (see *Channeling and Concentration*) pours the dice from step 3 into it instead of rolling them. One that only counts Successes with nobody resisting — a healing Spell staunching a wound — is rolled unopposed.

### Saves and spell attacks

@player
A Spell with a **save** is resisted by a Saving Throw in the Attribute it names — a Wisdom save, a Dexterity save. The target rolls its full Dice Cap for that save, and a Saving Throw never costs Combat Pool. Bonuses and Penalties cross between the two Rolls as in any opposed Check, Inherent included, so Ascendancy applies when your Tiers differ.

- If the cast succeeds, the target has **failed** its save and takes the Spell's *fail* result.
- Otherwise the target has **saved** and takes the *success* result: often nothing, sometimes a lesser effect, sometimes the full effect **halved**.
- A *fumble* result, where the Spell lists one, replaces the fail result when the save's Degree of Failure reaches the Default Fumble Threshold of {{Default Fumble Threshold}}.

A Spell with an **attack roll** is an attack. The target may answer with a Defensive Action — a Dodge, or a Block if it carries a shield; a Spell cannot be parried — paying Combat Pool as usual, or stand undefended. A cast that succeeds is a hit.

Effects an entry lists outside its save apply however the save goes. Some lasting Spells let the victim **shake them off**: on its own turn it spends the action the Spell names to save again, and success ends the effect.

### Spell damage

@player
A damaging Spell that states a formula uses it. One that states none deals the **default Spell damage**. Add together:

- floor(casting Attribute / 4), using the Attribute behind the Skill you cast with;
- the Spell's Tier (Tier 0 counts as 0.5);
- that Skill's Competency, which therefore counts for the Roll and for the damage;
- your Successes: for a save Spell, your casting Roll's DoIS; for an attack-roll Spell, the Degree of Success of the hit.

Round the total down. A successful save against default damage halves it. What remains is reduced and sorted into Severities like any other damage (see **Combat**).

To **halve** a result, halve each Severity's amount separately, rounding down. A point lost to rounding drops one Severity step — Major to Moderate, Moderate to Minor — and only a leftover Minor is lost; dropped points are not halved again. Halving 1 Major, 1 Moderate and 3 Minor leaves 1 Moderate and 2 Minor.

### Worked example — a compulsion

@player
Mira casts a Tier 1 enchantment that compels its target on a failed Wisdom save. Her target is a guard.

- She pays the Tier 1 Mana cost and casts with Arcana, in which she has a Dice Cap of {{Minimum Dice Count + 2}} and Competency +1. The Spell is a Main Action, so she must commit at least {{Main Action Minimum}} dice; she commits all {{Minimum Dice Count + 2}}, and they leave her Combat Pool.
- Her Roll carries Competency +1, her Inherent +1 and Guidance +1 for the Spell's Tier.
- The guard rolls his full Wisdom-save Dice Cap, {{Minimum Dice Count + 1}} dice, at no cost. He has Competency +1 and Inherent +1.
- His two Bonuses cross to Mira as Penalties and cancel her own Competency and Inherent, leaving her Guidance: she rolls at TN {{Base Target Number - 1}}. Her three Bonuses cross to him, and his own two cancel all but the Guidance: he rolls at TN {{Base Target Number + 1}}. Their Inherents match, so there is no Ascendancy.
- Mira scores a DoIS of {{Default Success Threshold + 2}} and the guard a DoIS of 1, for a Degree of Success of {{Default Success Threshold + 1}}. That reaches the Default Success Threshold: the guard fails his save and is compelled.

## Area Spells

@player
A Spell with an **Area** fills a shape on the map — a line, cone, square or circle, its size counted in 5-foot squares. The Area sits on a point you choose, or is centred on a target or on you and moves with that creature. A Spell with an Area and no target affects every creature inside.

{{table: Area Shapes | label: Shape | value: How its size is counted}}

You make **one** casting Roll. Every creature caught makes its own save, and each save is compared with your Roll separately, so the same cast can take one creature and spare its neighbour. Your Bonuses cross onto every save. Theirs all cross onto your Roll, where only the strongest of each Type counts — for Ascendancy you are measured against the highest-Tier creature you caught.

An Area with a Duration **lingers** on the map (see the **Map** chapter). Creatures inside when it appears save at once; if the Spell also lists a save for *entering* the Area or for *ending a turn* in it, the DM calls for that save when it happens. Once the Duration is up, the Area vanishes at the start of the caster's turn.

## Channeling and Concentration

@player
A **Channeled** Spell lasts only while you feed it. On each of your turns you must spend a Main Action **channeling** it, or it ends as that turn ends; the cast counts as the first turn's channel. Its Duration is therefore the longest it can last, not a promise. A channel costs Combat Pool dice — never fewer than {{Main Action Minimum}} — and what they do depends on the Spell:

| The Spell channels by… | Each turn's channel… |
|---|---|
| **Firing** | …produces the effect again: the dice are rolled as the Spell's attack or casting Roll, often at a new target. Your Combat Pool, not your Dice Cap, limits them. |
| **Filling** | …adds its dice to a **Reservoir** for later. The Dice Cap does not apply, unless the Reservoir is filled by the Successes of a Check. |
| **Maintaining** | …is pure upkeep, at exactly {{Main Action Minimum}} dice. |
| **Sustaining itself** | …is not needed. The cast fills a Reservoir once and the Spell then runs for its whole Duration. |

### Reservoirs

@player
A **Reservoir** is a pile of dice set aside for one Ability. The cast that conjures it may pour in no more than your Dice Cap. Most Reservoirs empty at the start of your turn; a self-sustaining Spell's Reservoir lasts as long as the Spell.

You **discharge** a Reservoir by spending dice from it, with the action the entry names (usually a Reaction), for the effect it describes. Shield of Faith is the model: when the warded ally is attacked, the caster rolls Reservoir dice as a block against that attack. Dice rolled out of a Reservoir obey your Dice Cap. A self-sustaining Spell never discharges; its Reservoir sets the size of what it does each turn.

### Losing concentration

@player
A Channeled Spell ends when a turn passes without a channel, when its Duration runs out, or when you drop it. Damage can also break it: whenever you take damage, make a **Concentration save** for each Channeled Spell you hold — a Check with the Skill you cast it with, at a Circumstance Penalty equal to the Spell's Tier plus the damage taken. Fail, and the Spell ends with whatever was in its Reservoir. Despite the name, this is a Skill Check, not a Saving Throw.

## Long Casts and Rituals

@player
An activation of a **full turn** takes both of your turn's Main Actions and takes effect as the turn ends. An activation of **several turns** is a **Long Cast**: commit both Main Actions on each of those turns, and the Spell takes effect at the end of the last. Let a turn end without that commitment, or fail a Concentration save, and the cast is cancelled — no effect, and the Mana is gone. An activation of **minutes or more** cannot be attempted in a fight at all.

A **Ritual** lets a Creature cast a Spell it does not have as an Ability. Rituals are kept inscribed in a Ritual book. Drawing the ritual circle costs gold and time set by the Spell's Tier — the **Ritual** table below, in gold and in minutes — and lets you cast that Spell once, at its normal activation time, Mana cost and any other cost. The casting consumes the circle.

{{table: Ritual | index: Tier | label: Drawing the circle}}

## Spells from Items

@player
A Spell packed into an item can be used by anyone: the item supplies the Spell, and the user casts it with one of the Spell's own casting Skills or the universal one.

| Form | Spells | Use |
|---|---|---|
| **Scroll** | Any | Read to cast once, as if you knew the Spell. No Mana. Used up. |
| **Wand** | Any | While held, its Spell is yours to cast, with your own Mana. Never used up. |
| **Potion** | Those that allow it | The drinker is the target. No Mana. Used up. |
| **Oil** | Those that allow it | Thrown at a target or applied to one beside you. No Mana. Used up. |

The item's Tier decides which Variant of a Tier-ladder Spell it holds. Prices are in the **Equipment** chapter.

## Magic Toxicity

@player
Magic that pours energy into a body leaves **magic toxicity** behind (see **Magical Tier** and **Conditions**). Potions and Oils always add it — more for a higher-Tier item, and more again when the item's Tier is above the drinker's. A Spell adds it when its entry says so, which chiefly means healing and restoring Mana; the toxicity goes to the creature that receives the magic. Scrolls and Wands add nothing of their own.

What happens next depends on the magic. **Beneficial** magic is refused by a body already above its Toxicity Threshold: no effect, and no toxicity added. **Harmful** magic is never refused. Either way, every point that lands above the Threshold is dealt as Charisma Ability Damage. A Spell is harmful if it has an attack roll or deals damage, and beneficial otherwise, unless its entry says differently.

## Talents

@player
A Talent's entry reads like a Spell's — activation time, range, target, duration, sometimes a save — but it has no School, and it costs Mana only when its entry says so. Using an active Talent in a fight costs Combat Pool dice equal to the Action Minimum of its action ({{Main Action Minimum}} for a Main Action, {{Bonus Action Minimum}} for a Bonus Action, {{Free Action Minimum}} for a Free Action) plus its Mana. If it calls for a Roll, you choose dice as for a Spell and those dice are the cost instead.

Some Talents carry a **required condition** and work only while you are in that state — a barbarian's fiercest tricks only while raging.

### Triggers and Reactions

@player
A **triggered** Talent takes no action. It fires during your own action when its Trigger happens — you attack, your attack hits, you roll a 1, you make a kill — and adds what its entry says: extra dice, extra damage, a reroll, a condition on the target. Further requirements (the target must be Flatfooted, the attack must be a bite) are in its description, and the DM rules on whether they are met.

A **Reaction** is used during another creature's Main Action, and a creature gets one Reaction per Main Action. A Reaction that rolls dice pays for them from the Combat Pool, at least {{Reaction Action Minimum}}; one that rolls nothing costs only its Mana.

### Channel Divinity

@player
**Channel Divinity** is a Cleric's family of Talents, granted by deity and domains (see **Characters**). Each use costs Mana — the deity's own channel more than the rest — and any Roll it calls for uses Invocation. For a channel that fires on a table, roll the dice you spend for **Channel Successes**, then roll on the table: the Channel Successes scale the entry, and the DM applies it.

Kesser's Gambit rolls on the Kesser Reversal Table:

{{table: roll_tables.yaml > Kesser Reversal Table > entries | columns: name=Result, effect=What happens | label: Roll}}

### Luck

@player
**Luck** rerolls dice. Its main source is a bard's Bardic Inspiration: a Main Action, some Mana and a Performance check, each Success putting one point of Luck into a Reservoir that empties at the start of the bard's next turn. Luck is spent as a Reaction and must be committed **before** the Roll is thrown. Each point rerolls one die by the Reroll rules of **Dice Resolution**: helping Luck rerolls a Roll's worst dice, and hindering Luck — which needs its own Talent — its best. No die is rerolled twice, a Roll cannot take more Luck than it has dice, and Luck from several sources does not stack: only the largest helping and the largest hindering amount count.

If the Performance check comes out below zero, the DM gains that many points of Luck instead, to spend the same way until the fight ends.

## Bonus Types

@player
Every Bonus and Penalty an Ability grants has a **Bonus Type**, and the stacking rule of **Dice Resolution** applies: of each Type, only your largest Bonus and your largest Penalty count.

{{table: Bonus Types List | label: Bonus Type | value: Comes from}}

Most Spell buffs and magical gear grant Guidance, so the larger wins rather than both adding. Bonuses are not only to Target Numbers: Abilities also grant typed Bonuses to Speed, damage reduction, damage resilience, saves and Attributes, which stack by the same rule.

## For the DM — Adjudicating Magic

@player
Most magic resolves by the numbers above; some is left to you.

- **Effects in words.** Charms, compulsions, illusions, magical darkness and mist describe what they do rather than count it. You decide what a failed save means in the scene.
- **Triggers and Areas.** You rule on whether a Trigger's conditions are met, and on whether a move counts as entering a lingering Area.
- **Tables.** When an Ability rolls on a table, the die picks the entry and you apply it.

## What lives in the next chapter

@player
Spells last for turns, minutes, hours and days, and a Ritual's circle takes time to draw. The next chapter, **Time and the Calendar**, sets out how the game measures all of it, from the {{Round Length}}-second Round to the months of the year.

## Common types

### Catalog Ability

The schema for entries in `spells.yaml` and `talents.yaml`. Looked up by display name (the key in the YAML file).

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | enum | yes | `spell` or `talent`. |
| `tier` | int or list of int | conditional | Required for Spells (the Spell's intrinsic magical density). Optional for Talents — when omitted, the using Creature's Tier supplies the value at evaluation time. A list indicates a Tier-axis Variant. Tier 0 → 0.5 in formulas. |
| `aspects` | list of string | no | An Aspect-axis Variant. Mutually exclusive with a list `tier`. |
| `school` | string | spell only | Key into `Spell Schools`. Rejected on Talents. |
| `activation_time` | string | no | Action Alias, Real-Time Alias, `"<N> turns"`, or `"<N> minutes"`. **Default `main`** when omitted on a Spell or Talent without a `trigger`. |
| `range` | string or int | no* | A named Range (e.g. `Close`), a bare integer in feet, or an inline per-rank Formula declared on the Spell (e.g. `"50*rank"`). *Optional when `trigger` is present.* |
| `target` | string | no | `"self"`, `"object"`, an integer string, or a Formula. **Optional.** A Spell with an `area` and no `target` affects every creature in the area. A Spell with both `target` and `area` uses the named target as the area's anchor (when the Area's `anchor` is `target`). A Spell with `target` only and no `area` directly names creatures or an object. |
| `requires_willing` | bool | no | Default `false`. When `true`, the Ability only affects willing targets; unwilling targets are unaffected even if no save is offered. Implicit `true` for `target: self`. |
| `save` | list of Save Spec | no | **Default `[]`** (no save) when omitted. |
| `attack_roll` | bool | no | Default `false`. |
| `trigger` | Trigger Spec | no | Presence makes the Ability fire during another action; see Triggers below. |
| `damage_type` | string | no | Key into the damage_types catalog. Required when any damage Effect omits explicit Severity. |
| `threshold` | non-neg int | conditional | Required when `damage_type: physical`; rejected otherwise. |
| `effects` | list of Effect | no | Unconditional Effects — apply regardless of save. |
| `effect_hash` | dict | no | Named values referenced from `description` and Effect strings. |
| `channel` | Channel Block | no | Presence makes the Ability a Channeled Ability. |
| `reservoir` | Reservoir Block | no | Presence gives the Ability a Reservoir. Required when `channel.mode` is `reservoir` or `auto`. |
| `prerequisite` | string | no | Catalog Ability name of a lower-tier this spell is based upon. This prerequisite spell will sometimes be required to learn before this one can be learned. |
| `inherits_from` | string | no | Catalog Ability name of a parent Ability whose fields seed this entry's defaults. The Abilities module resolves a child by starting with the parent's resolved Ability, then shallow-overriding with the child's declared fields. Used for talent families. |
| `mana_cost` | integer | `0` | Mana spent on activation (Talents only — Spells use the per-Tier Mana Cost table in `abilities_config.yaml`). |
| `required_condition` | string | no | Names a Condition the user must currently hold for this Ability to be available. Combat surfaces the Ability only when the Creature has the named Condition active. Example: `rage` for talents that only function while raging. |
| `duration` | string | no | Free-form. |
| `description` | string | no | Free-form; `{name}` and `{aspect}` substitution. |
| `skills` | list of string | no | Keys into `Casting Skills List`. **Default `[arcana]`** when omitted. |
| `items` | list of string | spell only | Keys into `Item Forms`. **Default `[]`** when omitted. Rejected on Talents. Universal forms appended at lookup unless `item_only`. |
| `item_only` | bool | spell only | Default `false`. Suppresses universal item form appending. Rejected on Talents. |
| `polarity` | enum | spell only | One of `positive` or `forced` — the Spell's Toxicity Source Kind (see `conditions/conditions_design.md`). `positive` marks a beneficial Spell (cure, buff, voluntary attunement) whose Magic Toxicity is subject to the Toxicity Block; `forced` marks a harmful or involuntary Spell whose Toxicity always applies. **Optional** — when omitted it is inferred at resolution time (`forced` when the Spell has `attack_roll: true`, a `damage_type`, or a damage Effect string; `positive` otherwise). Rejected on Talents. |
| `area` | Area | no | Turns the Ability into AOE. |
| `properties` | list of string | no | Keys into `Properties`. |
| `prefix`, `suffix`, `name` | list of string \| null | no | Per-Variant name parts. Parallel to the Variant Axis. |
| `variant_overrides` | list of (dict \| null) | no | Sparse per-Variant overrides. |
| `modifiers` | list of Modifier Entry | no | Always-On Modifier read-through. See Operations. |
| `target_escape_save` | Target Escape Save | no | When present, the Ability's target may spend the indicated action on its own turn to attempt a new save; success ends the effect early. |
| `grants_equipment` | list of string | no | Equipment IDs the Ability grants to the Creature. Used by the Natural Attack Talent and similar; the granting Class or Race fills in the list. Schema defined here; aggregation and weapon lookup are deferred to the Equipment domain. |

### Defaults

The loader applies these defaults to a Catalog Ability that does not declare the field:

- `activation_time` → `main`
- `skills` → `[arcana]`
- `items` → `[]`
- `save` → `[]`
- `requires_willing` → `false` (or `true` if `target: self`)

Authors should omit a field when the default applies. The lookup result always carries the resolved (defaulted) value.

**Universal Item Forms are appended automatically.** Spells do not need to list `scroll` and `wand` in their `items` field — they are added at lookup time (unless `item_only: true`). List only non-universal item forms (`potion`, `oil`).

### Modifier Entry

Field on a Catalog Ability or on an entry in `modifier_abilities.yaml`. Shape:

| Field | Type | Description |
|---|---|---|
| `target` | string | What the bonus applies to (`speed`, `attack`, `perception`, etc.). The target vocabulary is owned by the consuming domain (Combat, Equipment, etc.) — Abilities does not police it. |
| `type` | string | Bonus Type Name — must name an entry in the `Bonus Types List` config. Validated by Abilities at load time. |
| `descriptors` | list of string | Optional scope tags. Free-form. |
| `add` | signed number or Formula | Value to apply. May be a Formula of `level` / `tier` / `caster_tier`. Abilities returns Formulas verbatim; consumers evaluate. |

The Abilities module validates `type` against the `Bonus Types List` and returns the Modifier Entry verbatim. Aggregation across Abilities, type-stacking rules, and Formula evaluation against the Creature's level happen in Creatures and Combat.

### Save Spec

| Field | Type | Description |
|---|---|---|
| `attribute` | enum | One of `none`, `str`, `dex`, `con`, `int`, `wis`, `cha`. |
| `condition` | enum or absent | `on_fail` or `on_fumble`. Absent means unconditional. |
| `save_target` | enum | Who rolls the save. Default `target` (the Ability's named target). Other values: `observers` (creatures who perceive the effect), `area_creatures` (every creature in the Ability's `area`), `caster` (the caster rolls). |
| `<outcome_key>` | Effect string | One entry per Save Outcome Key — `fail` (required), `success` (optional), `fumble` (optional). |

An Effect string is one of:

- `"0"` — no effect on that outcome.
- An Effect Name from `conditions/effect_names.yaml`.
- A damage Formula (per the rules in *Damage Object*).
- The directive `halved` — the spell's full output is halved per the *Halved Effect* rule below. Useful when a successful save reduces but does not negate the spell's output.

**Halved Effect.** When a Save Outcome's Effect is `halved`, the consuming domain applies a cascading downgrade to the spell's outputs (damage, healing, and named effects whose `amount:` is numeric). The cascade halves each Severity's *original* count separately — downgraded amounts are never halved a second time.

For each Severity from Major down to Minor:
1. Divide the original count by 2, rounded down. Keep the quotient at this Severity.
2. The remainder (if any) downgrades by one Severity step (Major → Moderate → Minor → discarded).
3. Add the downgraded remainder to the next-lower Severity's *added* tally (not its original count, which is halved separately in the next iteration).

**Worked example:** starting 3 Minor, 1 Moderate, 1 Major.
- Major (1): halves to 0 with remainder 1. Remainder downgrades — adds 1 Moderate.
- Moderate (original 1, ignoring the added Moderate from Major): halves to 0 with remainder 1. Remainder downgrades — adds 1 Minor.
- Minor (original 3): halves to 1 with remainder 1. Remainder is below Minor — discarded.
- Combine: Minor = 1 (halved) + 1 (from Moderate downgrade) = 2. Moderate = 0 (halved) + 1 (from Major downgrade) = 1. Major = 0.
- Final: 2 Minor, 1 Moderate, 0 Major.

### Target Escape Save

| Field | Type | Description |
|---|---|---|
| `action` | string | Activation Time string for the action the target spends on its own turn. |
| `attribute` | enum | Save attribute the target re-rolls. One of `str`, `dex`, `con`, `int`, `wis`, `cha`. |

Resolution is caller-side: Combat / Conditions presents the option to the target on its turn; on success, the effect ends.

### Channel Block

Presence of a Channel Block makes a Catalog Ability a Channeled Ability. The Combatant spends a Main Action on it each of their turns (the cast itself counts as the first such channel) or the spell ends. Reservoir-mode and auto-mode Channeled Abilities require a Reservoir Block (see below) — the Channel Block does not duplicate Reservoir mechanics.

| Field | Type | Default | Description |
|---|---|---|---|
| `mode` | enum | required | One of `fire`, `reservoir`, `maintain`, `auto`. See per-mode notes below. |
| `apply_on_cast` | bool | `false` | Controls whether the channel/discharge effect fires on the initial cast. When `true` in **fire** mode: the cast fires the channel effect (using the cast's dice). When `true` in **reservoir** mode: the cast fires the Discharge effect once using the cast's dice — the Reservoir is **not** filled by the cast. When `false`: the cast applies only the spell's top-level effect (if any); the channel/discharge effect waits until the first subsequent channel. Examples: Heal's `apply_on_cast: true` (heal damage from top-level + reduce bleeding from channel — both fire on cast); Grasp's `apply_on_cast: true` (reservoir mode — cast fires the climb boost from cast dice, no Reservoir fill); Create Illusion's `apply_on_cast: false` (cast resolves the save against the illusion; subsequent channels handle DM-adjudicated alterations). |
| `retarget` | bool | `false` | Whether the channel may pick a new target each turn (fire-mode spells with a single target). |
| `description` | string | absent | Free-form description of what the channel does each turn. |
| `attack_roll` | bool | `false` | When `true`, the channel resolves as an attack roll using the channeled dice. (fire-mode only.) |
| `save` | list of Save Spec | empty | Save Specs evaluated against the channel effect. (fire-mode only.) |
| `effect_hash` | dict | empty | Channel-effect values. Namespaced separately from the top-level `effect_hash`. |

**Channel Mode notes:**

- **fire**: each turn's channel fuels the spell's effect directly. The channeled dice serve as the Roll (when `attack_roll` or a Save is involved) or drive the effect formula (e.g. Heal's bleed reduction scales with successes on the casting check). Channel dice are Main Action Minimum to Combat Pool Remaining; the Dice Cap does not apply, because the dice are poured straight into the effect rather than rolled as a skill Check.
- **reservoir**: each turn's channel fills an associated Reservoir Block. With `fill.source: channel_dice` the channeled dice are poured into the Reservoir (Dice Cap does not apply, as in *fire*). With **`fill.source: check_successes`** (Bardic Inspiration) the channel instead rolls a real **skill Check** — each Success fills the Reservoir — so the dice **are** bounded by that skill's **Dice Cap** (Main Action Minimum up to `min(Dice Cap, Combat Pool Remaining)`). The Reservoir is consumed by its Discharge.
- **maintain**: channel is upkeep only. No fueled effect, no Reservoir. Channel always costs exactly Main Action Minimum dice. The spell's text and the GM resolve what the maintained effect looks like.
- **auto**: the cast itself fills the associated Reservoir Block (which must have `reset: persistent`). After cast, the spell self-sustains — no Main Action channel is required each turn. The Reservoir is not Discharged; instead it defines the per-turn effect's magnitude (e.g. Spiritual Weapon attacks each turn using a number of dice equal to its Reservoir). The spell ends when its declared `duration` expires.

### Reservoir Block

Presence of a Reservoir Block gives a Catalog Ability a Reservoir — a tagged counter filled from a configured source and consumed by a Discharge. Reservoirs may appear on Channeled Abilities (paired with `mode: reservoir` or `mode: auto`) or on standalone Abilities like Talents (e.g. Bardic Inspiration).

| Field | Type | Default | Description |
|---|---|---|---|
| `fill.source` | enum | required | How the Reservoir gains amount. `channel_dice` (per-channel dice add to the Reservoir, used by channeled spells; Dice Cap does not apply) or `check_successes` (each Success on a designated Check adds one — the dice are a real skill Check, so they obey that skill's Dice Cap). *(configurable)* |
| `fill.ratio` | int | `1` | Multiplier applied to the Fill Source's input. Spiritual Weapon uses 1; ratios above 1 grant amplification (n channeled dice → ratio × n Reservoir). |
| `reset` | enum | `per_turn` | When the Reservoir resets to zero. `per_turn` (default) resets at the start of the holder's turn; `persistent` never resets and ends only with the owning Ability. Auto-mode Channeled Abilities use `persistent`. |
| `discharge` | Discharge | optional | Defines how the Reservoir is spent. Omitted for auto-mode reservoirs (whose amount drives a per-turn effect without being consumed). |

**Discharge**:

| Field | Type | Default | Description |
|---|---|---|---|
| `action` | enum | required | Action category for the Discharge — `bonus`, `reaction`, `free`, or `main`. |
| `amount` | int or range | `"2..dice_cap"` | The amount of Reservoir consumed per Discharge. May be a fixed integer or a range. The default `"2..dice_cap"` lets the caller spend anywhere from Reaction Action Minimum dice up to the Dice Cap. Fixed amounts (e.g. `1`) are valid for Abilities where each Discharge costs a constant. |
| `description` | string | absent | What the Discharge does. May reference the chosen amount via `{amount}`. |
| `attack_roll` | bool | `false` | Whether the Discharge resolves as an attack roll. |
| `save` | list of Save Spec | empty | Saves evaluated on the Discharge effect. |
| `effect_hash` | dict | empty | Discharge-effect values. May reference `{amount}`. |

A Reservoir Discharge with `amount: "X..dice_cap"` follows the normal Dice Cap rule when the discharge produces a Roll — Dice Cap caps the spend just like any other Roll. Channeling itself (filling the Reservoir) is the exception to Dice Cap; spending from a Reservoir is not.

### Area

| Field | Type | Default | Description |
|---|---|---|---|
| `shape` | enum | required | `line`, `cone`, `square`, `circle`. *(configurable)* |
| `size` | non-neg int or Formula | required | In 5-foot squares. Never feet. May be a Formula string (e.g. `"rank"`, `"8*rank"`) resolved against `rank` and floored at cast time, the same way `range` and `target` scale. |
| `anchor` | enum | `point` | Where the area is centered. `point` (caster designates a point at cast time), `target` (centered on and moves with the Ability's named target), `caster` (centered on and moves with the caster). |
| `on_enter` | Save Block | null | Save Block applied to any Creature that enters the Zone after cast. Becomes the `on_enter` trigger of the Conditions Zone Effect when the spell creates a Zone. |
| `on_end_of_turn` | Save Block | null | Save Block applied to any Creature that ends a turn inside the Zone. Becomes the `on_end_of_turn` trigger of the Conditions Zone Effect. |

The top-level `save:` block on a spell with an `area:` doubles as the Zone's `on_create` trigger — fired on cast for every Creature already inside the Zone. The spell-domain casting routine calls Conditions' *Create Zone Effect* with the three triggers (on_create from the top-level save, on_enter, on_end_of_turn) and the area geometry; Atlas and Conditions own the Zone's lifecycle from there.

### Trigger Spec

| Field | Type | Required | Description |
|---|---|---|---|
| `on` | enum | yes | Action-name events (`attack_check`, `attack_action`, `on_hit`) fire during the Creature's own action of that name or class. Event-name triggers (`on_kill`, etc.) fire on a specific occurrence. *(configurable)* |
| `condition` | string | no | Scope tag referenced against Combat's `Trigger Conditions` catalog. Unknown values produce a load-time warning and never fire at runtime. |
| `effect` | Trigger Effect | yes | Structured one-shot outcome. |

### Trigger Effect

| Field | Type | Description |
|---|---|---|
| `kind` | string | Outcome shape. Recognized today: `bonus_dice` (adds dice to the triggering Roll), `bonus_damage` (adds damage to the triggering attack after it lands; carried by abilities like Sneak Attack and Rend), `scale` (a scaling adjustment to the Roll, e.g. reroll a die), `ui_reveal` (Combat surfaces the option to the GM without auto-firing), `invoke_named_effect` (the consuming domain applies a named effect from `conditions/effect_names.yaml`). |
| (kind-specific) | — | Further fields depending on `kind`. The Abilities module does not interpret them. |

### Damage Object (deferred damage)

Returned from Effect classification when an Effect is a damage expression.

```
{
  kind: 'damage',
  formula: '<expr>',
  damage_type: <string|null>,
  severity: <string|null>,
  context: { rank, tier, ...effect_hash }
}
```

`severity` is the explicit per-Effect Severity if the string had one, otherwise `null` — leaving lookup of the default to the consumer, since the damage_types catalog isn't an Abilities-module dependency at evaluation time. The caller later supplies `success`, `critical`, and `attribute` to evaluate.

### Effect Classification Result

One of:
- `{ kind: 'none' }` — for the literal strings `"0"` and `"none"`.
- `{ kind: 'effect', name: '<string>' }` — for any other non-damage string.
- A Damage Object — for damage expressions.

## Public entry points

### Look up a Catalog Ability by name

Input: ability name (display string), optional `axis_index` (default 0).

Returns the resolved Variant at `axis_index`:
- Inheritance resolved (if the Ability declares `inherits_from`, the parent's resolved Ability is the base and the child's declared fields shallow-override it). The parent itself is resolved first, recursively. Circular inheritance is a configuration error.
- Variant Overrides applied.
- Effect Hash resolved against the merged Ability.
- Variant name constructed.
- `{name}` and `{aspect}` substitution performed on `description` and Channel Block `description`.
- Universal Casting Skills appended (Spells only).
- Universal Item Forms appended (Spells, unless `item_only`).

Out-of-range `axis_index` is an error. Looking up a name that doesn't exist returns null.

### Look up a Stateful Ability by name

Returns `{ name, description }` from `stateful_abilities.yaml`, or null. Carries no schema — Conditions owns behavior.

### Look up an Always-On Modifier Ability by name

Returns `{ name, description, modifiers }` from `modifier_abilities.yaml`, or null. Modifier values are returned verbatim; Formulas in `add` are deferred.

### Resolve a Catalog Ability's range

Input: the Catalog Ability and an optional per-cast `reach`.

Returns range in feet:
- A bare integer `range` is returned as-is.
- A named Range is looked up in `Range Formulas` and evaluated against `rank` and the caller's `reach` (defaulting to `Default Reach Feet`).
- Any other string is treated as an inline Formula declared on the Spell and evaluated against `rank` and `reach` (and floored). This is for one-off per-rank ranges (e.g. `"50*rank"`) that don't warrant a shared named Range. A string that is neither a known Range nor an evaluable Formula (a typo'd Range name) is a load-time validation error.

### Resolve a Catalog Ability's activation time

Returns a structured activation result rather than a single number, since Action-aliased and Real-Time-aliased activations are not directly comparable:

```
{ kind: 'action', alias: <name>, value: <number> }      # Action Alias
{ kind: 'real_time', alias: <name>, minutes: <number> } # Real-Time Alias
{ kind: 'turns', turns: <number> }                      # "<N> turns"
{ kind: 'real_time', minutes: <number> }                # "<N> minutes"
```

Aliases are looked up in `Action Aliases` and `Real-Time Aliases`. `"<N> turns"` and `"<N> minutes"` strings are parsed directly. Conversion between turns and wall-clock minutes is owned by Combat / Timekeeping — the Abilities module never converts; callers who need both ask Combat for turn duration when they want one in terms of the other.

The `value` field on an Action result is a categorical label, not a duration. Combat maps it to an action category.

### Resolve a Catalog Ability's target

Returns `'self'` or a non-negative integer count. Formula strings evaluate against `rank` and the Effect Hash. A target count of zero means the Ability has no valid targets and cannot be cast.

### Resolve an Area's size

Input: an Area `size` value and a `rank`. Returns a concrete non-negative integer count of 5-foot squares: a bare integer (or numeric string) is returned as-is; any other string is a Formula evaluated against `rank` and floored. Returns `null` when the value is missing or the Formula references an unbindable name, so the caller can fall back rather than crash. The casting pipeline resolves the size before handing the footprint to Atlas (which requires an integer).

### Resolve a Spell for item consumption

Input: a Spell name and the consumed Item's `tier`.

Returns the consumption view the Equipment domain routes at *Consume Item* time, or null for an unknown name:

```
{ effects: [ { <effect-key> => value }, ... ],
  polarity: 'positive' | 'forced' }
```

`tier` selects the Variant on a Tier-axis Spell (the Variant whose Tier matches the Item, falling back to the nearest in-range index); it is ignored on a single-Variant or Aspect-axis Spell. The Spell is resolved to that Variant, then its consumption-relevant outputs are flattened into the `effects` list. Each entry carries one of these keys:

- `minor_damage` / `moderate_damage` / `major_damage` — Severity-keyed magnitudes drawn from the resolved Effect Hash. The sign follows polarity: a `positive` (cure) Spell emits **negative** magnitudes (Equipment routes them to *Apply Heal*); a `forced` Spell emits **positive** magnitudes (routed to *Apply Damage*). All Severity keys present on one Variant share a single Effect Hash entry.
- `temp_hp` — a Ward magnitude from the Effect Hash.
- `mana` — a Mana-restore magnitude from the Effect Hash.
- `damage` — `{ amount, type }` from an explicit damage Effect string. The amount is the Effect's Formula evaluated with the Effect Hash plus `rank = 0` and the Variant's Tier; the damage-only variables `success` / `critical` / `attribute` default to `0` (a consumed Item rolls no casting check). An Effect string whose Formula still references an unbound name is skipped rather than raising. `type` is the Spell's Damage Type, omitted when it has none.

`polarity` is the Spell's `polarity` field when declared, otherwise the inferred value (see the field table). A Spell with no consumption-relevant Effects — e.g. a pure attack Spell whose damage is computed implicitly by Combat — returns an empty `effects` list and still reports its polarity.

This entry point is a convenience view layered on the standard lookup pipeline; it adds no new resolution rules beyond selecting the Variant and projecting its Effects into the Equipment-facing shape.

### Is a Spell Item-Only?

Input: a Spell name. Returns the Spell's `item_only` flag as a boolean — `false` for an unknown name or a Spell that does not declare it. Equipment's *Is Item-Only?* delegates here so UI surfaces can suppress non-item invocation paths without depending on Abilities directly.

### Get an Ability's Trigger

Input: ability name. Returns the Trigger Spec verbatim, or null if the Ability has no `trigger` field (or isn't a Catalog Ability). The Abilities module does not evaluate the Trigger.

### Get an Ability's Modifiers

Input: ability name, optional `source: 'class' | 'race'`. Returns the `modifiers:` list from the Ability's entry — across Catalog Abilities, `modifier_abilities.yaml`, and any other Ability flavor that carries `modifiers:`. Returns an empty list if none.

### List Catalog Abilities by Type / School

Returns Catalog Abilities matching the given `type` and/or `school` filter. Filters on un-resolved Ability data; does not iterate Variants.

### Classify an Effect string

Input: an Effect string and the context Effect Hash. Returns an Effect Classification Result. For damage expressions, parses the optional inline Severity and constructs a Damage Object with the appropriate context.

### Evaluate a deferred Damage Object

Input: a Damage Object and the caller-supplied `success`, `critical`, `attribute`. Returns the integer damage. Negative values clamp to 0.

The `success` / `critical` semantics are caller-defined: defender's save results inside a Save Outcome, caster's casting-roll results inside an Unconditional Effect.

### Resolve the Channel Block

The Channel Block has its **own Effect Hash, namespaced separately** from the top-level — the two never share variable names at evaluation time. Resolution mirrors the top-level lookup path: apply Variant Overrides to the block's fields, resolve the block's Effect Hash, substitute `{name}` and `{aspect}` in the block's description.

The Channel Block's `attack_roll` and `save` (in fire mode) and the Activation's `attack_roll` and `save` (in reservoir mode) are **independent** of the Ability's top-level versions.

**Rule: a Channeled Ability ends when channeling stops.** Any Catalog Ability with a Channel Block (fire / reservoir / maintain modes) terminates at end-of-turn on any turn where the caster did not spend a Main Action channeling it. The `duration` value is the **maximum** time the effect can be sustained, not a guaranteed duration. Auto-mode is the exception: the cast fills the Reservoir, and the spell self-sustains for its full `duration` without needing per-turn channeling.

## Operations

### Variant resolution

A Catalog Ability's Variants are indexed by exactly one **Variant Axis** — `tier` (a list of integers) or `aspects` (a list of opaque labels). The two are mutually exclusive (validator rejects both). A Catalog Ability that declares neither has a single Variant at index 0.

Resolving a Variant at `axis_index` follows a fixed order:

1. **Apply Variant Overrides.** If `variant_overrides[axis_index]` is a dictionary, shallow-replace each key on a copy of the base Ability. **A `null` override value removes the key entirely** — this is how a higher tier opts out of a Channel Block, or how one aspect of a multi-element Spell drops a save the other aspects retain. List- and dictionary-valued overrides replace the base value wholesale; there is no deep merge.
2. **Resolve the Effect Hash** for `axis_index` against the merged Ability.
3. **Construct the Variant name.** If `name[axis_index]` is a non-empty string, that's the name verbatim and `prefix`/`suffix` at this index are ignored. Otherwise the name is `<prefix> <Ability name> <suffix>` with empty/null parts dropped.
4. **Substitute description tokens.** `{name}` tokens replaced from the resolved Effect Hash. When axis is `aspects`, `{aspect}` is replaced with `aspects[axis_index]`. Substitution applies to `description`, the Channel Block's `description` (and Activation `description` in reservoir mode), and any future display-string field.

Variant Overrides may not change `tier`, `aspects`, `prefix`, `suffix`, `name`, or `variant_overrides` itself — those are structural or have their own parallel-list mechanisms.

### Effect Hash resolution

The Effect Hash is a flat dictionary, but its values cross-reference each other through Formulas. Resolution walks entries in declaration order, evaluating each against a context that already contains every previously-resolved name:

- A list-valued entry on a multi-Variant Ability uses the value at `axis_index`.
- A string-valued entry is treated as a Formula and evaluated.
- Any other value is taken verbatim.

`tier` is always present (Tier 0 → 0.5 per project convention). `rank` is always present. `caster_tier` — the casting Creature's Tier — is supplied by the casting pipeline at cast time; it differs from `tier` (the Ability's own Tier) and lets an Effect scale with whoever cast it rather than with the affected Creature. An Ability whose `modifiers` must resolve against the caster (e.g. Magic Weapon, whose bonus follows the *caster's* Tier even when the weapon's wielder is someone else) plumbs `caster_tier` into the Active Effect's `metadata` through an Effect Hash entry, the same way `rage` plumbs `level`. Names from the Effect Hash become available as soon as they're resolved, so a later entry's Formula may reference an earlier entry's value.

Damage-expression-only variables (`success`, `critical`, `attribute`) must **not** appear in Effect Hash Formulas, Range Formulas, or Target Formulas — those are resolved before any roll. The validator does not catch this; it surfaces as an unresolved-name error at evaluation time.

### Damage Type, Severity, and Threshold

The Abilities module enforces the rules linking damage Effects to the damage_types catalog:

- A Catalog Ability may declare a `damage_type` matching a name in the catalog.
- A damage Effect's Severity comes from the **explicit per-Effect form** (`"<formula> <severity> damage"`) when present, otherwise from the Ability's `damage_type`'s default Severity.
- A Catalog Ability whose `damage_type` is **`physical`** must additionally declare a non-negative integer `threshold`. Physical damage opts into Runtime Bucketing, so Severity is decided at damage-application time by Combat — but the Threshold input is data the Ability itself must carry.
- A `threshold` field on a non-physical Ability is a validation error.
- Every damage Effect must have a determinable Severity (explicit per-Effect or via the Ability's `damage_type`).
- A Catalog Ability with `attack_roll: true` and **no** declared damage Effects is allowed — Combat computes implicit damage (`Tier + Degree of Success + attack bonus`).

Aspect-axis Abilities that vary `damage_type` per aspect declare it as a parallel list (e.g. `damage_type: [fire, acid, electricity, cold]`).

### Effect classification

Every Effect string falls into exactly one of three kinds, by string shape:

- `"0"` or `"none"` → `{ kind: 'none' }`.
- `"<expression> damage"` or `"<expression> <severity> damage"` → Damage Object.
- Otherwise → `{ kind: 'effect', name: <string> }`. The Abilities module does not check that the name exists in any catalog — that's the Conditions module's job at apply time.

### Universal forms and skills

`Universal Spell Casting Skills` and `Universal Item Forms` are appended **implicitly** at lookup time, not stored on the Ability. Data files must not list a universal entry in `skills` or `items` (validator rejects). Spells get universal skills/forms appended; Talents do not. Item-Only Spells do **not** receive universal Item Forms — only the explicit list applies, since the universal forms (scroll, wand) wouldn't make sense for them.

### Conditional saves

A Save Spec may carry a `condition` field (`on_fail` or `on_fumble`) that gates whether the save is offered. The Abilities module reports conditional saves verbatim; **dispatch is the caller's job** — the Abilities module never inspects prior save results.

`fumble` outcome dispatch is also caller-side: when a save's Degree of Failure meets or exceeds the Default Fumble Threshold, the `fumble` outcome (if defined) replaces the plain `fail` outcome.

### Trigger lookup

Triggers are exposed via two paths:

- **On Catalog Abilities directly.** If a Spell or Talent has a `trigger` field, `GET_TRIGGER(name)` returns it. Procedural class/race features (sneak_attack, halfling_luck, etc.) live as Talents with a `trigger` field and typically omit `activation_time` / `range` / `target`.
- **Trigger is not evaluated here.** The Abilities module returns the Trigger Spec; the consuming module evaluates `condition` and applies `effect`. This keeps the Abilities module ignorant of action semantics, the same way it's ignorant of dice rolls.

A Catalog Ability may have a Trigger, a normal cast pipeline, both (an active Ability that also acts as a rider when the Creature performs the right action), or neither.

### Always-On Modifier read-through

Flat numeric bonuses while the Creature has the Ability are handled by Modifiers via the `modifiers:` field. `GET_ABILITY_MODIFIERS(ability_name)` returns the list across every Ability flavor (Catalog Ability, Always-On Modifier Ability, Stateful Ability that also grants passive modifiers). Actual application — summing across earned Abilities, posting to bonus calculations, evaluating Formulas in `add` against the Creature's level — is the Modifiers / Creatures path.

## Responsibilities

### Owned by the Abilities domain

- Loading and validating `spells.yaml`, `talents.yaml`, `stateful_abilities.yaml`, `modifier_abilities.yaml`, `roll_tables.yaml`, and `abilities_config.yaml`.
- Loading and validating **Roll Tables** (`roll_tables.yaml`): named die-tables an Ability fires on. A Catalog Ability points at one through its `roll_table:` field (a Talent like Kesser's Gambit → the *Kesser Reversal Table*). Each table declares a `die` and one `entries` row per face, keyed `1..die`, each with a `name` and `effect`; the validator rejects a missing/out-of-range face, an entry missing its `name`/`effect`, and any Ability whose `roll_table` names a table that does not exist. Exposed through `Abilities.roll_table(name)` and `Abilities.roll_table_for(ability)`. The combat-side roll + resource spend lives in the Encounter domain (`encounter_roll_table_stub.md`); Abilities only stores the table.
- Schema validation: rejecting unknown Types, Schools, Casting Skills, Item Forms, Properties, Save Attributes, Save Outcome Keys, Action Aliases, Real-Time Aliases, Range names, Area Shapes, Damage Type names, Trigger Event names, Bonus Type names, Polarity values; checking Variant parallel-list lengths; rejecting overrides of structural fields; rejecting universal-entry leaks; rejecting Abilities that declare both `tier` (as a list) and `aspects`; rejecting `school`/`items`/`item_only`/`polarity` on Talents.
- Validating Severity rules: every damage Effect has a determinable Severity; `damage_type: physical` requires `threshold`; `threshold` rejected on non-physical Abilities.
- Resolving Variants: applying Overrides, constructing names, performing `{name}` and `{aspect}` substitution.
- Resolving Effect Hash with axis-indexed picks and cross-reference Formula evaluation.
- Classifying Effects (none / named / damage), parsing optional inline Severity from damage Effect strings.
- Building partial contexts and evaluating damage Formulas when `success` / `critical` / `attribute` are supplied.
- Resolving the Channel Block.
- Implicitly appending Universal Casting Skills and Universal Item Forms.
- Resolving `activation_time` to a structured action / real-time / turns result, `range` to feet, `target` to either `'self'` or a count.
- Resolving a Spell to its Equipment-facing consumption view (routed `effects` list + `polarity`), and reporting a Spell's `item_only` flag.
- Filtering and listing Catalog Abilities by Type and/or School.
- Returning Trigger Specs verbatim from `GET_TRIGGER`.
- Returning `modifiers:` lists verbatim from `GET_ABILITY_MODIFIERS`.
- Returning `{ name, description }` for Stateful Abilities.

### Explicitly *not* owned here

- **Rolling dice and resolving saves.** Dice Resolution and Combat.
- **Damage Type behavior.** Severity defaults, Mechanics, Runtime Bucketing live in damage_types (folded into Combat) and its consumers.
- **Computing implicit damage from attack rolls.** Combat.
- **Applying named effects.** Conditions.
- **Active-effect bookkeeping, channel and Reservoir tracking.** Conditions and Combat.
- **Consuming spell slots, charges, mana.** Creatures and Item modules.
- **Mapping Creatures to known Abilities.** Creatures.
- **Determining who is in an `area`.** Combat computes overlap.
- **Property mechanics.** The keyword list is validated here, but behavior of each property lives elsewhere.
- **Magic Toxicity application.** Conditions reads and applies.
- **Evaluating Trigger conditions or applying Trigger Effects.** The consuming module's job.
- **Aggregating `modifiers:` entries into Creature bonus totals.** Creatures (with type-stacking rules from Combat).
- **Bonus Type stacking semantics** (which Bonus Type stacks with itself, which doesn't). Combat owns this.
- **Stateful Ability behavior.** Conditions.

### Unassigned (no current owner)

- Validating that a passed `rank` is non-negative.
- Tracking which Properties exist purely for display vs. those with mechanical effects.
- Cross-domain validation that every name in named-Effect strings whose `mechanics` are non-empty corresponds to a Condition Mechanic the Conditions module actually understands.
- Cross-domain validation that the `condition` and `condition_name` strings inside damage_types Mechanics resolve to real concepts.
