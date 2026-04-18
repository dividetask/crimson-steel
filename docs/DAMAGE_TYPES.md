# Crimson Steel Online — Damage Types

This document defines the categories of damage and the magical damage
types used by spells. Physical damage types are also defined in
`data/rules.json` (`weapon_speed`, `weapon_dmg`, `weapon_bleed`,
`weapon_threshold`).

Related documents:
- [SPELLS.md](SPELLS.md) — spell mechanics
- [CONDITIONS.md](CONDITIONS.md) — bleeding, shock, magic toxicity

## Damage Categories

Damage dealt to a creature falls into three categories of severity:

| Category | Description                                           |
|----------|-------------------------------------------------------|
| Minor    | Surface harm. Recovers most quickly.                  |
| Moderate | Real injury. Recovers more slowly.                    |
| Major    | Serious injury. Recovers very slowly.                 |

A spell's healing or damage values are usually given as a triple of
minor / moderate / major points (see the `Cure` and `Heal` entries in
`data/compendium.json` for examples).

## Physical Damage Types

These are dealt by mundane weapons and are defined alongside weapon
mechanics in `data/rules.json`.

| Type         | Notes                                                  |
|--------------|--------------------------------------------------------|
| Bludgeoning  | See `weapon_bleed`, `weapon_threshold` in rules.json.  |
| Slashing     | See `weapon_bleed`, `weapon_threshold` in rules.json.  |
| Piercing     | See `weapon_bleed`, `weapon_threshold` in rules.json.  |

## Magical Damage Types

Magical damage types each have a unique property that triggers when the
target takes damage of that type.

### Radiant

- **Property:** Damage dealt to undead targets is upgraded to **major**
  damage regardless of the spell's normal damage category.

### Fire

- **Property:** Each *hit* deals **+1 damage**. The bonus applies once
  per hit, not per die rolled and not per target.

### Acid

- **Property:** Acid damage dealt to a creature carries over to the
  following turn. At the start of the creature's turn, it takes
  `floor(previous_acid_damage / 2)` acid damage. If the creature is hit
  by multiple sources of acid damage in a turn, those sources are summed
  before computing next turn's residual.

### Electricity

- **Property:** Electricity attacks gain bonus successes equal to the
  target's damage reduction from **metal armor** (see Metal Armor below).

### Cold

- **Property:** Cold damage inflicts **shock** equal to the damage dealt.
  See [CONDITIONS.md](CONDITIONS.md) for the shock condition.

## Metal Armor

For purposes of damage-type interactions (notably Electricity), the
following armor counts as metal:

- All **medium** armor.
- All **heavy** armor.

This is a placeholder definition; per-armor metal classification will be
added to `data/rules.json` as the equipment system is finalized.
