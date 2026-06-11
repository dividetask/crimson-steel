# Encounter Roll Table Stub

Fires a **Roll Table Reaction** during an attack: a Reaction Ability that resolves by rolling on a provided table (talents.yaml `roll_table:`, e.g. **Kesser's Gambit** → the **Kesser Reversal Table**). The channeler rolls a channel check (its Combat Pool dice → **Channel Successes**), a die is rolled on the table, and the matched entry is **previewed** — the DM may **reroll** the effect freely, then **Confirm** to spend the Combat Pool dice + the Ability's Mana and lock the shown entry. Spending happens only on Confirm; a preview / reroll costs nothing. Combat does **not** apply the entry's mechanical effect; the DM adjudicates it, and the stub lists every **modifier on the channel check** (Competency, Inherent) beside the Channel Successes so the DM can set save TNs against the effect by hand.

The stub rides alongside the Attack **Action Builder**, in the same place as the **Standard Shield**'s ally block (`encounter_design.md` → *Shield of Faith hangs a defended ally*). It is offered to a Combatant **other than the attacker** who holds a Roll Table Reaction. Lives in `views/_encounter_roll_table_stub.erb`; driven by `public/js/ui/turnRollTable.js`.

See `ui_conventions.md` for shared rules, `action_builder_stub.md` for the channel-check Builder it embeds, and `turn_action_stub.md` → *Attack* for the host attack flow.

## Who is offered the reaction

`roll_table_reaction_channelers(attacker_id)` (lib/routes/encounter.rb) walks every Combatant except the attacker and keeps those who can field a Roll Table Reaction. The Ability — and the **skill its channel check rolls with** — depends on where the Combatant got it:

- An **equipped Item** that grants it (Kesser's Ring, `equipment_config.yaml` → *Unique Items*) rolls with **Evocation**. Combat reads the grant straight off the equipped Item (`equipped_granted_abilities`); equipped grants are not yet folded into Creatures' Granted Abilities.
- A **Cleric's Channel Divinity** grant (a Granted Ability whose `source` is `class:<key>`) rolls with **Invocation**.

Each channeler entry carries the channel `skill` + its **Dice Cap**, the Reaction's **Mana cost** (resolved through the Ability's inherited cost — Kesser's Gambit inherits 4 Mana from the base Channel Divinity Talent), and whether the channeler can afford it (≥ the **Reaction Action Minimum** in its Combat Pool, and enough Mana). A channeler that cannot afford it renders disabled with the reason.

## Layout

A **Reactions** section with one button per eligible channeler — `<Name> — <Ability> (<Skill>, <N> mana)`. Picking one:

1. Mounts the **channel-check Action Builder** (`GET /encounter/roll_table_builder`) — a single supporting Roll in the channeler's Evocation / Invocation skill (its Competency + the channeler's Tier Inherent Bonus fold into the Roll), with a **Channel dice** step from the Reaction Action Minimum up to `min(Combat Pool, Dice Cap)`. The DM rolls the check; its Successes are the **Channel Successes**.
2. On the Builder's `action:confirmed`, the chosen dice + Channel Successes POST to `/encounter/roll_table_reaction` as a **preview** (`commit:false`). The server (`Encounter::State#use_roll_table_payload`) rolls the table die and returns the matched entry **without spending** anything.
3. The **result** renders: `d<die> → <face>`, the entry **name**, the **Channel Successes**, the entry **effect** text, the **channel-check modifiers** (`<Skill> check: +N Competency +N Inherent · <N> successes — roll any saves against this`), a "will spend" note, and two buttons:
   - **Reroll effect** — re-POSTs the preview without a `face`, drawing a fresh die (no spend); the entry re-renders.
   - **Confirm** — re-POSTs with `commit:true` and the shown `face`, which spends the dice from the channeler's Combat Pool + the Mana cost and locks that entry. The result re-renders with a "spent" note and the buttons removed.

The channel-check Builder's `action:confirmed` is scoped to this stub (the JS stops its propagation) so the host attack's own Builder never sees the channel roll.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/encounter/roll_table_builder?combatant_id=&ability=` | The channel-check Action Builder fragment for a channeler. |
| `POST` | `/encounter/roll_table_reaction` | `{ combatant_id, ability, dice, successes, commit?, face? }` — roll the table; spend only when `commit:true` (default). `face` locks a previewed entry on Confirm; omitted (preview / reroll), the server rolls a fresh die. The response carries the channel-check `skill_label` + `modifiers`. Mutates Conditions (Mana) only on commit, so the store is persisted then. |

## Out of scope (for now)

Combat reports the rolled entry but does not apply it — counter-attacks, tier/dice swaps, target redirection, equipment teleports, and AoE re-damage are the DM's to adjudicate. The table entries reference Channel Successes; the stub fills in the concrete number beside the entry so the DM can scale it.
