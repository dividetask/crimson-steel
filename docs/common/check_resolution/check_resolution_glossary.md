# Check Resolution — Glossary

Defines the vocabulary used by `check_resolution_design.md` and `check_resolution_tests.md`. Single-Roll terms live in the dice resolution glossary and are not redefined here.

- **Check** — Two ordered lists of Rolls (Supporting and Opposing) resolved together into a single Check Outcome (or, for a Spread Check, one Outcome per Opposer).
- **Supporting Roll** — A Roll on the side trying to make the action succeed. The list is required and non-empty.
- **Opposing Roll** — A Roll on the side trying to make the action fail. The list may be empty.
- **Initiating Roll** — The first Supporting Roll: the creature actually attempting the action.
- **Defending Roll** — The first Opposing Roll, when one exists: the primary target. A null first entry means the Check has Opposing Rolls but no Defender.
- **Cross-side propagation** — The operation that inverts each side's Bonuses/Penalties (Bonus ↔ Penalty, names kept) onto specific Rolls of the other side before any dice are rolled.
- **Ascendancy** — The derived modifier that amplifies an Inherent imbalance: after propagation, a Roll whose strongest Inherent Bonus exceeds its strongest Inherent Penalty gains an Ascendancy Bonus of `floor(2 × gap)`; the reverse yields an Ascendancy Penalty. A zero or absent side of the comparison reads as 0.5 (Tier 0); a Roll with no Inherent entries at all derives nothing. See `check_resolution_design.md` → *Ascendancy*.
- **`no_propagate`** — An optional per-Roll list of Bonus Type names whose entries stay on the Roll's own side and never cross to the opponent (e.g. a Dodge's Competency).
- **Degree of Success** — Sum of Supporting DoIS minus sum of Opposing DoIS. Its negative magnitude is the **Degree of Failure**.
- **Check Outcome** — `success`, `failure`, or `fumble`, classified from the Degree of Success against the dice resolution thresholds. A Check can always Fumble.
- **Spread Check** — An area-effect Check (`spread: true`): prepared like any other, but the Supporting total nets against **each** Opposing Roll independently — one Outcome per caught creature.
