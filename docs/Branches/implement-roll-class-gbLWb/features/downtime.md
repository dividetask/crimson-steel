# Downtime

The `/downtime` page batches between-encounter actions: cast spells, cast rituals, use items, perform services, rest, and resolve urgent actions in bulk.

## Glossary

- **Downtime Action** — Any non-combat action a PC takes between encounters: cast, cast-ritual, use-item, service, rest, urgent-action.
- **Service** — A non-combat skill use (craft, profession, perform, etc.) that yields gold or consumed time.
- **Urgent Action** — An action that must be resolved before downtime closes; these get a dedicated batch endpoint.
- **Quick Resolve** — A bulk-apply path that runs multiple downtime actions in one submit.

## Design

The page lists each PC and the downtime actions available to them. Each action has its own POST endpoint:

- `POST /downtime/cast` — cast a spell (using mana, no skill check skip; the standard cast path).
- `POST /downtime/cast_ritual` — cast a ritual (longer cast time, scroll-style semantics).
- `POST /downtime/use_item` — consume a potion or scroll.
- `POST /downtime/service` — perform a skill-based service for gold.
- `POST /downtime/rest` — recover HP/mana per the rest type's recovery rules.
- `POST /downtime/urgent_actions` — resolve a batch of urgent actions.
- `POST /downtime/quick_resolve` — bulk-apply staged actions.

Rest recovery uses `rules.json` `advancement.natural.heal_rate` and `mana.recovery` to compute how much returns per rest unit (hour / day / week).

Service results post a Chronicle entry (if Chronicle exists for the campaign). Item use shares the consume path with the combat-tracker's `item_use` resolver.

## Cross-domain interactions

- Cast / use-item routes share resolvers with [spells.md](spells.md) and [scrolls-and-potions.md](scrolls-and-potions.md).
- Rest recovery reads from `rules.json` and writes to `data/characters.json`.
