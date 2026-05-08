# Check Resolution Tooltip

A read-only informational popup that displays a Check's per-Roll breakdown and aggregate Degree of Success. Composes one Dice Resolution Roll Tooltip per Roll, with role labels and a Result line.

See `ui_conventions.md` for shared rules and `dice_resolution_roll_tooltip.md` for the child tooltip.

## Layout

For each Roll in the Check:
- A bolded role label (`Self:` for Supporting Rolls, `Opponent:` for Opposing Rolls) prefixed to the Roll's identity line.
- The Roll's three-line Dice Resolution Roll Tooltip block.

After all Rolls, a single Result line:

```
Result: <signed DoIS> <signed DoIS> ... = <signed Degree of Success>
```

Each term is a per-Roll DoIS, signed positively for Supporting Rolls and signed negatively for Opposing Rolls. The sum on the right is the Check's Degree of Success.

## Parameters

Required:
- For each Roll in the Check, the parameters required by the Dice Resolution Roll Tooltip (Creature Name, Roll Name, dice count, Base TN, Final TN, final dice, DoIS, optional modifier list).
- The role of each Roll (Supporting or Opposing) — determines the prefix label and the sign in the Result line.

## Role labels

The role labels (`Self:`, `Opponent:`) are added by this tooltip; the dice resolution roll tooltip does not render them itself. The labels prefix the identity line of each composed roll tooltip block.

## Result line

Each per-Roll DoIS appears as a signed term. Supporting DoIS keeps its sign as-is. Opposing DoIS is negated — a Defender with DoIS = +3 contributes `-3` to the Result line. The right-hand side of the equation is the Check's Degree of Success.

For a Check with three Supporting Rolls (DoIS +2, +1, -1) and one Opposing Roll (DoIS +3):

```
Result: +2 +1 -1 -3 = -1
```

For a solo Supporting Roll (DoIS +3) with no Opposing Rolls, the Result line is omitted — the per-Roll DoIS already shown in the roll tooltip is the Degree of Success.

## Composition

The Check Resolution Tooltip is composable in turn — a higher-level tooltip may embed it as a block, supplying its own framing. When composed, this tooltip renders only its per-Roll blocks and Result line; the parent owns surrounding markup.
