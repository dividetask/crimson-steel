# Combat — Test Data

The combat encounter stub is demonstrated on `/status` from a single
self-contained blob. **The stub never reads the `data/` directory or any
`.example.*` file** — every value it shows comes from the test data described
here (today: `lib/combat/sample_turn.rb`, embedded into the page as JSON). When
the real domains land, the same blob shape is what they must produce; until
then this is the only source the stub touches.

The blob has one Acting Combatant and everything that Combatant's turn can
offer. All fields are literal sample values, not lookups.

## `combatant`

The Acting Combatant whose turn the panel drives.

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Shown in the header. |
| `mana` | `{ remaining, max }` | Header resource. |
| `pool` | `{ remaining, max }` | Combat Pool; caps dice spends (`Speed + dice`). |
| `main_actions` | integer | Main Actions left this turn (`-1` = turn not begun). |
| `incapacitated` | boolean | When true, only **End Turn** is offered. |

## `config`

`{ die_size, base_target_number, move_cost }` — the only rule constants the demo
needs (a real build would read these from Check Resolution / the combat config).

## `targets`

Every other Combatant, as a target option: `{ id, name, side }` where `side` is
`enemy` or `ally` (drives the enemy quick-pick).

## `weapons`

The acting Combatant's equipped weapons, for the Attack flow:
`{ name, kind, dice_cap, speed }` — `kind` is `melee` / `ranged` / `spell`
(gates which defences are eligible); dice buttons run `2…dice_cap`; pool cost is
`speed + dice`.

## `defences`

The target's reaction options: `{ name, kinds, dice_cap, speed }` — `kinds`
lists the attack kinds it may answer (Parry: `[melee]`; Dodge / Block: all).
`No defense` is always offered and is implicit (not listed here).

## `spells`

The Cast list: `{ name, tier, mana, dice_cap, skill, targeting, resolution,
save? }`.

- `targeting` — `single` | `area` | `multi` | `self` (chooses the targeting step).
- `resolution` — `save` (target rolls a saving throw; `save` names the attribute) | `attack` (a magic combat check; target picks a Defence) | `utility` (no defence) | `buff` (no-roll: skips Dice / Luck / Roll).
- A spell whose `mana > combatant.mana.remaining` renders greyed.

## `items`

Usable consumables: `{ name, qty, targeting?, resolution?, target? }`. A Potion
is `target: self` (its Target step auto-resolves); a Scroll carries the same
`targeting` / `resolution` as the spell it casts. Spends no Mana.

## `specials`

Usable special abilities: `{ name, activation, kind }` — `activation` is
`main` / `bonus` / `free` (the menu group); `kind` is `channeled` (rolls a
check), `named` (applies an effect, Confirm only), or `other` (Confirm; DM
adjudicates).

## `luck_sources`

Sources that can spend Luck on a rolled action: `[{ name }]` (e.g. an ally's
Bardic Inspiration reservoir, the DM's DM Luck). Drives the Luck step; omit /
empty to skip it.

## What the demo deliberately exercises

- Every menu group (Main / Bonus / Free) and the **hide rules** — set
  `spells`, `items`, or `specials` empty (and leave `active_spells` out) to see
  a group's button disappear.
- Each Cast branch — a `save` area spell (Fireball), an `attack` single-target
  spell (Elemental Dart), a `multi` save spell (Hold Person), a `buff` no-roll
  spell (Bless), and a mana-unaffordable spell (greyed).
- An incapacitated Combatant (`incapacitated: true`) collapsing to End Turn.
