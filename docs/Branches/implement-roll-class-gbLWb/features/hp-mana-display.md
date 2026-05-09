# HP / Mana Display

Surface a combatant's current HP and mana on character sheets and the combat tracker, with the moderate/major damage breakdown visible alongside.

## Glossary

- **Current HP** — `hp_max - minor_damage - moderate_damage - major_damage + temporary_hit_points`. Temp HP is additive on top of the post-damage value.
- **Moderate Damage** — Mid-severity ability damage; takes longer to heal than minor damage.
- **Major Damage** — High-severity ability damage; healed only by extended rest or specific cures.
- **Temporary Hit Points** — A buffer pool granted by spells like Ward; absorbs damage before HP and does not regenerate.
- **Mana** — Caster resource; tier-scaled maximum from `rules.json` (`tier.mana.maximum`).

## Design

Current HP is exposed on `CombatTurn` as `hp` and combines all four damage tracks plus temp HP:

```
hp = hp_max - minor_damage - moderate_damage - major_damage + temporary_hit_points
```

Damage tracks are independent — minor damage healing does not reduce moderate or major. Each track has its own healing rate from `rules.json` (`advancement.natural.heal_rate` / `ability_heal_rate`).

Temp HP is set/cleared explicitly (e.g. by Ward), is not regenerated, and is included in the displayed current HP. When damage is applied, temp HP absorbs first.

Mana display reads `mana_max` (tier-scaled from `int`) and the spent-mana counter. Recovery is `floor(mana_maximum/4)` per day.

The minimal character card and the combat tracker both read the same `current_hp` accessor so the displayed values stay consistent.

## Cross-domain interactions

- Damage tracks are written by `Combat.calculate_damage` and the `apply_cure_cascade` / `apply_ability_cure_cascade` paths.
- Tier and attribute formulas come from `rules.json`.
- Spell-driven temp HP changes happen in [spells.md](spells.md) (Ward).
