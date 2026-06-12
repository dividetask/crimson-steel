# Conditions Bulk Affliction Stub

The **Urgent Actions** panel: a DM-only control that gathers every Creature's due Affliction saves into one place during the peaceful Phases, so the party's Bleeds, poisons, and other ticking Afflictions can be resolved together instead of one Combatant turn at a time. It is the bulk twin of the per-save `conditions_save_resolution_stub.md` — it does not resolve a save itself, it lays out one Save Resolution Stub per due Affliction and adds a single **End Turn** action that settles whatever the DM left un-rolled.

See `ui_conventions.md` for shared rules. Cross-domain terms (Affliction, Potency, Inflicter Tier, Tier) live in `../common_glossary.md` and `../conditions/conditions_glossary.md`.

## When it shows

- **Phase** — every Encounter Phase *except* Combat (Downtime, Traveling, Social, Looting). During Combat, Affliction saves are taken one Combatant at a time in the Start of Turn pane (`turn_action_stub.md`); this panel is the out-of-combat counterpart. Note that leaving the Combat Phase does **not** end Combat: when a fight winds down the DM typically switches to a peaceful Phase and keeps an active Combat running here until every Affliction is treated.
- **Viewer** — DM only. Players never see another Creature's Affliction internals; their view of the peaceful page is the PC health cards (`conditions_downtime_pc_card_stub.md`).
- **Gate** — shown only while at least one Creature on the roster carries an **active Affliction**. The save rows inside it are limited further to the Afflictions that are **due** per the Chronicle clock (their Next Resolution Round has arrived); a Creature with active-but-not-yet-due Afflictions contributes no save rows until time advances.

## Parameters

| Field | Shape | Purpose |
|---|---|---|
| `groups` | array of `{ combatant_id, creature_id, name, is_pc, saves: [...] }` | One entry per roster Creature that owes at least one due Affliction save. `saves` is a list of Conditions Save Resolution Stub `save` blobs (the same shape `start_of_turn_saves` builds), each carrying a `resolve` reference so its Confirm POSTs to `/encounter/resolve_affliction`. |
| `end_turn_url` | string | POST target for the bulk End Turn commit. |

The parent page builds `groups` by running each Combatant through the Start-of-Turn save builder and dropping the Creatures with no due Affliction. Because each `save` blob is the ordinary Save Resolution Stub shape, every row renders, rolls, and Confirms exactly as it does in Combat.

## Layout

A bordered panel, tinted with the Affliction/danger hue:

1. **Header** — `Urgent Actions` with a small `(DM only)` tag.

2. **Show actions for** — a checkbox row, one box per Creature in `groups`, all checked by default. Unchecking a box hides that Creature's save block below (a visual filter only; it does not exclude the Creature from End Turn).

3. **Summary** — one line per Creature: `<Name>: <due saves>`. Before a save is rolled each line reads `<Category> (potency N)` for every due Affliction. Once a save is rolled (or the DM overrides its preview), the line rewrites in place to the previewed outcome — `<Category>: <effect>, potency <before>→<after>` — so the DM can read the whole party's pending result at a glance. The Summary is a read-out of the live save stubs; it mutates nothing.

4. **End Turn** — a prominent button beside the Summary. See below.

5. **Save blocks** — below the overview, one block per Creature (toggled by the checkboxes), each holding that Creature's due Save Resolution Stub(s) with the Creature's name and a PC / NPC badge.

## End Turn

End Turn is the bulk commit. On press it:

1. **Rolls every still-due save the DM did not resolve by hand.** A save the DM rolled and Confirmed already ran *Resolve Affliction* and rescheduled its Affliction's Next Resolution Round, so it is no longer due and is skipped. Each remaining due save is rolled server-side using the same Bonus/Penalty list the Save Resolution Stub composes (the Creature's `save_modifiers`, the Creature Tier Inherent Bonus, the Potency Save Penalty, and the Inflicter Tier Penalty), the same TN computation, and the Roll's default scoring (Die Size → Critical, a 1 → Failure, ≥ TN → success). The rolled Degree of Individual Success is applied through Conditions' *Resolve Affliction*.
2. **Applies the players' own actions.** Cures a player or the DM has already taken to deal with the Conditions — a Use-Item from a PC card, a cast healing Spell — apply the moment they are taken, so they are already reflected in the state End Turn resolves against; nothing is replayed.
3. **Advances Combat by one turn** when Combat is active (it usually is — see *When it shows*), via the same *Advance Turn* the Combat tracker's Next Turn uses, rolling the Round over when the last Combatant ends their turn. With no active Combat, End Turn settles the due saves and advances nothing.

Repeated End Turns walk the party forward turn by turn — each one resolves the saves that have come due and ticks Combat on — until every Affliction has decayed away and the panel's gate closes.

## What this stub does not do

- It does not decide which Afflictions are due — the parent page enumerates them from the Conditions schedule against the Chronicle clock.
- It does not advance the Chronicle clock. Passing larger spans of time is the Advance Time control's job; End Turn only moves Combat by a single turn.
- It does not roll or display non-Affliction Conditions. Natural Recovery (HP / Ability Damage / Mana / Toxicity drift) is the Advance Time path, not this panel.
- It does not gate on viewer role internally — the parent page renders it for the DM only.
