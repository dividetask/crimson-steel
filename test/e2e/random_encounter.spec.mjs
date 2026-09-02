import { test, expect } from './support/fixtures.mjs';

// First test — Random Encounter.
//
// The DM opens the Sheets page, finds the Ogre gang table under General
// Orange Tier, rolls it a few times to see what it gives, and only then
// puts the result on the Combat Tracker.
//
// Start of test conditions: no Initiative rolled, no monsters added to
// Combat — which is how the default Campaign starts
// (test/e2e/campaign/default/encounter_data.json).
test.describe('Random Encounter', () => {
  const OGRE_GANG = 'general_ogre_gang';

  // The Ogre gang spawns 1× Ogre Brute and `1d3 + 1` Ogres, so the count
  // to expect is 2 to 4. Each roll below is seeded, so the sequence is the
  // same on every run: 2 Ogres, then 3, 4, 2, 3.
  const SEEDS = { 2: 2, 3: 1, 4: 3 };
  const ROLL_SEQUENCE = [2, 3, 4, 2, 3];

  const rollButton = (page) =>
    page.locator(`button.cs-random-encounter-roll-btn[data-table-id="${OGRE_GANG}"]`).last();

  // The Player Characters are reconciled onto the roster on their own, so
  // "no monsters in Combat" means no Ogres — not an empty Tracker.
  const monstersInCombat = async (dm) =>
    (await dm.combatantNames()).filter((name) => /^Ogre/.test(name));

  async function rollExpecting(page, dm, ogreCount) {
    await dm.armRolls({ encounter_seed: SEEDS[ogreCount] });
    await rollButton(page).click();
    const result = page.locator('.cs-roll-result');
    await expect(result).toBeVisible();
    await expect(result).toContainText('1× Ogre Brute');
    await expect(result).toContainText(`${ogreCount}× Ogre`);
    return result;
  }

  test('rolls the Ogre gang, and adds it to Combat only when the DM says so', async ({ page, dm }) => {
    // The roll currently spawns the Creatures and puts them straight on
    // the Combat Tracker in the same request — there is no preview, and
    // no "Add to combat" button on the result. This test describes the
    // behavior being built: the roll shows what it got, and a separate
    // press commits it. Drop this line when that lands.
    test.fail();

    // Start of test conditions.
    await page.goto('/encounter');
    expect(await monstersInCombat(dm)).toEqual([]);

    // Click on Sheets.
    await page.getByRole('link', { name: 'Sheets' }).click();
    await expect(page).toHaveURL(/character-sheets/);

    // Click on General Orange Tier.
    const orangeTier = page.locator('details.cs-roster-group[data-group-key="general_orange_tier"]');
    await orangeTier.locator('summary').click();
    await expect(orangeTier).toHaveAttribute('open', '');

    // Click on Ogre Gang.
    await orangeTier.locator(`a.cs-random-encounter-link[data-table-id="${OGRE_GANG}"]`).click();
    await expect(page).toHaveURL(new RegExp(`random_encounter_template=${OGRE_GANG}`));

    // Click on the Roll button inside the Ogre Gang div. Expect to see a
    // div indicating 1 Ogre Brute and 2-4 Ogres.
    const result = await rollExpecting(page, dm, ROLL_SEQUENCE[0]);

    // Expect to see a button to add the generated creatures to combat.
    const addToCombat = result.getByRole('button', { name: /add to combat/i });
    await expect(addToCombat).toBeVisible();

    // Expect to see no monsters added to combat: no Ogres on the Tracker,
    // and no Ogre spawned into the Campaign yet either.
    expect(await monstersInCombat(dm)).toEqual([]);
    expect(await dm.spawnedCreatures()).toEqual([]);

    // Click on Roll 4 times and expect the same shape each time. Each
    // re-roll replaces the previous result rather than stacking.
    for (const ogreCount of ROLL_SEQUENCE.slice(1)) {
      await rollExpecting(page, dm, ogreCount);
      await expect(result).toHaveCount(1);
      expect(await monstersInCombat(dm)).toEqual([]);
    }

    // Click on Add to combat.
    const finalOgres = ROLL_SEQUENCE[ROLL_SEQUENCE.length - 1];
    await addToCombat.click();

    // Expect 1 Ogre Brute and the rolled number of Ogres added to combat.
    const combatants = await dm.combatantNames();
    expect(combatants.filter((n) => n === 'Ogre Brute')).toHaveLength(1);
    expect(combatants.filter((n) => n === 'Ogre')).toHaveLength(finalOgres);

    // Only the committed roll spawned Creatures — the four discarded
    // previews left nothing behind.
    const spawned = await dm.spawnedCreatures();
    expect(spawned.filter((n) => n === 'Ogre')).toHaveLength(finalOgres);
    expect(spawned.filter((n) => n === 'Ogre Brute')).toHaveLength(1);
  });

  // The half of the flow that works today, kept separate so it does not
  // ride on the unbuilt preview/commit split.
  test('the roll result is seeded, so the same seed gives the same Ogres', async ({ page, dm }) => {
    await page.goto(`/character-sheets?random_encounter_template=${OGRE_GANG}`);

    await rollExpecting(page, dm, 2);
    await rollExpecting(page, dm, 4);
    await rollExpecting(page, dm, 2);
  });
});
