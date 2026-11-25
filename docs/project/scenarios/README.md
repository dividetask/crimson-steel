# Scenario Tests

Scenarios simulate a session at the table: the DM's laptop and four or more
player tablets talking to one Crimson Steel server. Each scenario's outline
lives in this folder; its test lives in `test/scenarios/<name>.rb`.

## Scenarios

| Scenario | Outline | Status |
|---|---|---|
| Simple Combat | [simple_combat.md](simple_combat.md) | In progress |
| Scouting Fort | — | To define |
| Assault on Cultists | — | To define |
| Stumpy Dream Encounter | — | To define |
| Character Creation | — | To define: a level 1 Barbarian, Cleric, Rogue and Bard. The DM assigns a tablet to *New Character*; the tablet walks the player through creation. Not on the tablets yet |
| Level Up to 6 | — | To define: the four new characters to level 6. A DM Level Up button (placement to be decided) adds a level-up button to that Character's sheet on their tablet, where the player goes through it. Not built yet |
| Random Encounter Preview | — | To define: roll Ogre Gang (1 Ogre Brute, 2–4 Ogres) as a preview with nothing added to combat; re-roll; Add to combat. Today each roll spawns and adds |
| Roll Init Starts the Turn | — | To define: Roll Init begins the first Combatant's turn. Today only Start Combat does |
| Standard Shield Blocks for an Ally | — | To define: an orc attacks Garroth, who picks No defense on his tablet; Thora interposes from hers. Paired with the same attack unshielded |
| Spells of Interest | — | To define: Shield of Faith, Standard Shield, Spiritual Weapon / Hammer, Grease, Create Pit, every healing spell, every ward spell (e.g. Ward's temp HP by tier) |
| Long-Term Afflictions | — | To define: hour- and day-long time jumps owe one save per missed interval and apply natural recovery. Today nothing calls the due-save code |
| Multi-Day Travel | — | To define: pace and distance, rations eaten, a random encounter on the road, the clock advancing. Not tracked today |
| City and Shops | — | To define: shop stock restocks over days; selling pays. Today restock is never called and the Sell Pile deletes |
| Equipment Slots | — | To define: equipping a Breastplate takes off the Chain shirt. Today both can be worn |
| Non-Combat Encounter | — | To define: spells, items and rolls spending resources, with time tracked |
| Several Tablets Rolling at Once | — | To define: Fireball on three PCs, each Dexterity save on its own tablet; the DM cannot confirm until every roll is in |
| Luck from Another Tablet | — | To define: Lira spends Bardic Inspiration on Ash's attack from her tablet |
| Reconnecting | — | To define: a tablet drops while a prompt waits and comes back to it; the DM leaves the Encounter page mid-action and returns to it |
| Fudged Rolls | — | To define: a fudged roll shows only on that player's tablet, and nobody can tell |
| What Players Can See | — | To define: tablets never get enemy vitals or DM-only notes; View as Player matches a tablet |
| Fatigue and Unconscious | — | To define: Winded, Tired, Exhausted; Unconscious sets the Combat Pool to 0; shown on the player's tablet |
| Free Actions Out of Turn | — | To define: a Free action on someone else's turn is allowed; anything else is refused |
| New Character and Unassigned Tablets | — | To define: a tablet waits unassigned, is assigned *New Character*, then switches to the finished Character |

`connect` is a smoke test for the harness itself.

## Running

- **Full run** — a real server on its own port and an empty data folder, the
  DM in headless Chromium at `127.0.0.1`, tablets on this machine's LAN
  address (so the server sees them as players):
  `bundle exec ruby test/scenarios/run.rb [name filter]`
- **Fast track** — the same scenarios in process through rack-test, each in its
  own process and data folder: `bundle exec ruby test/scenarios/run.rb --fast [name]`,
  and as part of `bundle exec rspec` (`spec/scenarios/`). DM click steps use their
  route version instead.

The full run never touches `data/`, and its server does not answer the
tablets' LAN discovery, so it can run next to a real session.

## Test-only switches

Read by the server at startup; none are set in normal play.

| Variable | Effect |
|---|---|
| `CRIMSON_DATA_DIR` | Folder for the state files instead of `data/` |
| `CRIMSON_PORT` | Port instead of 4567 |
| `CRIMSON_TEST_DICE=1` | Scripted dice (`lib/test_dice.rb`), adds the `/test/*` routes (dice, inventory, encounter state), turns off LAN discovery |

## Scripted dice

With `CRIMSON_TEST_DICE=1`, every die the server or the DM's browser rolls
comes from one queue, in the order rolled: whole numbers for dice, decimals in
[0, 1) for chance draws (Loot Table rows). A scenario queues faces
before the step that rolls them (`dm.dice(6, 6, 3)`); a die rolled with the
queue empty is random and counted as unscripted, which `check_dice_scripted`
fails on. Tablets roll on the device, so a tablet step sends its faces
directly (`tablet.roll(prompt, dice: [7, 2, 9])`).

Not yet scripted: an Affliction relief run, which previews and confirms with
one seed.

## Writing a scenario

```ruby
Scenarios.define 'simple combat' do
  step 'everyone connects' do
    party.each_value(&:hello)
  end

  step 'the DM starts combat', browser: true, fast: -> { dm.http.post_form('/encounter/start_combat') } do
    dm.browser.go_to('/encounter')
    # clicks…
  end
end
```

- `seed_data: 'name'` on `Scenarios.define` starts from `test/scenarios/data/name/`.
- `before_step 'title'` runs before that step on both tracks (e.g. queuing its dice);
  `helpers do … end` defines methods the steps share; `blocking: false` lets the
  steps after a failed check still run.
- `party` — the four tablets by first name (`party['Ash']`); `ids` — their
  Character ids.
- `dm.http` — DM routes (the fast track); `dm.browser` — the Ferrum page, for
  steps marked `browser: true`; `dm.inventory('creature:2003')` — an owner's Item Stacks.
- `check`, `expect_eq`, `check_ok`, `check_dice_scripted` — a failed check
  fails the step; the steps after it are not run.
