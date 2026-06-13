# Check Resolution — Implementation

How the [Check Resolution chapter](../game_rules/check_resolution/check_resolution_overview.md)
is implemented. The player-facing rules and the canonical formulas live in
`game_rules`; this document only points at them and fills in the internal
pieces that are not exposed to players.

## Canonical formulas (defined in `game_rules`)

These are defined in
[`check_resolution_config.yaml`](../game_rules/check_resolution/check_resolution_config.yaml)
and rendered in the overview. **Do not restate them here** — read them from the
config so a change there flows everywhere.

| Formula (config key) | Inputs | Implemented in |
|---|---|---|
| `Dice Cap Formula` | `Attribute`, `Prowess`, + config scalars | _planned_ `lib/check_resolution/dice_cap.rb` |
| `Maximum Dice Formula` | config scalars only (evaluates to a constant) | folded into the Dice Cap implementation |
| `Starting Value Formula` | `Dice Modifier`, + config scalars | _planned_ `lib/check_resolution/starting_value.rb` |
| `Check Target Number Formula` | `Dice Modifier`, + config scalars | _planned_ `lib/check_resolution/target_number.rb` |
| `Attribute Contribution Formula` | `Attribute` | folded into the Dice Cap implementation |

> The `lib/check_resolution/` domain has not been re-added since the project was
> trimmed; the file paths above are the intended homes when it returns.

## Internal formulas (NOT in `game_rules`)

Computations the rules describe in prose but don't pin to a config formula. They
are defined here because they never need to surface to players verbatim.

### Dice Modifier

The Dice Modifier is an aggregation over a Check's Bonus/Penalty list, not a
plain arithmetic expression, so it is not a config formula:

```
group entries by (sign, type)
best_bonus[type]    = max(bonus.value  for each type)      # one per type
worst_penalty[type] = max(penalty.value for each type)     # one per type, by magnitude
Dice Modifier = Σ best_bonus[type] − Σ worst_penalty[type]
```

Same-type Bonuses (or Penalties) do not stack: only the strongest of each type
counts. See the worked cases in the overview's Dice Modifier `test` block.

### Dice count bounds

A Check rolls between `Minimum Dice` and the `Maximum Dice Formula` (both in
the config). The upper bound is the maximum the Dice Cap Formula can produce
(the `% Dice Range` term contributes `0 … Dice Range-1`). With the shipped
config that is `6 … 10`.

### Competency Bonus

Referenced by the overview but **not yet specified** as a formula in either
`game_rules` or here. When pinned down, add it to
`check_resolution_config.yaml` as `Competency Bonus Formula` (so the overview
renders it like the others) and link its implementation here.

## Cross-side sharing of Bonuses

The per-check-type sharing rules (inversion, Opposed-Aptitude bonus→penalty
copy, Spell single/multi/area, Combat propagation) and Ascendancy are described
in the overview. Their implementation belongs in the (planned)
`lib/check_resolution/` and `lib/dice_resolution/` domains:

- **Cross-side propagation** — `lib/check_resolution/` (prepares each Roll's
  Bonus/Penalty list before TN computation).
- **Ascendancy derivation** — `lib/dice_resolution/` (derived per Roll during
  Target Number computation, from the Inherent imbalance; gated on a present
  Inherent Penalty). Attribute and Aptitude Checks carry no Inherent entries
  and so derive no Ascendancy.
