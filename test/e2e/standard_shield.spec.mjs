import { test, expect } from './support/fixtures.mjs';

// Third test — Standard Shield.
//
// Thora conjures a shield over Ash on her turn. When the Ogre Brute
// slams Ash, Ash declares no defense of his own and Thora interposes the
// shield instead, spending her own Combat Pool dice as a reaction.
//
// The Ogres get onto the Tracker the way the first test puts them there.
// Every roll is predetermined: the encounter count by seed, the
// Initiative Strings by name, and the attack's dice by script — so the
// Net Degree of Success below is the same number every run.
test.describe('Standard Shield', () => {
  const OGRE_GANG = 'general_ogre_gang';
  const TWO_OGRES = 2; // the seed that makes the Ogre gang 1 Brute + 2 Ogres

  // Thora acts first, the Ogre Brute second. Initiative Strings sort
  // descending, so these read straight off the Tracker.
  //
  // Every Combatant is preselected, not just those two: anyone left to
  // roll freely can out-roll Thora and take the first turn, which would
  // make this test pass or fail by luck. The two Ogres share a name and
  // so share a String; the tie breaks by Combatant id.
  // All the same length: an Initiative String is compared character by
  // character, so a shorter string that shares a prefix sorts *above* a
  // longer one ("XXXX" beats "XXXXX"). Equal lengths keep the order
  // saying what it looks like it says.
  const INITIATIVE = {
    'Thora Stoneveil': 'XXXXXXXXX',
    'Ogre Brute': 'XXXXXXXX9',
    'Ash Windmere': '888888888',
    'Lira Duskmoor': '777777777',
    'Garroth Vask': '666666666',
    Ogre: '111111111',
  };

  // The Ogre Brute's Slam rolls 9 dice at TN 9; Thora's shield opposes
  // with 7 at TN 6. Queued in that order — the page rolls the Supporting
  // side first.
  const SLAM_DICE = [10, 9, 9, 8, 7, 6, 5, 4, 3];
  const SHIELD_DICE = [9, 8, 7, 6, 5, 4, 3];

  // Roll the Ogre gang onto the Tracker, set the Phase, fix Initiative,
  // and begin Combat on Thora's turn.
  async function openCombat(page, dm) {
    await dm.armRolls({ encounter_seed: TWO_OGRES });
    await page.goto(`/character-sheets?random_encounter_template=${OGRE_GANG}`);
    await page.locator(`button.cs-random-encounter-roll-btn[data-table-id="${OGRE_GANG}"]`).last().click();
    await expect(page.locator('.cs-roll-result')).toContainText('1× Ogre Brute');
    await expect(page.locator('.cs-roll-result')).toContainText('2× Ogre');

    await page.getByRole('link', { name: 'Encounter' }).click();
    await dm.setPartyPhase('combat');
  }

  const ashHitPoints = async (dm) =>
    (await dm.combatTracker()).find((row) => row.name === 'Ash Windmere').hp;

  test('interposes for an ally who declared no defense of their own', async ({ page, dm }) => {
    await openCombat(page, dm);

    // Expect to see Init empty for everyone.
    const beforeInit = await dm.combatTracker();
    expect(beforeInit.map((row) => row.initiative)).toEqual(beforeInit.map(() => '—'));

    // Expect to see the Ogres and the Ogre Brute in combat.
    const names = beforeInit.map((row) => row.name);
    expect(names.filter((n) => n === 'Ogre Brute')).toHaveLength(1);
    expect(names.filter((n) => n === 'Ogre')).toHaveLength(2);

    // Preselect the Initiative outcome, then roll it.
    await dm.armRolls({ initiative: INITIATIVE });
    await dm.rollInitiative();

    // Expect to see Init for each player including enemies.
    const rolled = await dm.combatTracker();
    expect(rolled.every((row) => row.initiative && row.initiative !== '—')).toBe(true);
    expect(rolled[0]).toMatchObject({ name: 'Thora Stoneveil', initiative: INITIATIVE['Thora Stoneveil'] });
    expect(rolled[1]).toMatchObject({ name: 'Ogre Brute', initiative: INITIATIVE['Ogre Brute'] });

    // On to Thora's turn. Roll Init is meant to begin it on its own;
    // until it does, this press is what starts the first turn — see
    // combat_start.spec.mjs.
    await dm.startCombat();
    expect(await dm.actingCombatant()).toBe('Thora Stoneveil');

    // --- Thora casts Standard Shield on Ash ----------------------------
    expect(await page.locator('.ta-resources').innerText()).toContain('30/30');

    const cast = await dm.openAction('cast');
    await cast.pick('Standard Shield');
    await cast.pick('Ash Windmere');
    await cast.commit('Confirm');

    // A Tier 1 Spell costs 4 Mana, and the cast spends the Main Action.
    // (The page reloads on a committed cast, so this reads the result off
    // the Turn Action panel rather than the response body.)
    const afterCast = await page.locator('.ta-resources').innerText();
    expect(afterCast).toContain('26/30');
    expect(afterCast).toMatch(/MAIN ACTIONS\s*1/i);
    expect(await dm.actingCombatant()).toBe('Thora Stoneveil');

    // --- The Ogre Brute's turn -----------------------------------------
    // End Turn twice: the first press opens the confirm screen, the
    // second confirms it (see dm.endTurn).
    await dm.endTurn();
    expect(await dm.actingCombatant()).toBe('Ogre Brute');

    // --- Slam on Ash, blocked by Thora's shield ------------------------
    const hpBefore = await ashHitPoints(dm);

    const attack = await dm.openAction('attack');
    await attack.pick('Ash Windmere');
    await attack.pick('Slam');
    await attack.pick('No defense');

    // The Ally Defense step offers Thora's shield over Ash.
    expect(await attack.options()).toContain('Standard Shield');
    await attack.pick('Standard Shield');

    // The attacker rolls; Ash does not (no defense); the shield opposes.
    const rolls = await attack.rolls();
    expect(rolls.find((r) => r.id === 'attacker')).toMatchObject({ side: 'supporting', dice: SLAM_DICE.length });
    expect(rolls.find((r) => r.id === 'defender').excluded).toBe(true);
    expect(rolls.find((r) => r.id === 'shield')).toMatchObject({ side: 'opposing', dice: SHIELD_DICE.length });

    await dm.scriptDice([...SLAM_DICE, ...SHIELD_DICE]);
    await attack.rollAll();
    await dm.assertDiceNotExhausted();
    expect(await dm.diceRemaining()).toBe(0);

    await attack.confirm();

    // The shield out-rolled the Slam: the attack nets below zero, so
    // there is no damage to apply.
    const preview = await attack.resultText();
    expect(preview).toContain('ALLY DEFENSE: Standard Shield (Thora Stoneveil) — 7 dice');
    expect(preview).toContain('Net Degree of Success -1');

    await attack.commit('Commit attack');

    // Ash is untouched: the shield is what stopped it.
    expect(await ashHitPoints(dm)).toEqual(hpBefore);
  });

  // The other half of the claim: the same Slam, the same dice, nobody
  // interposing. Without this, "Ash took no damage" above could be true
  // for any reason at all.
  test('without it, the same Slam lands on the same target', async ({ page, dm }) => {
    await openCombat(page, dm);
    await dm.armRolls({ initiative: INITIATIVE });
    await dm.beginCombat();

    await dm.endTurn(); // Thora casts nothing; the Ogre Brute acts
    expect(await dm.actingCombatant()).toBe('Ogre Brute');

    const hpBefore = await ashHitPoints(dm);

    const attack = await dm.openAction('attack');
    await attack.pick('Ash Windmere');
    await attack.pick('Slam');
    await attack.pick('No defense');

    // With no shield cast over Ash there is no Ally Defense step to
    // answer — the builder goes straight to the dice.
    await dm.scriptDice(SLAM_DICE);
    await attack.rollAll();
    await dm.assertDiceNotExhausted();
    expect(await dm.diceRemaining()).toBe(0);
    await attack.confirm();

    const preview = await attack.resultText();
    expect(preview).not.toContain('ALLY DEFENSE');
    // The same nine dice, unopposed: net 10 instead of the shielded -1.
    expect(preview).toContain('Net Degree of Success 10');
    expect(preview).toMatch(/Damage Bludgeoning/);

    await attack.commit('Commit attack');
    expect(await ashHitPoints(dm)).not.toEqual(hpBefore);
  });
});
