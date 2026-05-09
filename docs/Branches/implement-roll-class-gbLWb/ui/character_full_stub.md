# Character Full Stub

Full character sheet. Default on `/character/<index>` unless the viewer has switched to minimal.

## Layout

1. **Header** — Name, race + class summary, tier, portrait.
2. **Vitals** — HP (current + max + temp), mana, magic toxicity, initiative, perception, speed.
3. **Attributes** — str / dex / con / int / wis / cha with effective values.
4. **Saves** — Wisdom, Dexterity, Constitution.
5. **Skills** — Full skill list with ranks, attribute, dice count, proficiency bonus.
6. **Abilities** — Class and race abilities with descriptions.
7. **Spells** — Grouped by tier.
8. **Equipment** — Equipped, consumable, other.
9. **Notes** — Public notes attached to this character.

## Parameters

Required:
- Character index.
- Viewer role — `dm` or `player`.

## Visibility

Same parent-filters-it rule as the minimal stub.

## Data sources

- All of the same sources as `character_minimal_stub`, plus full ability descriptions, skill detail, and equipment item descriptions.
