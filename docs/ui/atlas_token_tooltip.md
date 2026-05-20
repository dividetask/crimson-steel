# Atlas Token Tooltip

A read-only popup that surfaces the identity of a Token on a Map. Triggered by hover (or tap on touch devices) over a Token rendered by `atlas_stub.md`. The tooltip's content is intentionally lightweight — its purpose is to answer the question *which creature is this?* without leaving the map view.

See `ui_conventions.md` for shared rules, including the Tier Color mapping.

## Content

A small panel with the following rows, top to bottom. Rows with no data are omitted.

1. **Name** — large. The Token's `label` override when set; otherwise the referenced Creature's name from the Creatures domain. Colored using the Creature's Tier Color.
2. **Subtitle** — the Creature's race + class summary (e.g., `Human Bard 3`) and Tier label. Only shown when the viewer is the DM or the Creature is a `player_character`. For unknown opponents seen by a player viewer, the subtitle is omitted.
3. **Vitals strip** — HP, Mana, Toxicity for the referenced Creature. Only shown when:
   - the viewer is the DM, OR
   - the viewer is a player and the Token's `owner_id` matches the viewer's Creature ID.
4. **Conditions row** — a short list of active condition labels on the Creature (e.g., `Prone`, `Concentrating`). Visible to the DM and to the Token's owner; hidden from other players.
5. **Combat status** — when a Combat roster is supplied to the parent stub and the referenced Creature is a Combatant, shows the Combatant's Initiative String and a *Acting now* badge when the Combatant is the `acting_combatant_id`.

When the referenced Creature does not exist (the Token references a deleted Creature ID), the tooltip shows a single line: `Unknown creature (#<creature_id>)`.

## Parameters

Required:
- A Token — the record from Atlas.
- Viewer role — `dm` or `player`. Determines which rows are visible.

Optional:
- Viewing Creature ID — for player viewers. Used to decide whether the vitals and conditions rows are visible.
- Combat roster — list of Combatant records (each carrying at least `creature_id`, `initiative_string`, and a flag indicating whether it is the Acting Combatant). When supplied and the referenced Creature is in the roster, the Combat status row is populated.

## Data sources

The tooltip composes data from:

- **Atlas** — Token record (label, image, position, owner_id, hidden flag).
- **Creatures domain** — name, race + class summary, Tier.
- **Conditions orphan data** — current HP / Mana / Toxicity, active condition flags. (Moves to the Conditions domain when designed.)
- **Combat domain** (via parent stub) — Combat roster pass-through.

The tooltip itself does not call any of these directly; the application gathers the inputs and passes them in.

## Visibility

The tooltip is read-only and does not filter Tokens — the parent stub decides which Tokens render and therefore which Tokens are hoverable. The visibility rules above govern only *which rows* render once the tooltip is shown.

## Composition

This tooltip is self-contained. It is not designed to embed inside another tooltip. The `atlas_stub.md` triggers exactly one instance per hovered Token.
