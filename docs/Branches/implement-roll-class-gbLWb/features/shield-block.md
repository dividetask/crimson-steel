# Shield Block Defense

A defensive action that mirrors parry but uses shield stats. Available to combatants wielding a shield.

## Glossary

- **Shield Block** — Defense action: spend combat-pool dice, roll vs incoming attack, success negates the attack.
- **Shield Stats** — `shield.subtype` (`light` / `medium` / `tower`) determines the dice pool and bonus, parallel to weapon parry stats.
- **Parry** — The pre-existing defense action this one is modeled on.

## Design

Shield Block uses the same resolution path as Parry: declare defense, spend combat-pool dice, roll vs the attacker's hit roll, success negates damage. The shield's subtype and properties (from `rules.json` `item_tree.shield.subtype`) drive the dice and bonuses, in the same way that weapon properties drive Parry.

Eligibility: a combatant must have a shield equipped. The action is exposed in the action stub when eligible and hidden when not.

## Cross-domain interactions

- Reads shield definitions from `rules.json` `item_tree.shield`.
- Shares its resolution path with Parry — see the existing combat-defense design.
- See `../common/data/shields.yaml.example` for shield stat data.
