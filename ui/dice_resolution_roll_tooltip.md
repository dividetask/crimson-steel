# Dice Resolution Roll Tooltip

A read-only informational popup that displays a single Roll: who owns it, how its TN was computed, and how the dice landed. Backed by the public entry points of the dice resolution domain.

See `ui_conventions.md` for shared rules (dice highlighting, modifier presentation).

## Layout

Three text lines:

1. **Identity line** — `<Creature Name> · <Roll Name> (<dice_count>d)`.
2. **Computation line** — `<Base TN> <signed modifier list> = TN <final TN>`. When no modifiers apply, collapses to `<Base TN> = TN <Base TN>`.
3. **Dice line** — `<die> <die> ... → <DoIS>`. Each die is rendered with its category highlighting; DoIS is signed and rendered in bold.

## Parameters

Required:
- Creature Name — string.
- Roll Name — string.
- Dice Count — integer.
- Base TN — integer.
- Final TN — integer.
- Final dice — list of integers.
- DoIS — signed integer.

Optional:
- Modifier list — an ordered list of `(magnitude, label)` pairs that contributed to the final TN. Each entry's sign is encoded in `magnitude` (positive raises, negative lowers). When empty or omitted, the computation line collapses to `<Base TN> = TN <Base TN>`.

## Identity line

Single line, three pieces separated by `·` and ending with the dice count in parentheses:

```
<Creature Name> · <Roll Name> (<dice_count>d)
```

The `<dice_count>d` form is a compact shorthand (e.g., `9d` for nine dice).

## Computation line

Reads as an arithmetic expression with the Base TN on the left, each modifier as a signed term, and the final TN on the right:

```
<Base TN> <±magnitude> <label> <±magnitude> <label> ... = TN <final TN>
```

Each modifier term is rendered per `ui_conventions.md` (sign prefix, magnitude, space, label). When the modifier list is empty, the line is just `<Base TN> = TN <Base TN>`.

## Dice line

Each die in `final_dice` is rendered in original order, separated by spaces, with category highlighting per `ui_conventions.md`. Followed by `→` and the signed DoIS in bold:

```
<die> <die> ... → <±DoIS>
```

## Composition

Other tooltips may render a Dice Resolution Roll Tooltip as a block within their own layout. The tooltip's three lines render in sequence with no surrounding markup; the parent tooltip is responsible for any framing, headers (e.g., a `Self:` or `Opponent:` prefix on the identity line), and additional content such as a result calculation.

When composed, the parent tooltip supplies whatever role label it needs prepended to the identity line; the dice resolution tooltip itself does not know about Check sides or roles.
