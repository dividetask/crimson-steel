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

test('A crossed Inherent keeps its name and drives the Ascendancy', () => {
  // Tier-1 attacker (Inherent +1) vs Tier-2 defender (Inherent +2).
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 1]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 2]] }],
  });
  // Attacker: own +1 Inherent, the defender's crossed as a -2 Inherent
  // Penalty, and the one-point deficit amplified into a -2 Ascendancy.
  // Net +1 - 2 - 2 = -3 → TN 8 + 3 = 11 clamps to the Maximum TN 9
  // (fighting up is harder; the overflow becomes Starting Failures).
  assert.deepEqual(params.supporting[0].bonusPenaltyList,
    [['Inherent', 1], ['Inherent', -2], ['Ascendancy', -2]]);
  assert.equal(params.supporting[0].tn, 9);
  assert.equal(params.supporting[0].startingValue, -2);
  // The defender mirrors it: +2 - 1 + 2 = +3 → TN 5.
  assert.deepEqual(params.opposing[0].bonusPenaltyList,
    [['Inherent', 2], ['Inherent', -1], ['Ascendancy', 2]]);
  assert.equal(params.opposing[0].tn, 5);
});

test('Equal Inherents cancel and produce no Ascendancy', () => {
  // Both sides carry Inherent +2: each crosses onto the other, the Bonus
  // and Penalty balance, and no Ascendancy entry appears anywhere.
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 2]] }],
  });
  assert.deepEqual(params.supporting[0].bonusPenaltyList, [['Inherent', 2], ['Inherent', -2]]);
  assert.deepEqual(params.opposing[0].bonusPenaltyList, [['Inherent', 2], ['Inherent', -2]]);
  // The +2 and -2 net to zero on each side: Base TN 8, symmetric.
  assert.equal(params.supporting[0].tn, 8);
  assert.equal(params.opposing[0].tn, 8);
});

test('An explicit Ascendancy entry never crosses sides', () => {
  // Ascendancy is derived per Roll, never exchanged: a pre-existing entry
  // (e.g. from re-preparing an already-prepared Check) must not invert onto
  // the other side as a phantom bonus.
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Ascendancy', 4]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 1]] }],
  });
  assert.deepEqual(params.opposing[0].bonusPenaltyList, [['Competency', 1]]);
});
