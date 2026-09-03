import { test, expect } from './support/fixtures.mjs';

// Starting Combat.
//
// Roll Init should put the Tracker on the first Combatant's turn. Today
// it only rolls the Initiative Strings; the Turn Action panel stays empty
// until Start Combat is pressed.
//
// This lives on its own so the tests that need Combat running can go
// through dm.beginCombat() and keep their coverage in the meantime. When
// this passes, drop the test.fail() here and the startCombat() call from
// beginCombat().
test.describe('Starting Combat', () => {
  const OGRE_GANG = 'general_ogre_gang';

  const INITIATIVE = {
    'Thora Stoneveil': 'XXXXXXXXX',
    'Ogre Brute': 'XXXXXXXX9',
    'Ash Windmere': '888888888',
    'Lira Duskmoor': '777777777',
    'Garroth Vask': '666666666',
    Ogre: '111111111',
  };

  test('Roll Init begins the first Combatant\'s turn', async ({ page, dm }) => {
    test.fail();

    await dm.armRolls({ encounter_seed: 2 });
    await page.goto(`/character-sheets?random_encounter_template=${OGRE_GANG}`);
    await page.locator(`button.cs-random-encounter-roll-btn[data-table-id="${OGRE_GANG}"]`).last().click();
    await expect(page.locator('.cs-roll-result')).toContainText('1× Ogre Brute');

    await page.getByRole('link', { name: 'Encounter' }).click();
    await dm.setPartyPhase('combat');

    await dm.armRolls({ initiative: INITIATIVE });
    await dm.rollInitiative();

    // Everyone has an Initiative String...
    const rolled = await dm.combatTracker();
    expect(rolled.every((row) => row.initiative && row.initiative !== '—')).toBe(true);
    expect(rolled[0].name).toBe('Thora Stoneveil');

    // ...and the Tracker is on the first of them, with no further press.
    // Bounded, so this fails in seconds rather than hanging out the test
    // timeout — a timed-out test counts as a hard failure even under
    // test.fail().
    await expect(page.locator('h3.ta-title')).toBeVisible({ timeout: 3_000 });
    expect(await dm.actingCombatant()).toBe('Thora Stoneveil');
  });
});
