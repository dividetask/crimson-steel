# Turn Action Stub

A widget that drives the current Combatant's turn on `/encounter`. The DM picks an action from a vertical menu on the left; the right pane changes to show controls for that action. The stub renders directly below the Encounter Initiative Stub (the Combat Tracker) on the Encounter page and acts on the Acting Combatant (`acting_combatant_id`). Lives in `views/encounter.erb` (action-panel section).

See `ui_conventions.md` for shared rules, `encounter_design.md` for the Combat domain entry points this stub drives, and `encounter_initiative_stub.md` for the tracker it sits beneath.

## Layout

Two regions side by side.

- **Left — action menu.** A vertical list of action buttons in this order:
  1. `Start of Turn`
  2. `Attack`
  3. `Move`
  4. `Cast`
  5. `Item`
  6. `Special`
  7. `End Turn`

  The currently-selected action is rendered as the selected state (filled background, contrasting text). When the Acting Combatant cannot act (Conditions' *Creature Can Act?* is false — Dying, Dead, or carrying a "cannot act" Active Effect), every action except `Start of Turn` and `End Turn` is hidden and the header carries an `(Incapacitated)` suffix.

- **Right — action pane.** The action-specific UI. Each pane has a heading naming the action and showing the Combatant's standing resource state — Mana remaining and Combat Pool remaining (`Get Combat Pool − combat_pool_spent`).

## Header

Above both regions: `<Combatant Name>'s Turn`. The name is resolved via Creatures' *Look up Creature*, falling back to the Combatant's stored `name`, then to `Creature #<id>`. An optional `(<state>)` suffix appears when the Combatant has a salient state — `(Incapacitated)` (Conditions' *Creature Can Act?* is false) or `(Dead)` (Conditions' *Dead?*). The suffix color matches the severity.

## Per-action panes

### Start of Turn

One success input per Affliction that is due this Round for the Acting Combatant (Conditions' *List Pending Afflictions* for the current Round — e.g. `bleeding`, `ghoul_paralysis`, the catalog's poisons and diseases). The DM enters how many Successes the Combatant rolled on each Affliction's Save; a single Submit resolves them through Conditions' *Resolve Affliction* (per-Affliction) or *Resolve Due Afflictions* (batched), which applies each Affliction's consequence, then decays and reschedules survivors per `conditions_design.md`.

The same Submit also runs Conditions' *Clear Expired Effects* for the current Round, removing every Active Effect whose `ends_on_round ≤` the current Round.

A `Roll All` button (client-side) auto-fills the Success inputs with sampled values per Affliction.

### Attack

A **progressive-disclosure** flow: the DM makes one decision at a time, and each completed decision collapses to a thin `<Label>: <value>` row with a `change` affordance that reopens it (and invalidates the later decisions). It is backed by the Encounter attack pipeline (`encounter_design.md` → *Attack / Cast / Use Item*, *Defensive Actions*; `Encounter::Attack.build_spec` + `Encounter::State#resolve_attack_payload`). Steps:

1. **Target.** Buttons for every other Combatant (the roster the initiative stub above provides). The attack kind (`melee` / `ranged` / `spell`) follows the chosen weapon's category.
2. **Weapon.** The attacker's equipped weapons come from the *Attack Options* fetch — each shows name and Speed cost.
3. **Target's defense.** `No defense`, or one Defensive Action eligible against this attack kind (`encounter_design.md` → *Defensive Actions*): `Dodge` (a **Dexterity save**, any kind, no Combat Pool), `Block` (Martial, any kind), and `Parry` (Martial, **melee only** — hidden for ranged). Declaring an eligible defense clears the defender's Flatfooted status.
4. **Dice.** A strip of dice-count buttons from 1 up to `min(Dice Cap, floor(Combat Pool Remaining / Speed))` — the largest roll the Combat Pool can afford. The Dice Cap and Speed come from the *Build Attack* fetch.
5. **Roll.** The attacker's Roll (and the declared defender's Opposing Roll) render as a **Check Resolution Stub** (`check_resolution_stub.md`) — the exact same Roll UI and engine the Dice / Check stubs use. The Bonus/Penalty sources (Competency, Flatfooted, Unaware) are folded into each Roll's TN + Starting Value server-side via `DiceResolution.compute_target_number`. The DM rolls it (`Roll All`), may reroll/nudge, and may type a manual override into the Result field (the standard Check-stub affordance).
6. **Resolve.** A single POST carries the Confirm payload (below), reading each Roll's resolved Successes out of the Check stub. The server spends Combat Pool for every participant, nets Supporting minus Opposing Successes per *Check Resolution*, and on a positive net Degree of Success routes the damage through *Apply Damage* → Conditions' *Apply Hit Point Damage*. Temporary HP absorbs worst-first (Major → Moderate → Minor) before the Severity counters increment, per `conditions_design.md`.

#### Confirm payload

The shape `Encounter::State#resolve_attack_payload` consumes (symbol or string keys):

- `target_id` — the defender's Combat ID.
- `attack_kind` — `melee` | `ranged` | `spell` (default `melee`).
- `weapon` — `{ damage_types, threshold, base_damage }` (optional; falls back to `damage_bonus` + `physical`).
- `attacker` — `{ id, dice, speed, successes }`.
- `defense` — `{ choice, id, dice, speed, successes }`. `choice` of `none`/empty skips it; an ineligible defense is rejected before any Combat Pool is spent; Dodge costs no Combat Pool.
- `allies` — `[ { id, dice, speed, successes }, … ]` for ally Reactions (e.g. a Granted-Action block).

### Move

A free-form text input for a move description. Submits a log line without any mechanical effect.

### Cast

1. **Pick spell.** A dropdown of the Combatant's known spells from the character sheet — the tier-grouped `spells` list (plus `rituals` and `item_spells` where castable). Options the Combatant lacks the Mana for are disabled (per-Tier Mana Cost from `abilities_config.yaml`).
2. **Pick target(s).** Driven by the spell's `target` / `area` / `save` fields (`abilities_design.md`): no target, `self`, a single target, or a multi-target count/Formula. Multi-target offers checkboxes for any Combatant; area spells anchor on the chosen target.
3. **Roll casting check.** Client-side dice for the spell's casting skill (`skills`, default `arcana`); the DM picks net Successes. Spells with a `save:` block prompt the target's Saving Throw (named by the Save Attribute — e.g. a **Wisdom save** or **Dexterity save**).
4. **Submit.** The Spells/Abilities domain resolves the spell's Effects and applies them to the target(s): Mana is debited via Conditions' *Apply Mana Cost*; **magic toxicity** rises via Conditions' *Apply Magic Toxicity* (a positive contribution is blocked when the Combatant's toxicity already exceeds the Toxicity Threshold — `floor(Charisma × Tier)`, with Tier 0 treated as 0.5); cure / heal / Temporary HP / mana / Active-Effect (ward, enhancement) outcomes route to Conditions. Channeled or multi-turn spells register a Concentration or Casting Entry via Encounter (`encounter_design.md` → *Begin Concentration* / *Begin Long Cast*).

### Item

1. **Pick consumable.** A dropdown of the Combatant's carried consumables — the character sheet's `items.consumable` list.
2. **Pick target.** A single Combat ID (consumables are always single-target regardless of the underlying spell).
3. **Submit.** Equipment's *Consume Item* resolves the carried spell at the Stack's Tier, routes its cure / mana / Temporary HP / damage outcomes to the owning domains, imposes **magic toxicity** for Potions and Oils (Cure and Mana outcomes are gated when the target is already over threshold), and decrements the Stack's quantity (deleting it when it hits zero).

### Special

A free-form text input for a one-off action ("breath weapon", "improvise"). Submits a log line as a labeled Move action (no separate handler).

### End Turn

A single confirm-and-submit button that invokes Encounter's *Advance Turn*, which skips Combatants who cannot act and applies *Apply Per-Turn Cleanup* to the outgoing Combatant — resetting `combat_pool_spent` to 0, clearing per-Combatant `luck_points`, and marking `performed_this_turn`. A Round wrap additionally triggers *Apply Per-Round Cleanup* and Chronicle's *Advance current Timestamp*.

## Parameters

Required:
- The Acting Combatant (the Combatant identified by `acting_combatant_id`).
- Viewer role — DM only; the stub does not render for players.
- The full Combatant roster (for picking targets).

Optional:
- A combat-log array — the stub appends preview lines as the DM picks values, then commits them on submit.

## Behavior

- Each action pane is client-side until Submit. State accumulates in the browser; only Submit POSTs back.
- Per-Combatant `luck_points` are debited per reroll; a reroll re-rolls a single die client-side. Saving Throws (including Dodge) never cost Combat Pool.
- The Combat Pool is decremented on submit by the chosen dice count × the action's Speed (the weapon's Speed cost for Attack; the spell's casting time for Cast).
- **DM Luck Points** (`dm_luck_points`) are a Combat-level pool shown read-only to the DM; they persist across turns and rounds and clear only at *End Combat*. The Initiative Stub also surfaces this total.

## DM-only

The entire stub is DM-only. The Encounter page is gated by the project's DM identification (a loopback request is the DM; see the project's DM-vs-player rule). The stub renders nothing for player viewers.

## Composition

The stub renders inline on the Encounter page only, directly below the Encounter Initiative Stub, which provides the targeting roster. It is not designed to embed elsewhere.

## First-pass implementation status

The full layout above is the target. It grows as the owning domains and routes land:

- **Implemented:** the panel (`views/_turn_action.erb`, rendered by `views/encounter.erb`; menu switching + Attack flow in `public/js/ui/turnAttack.js`).
  - **End Turn** — `POST /encounter/advance_turn` (Encounter's *Advance Turn*).
  - **Attack** — the progressive-disclosure flow above, driving `GET /encounter/attack_options`, `POST /encounter/build_attack`, `POST /encounter/attack_check` (renders the Check Resolution Stub), and `POST /encounter/resolve_attack`. Attacker Bonuses (Flatfooted, Unaware) and Defensive Actions (Parry / Block / Dodge) are assembled server-side; the dice are resolved by the shared Check engine.
- **Deferred (panes render a staged note):**
  - **Start of Turn** — Conditions' *List Pending Afflictions* / *Resolve Due Afflictions* / *Clear Expired Effects* exist, but nothing in the app yet inflicts Afflictions with a Round or establishes a "current Round", so there is no live data to drive the pane.
  - **Item** — Equipment's *Consume Item* exists, but its collaborator contract (`@abilities.resolve_spell`, `@creatures.restore_mana`) is met only by test stubs today; the real Abilities/Creatures methods and the target-bound Conditions/Combat adapters still need building.
  - **Cast** — Encounter's *Attack / Cast / Use Item* is declared future work in `encounter_design.md`.
  - **Move / Special** — need a combat scene-log sink.
  - **Luck rerolls / DM Luck Points display** — `luck_points` / `dm_luck_points` are tracked on the Combat State, pending a luck-spend endpoint and the read-only display.
