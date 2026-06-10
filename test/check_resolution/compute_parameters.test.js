import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';

// docs/common/check_resolution/check_resolution_tests.md
// "Compute Check parameters"

test('A solo Check has no propagation', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 2]] }],
    opposing: [],
  });
  assert.equal(params.supporting[0].tn, 6);
  assert.equal(params.supporting[0].startingValue, 0);
});

test('Initiating receives inversions from every Opposing Roll', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 1]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }, { bonusPenaltyList: [['B', 1]] }],
  });
  // Effective [('A',+1),('B',-2),('B',-1)]; per-Type B keeps -2.
  // Net = +1 - 2 = -1; TN = 8 - (-1) = 9.
  assert.equal(params.supporting[0].tn, 9);
});

test('Defending receives inversions from every Supporting Roll', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 3]] }, { bonusPenaltyList: [['A', 1]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }],
  });
  // Effective [('B',+2),('A',-3),('A',-1)]; per-Type A keeps -3.
  // Net = +2 - 3 = -1; TN = 9.
  assert.equal(params.opposing[0].tn, 9);
});

test('Equal opposing bonuses cancel: +2 attacker vs +2 defender both land at TN 8', () => {
  // The combat scenario: each side has a +2 Competency. Propagation inverts
  // the opponent's +2 onto each roll, so each nets to 0 and stays at Base TN 8.
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['Competency', 2]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2]] }],
  });
  assert.equal(params.supporting[0].tn, 8);
  assert.equal(params.opposing[0].tn, 8);
});

test('previewParameters returns the propagated bonusPenaltyList for display', () => {
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Competency', 2]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2]] }],
  });
  // Attacker roll: own +2, plus the inverted defender +2 => -2.
  assert.deepEqual(params.supporting[0].bonusPenaltyList, [['Competency', 2], ['Competency', -2]]);
  assert.equal(params.supporting[0].tn, 8);
});

test('Non-lead Supporting Rolls receive only the Defender inversion', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 5]] }, { bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }],
  });
  // Second Supporting effective [('B',-2)]; Net = -2; TN = 8 - (-2) = 10,
  // clamped to the Maximum TN 9 (the overflow becomes a Starting Failure).
  assert.equal(params.supporting[1].tn, 9);
});

test('Non-lead Opposing Rolls receive only the Initiator inversion', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 3]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }, { bonusPenaltyList: [] }],
  });
  // Non-lead Opposing effective [('A',-3)]; Net = -3; TN = 8 - (-3) = 11,
  // clamped to the Maximum TN 9.
  assert.equal(params.opposing[1].tn, 9);
});

test("A creature's Inherent becomes the opponent's Ascendancy when it crosses sides", () => {
  // Tier-1 attacker (Inherent +1) vs Tier-2 defender (Inherent +2).
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 1]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 2]] }],
  });
  // Attacker keeps its own Inherent; the defender's Inherent crosses as an
  // Ascendancy Penalty. Net +1 - 2 = -1 → TN 8 - (-1) = 9 (fighting up is harder).
  assert.deepEqual(params.supporting[0].bonusPenaltyList, [['Inherent', 1], ['Ascendancy', -2]]);
  assert.equal(params.supporting[0].tn, 9);
  // The defender sees the attacker's Inherent as its own Ascendancy (a Bonus,
  // since it out-ranks): +2 Inherent, -1 Ascendancy → net +1 → TN 7.
  assert.deepEqual(params.opposing[0].bonusPenaltyList, [['Inherent', 2], ['Ascendancy', -1]]);
  assert.equal(params.opposing[0].tn, 7);
});

test('Equal-Tier opponents exchange no Ascendancy at all', () => {
  // Both Rolls carry tier 2: the Inherent does not cross — each side keeps
  // only its own +2 Inherent, and no Ascendancy entry appears anywhere.
  const params = CheckResolution.previewParameters({
    supporting: [{ tier: 2, bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ tier: 2, bonusPenaltyList: [['Inherent', 2]] }],
  });
  assert.deepEqual(params.supporting[0].bonusPenaltyList, [['Inherent', 2]]);
  assert.deepEqual(params.opposing[0].bonusPenaltyList, [['Inherent', 2]]);
  // Each TN improves by its own Inherent only: TN 8 - 2 = 6, symmetric.
  assert.equal(params.supporting[0].tn, 6);
  assert.equal(params.opposing[0].tn, 6);
});

test('Tier-less Rolls keep the structural crossing (Inherent → Ascendancy)', () => {
  // Without tiers the equal-Tier carve-out cannot apply; the Inherent still
  // crosses, relabeled — the pre-Tier behavior for non-combat checks.
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 2]] }],
  });
  // +2 Inherent and -2 Ascendancy (different Types, both apply) net to 0 → TN 8.
  assert.equal(params.supporting[0].tn, 8);
});

test('An explicit Ascendancy entry never crosses sides', () => {
  // A no-defense attack carries its Ascendancy directly (the server supplies
  // it when the defender does not roll). It must not invert onto another
  // Opposing Roll (e.g. a shielding ally) as a phantom bonus.
  const params = CheckResolution.previewParameters({
    supporting: [{ tier: 1, bonusPenaltyList: [['Inherent', 1], ['Ascendancy', -2]] }],
    opposing: [{ tier: 2, bonusPenaltyList: [['Inherent', 2]] }],
  });
  const shieldTypes = params.opposing[0].bonusPenaltyList.map((e) => e[0]);
  assert.ok(shieldTypes.includes('Inherent'));
  // The opposing Roll's Ascendancy entries come only from its own Tier
  // Mismatch (+2, it out-Tiers the attacker) and the crossed attacker
  // Inherent (−1) — the attacker's explicit −2 never inverts into a +2.
  const ascValues = params.opposing[0].bonusPenaltyList.filter((e) => e[0] === 'Ascendancy').map((e) => e[1]);
  assert.deepEqual(ascValues.sort((a, b) => a - b), [-1, 2]);
});
