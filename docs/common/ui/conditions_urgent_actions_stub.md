# Conditions Urgent Actions Stub

A DM-only panel for resolving pending Affliction saves and queued Consumable actions for every Creature with outstanding business between Combats. Renders on the downtime page.

See `ui_conventions.md` for shared rules.

## Layout

A panel with one section per Creature carrying at least one Pending Affliction (per Conditions' *List Pending Afflictions*) or a queued Consumable / cast action. Each section has:

1. **Header** — Creature name, current HP / Mana, and a row of badges for the Creature's non-Modifier Active Effects (per `conditions_downtime_pc_card_stub.md`'s Active Effects block).
2. **Affliction save rows** — one row per entry in the Creature's `afflictions` list that is currently Pending. Each row has:
   - The Affliction name and current Potency (e.g. `bleeding · Potency 12`).
   - A summary of the save Roll the resolution will use: dice count and TN per `conditions_design.md`'s *Affliction Resolution* (Potency Save Penalty already factored in).
   - A `Roll` button that builds the save through Conditions' *Resolve Affliction* and surfaces the rolled dice.
   - A manual `Successes` override (per `ui_conventions.md`'s Manual override fields convention) — authoritative for the resolution submitted at batch time.
3. **Queued action selector** — a dropdown listing what this Creature should do at the end of the batch:
   - `Nothing`
   - `Cast <ability>` — one option per Ability the Creature has access to and can currently pay for. Sourced from Creatures' *Get Granted Abilities* and filtered by the Creature's Current Mana.
   - `Use <item>` — one option per Consumable Stack in the Creature's Inventory (via Equipment's *Get Inventory*).
   - **Target** dropdown — the Creature receiving the action's effect. Defaults to self.

A single `Submit` button at the bottom of the panel resolves every Creature's Affliction saves and queued action in one batch, emitting a single `urgent_actions` event the parent page resolves.

## Parameters

Required:
- The list of Creatures with pending Conditions business — the parent page builds this by combining Conditions' *List Pending Afflictions* (called per Creature with the Chronicle Current Round) with any Creature carrying a queued action selection.
- The Chronicle Current Round — needed by *Resolve Affliction* for rescheduling.
- Viewer role — must be `dm`. The stub renders nothing for player viewers.

## Behavior

- Each Creature's section is independent in the UI but combines into one Submit.
- Inside each section, Affliction rows build their save Roll via *Resolve Affliction*'s Save Input contract (per `conditions_design.md`). The DM may override the rolled `Successes` value before submitting — the override is what the resolution uses.
- The queued action runs after the Affliction saves resolve. Cast actions are dispatched by the parent page through whichever Abilities entry point produces the action's Effects; Use-Item actions go through Equipment's *Consume Item* (which routes through Conditions for Heal / Mana / Temporary HP and imposes Magic Toxicity per the item form).

## DM-only

The panel is DM-only. The parent page does not invoke the stub for player viewers.

## Composition

The downtime page may also expose a sibling **Quick Resolve** simulator that auto-rolls a configurable number of saves per Affliction to preview cumulative damage and Affliction lifespan. That stub (when present) lives on the same page; the DM uses one for authoritative resolution and the other for previewing outcomes. Both stubs operate on the same Conditions State; only one of them persists the result.

## What this stub does not do

- It does not advance time. The parent page calls Conditions' *Apply Natural Recovery* and Chronicle's *Advance time* as needed.
- It does not enumerate every Active Affliction. Only Pending Afflictions (per *List Pending Afflictions* with the current Round) surface here; non-due Afflictions show up on `conditions_downtime_pc_card_stub.md`.
- It does not interpret cast or Use-Item Effects. The stub emits structured payloads; the parent page resolves them.
