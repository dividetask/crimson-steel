# Combat Tracker

Per-combatant initiative-ordered list with action buttons. Adds Set-Turn, per-row reroll, end-combat, bardic inspiration, luck spend, and tracks bleed (including from ranged attacks) and ghoul paralysis.

## Glossary

- **CombatTurn** — The per-combatant state (init order, conditions, ability damage, temp HP). One per combatant.
- **Set Turn** — Manually move the active turn to a chosen combatant without advancing through intervening turns.
- **Bleed** — Condition tracked on a combatant, applies after attacks of any range (melee or ranged).
- **Ghoul Paralysis** — Condition applied by ghoul natural-weapon attacks (bite, claw); tracked on the combatant and decremented per round.
- **Luck Points** — Bardic luck-reroll resource; spent via `POST /combat/spend_luck/<source_id>`.
- **Bardic Inspiration** — Granted via `POST /combat/bardic_inspiration/<id>`; consumed by recipient.
- **Temporary Hit Points** — A separate HP pool (see [hp-mana-display.md](hp-mana-display.md)).

## Design

Combatants are sorted by initiative descending, with ties broken by `init_compare` (string-based dice digits, sorted high→low). `set_current_turn` jumps the pointer; `advance_turn` moves it forward and triggers per-turn effects.

Endpoints:

- `POST /combat/update/:id` — generic state update.
- `POST /combat/sat/:id` — magic toxicity update.
- `POST /combat/reset_dice` — reset round dice pool.
- `POST /combat/action` — apply an action result (damage, condition, etc.).
- `POST /combat/reroll_init` and `/combat/roll_init/:id` — reroll initiative for all or one.
- `POST /combat/end_combat` — terminate the encounter, freeing combatants.
- `POST /combat/set_turn/:id` — set active turn.
- `POST /combat/bardic_inspiration/:id` — grant bardic inspiration to a combatant.
- `POST /combat/spend_luck/:source_id` — spend a luck point from a bard.
- `POST /combat/add_enemy`, `/combat/remove_enemy`, `/combat/clear_enemies` — manage roster.

Bleed semantics: previously only melee attacks applied bleed; the branch broadens this to ranged attacks as well so that `weapon_bleed` resolves the same way regardless of weapon range. Bleed and ghoul paralysis are tracked on the CombatTurn alongside other conditions.

Death/incapacitation: the tracker computes `incapacitated?` and `dead?` per combatant; killed combatants move to a `killed_list` partition and are filtered out of `living_turn_list`.

## Data shape

```
combat_turn = {
  id: <int>,
  character: <ref>,
  initiative: <str>,           # die-face string, e.g. "98654"
  conditions: {bleed: <int>, paralysis: <int>, ...},
  ability_damage: {minor: {...}, moderate: {...}, major: {...}},
  temporary_hit_points: <int>,
  luck_points: <int>            # bards only
}
```
