# Combat Active Effects Stub

A list of every Active Effect currently posted on Combatants in the active Combat, with a per-row dismiss affordance. Lives below the initiative stub on the Combat page.

See `ui_conventions.md` for shared rules.

## Layout

A panel labeled **Active Effects** containing a vertical list. One row per Active Effect read from the Conditions domain, in append order across all Combatants (which doubles as application order, since Conditions preserves insertion order).

Each row shows:

- **Caster** — the source Combatant's display name. Looked up by resolving the Active Effect's `source_id` back to its applying Combatant via the parent page's bookkeeping. Hidden when the source cannot be resolved (Conditions stores `source_id` opaquely and Combat does not own a reverse index).
- **Source name** — a human-readable label for what produced the Effect (e.g. the spell name, the Effect Name from `effect_names.yaml`, an Equipment Stable Stack Key). Supplied by the parent page alongside the Effect; the stub does not interpret it.
- **Targets** — the names of the Combatants this Effect is currently attached to, comma-joined. When more than three targets, truncates to `<first>, <second>, … (+N more)`.
- **Duration** — `R<current> / R<ends_on_round>`. The current Round is the value read from Chronicle's *Get current Timestamp*; the end Round is the Effect's `ends_on_round` per `conditions_design.md`. Color: green when three or more Rounds remain, yellow when one or two, red when this is the final Round before expiry. Effects with `ends_on_round = null` (permanent) render the second segment as `∞` and use the neutral color.
- **Payload** — a small chip describing the Effect:
  - Temporary HP grants render as `+<amount> temp HP`.
  - Modifier-shaped Active Effects render as the standard modifier presentation (see `ui_conventions.md`) followed by the Target Key in muted text — e.g. `+2 Guidance str`.
  - Named-Effect-shaped Active Effects render the Effect Name as a badge — e.g. `Paralyzed`, `Frightened`.

Cure-style payloads (Heal Cascade applications, Mana restores) do not appear in this list — they are applied immediately by Conditions and carry no Active Effect entry to display.

- **Dismiss button** — a `×` button on the right. The stub emits a `dismiss` event carrying the Effect's `source_id`; the parent page resolves dismissal via Conditions' *Remove Effects by Prefix* (or domain-appropriate teardown for Named Effects and Temporary HP).

When no Active Effects are attached to any Combatant, the panel renders `No active effects`.

## Parameters

Required:
- The list of Active Effects to display — typically the union of every Combatant's `effects` list (from Conditions) plus any Temporary HP grants, with per-Effect display metadata already resolved by the parent page.
- The current Round (from Chronicle).
- Viewer role — `dm` or `player`.

Optional:
- Combat ID filter — when set, only Effects whose target list includes the supplied Combat ID are shown. Used by a per-row "view this Combatant's effects" toggle on the initiative stub.

## DM-only

Dismiss buttons render only when the viewer role is `dm`. Players see the same rows but cannot remove anything.

## Composition

The stub renders inline on the Combat page directly below the initiative stub. The creature stubs have their own compact Active Effects mini-lists (see `creatures_minimal_stub.md`) with no dismiss controls; this stub is the authoritative scene-level view.

## What this stub does not do

- It does not compute who applied an Effect. Reverse lookup from `source_id` to a Combatant is the parent page's job — Conditions stores `source_id` opaquely.
- It does not interpret payload shape. Each row's chip is rendered from metadata the parent page passes in.
- It does not enforce expiry. Conditions' *Clear Expired Effects* is the sole authority; this stub only colors the duration display.
