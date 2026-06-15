# Initiative — Required Interfaces

The Combat Tracker is read-only display plus turn-management controls. This is
the partial stub it needs from each other domain.

Notation: **Name** — `inputs` → result / behavior.

---

## Combat State / Turn Order

The tracker reads the single active Combat and surfaces its turn controls.

- **Combat State (read)** — the Combatant list, `acting_combatant_id`,
  Initiative Strings, `time_tick`, `time_ticks_per_round`, `excluded_pcs`,
  `dm_luck_points`, and `combat_active?`.
- **Get Combat Pool** — `combatant` → max Combat Pool (remaining is the stored
  value).
- **Advance Turn** — advance to the next Combatant in initiative order, rolling
  the Round when the last one ends.
- **Reroll Initiative** — reroll and re-sort the Combatants.
- **Start Combat** / **End Combat** — enter / leave combat mode.
- **Set Acting Combatant** — set `acting_combatant_id` directly (the `Set`
  button override).
- **Set PC Exclusions** — `excluded_pcs set` → add/remove PC Combatants.

## Creatures

- **Look up Creature** — `creature_ref` → name and `tags` (incl.
  `player_character`).
- **Vitals** — Max HP, Max Mana, Tier (for the bars and the Toxicity Threshold).

## Conditions

All the per-Combatant vitals the columns display, plus the cannot-act / dead
flags and the badge removal calls.

- **Reads** — per-Severity HP damage (Minor / Moderate / Major), `mana_spent`,
  `magic_toxicity`, `acid_counter`, `shock`, `ability_damage` map, active
  afflictions (Bleed / Poison Potency) and other Active Effects.
- **Creature Can Act?** / **Dead?** — drive the red row highlight and the Killed
  table.
- **Toxicity Threshold** — `floor(Charisma × Tier)` (Tier 0 = 0.5), for the
  toxicity color ramp.
- **Removal** — *Remove Active Effect* / *Remove Active Affliction* / clear a
  counter, for a badge's `×`.
