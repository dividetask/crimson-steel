# Conditions Save Resolution Stub

Resolves one Affliction save end-to-end: composes the save Roll, walks the DM through any Reroll / Mass Reroll / Nudge picks, rolls the dice, previews what *Resolve Affliction* would do, and applies the result on Confirm. Renders as a single Rolls wrapper that visually matches the Roll Resolution / Check Resolution stub shell. Nothing is mutated server-side until the DM presses Confirm.

See `ui_conventions.md` for shared rules. Cross-domain terms (Magic Toxicity, Toxicity Threshold, Tier) live in `../common_glossary.md`. The Check Resolution Builder pattern that drives the step-by-step disclosure is documented in `check_resolution_builder_stub.md`; for the save case the Builder is integrated directly into this stub rather than rendered as a child.

## Parameters

| Field | Shape | Purpose |
|---|---|---|
| `creature` | `{id, name, tier}` | The Creature taking the save. |
| `affliction` | `{name, rule, potency, inflicter_tier}` | The Affliction being resolved. `rule` is the entry from `conditions_afflictions.yaml`. |
| `save_dice` | integer | Dice count for the save Roll (caller-computed from Creature stats + Affliction). |
| `save_tn` | integer | Target Number for the save. |
| `die_size` | integer | |
| `potency_divisor` | integer | The configured Potency Divisor (used for Magnitude preview). |
| `reroll_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | Each entry becomes a labelled group of magnitude buttons in the Rerolls step. |
| `mass_reroll_sources` | array of `{creature_ref, creature_name, source_name, direction}` or null | Each entry becomes a single ± button in the Mass Rerolls step. |
| `nudge_sources` | array of `{creature_ref, creature_name, source_name, direction, pool}` or null | Each entry becomes a labelled group of magnitude buttons in the Nudges step. |
| `stub_id` | string | Unique identifier. |

## Layout

The stub is a single `.rolls-wrapper`. The shell mirrors the Roll Resolution / Check Resolution stubs (light-grey `.rolls-header`, same border treatment) so the family reads consistently.

1. **Header** — `.rolls-header`. Title (left): `<Category> Save (Potency <n>) - <Creature Name>` (e.g. `Bleed Save (Potency 25) - Wisp Trueheart`). Category is the Affliction Rule's `category` field, title-cased. Potency is the current Affliction Potency before this resolution. The right side (`.rolls-actions`) hosts whichever step is currently active: during Rerolls / Mass Rerolls / Nudges the active step's `None` button + the per-source magnitude buttons live there; once every interactive step is resolved the slot swaps to `Roll All` + `Confirm All` (identical to the Check Resolution Stub's own actions). None and the magnitude buttons share the same vertical sizing as Roll All so the header height never jumps.

2. **Step summaries** — a thin stack between the header and the dice table. One row appears per completed non-check step in DOM order: `<Step Label>: <choice> [Change]`. Pressing Change re-opens that step in the header, rewinds every later step (and the dice table / preview) back to pending, and clears the corresponding modifier on the Roll.

3. **Dice table** — the standard Roll Resolution body (Roll / Reroll / Mass Reroll / Nudge rows, Result + Crits + Lock columns). Hidden via `data-roll-state="pending"` until the check step becomes active.

4. **Effect preview** — hidden until the first Roll All; surfaces editable inputs the DM can adjust before Confirm:
   - **DoIS** — mirrored from the dice table's Result cell.
   - **Net Magnitude** — auto-computed from `magnitude = 1 + floor(potency / potency_divisor)` and `successes = max(0, DoIS)`. `net_magnitude = max(0, magnitude - successes)`.
   - **Effect amount field** — shape depends on the Affliction rule's effect kind (`hit_point_damage`, `ability_damage`, `named_effect`).
   - **New Potency** — auto-computed from the default evolution formula `−floor(decay) − floor(successes × per_success) + floor(failures × per_failure)`. Per-Affliction overrides in the rule are not threaded into the JS preview; the DM may override the value directly.

The Confirm button is disabled until at least one Roll All has fired. On press, applies the displayed values via Conditions' *Resolve Affliction* (or, in the Status demo, records "Recorded — no state mutated").

Everything between Roll All and Confirm is client-side: the DM can change reroll picks (via Change), re-roll, override DoIS, and the preview recomputes live.

## What this stub does not do

- It does not pick which Affliction to resolve. The caller decides which Affliction is due and constructs the parameters.
- It does not advance time. Rescheduling of `next_resolution_round` is the *Resolve Affliction* side-effect, not this stub's; the stub just calls it.
- It does not enumerate all of a Creature's pending Afflictions. One stub instance handles one save.
- It does not understand combat reactions. Target / Defense / Supporting / Opposing inputs are out of scope for an Affliction save; the Builder pattern handles those for other check kinds.
