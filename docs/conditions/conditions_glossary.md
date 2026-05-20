# Conditions — Glossary

Defines the vocabulary used by `conditions_design.md` and `conditions_tests.md`. Conditions tracks per-Creature mutable state — HP damage, Ability Damage, Temporary Hit Points, Mana Spent, Magic Toxicity, Shock, the Acid Counter, ongoing Afflictions, and Active Effects. The module is deliberately ignorant of who or what produces an effect; sources are identified by opaque Source IDs and Tier values. Glossary entries describe terms in domain language — formulas, field names, and other code-level detail belong in `conditions_design.md`. *(configurable)* values come from `conditions_config.yaml`. The Affliction catalog lives in `afflictions.yaml`; the Effect Name catalog lives in `effect_names.yaml`.

## Core Concepts

**Conditions Instance**: The Conditions state belonging to one Creature. Every participant in a Check has its own instance; the module never compares state across Creatures.

(Round, Tier: see common glossary.)

**Source ID**: An opaque, caller-owned identifier carried alongside an Active Effect or Temporary Hit Point grant. Conditions treats it as text — never inspects, parses, or interprets it — and uses it only to find or remove the entry the caller posted.

## Hit Points and Damage

(Severity: see common glossary. The canonical Severity list — Minor, Moderate, Major, ordered least to most serious — is owned by Combat per `combat_glossary.md`. Conditions consumes the list in canonical order; Heal Cascades pour worst-first.)

**Minor / Moderate / Major Damage**: Counters of HP damage in each Severity Category. Each accumulates independently; damage never cascades between categories.

**Temporary Hit Points**: A pool that absorbs incoming HP damage before the Severity counters. Exactly one grant is active at a time; a new grant replaces the existing one only when its amount is strictly higher.

**Current Hit Points**: The Creature's currently-available hit points, derived by the Creatures domain from maximum HP, the three Severity damage counters, and Temporary Hit Points. Conditions exposes the inputs; Creatures owns the derived value.

**Heal Cascade**: A worst-first heal operation. A heal supplies one pool per Severity; each pool tries to heal its Severity, with any leftover draining into the next worse-first pool. Excess past Minor is wasted.

## Ability Damage

**Ability Damage**: Damage dealt to ability scores. Stored per attribute per Severity Category; insertion order across attributes is preserved so the Ability Heal Cascade can pop FIFO.

**Ability Heal Cascade**: Heal Cascade applied to Ability Damage. Within a Severity, heal points pop damage from attributes in the order they were first affected.

## Mana

**Mana**: A Creature's expendable magical energy resource. Mana Max is owned by Creatures; Conditions tracks how much of it the Creature has currently consumed.

**Mana Spent**: The amount of Mana the Creature has consumed since last at full. Mirrors the HP and Ability Damage convention — a counter measured upward from "nothing wrong" — so Mana doesn't need special treatment compared with the other tracked resources, and a buff that raises Mana Max never retroactively spends more.

**Current Mana**: The Creature's currently available Mana. Derived by Creatures from Mana Max and Mana Spent. Conditions exposes Mana Spent; Creatures owns the derived value.

**Mana Cost**: A spend on Mana — increases Mana Spent toward Mana Max.

**Mana Restore**: A recovery on Mana — decreases Mana Spent toward zero.

## Natural Recovery

**Natural Recovery**: The accumulated effect of time passing — HP damage healing, Ability Damage healing, Mana regeneration, Magic Toxicity decay, Temporary HP clearing. Rates come from `conditions_config.yaml`.

**Recovery Tick**: The smallest unit of game time Natural Recovery advances by, distinct from Combat's Time Tick. The consuming project decides what one Recovery Tick represents — a Day in the tabletop game, a much shorter wall-clock interval in a real-time game. Conditions never reads the wall clock itself; callers supply the elapsed Recovery Tick count when they invoke Natural Recovery. The duration of one Recovery Tick in rounds is configurable, so a caller working in absolute round counts can divide rounds by the configured length to get Recovery Ticks. *(configurable: rounds per Recovery Tick.)*

**Recovery Mode**: One of `slow` or `fast`. Slow Mode represents recovery while travelling or otherwise active; Fast Mode represents bed rest or active care from a healer. Each Heal Rate row supplies one rate per Mode.

**Heal Rate**: A Tier-indexed table defining how HP Damage heals at each Severity, in each Recovery Mode. Higher Tiers heal faster; Minor heals fastest at every Tier; Major heals slowest. *(configurable)*

**Ability Heal Rate**: A second Tier-indexed table with the same shape governing Ability Damage recovery. Each heal point pops one queued Ability Damage point at that Severity in FIFO order. *(configurable)*

**Mana Per Recovery Tick Divisor**: Integer divisor applied to Mana Max to produce per-Recovery-Tick Mana regeneration. *(configurable)*

**Magic Toxicity Per Recovery Tick Divisor**: Integer divisor applied to the Magic Toxicity attribute (typically `cha`) to produce per-Recovery-Tick Magic Toxicity decay. *(configurable)*

## Magic Toxicity

(Magic Toxicity, Toxicity Threshold, Toxicity Block, Toxicity Damage: see common glossary.)

**Toxicity Source Kind**: A caller-supplied classification distinguishing a positive Magic-Toxicity-imposing effect (a buff, magical healing, voluntary attunement) from any other source (harmful magic, environmental exposure). Toxicity Block applies only to positive sources; Toxicity Damage applies to any source.

## Death

**Death Threshold**: A Creature is Dead when any one of three Death Tracks (HP, Attribute, Toxicity) has accumulated enough state to cross its threshold. Each Death Track's threshold is derived from a Creature-side maximum (max HP, the relevant attribute score, the Toxicity Threshold) scaled by the configurable Death Multiplier. *(configurable: Death Multiplier.)*

**Death Multiplier**: The scalar that turns each Death Track's Creature-side maximum into the threshold at which death occurs. Stored as a number — fractional values are permitted, allowing a game to tune lethality without changing the per-track maxima. *(configurable)*

## Shock

**Shock**: A counter of battlefield disorientation. Each point removes one die from the Creature's Combat Pool on the next pool refresh. Shock has no save and no automatic decay.

**Shock Consumption**: The operation where the caller asks Conditions "how much Shock can I consume against up to N dice", receives the amount, and decrements the counter. Excess Shock persists across rounds until fully spent. Conditions does not know Combat Pool size — the caller passes it in.

## Acid Counter

**Acid Counter**: A non-negative integer counter representing residual corrosive damage. Combat adds to it when acid damage lands. At the start of the affected Creature's turn the counter is halved (rounded down) and the post-halving value is dealt as **Minor** HP damage to the same Creature; a counter that drops to zero is removed.

Like Shock, the Acid Counter is a built-in top-level field with hardcoded behavior. New damage-type counters with similarly distinctive behavior are added the same way — a code change, not a config change.

## Afflictions

**Affliction**: An ongoing condition with a Potency counter and a data-driven resolution rule (bleeding, common venom, ghoul paralysis, sleeping sickness). Each Affliction is named by a key in `afflictions.yaml`. The Potency counter is named distinctly from Damage Severity to avoid confusion — "Potency" is the Affliction's strength; "Severity" is reserved for the Damage Severity Categories owned by Combat.

**Potency**: A non-negative integer counter for a single Active Affliction. Higher Potency produces a larger save Target Number Penalty and (via Magnitude) a larger resolved effect. Accumulates when re-inflicted; decreases on save successes and via Potency Decay; increases on save failures.

**Active Affliction**: An Affliction with Potency above zero. A Creature may carry multiple simultaneously.

**Affliction Order**: Active Afflictions are held in insertion order. When Potency decays to zero the entry is deleted; re-inflicting later re-inserts at the end.

**Affliction Category**: A free-form string label for presentation and grouping (`poison`, `disease`, `curse`, `bleed`, `other`, etc.). Conditions stores it but does not branch on it. *(per-Affliction)*

**Inflicter Tier**: The highest Tier among all sources that inflicted this Affliction since it last reached zero Potency. First-class field on every Active Affliction; rises to match any new inflicter that is higher than the current value while the entry lives. Callers that compute a save TN penalty based on Inflicter Tier read it back and fold the modifier into their own modifier dict — Conditions does not auto-inject it.

**Save Frequency**: How often the Affliction is meant to resolve. One of `round`, `minute`, `hour`, `day`, `month`, `year`. Drives Affliction Scheduling — Conditions advances each Active Affliction's next-resolution time by the corresponding number of rounds whenever it is inflicted or resolved. *(per-Affliction)*

**Affliction Scheduling**: The mechanism by which Conditions tracks when each Active Affliction is next due to resolve. The caller drives the clock by passing a current Round at inflict / resolve time; Conditions advances the Affliction's next-resolution time by the configured number of rounds for its Save Frequency.

**Affliction Rule**: The data-driven spec of what an Affliction does, defined in `afflictions.yaml`. Specifies: optional save attribute (defaults to `con`), Affliction Category, Save Frequency, Potency Per Success / Failure / Decay, and Affliction Effect.

**Potency Divisor**: The divisor used in computing Magnitude and the Potency Save Penalty from an Affliction's current Potency. Same Divisor for every Affliction — no per-Affliction override. *(configurable globally only)*

**Potency Per Success**: Amount Potency decreases per net save success. Integer or the literal `"tier"`. *(configurable globally and per-Affliction)*

**Potency Per Failure**: Amount Potency increases per net save failure. Integer or the literal `"tier"`. *(configurable globally and per-Affliction)*

**Potency Decay**: Amount Potency decreases each resolution, independent of save successes. Integer or the literal `"tier"`. Applied in addition to the Per Success reduction. *(configurable globally and per-Affliction)*

**Tier Substitution**: When a Potency Per Success / Failure / Decay value is the literal `"tier"`, it is replaced at resolution time with the Creature's Tier (Tier 0 → 0.5 per project convention). Final Potency deltas are rounded down to integers.

**Potency Save Penalty**: A Competency Penalty Conditions automatically merges into an Affliction save's modifier dict, scaled with the Affliction's current Potency via the Potency Divisor. Inflicter Tier and Creature Tier are **not** auto-added — that is the caller's responsibility.

**Affliction Effect**: The shape of what an Affliction resolution produces. Closed list — new kinds require a code change:

- `hit_point_damage` — deals damage to a specified Severity Category.
- `ability_damage` — deals damage to a specified attribute at a specified Severity Category.
- `named_effect` — applies an Effect Name by name for a specified duration.

**Magnitude**: The pre-save effect size of one Affliction resolution, scaled with Potency. A fresh Potency-1 Affliction resolves at Magnitude 1; higher Potencies produce larger Magnitudes.

**Net Magnitude**: The Magnitude that actually lands after the save reduces it by the number of net successes. Floored at zero — a fully-saved resolution is a no-op for the effect (Potency still evolves).

**Pending Afflictions**: The Active Afflictions currently due to resolve, per Affliction Scheduling. The caller resolves them one at a time, or bulk-resolves them in insertion order.

## Effect Names

**Effect Name**: A reusable named non-damage effect defined under `Effect Names` in `effect_names.yaml`. The **single source of truth** for the catalog across the project — Abilities reference Effect Names by name without validating; Conditions raises at apply time when a name does not match. Examples: `blind`, `paralyzed`, `prone`, `frightened`.

**Effect Mechanic**: One element of an Effect Name's `mechanics` list. A dict with a `kind` field plus kind-specific fields. Recognized kinds:

- `modifier` — a TN modifier. Fields: `modifier_type` (drawn from the Modifiers domain's Bonus Types List), `amount` (signed integer — positive for a Bonus, negative for a Penalty), `applies_to` (list of free-form scope tags), optional `notes`.
- `reroll` — triggers a Reroll Operation. Field: `scope`; optional `applies_to`, `amount` (signed; positive for "advantageous," negative for "disadvantageous"), `notes`.
- `nudge` — triggers a Value Adjustment. Fields: `applies_to`, `amount` (signed integer — positive shifts dice up, negative shifts them down); optional `notes`.
- `set_value` — overrides a derived value. Fields: `target`, `value` (integer or formula).
- `scale_value` — multiplies a derived value. Fields: `target`, `factor`.
- `flag` — sets a boolean state. Field: `flag`.
- `display` — a free-form rule the program does not encode. Field: `text` — surfaced to the DM.

Scope tags, target names, and flag names are intentionally free-form; Conditions does not validate them against any catalog.

## Active Effects (Buffs and Debuffs)

**Active Effect**: A typed modifier currently applied to the Creature. Generic representation of both buffs (Eagle's Splendor) and debuffs (Paralyzed, Shaken). An Active Effect may be permanent or expiring; only Active Effects that have not yet expired contribute to modifier lookups.

**Target Key**: An opaque, caller-owned key naming what an Active Effect adjusts — an attribute, a derived stat like Initiative or Speed, a named skill, or anything else the caller cares about. Conditions does not validate or enumerate the set.

**Bonus Type**: The TN Modifier type governing stacking. Drawn from the Modifiers domain's Bonus Types List. Stacking follows Dice Resolution's rule: within a single Target Key and Bonus Type, only the largest positive Amount and the most-negative Amount apply, and the net contribution is their arithmetic sum.

**Amount**: A signed integer magnitude carried by an Active Effect. A positive Amount represents a Bonus; a negative Amount represents a Penalty; zero is legal but has no mechanical effect.

**Modifier Lookup**: The query returning the surviving positive and negative Amounts per Bonus Type for a given Target Key, after stacking, limited to non-expired Active Effects.

## Serialization

**Conditions State**: The full persistent state of one Conditions Instance — damage counters, Ability Damage, Mana Spent, Magic Toxicity, Shock, Acid Counter, Temporary HP grant, Affliction list, Active Effect list. Sufficient fidelity to round-trip through serialization. Conditions does not own the storage format.

## Interactions with other domains

- **Combat** owns Severity Calculation and Damage Type Mechanics; it hands Conditions a per-Severity damage map and routes side-effects (Acid → Acid Counter, Cold → Shock) through Conditions' APIs.
- **Dice Resolution** owns the Roll mechanics used by save rolls and the per-type stacking rule used by Modifier Lookup. Bonus Type names are opaque to both domains; the canonical list lives upstream in the Modifiers domain.
- **Creatures** owns Mana Max, attribute scores, max HP, and the Charisma / Tier values that feed the Toxicity Threshold. Conditions reads these through callbacks or accepts them as parameters where needed.
- **Abilities** declares Effect Names without validating them; Conditions raises at apply time when a name is not in the catalog.
