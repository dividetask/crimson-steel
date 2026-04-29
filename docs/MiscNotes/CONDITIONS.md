# Crimson Steel Online — Conditions

This document defines persistent conditions that may be inflicted on a
creature by spells, weapons, or other effects.

Related documents:
- [SPELLS.md](SPELLS.md) — spell mechanics
- [DAMAGE_TYPES.md](DAMAGE_TYPES.md) — damage categories and types

## Bleeding

Bleeding represents an open wound that continues to harm a creature
each round until it is treated.

- A creature with bleeding takes ongoing damage. (Per-round amount and
  damage category — minor/moderate/major — TBD; see `weapon_bleed` in
  `data/rules.json` for the current per-weapon bleed values.)
- Bleeding is reduced by spells such as **Heal** (`Heal Petty Wounds`
  and higher tiers). The amount of reduction is calculated by the
  reducing spell.
- Multiple sources of bleeding stack.

## Shock

Shock represents disorientation from electrical or freezing harm.

- Shock reduces the number of combat dice the affected creature has
  available to spend on a given turn.
- If a creature suffers more shock than it has combat dice, the excess
  **lingers**: it persists across turns, continuing to subtract from
  the creature's available combat dice each turn until enough dice have
  been "absorbed" to clear the shock total.
- Shock is inflicted by, for example, the cold-damage property (see
  [DAMAGE_TYPES.md](DAMAGE_TYPES.md#cold)).

## Magic Toxicity

Magic toxicity (also called **magic saturation**; the two terms refer to
the same mechanic) represents a creature's accumulated exposure to
magical effects.

- Some spells impose magic toxicity on the target when cast. The amount
  imposed is described per-spell via the `minimum_saturation` and
  `saturation` keys in the spell's `effect_hash` (see
  [SPELLS.md](SPELLS.md#saturation-magic-toxicity)).
- A creature has a saturation resistance and a recovery rate; see
  `advancement.natural.sat_resist` and `advancement.natural.sat_recovery`
  in `data/rules.json`.
- Detailed effects of accumulated magic toxicity (penalties, thresholds,
  consequences of being over a creature's resistance) are TBD and will
  be documented here.

## Other Conditions Referenced by Spells

The following conditions are referenced by existing spell descriptions
in `data/compendium.json` and need formal definitions added to this
document over time:

- Exhaustion
- Confusion
- Insanity
- Fatigue
- Sickened / Disease
- Paralysis
- Fear
- Blindness / Deafness
- Charmed
- Stunned
- Helpless
- Staggered (passive ability defined in `data/rules.json`)
