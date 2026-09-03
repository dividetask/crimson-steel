# Browser Tests

These tests click through the site in a real browser: they open Sheets,
expand a roster group, press Roll, set the Phase, press Roll Init, walk
the Cast pane, and press Commit attack. What they assert is what a DM
would see on screen.

They live in `test/e2e/`, and each one runs against its own server and
its own Campaign.

```
npm run test:e2e                                   # every test
npx playwright test test/e2e/standard_shield.spec.mjs
npx playwright test --headed                       # watch it happen
npx playwright show-trace test-results/<dir>/trace.zip
```

`npm test` stays what it was — the fast Dice and Check Resolution suites
under `test/dice_resolution` and `test/check_resolution`. Those and the
RSpec suite are unaffected by anything here.

## The Campaign a test runs against

Nothing a test does can touch the DM's own campaign. Each test:

1. copies `test/e2e/campaign/default/` into a throwaway directory,
2. layers on whatever that test declares,
3. boots the app against it, and
4. deletes it afterwards.

The server is started with two environment variables (`lib/data_paths.rb`):

| Variable | Effect |
|---|---|
| `CRIMSON_DATA_DIR` | the directory every domain reads and writes. Defaults to `data/`. |
| `CRIMSON_ISOLATED_DATA` | the shipped `.example` files under `docs/common/**` do **not** stand behind it. The app sees only what the data directory declares. |

Without the second one, `Creatures::Dataset` would union the test's
roster with the shipped example rosters and the example party would walk
into every test. With it, a Campaign is exactly its own files.

Neither variable is set in a normal run, and nothing about a normal run
changes.

### The default Campaign

`test/e2e/campaign/default/` is a copy of the shipped example data — the
same Characters, enemies, templates and inventories — with the session
state blanked: no Combatants, no damage, a clean clock. It is checked in,
so it can be edited without touching the examples, and a test that only
wants "the usual campaign" declares nothing.

Ash Windmere, Thora Stoneveil, the Ogre (401) and the Ogre Brute (402)
all come from there. The Random Encounter Tables do not: they live in
`docs/common/creatures/random_encounter_tables.yaml` as rule data and
name their Creatures by id, so a Campaign can only roll a table whose ids
it carries. The default Campaign carries them all.

### Per-test data

```js
test.use({
  campaign: {
    'creatures_data_pcs.yaml': 'test/e2e/campaign/lone_cleric.yaml', // replace
    'creatures_data_npcs.yaml': null,                                // remove
    'chronicle_data.json': '{"campaign_name":"Winter"}',             // inline
  },
});
```

A value is a repo-relative path to copy in, a string of file content, or
`null` to drop the default file. Files are keyed by the name the app
loads them under, so `creatures_data_pcs.yaml` replaces the party and
leaves everything else alone.

## Predetermined rolls

Nothing in a test is left to chance. There are two sources of randomness
and each has its own control.

### Rolls the server makes

Initiative, and the `1d3 + 1` inside a Random Encounter Table. Arm them
before the click that triggers them:

```js
await dm.armRolls({
  initiative: { 'Thora Stoneveil': 'XXXXXXXXX', 'Ogre Brute': 'XXXXXXXX9' },
  encounter_seed: 2,
});
```

`initiative` hands out Initiative Strings by Creature name instead of
rolling them. `encounter_seed` seeds the table roll, so the Ogre gang
gives the same count every run (seed 2 → two Ogres, 1 → three, 3 → four).

This reaches the server through `POST /__test__/rolls`, a route that only
exists when `CRIMSON_TEST_MODE` is set (`lib/routes/test_control.rb`); in
a real run the file defines no routes at all.

Preselect *everyone*, not just the two Combatants you care about: one
left to roll freely can out-roll the one you meant to go first, and the
test then passes or fails by luck. Watch the String lengths too — see
"Two things that look like bugs and are not" below.

### Rolls the browser makes

Casting checks, attacks, Roll All. Queue the exact dice, in the order the
page asks for them — Supporting side first, then Opposing:

```js
await dm.scriptDice([...SLAM_DICE, ...SHIELD_DICE]);
await attack.rollAll();
await dm.assertDiceNotExhausted();
expect(await dm.diceRemaining()).toBe(0);
```

`RandomRng` (`public/js/randomRng.js`) reads `window.__scriptedDice` when
a test arms it. Production never sets it. Overriding `Math.random` from
the test instead would not work: the Atlas uses it for SVG ids and would
eat the dice.

Always follow a roll with `assertDiceNotExhausted()`. If the page asked
for more dice than were queued, the extra ones were random and the test
is no longer deterministic — the assertion says so instead of letting it
pass quietly. `diceRemaining()` catches the opposite mistake, a queue
longer than the roll.

## Driving the page

`test/e2e/support/fixtures.mjs` provides `page` (Playwright's, with the
server's base URL) and `dm`, which is the DM's browser:

| Call | What it does |
|---|---|
| `dm.setPartyPhase('combat')` | the Phase everyone sees, from the menu bar |
| `dm.rollInitiative()`, `dm.startCombat()` | the Combat Tracker's controls |
| `dm.beginCombat()` | get to the first turn, whatever that currently takes |
| `dm.endTurn()` | both End Turn presses — open the confirm screen, then confirm |
| `dm.actingCombatant()` | whose turn it is, from the Turn Action panel |
| `dm.openAction('cast' \| 'attack' \| 'item' \| 'move')` | opens the action and returns its Action Builder pane |
| `dm.combatTracker()` | every Tracker row: name, Initiative, HP |
| `dm.spawnedCreatures()` | Creatures spawned into the Campaign, from the roster sidebar |
| `dm.armRolls()`, `dm.scriptDice()` | above |

An Action Builder pane is driven the way the DM drives it — pick options
by their label, in order:

```js
const cast = await dm.openAction('cast');
await cast.pick('Standard Shield');
await cast.pick('Ash Windmere');
await cast.commit('Confirm');
```

`pick` only ever looks at the step the builder is waiting on, which is
what keeps a label like "No defense" unambiguous when both the target's
own defense step and the Ally Defense step offer one. It searches the
step's header quick-picks as well as its full option list, so `pick('Slam')`
takes the default dice and `pick('Slam (speed 0)')` opens the dice list.

`rolls()` returns what each Roll is about to be — `{ id, side, dice, tn,
excluded }` — so a test can assert the shape of a Check before rolling it.
`confirm()` previews, `commit(label)` applies. Both wait for the
resolution the press triggers rather than for a load state: a cast with
no Roll previews and applies in one press and then reloads the page, and
waiting on the load races the reload.

### Reading results

Prefer what the page shows over what the server returned. A committed
cast reloads the page, which can abort the read of its own JSON response,
so assert on the Turn Action panel's resources, the Tracker's HP column,
or the result screen's text:

```js
expect(await page.locator('.ta-resources').innerText()).toContain('26/30');
expect(preview).toContain('Net Degree of Success -1');
expect(await ashHitPoints(dm)).toEqual(hpBefore);
```

Read the Tracker through `dm.combatTracker()` rather than the page under
test. It only renders in the Combat Phase, so a peek from Downtime would
read an empty table whether or not anyone is on the roster — a check that
always passes. `combatTracker()` opens a separate browser context and
sets *that* session's private DM Phase override to Combat, which changes
nothing for the page the test is driving.

## Testing behavior that does not exist yet

Write the test as though the behavior were there and mark it `test.fail()`:

```js
test('rolls the Ogre gang, and adds it to Combat only when the DM says so', async ({ page, dm }) => {
  test.fail(); // no preview/commit split yet — drop this line when it lands
  ...
});
```

Playwright runs it, expects it to fail, and reports the suite green. The
day the feature lands the test passes, Playwright reports "expected to
fail but passed", and the annotation comes off. Keep the reason on the
line: what is missing, not what the fix should be.

Where a flow half-works, split it — one test marked `test.fail()` for the
part being built, one plain test for the part that works today, so the
working half keeps its coverage in the meantime.

Make it fail *fast*. A test that runs out the 60-second timeout counts as
a hard failure even under `test.fail()`, and costs a minute every run. If
the missing behavior means an element never appears, assert on it with a
short timeout rather than letting an unbounded read hang:

```js
await expect(page.locator('h3.ta-title')).toBeVisible({ timeout: 3_000 });
```

## What writing the first tests turned up

Two places where the app does not do what it should. Both are held by a
test marked `test.fail()`, so they go green when they are fixed.

**Roll Init does not begin the first turn.** It rolls the Initiative
Strings and stops; the Turn Action panel stays empty until Start Combat
is pressed. `combat_start.spec.mjs` holds the expectation on its own.
Every other test gets to the first turn through `dm.beginCombat()`, which
presses Start Combat as well — one line to delete when Roll Init does it.

**The encounter roll has no preview.**
`/random_encounters/roll/:table_id` spawns the Creatures, equips them
from their loadout, and adds every one to the Encounter roster in the
same request. There is no "Add to combat" button, and five presses of
Roll leave five encounters' worth of Ogres in the Campaign.
`random_encounter.spec.mjs` describes the split being built.

## Two things that look like bugs and are not

**End Turn takes two presses.** The first opens the End Turn confirm
screen, the second confirms it. `dm.endTurn()` makes both.

**A shorter Initiative String beats a longer one that starts the same
way.** `XXXX` sorts above `XXXXX`, because the comparison is character by
character. Give every Combatant a String of the same length and the
Tracker order reads the way it looks.
