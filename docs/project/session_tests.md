# Session Tests

A Session Test plays a session. Where the specs under `spec/` check one
domain operation at a time, a Session Test sits at the DM's laptop: it
adds Creatures to the tracker, starts Combat, opens the Cast pane, picks
a Spell, rolls the dice, confirms, ends the turn, camps for the night,
and walks into town. Everything it does goes over HTTP, through the same
endpoints the browser calls, in the same order.

That makes them slower and broader than the unit specs, and it makes them
fail for a different reason: not "this formula is wrong" but "the DM
cannot get from here to there".

They live in `spec/sessions/`, and there are five, one per kind of thing
a session is made of:

| File | The session it plays |
|---|---|
| `combat_spells_session_spec.rb` | A fight, driving the Cast / Attack / Active Spells panes for each Spell the project asked to cover |
| `noncombat_encounter_session_spec.rb` | Camp after the fight: Skill Rolls, potions and scrolls, the whole Heal axis and the whole Ward axis, Mana and Toxicity, the clock |
| `long_term_affliction_session_spec.rb` | A venomous bite followed from the Round it lands to the day it clears, plus a disease measured in days |
| `travel_session_spec.rb` | Four days on the road: hour and day jumps, nightly recovery, Maps, a wandering encounter |
| `city_session_spec.rb` | A week in town: the Store, kitting out, the Sell Pile, downtime |

## Running them

```
bin/session-tests                                   # every scenario
bin/session-tests spec/sessions/travel_session_spec.rb
```

A plain `bundle exec rspec` skips them. They are tagged `:session`, and
`spec/spec_helper.rb` excludes that tag unless the command targets
`spec/sessions` or `SESSION_TESTS` is set — so the fast unit suite stays
fast, and pointing rspec straight at a session file still works.

They need `node` on PATH (see *Scripted dice*). Without it each scenario
skips itself with a message rather than failing.

## What a Session Test may and may not do

**It drives the app.** A Session Test asks `/encounter/cast_builder` what
the DM's Cast pane would offer, picks one of those options, applies that
option's patch to the Rolls the way `public/js/ui/actionBuilder.js` does,
and POSTs the payload `turnCast.js` would have POSTed. If the builder
stops offering a Spell, or the payload shape drifts from what the
resolver reads, a Session Test breaks — which is the point. A spec that
calls `Encounter::State#resolve_cast_payload` directly would not.

**It does not reach past the app to set up state.** Wounds come from
someone hitting someone; potions come out of a fixture inventory or the
Store; time moves because the DM moved it. There is one documented
exception — `Session#inflict`, because nothing in the app can give a
Creature a disease — and that exception is itself one of the gaps below.

**It never touches `data/`.** See *The test Campaign*.

## The test Campaign

Every scenario runs against a frozen Campaign under
`spec/sessions/fixtures/`, copied into a throwaway directory and torn
down afterwards (`spec/sessions/support/campaign.rb`). The live `data/`
directory is never read and never written, so editing the real campaign
can never break the suite and the suite can never eat the real campaign.

Rule data is *not* fixture data. Spells, Afflictions, Skills, the item
catalog, the calendar and the shop rules all load from `docs/common/` as
normal — a Session Test asserts against the campaign's real rules, not a
second copy of them that could drift.

Creature files are shadowed, not merged. `Creatures::Dataset` unions the
writable overlay with the shipped `.example` rosters, so the Campaign
writes an empty `characters: []` file for every example basename it does
not itself supply. Without that, the example party walks into every
scenario.

The party:

| Id | Who | Why they are there |
|---|---|---|
| 1 | Ash Windmere, bard 3 | Skill Rolls and the Roll Log |
| 3 | Lira Duskmoor, wizard 6 (Tier 2) | Grease, Create Pit, Standard Shield |
| 7 | Thora Stoneveil, cleric 4 (Tier 2) | Shield of Faith, Spiritual Weapon, the low Heal and Ward Tiers, the Potion and Scroll |
| 8 | Garroth Vask, barbarian 4 (Tier 2) | The one who gets hit |
| 9 | Sister Auria, cleric 12 (Tier 5) | Every Heal Tier and every Ward Tier, up to Extreme and Superior |

The opposition is in `creatures_data_enemies.yaml`. Three notes on it,
each of which a scenario depends on:

- The **Bandit Captain** is Tier 2 and armed from the `soldier_loadout`.
  A Tier-0 goblin cannot scratch a Tier-2 Character — its damage vanishes
  into Inherent damage reduction — so the Captain is the only enemy in
  the roster who can leave a wound worth healing.
- The **Marsh Adder** is `race: spider`, which grants Fang Bite; the
  `Bite (Fangs)` weapon injects `spider_venom`. It is the only thing in
  the Campaign that can inflict an Affliction.
- Ids **302** and **303** are the templates the shipped
  `general_goblin_ambush` Random Encounter Table spawns. The tables ship
  in `docs/common` and name their Creatures by id, so a Campaign can only
  roll a table whose ids it happens to cover.

## Scripted dice

Dice are rolled in the browser. The Action Builder asks Check Resolution
for each Roll's Target Number after cross-side Propagation, the Roll
Controller rolls, and Scoring turns the dice into the Successes the page
POSTs back. A Session Test scripts the dice — it states the values, the
way the test docs under `docs/common/**` do — but runs them through
*those same modules*, in `node`, over a line protocol
(`spec/sessions/support/dice_bridge.mjs`, driven from `dice_bridge.rb`).

So a scenario writes:

```ruby
session.cast('Standard Ward', by: 'Sister Auria', on: 'Garroth Vask',
             dice: [9, 8, 7, 6, 5])
```

and the Successes that reach `/encounter/resolve_cast` are exactly the
ones the DM would have seen for those dice. Nothing re-implements TN
computation, Propagation, Ascendancy or Scoring in Ruby.

Reroll and Nudge are not applied — no scenario spends Luck yet. Adding
Luck to a scenario means teaching the bridge the reroll and nudge slots
`RollController.rollGroup` reads.

## Writing a scenario

`Sessions::Session` (`spec/sessions/support/session.rb`) is the DSL. The
useful half of it:

| Call | What it drives |
|---|---|
| `add_to_roster`, `spawn_enemy(t, as:)`, `exclude_from_combat`, `include_in_combat` | The roster sidebar |
| `start_combat`, `take_turn(name)`, `advance_turn`, `end_turn`, `end_combat` | The Combat Tracker |
| `cast(spell, by:, on:, dice:, save_dice:, item: false)` | The Cast pane (and the Item pane) |
| `cast_area(spell, by:, at:, affecting: {name => dice})` | An area Spell: placement plus one Save per Creature in the footprint |
| `attack(by:, on:, dice:, defense:, defense_dice:, shielded_by:, shield_dice:)` | The Attack pane, Ally Defense included |
| `strike_with(spell, by:, on:, dice:)` | The Active Spells pane |
| `skill_roll(by:, skill:, dice:)` | A player rolling off their sheet into the Roll Log |
| `resolve_affliction_save`, `treat_affliction(seed:)` | The Save Resolution and Affliction Relief stubs |
| `advance_time(rounds:, days:)`, `rest_night`, `advance_scene_round` | The campaign clock |
| `buy([{item:, for:, quantity:}])` | The Store cart checkout |
| `hp_damage`, `temp_hp`, `mana_spent`, `toxicity`, `afflictions`, `combat_pool`, `quantity_of`, `gold`, `clock` | Reading state back |

Creatures are named, not numbered. `spawn_enemy('Goblin Raider', as:
'Ford Raider')` labels one spawn so a scenario can field several of the
same template.

There is deliberately no `end_turn`. The Urgent Actions panel's bulk End
Turn rolls every due Affliction save server-side with a random RNG, which
a scripted-dice scenario cannot state or reproduce; scenarios confirm
each save by hand with `resolve_affliction_save(..., dois:)` instead, the
way the DM does in the Save Resolution stub.

Two things are worth copying from the existing scenarios. First, assert
against the rule data rather than a number you observed: the Ward
scenario walks `spells.yaml`'s `temp_hp` table Tier by Tier, so a change
to the table fails the test with a reason. Second, when a result is
surprising, say why in the test — the Create Pit scenario spells out that
a Tier-0 goblin cannot save against a Tier-2 caster no matter what it
rolls, because the caster's bonuses cross onto its Roll as penalties.

### Transcripts

Every scenario writes a readable log to
`tmp/session_transcripts/<scenario>.txt` — each action, its dice, each
Roll's TN and Successes, and the outcome:

```
── Round 1 — the goblins break cover ──────────────────────
• Thora Stoneveil casts Shield of Faith on Garroth Vask
    Thora Stoneveil: [9, 8, 3, 7, 2] @ TN 3 → 5 successes
    → hit
```

It is never diffed and never fails a run. It is there to be read: a DM
can check a scenario against the rules by eye without reading Ruby.

### Marking what is not built yet

A Session Test may describe behavior the app does not have. Write the
expectation for real and mark it with `gap`:

```ruby
it 'consumes the party Rations for each day travelled' do
  gap 'nothing in the app reads or decrements Rations'
  before = session.quantity_of('Rations', owner: 'party')
  session.advance_time(days: 4)
  expect(session.quantity_of('Rations', owner: 'party')).to eq(before - 4)
end
```

`gap` is `pending` with a reason. The suite stays green, RSpec lists
every gap at the end of a run, and the day someone implements the
feature the example fails as `FIXED` and tells them to unmark it. That
list is the to-do register — it lives in the tests, next to the scenario
that wants the behavior, not in a document that drifts.

Two rules for a gap. State the *behavior* a session wants, not the shape
of a fix — `gap` describes what the app should do, not which method
should exist. And check it is really missing: an expectation that passes
by accident is reported as `FIXED` and is worse than no test.

## What the gaps say today

At the time of writing, twelve gaps. Grouped by what they block:

**Time does not drive anything but the clock.**
`/chronicle/advance-time` moves the timestamp and nothing else.
`Conditions#resolve_due_afflictions` — which already handles jumped time
correctly, owing one save per missed interval — is called from nowhere in
`lib/`. So a day-frequency Affliction (`sleeping_sickness`, `ghoul_fever`)
never rolls a save on the road, and a night's rest does not roll the ones
that came due overnight. Natural Recovery runs one tick per press of Rest,
so a four-day jump mends nothing.

**Nothing can apply an Affliction but a weapon and a Spell.**
There is no route to inflict or cure one, so a disease, a curse or a trap
has to be poked into Conditions by hand — which is why `Session#inflict`
exists.

**There is no travel.** No pace, no distance per day, no route between
Maps; a journey is the DM pressing Advance Time and describing it aloud.
Rations sit in inventories and are never eaten. And
`/random_encounters/roll/:table_id` ignores a seed even though
`Creatures.roll_random_encounter` accepts one, so a rolled encounter
cannot be replayed — by the DM or by a Session Test.

**There is no shop, only a catalog.** `shops.yaml`'s population-scaled
stocking and finite purchasing budgets are loaded and unused: no page
visits a Shop, and `Equipment::Shops#advance_time` — which expires stale
Generic Shop stock — is called from nowhere, so the Shop Game Day never
moves. The Sell Pile deletes rather than sells: no route turns loot into
gold. Downtime costs nothing.

**Equipment Slots are not exclusive.** `equip_stack` flips a flag;
nothing stops a Character wearing a Chain shirt and a Breastplate at
once, and `reconcile_loadout` then posts the effects of both.

Run `bin/session-tests` for the current list — the register is the
pending output, not this paragraph.
