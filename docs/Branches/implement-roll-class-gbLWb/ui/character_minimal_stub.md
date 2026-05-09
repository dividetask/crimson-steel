# Character Minimal Stub

Compact character card. Forced on `/scene`. Toggleable on `/character/<index>` between this and `character_full_stub`.

## Layout

1. **Header** — Name, race + class summary, tier, current HP / mana / temp HP.
2. **Conditions** — Active condition list (bleed, paralysis, etc.) with per-condition counts.
3. **Actions** — Action table (Name / Speed / Roll / Bonus / Damage / Notes).
4. **Skills (two-up table under Actions)** — Skills split into a two-column table, with a transparent spacer column between them. All borders dropped.

Sections without content are omitted.

## Parameters

Required:
- Character index.
- Viewer role — `dm` or `player`.

## Visibility

The parent page filters which characters render. The stub does not enforce visibility.

## Data sources

- Character data from `data/characters.json`.
- HP/mana/temp HP from CombatTurn (in combat) or the character sheet (out of combat).
- Active conditions from CombatTurn.
