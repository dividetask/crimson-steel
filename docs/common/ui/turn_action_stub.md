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

A multi-step client-side flow that POSTs once at the end. It is backed by the Encounter attack pipeline (`encounter_design.md` → *Attack / Cast / Use Item*, *Defensive Actions*; `Encounter::Attack.build_spec` + `Encounter::State#resolve_attack_payload`). Stages:

1. **Pick target.** Buttons for every other living Combatant (the roster the initiative stub above provides). Incapacitated targets are dimmed but clickable. The attack kind is `melee`, `ranged`, or `spell`.
2. **Pick weapon and dice.** The attacker's equipped weapons come from the *Attack Options* fetch. For each weapon a row shows name, Speed cost, Dice Cap, and a horizontal strip of dice-count buttons from the action minimum up to `min(Dice Cap, Combat Pool Remaining)`. Pre-rolling dice maps to Set-Value Spend (`encounter_design.md` → *Set-Value Spend translation*).
3. **Declared defense (optional).** The defender may declare one Defensive Action against the incoming attack — `Parry`, `Block`, or `Dodge`. Eligibility follows the table in `encounter_design.md` → *Defensive Actions* (Parry: Martial, melee only; Block: Martial, any; Dodge: a **Dexterity save**, any, costs no Combat Pool). Declaring an eligible defense also clears the defender's Flatfooted status. Parry/Block let the defender pick dice from the Reaction minimum up to Combat Pool Remaining; Dodge rolls the full Dice Cap.
4. **Apply afflictions** (optional). Inputs that stack Affliction Potency on the target via Conditions' *Inflict Affliction*, keyed by catalog Affliction (e.g. `bleeding`, `ghoul_paralysis`).
5. **Roll dice.** Client-side dice rendering through the JS Check engine. The DM may spend the Combatant's `luck_points` on rerolls (e.g. Bardic Inspiration), which re-roll a single die client-side.
6. **Submit.** A single POST carries the Confirm payload (below). The server spends Combat Pool for every participant, nets Supporting minus Opposing Successes per *Check Resolution*, and on a positive net Degree of Success routes the damage through *Apply Damage* → Conditions' *Apply Hit Point Damage*. Temporary HP absorbs worst-first (Major → Moderate → Minor) before the Severity counters increment, per `conditions_design.md`.

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

- **Wired now (server side):** the Attack flow's pipeline — `GET /encounter/attack_options`, `POST /encounter/build_attack`, and `POST /encounter/resolve_attack` (`Encounter::Attack.build_spec` builds the Roll specs and eligible Defensive Actions; `Encounter::State#resolve_attack_payload` spends Combat Pool, nets Successes, and applies damage). Attacker Bonuses (Flatfooted, Unaware) and Defensive Actions (Parry / Block / Dodge) are assembled server-side. Equipment's *Consume Item* and Conditions' Affliction-resolution, mana, toxicity, and effect-expiry entry points all exist and back the Item / Start-of-Turn / Cast panes' effects.
- **Deferred:** the panel UI itself (no `views/_turn_action*.erb` partial yet) and its JS glue; the `Start of Turn`, `Move`, `Cast`, `Item`, `Special`, and `End Turn` POST endpoints (Encounter's *Attack / Cast / Use Item* is declared as future work in `encounter_design.md`; *Advance Turn* exists on the state but has no `/encounter/advance_turn` route yet); the per-Combatant luck-spend endpoint; and the DM Luck Points display. Each ships when its route and owning-domain wiring are in place.
