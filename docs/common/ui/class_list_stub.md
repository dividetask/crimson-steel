# Class List Stub

The **Classes** chapter of the Compendium (`/compendium?view=classes`). A
player-facing reference listing every base playable Class with a short
summary; clicking a Class opens its full page, laid out like the Classes
design document.

## List

- One card per **base playable Class** — every Class in
  `creatures_advancement.yaml` that is **not** flagged `npc_class: true`
  **and not an archetype** (a Class with `parent_class:`). So `warrior`,
  `feral`, `commoner`, `paragon` (NPC-only) and `ranger`, `arcane_trickster`
  (archetypes) never appear. Cards are sorted by display name.
- Each card shows the Class **name** and its one-line **summary**
  (`docs/common/creatures/class_descriptions.yaml` → `summary`). The summary
  appears **only** on the list — the detail page carries no prose blurb.
- The list is read-only reference data, visible to both the DM and players.

## Detail (click-through modal)

Clicking a card fetches `/class-detail?name=<class key>` and drops the
rendered fragment into the shared modal (the same modal used by the Spell
List). The page mirrors the design document's per-Class layout:

- **Proficiencies** — Armor and Weapons (`class_descriptions.yaml` →
  `armor`, `weapons`), and **Saving Throws**, the two good Saves derived as
  the six Attributes minus the Class's `saves.opposed` list.
- **Skills** — "Gain `bonus_skills` + ¼ Intelligence skills. (Optional Rule)
  Gain an additional background skill."
- **Aligned Skills** — the Skills that advance at the fast (Aligned) rate,
  faithful to `Proficiencies::Ranks#skill_rate`: an inclusion-form Class
  (`aligned_proficiencies`) names them; an inverse-form Class
  (`unaligned_proficiencies`) trains every Skill fast except those it names.
- **All Skills** — the full Skill catalog (collapsed by default).
- **Level progression table** (levels 1–5, or deeper when a Class has
  authored Spell data past it — the Bard runs to 6), all columns derived live:
  - **Mana** — `level × mana_per_level`.
  - **Aligned** / **Unaligned** / **Opposed** — the ranks a Skill (or the
    bonus a Saving Throw) gains per level at each of the three Proficiency
    Rates (`Proficiencies::Ranks.apply_rate`): 5·level/3, level, and
    2·level/3 respectively.
  - **Spells Known** (only for a `tiered_count` Class — its
    `spell_selection` in creatures_advancement.yaml carries the per-Tier
    progression, e.g. the Bard) — one column per tracked Spell Tier, giving
    the number of spells of that Tier known at each level. This is the same
    data character creation uses for the Bard's per-Tier spell picks. No
    counts are invented for other casters; they carry only a one-line
    spellcasting note under the table.
  - **Special** — the Abilities gained that level (`ability_progression`).
- **Class Features** — the `ability_progression`, grouped by the level each
  Feature is gained, each with its Abilities-catalog description.
