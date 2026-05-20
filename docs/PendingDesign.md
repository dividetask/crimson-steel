# PendingDesign.md

Open design questions inside existing domains. Distinct from
`MissingClasses.md`, which tracks *missing domains*: this file tracks
features and mechanics that still need design work within domains
whose file set already exists.

Each entry names the scope, what currently exists, what's missing, and
the questions that need to be answered before the design can land.

## Process

1. When a review or refactor surfaces a feature that needs design work
   but the surrounding domain is otherwise stable, add an entry here.
2. When the design lands, delete the entry.

## Entries

### Combat — Defensive Actions (Parry / Block / Dodge)

- **Where it sits:** Combat. `combat_glossary.md` defines Defensive
  Action as "resolved as an Opposed Roll against the attacker's
  to-hit". `combat_design.md:237` flags the full attack pipeline
  (including Defensive Actions) as "future work".
- **What's missing:**
  - The Roll construction for each defense type. Which skill drives
    Parry? Which drives Block (a worn shield's skill? Athletics?)?
    Which drives Dodge (Acrobatics)?
  - Whether Parry / Block / Dodge produce mechanically distinct
    outcomes on the same Opposed Roll (e.g. does a successful Block
    convert moderate damage to minor, while a successful Parry
    deflects entirely?), or whether they only differ in eligibility
    (weapon required, shield required, etc.).
  - Cost: do Defensive Actions consume Combat Pool dice? Reaction
    allowance? Both?
  - Interaction with the Flatfooted Bonus: glossary says Flatfooted
    triggers when the defender takes no Defensive Action, but if a
    Defensive Action *fails* (Opposed Roll lost), does Flatfooted
    still apply?
- **Open questions for the user:**
  - Skill mapping per defense type.
  - Cost model.
  - Whether failed Defensive Actions are "no Defensive Action" for
    Flatfooted purposes.

### Chronicle — Draft entries and scene staging

- **Where it sits:** Chronicle. UI conversations
  (`CrimsonSteelAidV0/dm-scene-management-smfJ7.md`) defined a staging
  workflow with Draft Entries (`draft_name`, `draft_note`,
  `draft_image`) that live on the scene page and can be promoted into
  permanent notes. None of this is in the Chronicle design.
- **What's missing:**
  - Whether Draft Entries are a new Entry Type (alongside Note and
    Creature Reference) or a marker on existing Entries.
  - Promotion semantics: when a Draft is promoted, it lands in the
    Current Chapter (see `chronicle_glossary.md`). Confirm the exact
    flow.
  - Visibility rules for Drafts (e.g., the `shared` flag the
    conversation introduces — orthogonal to `public` / `hidden_from`).
  - Whether a dedicated `image` Entry Type exists, or whether the
    `image` field on any Entry covers the use case.
- **Open questions for the user:**
  - Are Drafts a separate Entry Type or a flag on existing Entries?
  - How does the `shared` flag relate to `public`, `hidden_from`, and
    `active`?
  - Does an image-only Entry Type exist?

### Abilities / Combat — Trigger Condition validity

- **Where it sits:** Abilities owns Trigger Specs;
  `abilities_glossary.md:153` says the Trigger Condition is "free-form
  and opaque to the Abilities module" and the consuming domain
  (typically Combat) evaluates it.
- **What's missing:**
  - Whether the consuming domain validates Condition strings at load
    time (rejecting unknowns) or silently never fires unknown ones.
  - The canonical list of recognized Conditions (the current
    talents.yaml uses `target_flatfooted`,
    `spends_all_remaining_dice`, etc. — none enumerated anywhere).
- **Open questions for the user:**
  - Hard validation or silent miss?
  - Where does the recognized-Condition list live — Combat's config,
    Abilities' config, or a runtime registry the consuming app
    populates?

### Creatures — Effective Attribute formula

- **Where it sits:** Referenced by UI stubs
  (`creature_full_stub.md:44`) and implied by `common_glossary.md`
  (Tier → Inherent bonus). No formula exists.
- **What's missing:**
  - The exact formula relating Tier, raw attribute scores, and
    Effective Attributes.
  - Whether Inherent / Ascendancy modifiers from Tier appear as
    Modifier Entries on Rolls or as adjustments to attribute values
    that then drive everything downstream.
- **Open questions for the user:**
  - Formula.
  - Modifier-on-Roll vs. attribute-adjustment model.
- **Notes:** When the Creatures domain lands, this entry moves into
  the Creatures glossary/design and disappears from here. Tracked
  separately from `MissingClasses.md` because the formula question
  exists independently of the broader Creatures domain effort.
