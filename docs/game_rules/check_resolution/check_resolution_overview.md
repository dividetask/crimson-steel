# Checks

Whenever you attempt something that could fail, you make a **[[Check]]**.
Pushing a boulder, picking a lock, recalling a rumor, swinging a blade,
shrugging off a poison — each is resolved the same way: you gather a handful
of dice and roll them against a **[[Target Number]]**.

Every die has **{{Die Size}}** sides, and a die *succeeds* when it rolls at or
above the Target Number. Add up your successes and you have your result.

There are several kinds of Check, and the later sections of this chapter spell
each one out:

- **[[Attribute Check|Attribute Checks]]** — raw tests of a single attribute.
- **[[Aptitude Check|Aptitude Checks]]** — tests of a trained skill.
- **[[Saving Throw|Saving Throw Checks]]** — resisting something done to you.
- **[[Opposed Aptitude Check|Opposed Aptitude Checks]]** — skill against skill.
- **Single-Target, Multi-Target, and Area [[Spell Check|Spell Checks]]** — landing a spell.
- **[[Combat Check|Combat Checks]]** — striking and defending in a fight.

What changes between them is mostly *how the bonuses and penalties are shared*
among the creatures involved. The rest of the machinery is the same, so we
cover it first.

# The Dice Cap

Each Check rolls between **{{Minimum Dice}}** and **{{Maximum Dice Formula}}**
dice. The exact number — the **[[Dice Cap]]** — comes from the most relevant
[[Attribute]] for the task together with the creature's **[[Prowess]]**:

> **Dice Cap** = {{Dice Cap Formula}}

A higher attribute or more Prowess earns you more dice, and therefore more
chances to roll a success.

```test
# Dice Cap — with Minimum Dice 3 and Dice Range 5 for these cases.
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

# Bonuses and Penalties

A Check's Target Number is rarely the bare base. Circumstances, equipment, and
spells shift it: a **[[Bonus]]** lowers the Target Number (making the Check
easier), and a **[[Penalty]]** raises it (making the Check harder).

Every Bonus and Penalty has a **[[Bonus Type|type]]** — Circumstance, Guidance,
Equipment, and the like. **Bonuses and Penalties of the same type do not
stack.** Only the single largest Bonus of each type and the single harshest
Penalty of each type are counted; the rest are ignored.

Once same-type stacking is settled, add up the surviving Bonuses and subtract
the surviving Penalties. That total is the **[[Dice Modifier]]**.

```test
# Dice Modifier — same-type stacking keeps only the strongest of each type.
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

# Starting Value

A Target Number can never drop below **{{Minimum Target Number}}** or climb
above **{{Maximum Target Number}}**. When the Dice Modifier is large enough to
push it past one of those limits, the leftover doesn't vanish — it becomes a
**[[Starting Value]]** that is carried into your score: a head start when you
were over-qualified, or a hole to climb out of when you were overmatched.

> **Starting Value** = {{Starting Value Formula}}

```test
# Starting Value — with Minimum Target Number 3 and Maximum Target Number 9.
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

# The Check Target Number

With the Dice Modifier in hand, the Check's Target Number is the
**[[Base Target Number]]** ({{Base Target Number}}) shifted by the Dice
Modifier, then clamped to its allowed range:

> **Check Target Number** = {{Check Target Number Formula}}

If the shifted value would fall below {{Minimum Target Number}} it is set to
{{Minimum Target Number}}; if it would rise above {{Maximum Target Number}} it
is set to {{Maximum Target Number}}. (Any overflow becomes the Starting Value
described above.)

# Degree of Success and Check Outcome

Roll your dice against the Check Target Number and count the successes. The
**[[Degree of Success]]** is the Supporting side's total minus the Opposing
side's total; when it is negative, its size is the **[[Degree of Failure]]**.

The **[[Check Outcome]]** is then read from the Degree of Success:

- **[[Success]]** if it reaches the success threshold.
- **[[Fumble]]** if it sinks to the fumble threshold below zero.
- **[[Failure]]** otherwise — including a Degree of Success of exactly zero.

Unlike a single Roll, a Check **can always Fumble**, no matter how its
individual Rolls are protected.

# Competency Bonus

When a creature attempts something it is genuinely trained in, it adds a
**[[Competency Bonus]]** reflecting its skill and [[Tier]]. The exact size is
set per Check by the acting creature's proficiency.

> *(Drafting note: the Competency Bonus formula is not yet pinned down in the
> config — say the word and I'll add it as a named formula like the others.)*

# Sharing Bonuses Between Creatures

Most Checks involve more than one creature, and the interesting question is how
one creature's Bonuses and Penalties affect the others. The sections below give
the exact rule for each kind of Check. Two ideas recur:

- **Inversion.** On a contested Check, a Bonus that helps one side is felt as a
  Penalty by the other. This lets a single set of dice settle the contest — no
  separate "attacker rolls, then defender rolls, then subtract" step.
- **[[Ascendancy]].** Some Bonuses come from training; the **[[Inherent]]**
  Bonus comes from raw [[Tier]] power. When the two sides are badly mismatched
  in Tier, Ascendancy amplifies the gap — helping the stronger creature twice
  over and hurting the weaker one just as much. Ascendancy only ever looks at
  Inherent Bonuses and Penalties; it ignores everything else.

# Attribute Checks

The most basic Check, for tasks that training doesn't help with — heaving a
portcullis, holding your breath, noticing a draft. Compute the Dice Cap from
the relevant attribute using **0 for Prowess**, then apply your Tier's inherent
bonus and any Competency Bonus.

Attribute Checks are usually unopposed, and they are **not affected by
Ascendancy** — raw Tier power does not tip a test of pure attribute.

# Aptitude Checks

A Check for a trained skill, where know-how improves your odds. It works like
an Attribute Check but draws on the relevant skill's Prowess for its Dice Cap
and adds the skill's Competency Bonus.

Like Attribute Checks, an Aptitude Check is **not affected by Ascendancy**.

# Saving Throw Checks

A Saving Throw is made to resist something happening to you — a spell, a trap,
a poison. It is a one-sided Check: you carry your own [[Inherent]] Bonus, and
the source of the danger contributes its Inherent as a Penalty against you.
Because both Inherent entries are present, **Ascendancy applies**: out-Tiering
the source helps you resist, while being overmatched makes resisting harder.

# Opposed Aptitude Checks

Two creatures pit the same skill directly against each other — an arm-wrestle,
a staring contest, a chase. Each creature rolls, and **a copy of each
creature's Bonuses is turned into a Penalty of the same type against its
opponent.** The highest combined result wins.

Opposed Aptitude Checks measure skill, not Tier, so they carry no Inherent
entries and **Ascendancy does not apply**.

# Single-Target Spell Checks

Landing a spell on one creature works like a contested Check. The caster makes
the Initiating Roll and the target makes the Defending Roll, and their Bonuses
and Penalties **invert across the gap** — the caster's casting bonuses are felt
as Penalties by the target, and the target's defenses are felt as Penalties by
the caster.

Both sides carry their [[Inherent]] Bonus (the spell's own Tier rides along as
a Guidance Bonus, *not* an Inherent, so it stays out of the comparison), so
**Ascendancy applies** between caster and target.

# Multi-Target Spell Checks

Some spells name several specific targets. The caster makes a single Supporting
Roll; each named target makes its own Opposing Roll. The caster's bonuses
invert onto **every** target, and each target's defenses invert back onto the
caster — but the targets do not affect one another.

The Check resolves once for the caster, then nets against each target's Roll in
turn, producing one [[Check Outcome]] per target. **Ascendancy applies**
between the caster and each target independently.

# Area Spell Checks

An area spell — a fireball, a cloud of gas — is a **[[Spread Check]]**: one
caster against everyone caught in the area, with no single defender. It is
prepared like a Multi-Target Spell Check (the caster's bonuses invert onto each
caught creature, and each caught creature's defenses invert back onto the
caster), but every caught creature is a peer of the others.

The caster's side resolves once into a single total; each caught creature then
nets against that total independently, so the spell yields **one Outcome per
creature in the area**. **Ascendancy applies** between the caster and each
caught creature.

# Combat Checks

A Combat Check is the fully contested case — an attack against a defense. Every
participant's Bonuses and Penalties invert across the sides:

- The attacker (the **Initiating Roll**) receives the inverted entries of
  **every** defender.
- The primary defender (the **Defending Roll**) receives the inverted entries
  of **every** attacker.
- Supporting allies receive only the primary defender's inverted entries.
- Other defenders receive only the attacker's inverted entries.

Each creature carries its own Tier as an [[Inherent]] entry, so **Ascendancy
applies**: a higher-Tier combatant presses its advantage, and a lower-Tier one
feels the gap.

### Worked example — a Bonus on the attacker becomes a Penalty on the defender

The attacker has a +2 Circumstance Bonus; the defender has a +1 Equipment
Bonus. After inversion:

| Roll | Carries |
|---|---|
| Attacker | +2 Circumstance, and the defender's −1 Equipment |
| Defender | +1 Equipment, and the attacker's −2 Circumstance |

The attacker now faces an easier Target Number and the defender a harder one —
the contest settled with a single exchange of dice.
