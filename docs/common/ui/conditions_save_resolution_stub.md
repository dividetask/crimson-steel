# Conditions Save Resolution Stub

Resolves one Affliction save end-to-end: composes the save Roll, rolls it, previews what *Resolve Affliction* would do, and applies the result on Confirm. The only Conditions-owned UI in the Check-Resolution pipeline; everything earlier in the stack (the Builder and the Check Resolution Stub) is domain-agnostic. Nothing is mutated server-side until the DM presses Confirm.

See `ui_conventions.md` for shared rules. Cross-domain terms (Magic Toxicity, Toxicity Threshold, Tier) live in `../common_glossary.md`.

## Parameters

| Field | Shape | Purpose |
|---|---|---|
| `creature` | `{id, name, tier}` | The Creature taking the save. |
| `affliction` | `{name, rule, potency, inflicter_tier}` | The Affliction being resolved. `rule` is the entry from `conditions_afflictions.yaml`. |
| `save_dice` | integer | Dice count for the save Roll (caller-computed from Creature stats + Affliction). |
| `save_tn` | integer | Target Number for the save. |
| `die_size` | integer | |
| `potency_divisor` | integer | The configured Potency Divisor (used for Magnitude preview). |
| `reroll_sources` | array of source records or null | Forwarded to the Check Resolution Builder. |
| `mass_reroll_sources` | array of source records or null | Forwarded to the Check Resolution Builder. |
| `nudge_sources` | array of source records or null | Forwarded to the Check Resolution Builder. |
| `stub_id` | string | Unique identifier. |

## Layout

1. **Header** — a single thin bar showing `<Category> Save - <Creature Name>` (e.g. `Bleed Save - Wisp Trueheart`). The category is the Affliction Rule's `category` field, title-cased. The dice count, TN, and current Potency are not repeated here — the dice / TN appear inside the embedded Check Resolution Stub, and the Potency is editable in the effect preview.
2. **Embedded Check Resolution Builder** — built by this stub with `target_options`, `defense_options`, `supporting_actions`, `opposing_actions` all null, and a single locked `action_options` entry representing the save (`min_dice = max_dice = save_dice`). The Action step is suppressed by the Builder because the dice are locked. The save Roll is passed to the Builder via `rolls`. The Reroll / Mass Reroll / Nudge steps appear only when the corresponding source lists are populated; each renders progressively (only one interactive step visible at a time, with a `None` button to skip and a `Change` button on the completed summary). The embedded Check Resolution Stub stays hidden until every interactive Builder step is resolved.
3. **Effect preview** — hidden until the first Roll All; a row of editable inputs the DM can adjust before Confirm:
   - **DoIS** — mirrored from the embedded Check Resolution Stub's Result cell.
   - **Net Magnitude** — auto-computed from `magnitude = 1 + floor(potency / potency_divisor)` and `successes = max(0, DoIS)`. `net_magnitude = max(0, magnitude - successes)`.
   - **Effect amount field** — shape depends on the Affliction rule's effect kind:
     - `hit_point_damage` → integer (Minor / Moderate / Major HP Damage at the rule's severity).
     - `ability_damage` → integer (Severity + attribute from the rule).
     - `named_effect` → text (the Effect Name, or `(none)` when Net Magnitude is zero).
   - **New Potency** — auto-computed from the default evolution formula `−floor(decay) − floor(successes × per_success) + floor(failures × per_failure)`. Per-Affliction overrides in the rule are not applied to the preview; the DM may override the value directly.
4. **Confirm** button — disabled until at least one Roll All has populated the DoIS. On press, applies the displayed values via Conditions' *Resolve Affliction* (or in the demo Status page, just records "Recorded — no state mutated" as a confirmation).

Everything between Roll All and Confirm is client-side: the DM can change reroll picks, re-roll, override DoIS, and the preview recomputes live. Server state changes only when Confirm is pressed.

## Composition

The DM-facing flow:

1. Pick Reroll / Nudge magnitudes if any source is offered.
2. Press Roll All on the embedded Check Resolution Stub.
3. Inspect the dice, adjust DoIS if the DM is overriding.
4. Inspect the auto-computed effect preview; edit any field as needed.
5. Press Confirm.

The stub is intended for the Conditions Downtime page (between Combats) but composes anywhere a single Affliction save needs to be resolved.

## What this stub does not do

- It does not pick which Affliction to resolve. The caller decides which Affliction is due and constructs the parameters.
- It does not advance time. Rescheduling of `next_resolution_round` is the *Resolve Affliction* side-effect, not this stub's; the stub just calls it.
- It does not enumerate all of a Creature's pending Afflictions. One stub instance handles one save.
- It does not understand combat reactions. Defense / Supporting / Opposing panels are forwarded to the Builder if the caller supplies them, but Affliction saves never need them.
