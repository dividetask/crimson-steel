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
  assert.equal(params.supporting[0].tn, 4);
  assert.equal(params.supporting[0].startingValue, 0);
});

test('Initiating receives inversions from every Opposing Roll', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 1]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }, { bonusPenaltyList: [['B', 1]] }],
  });
  // Effective [('A',+1),('B',-2),('B',-1)]; per-Type B keeps -2.
  // Net = +1 - 2 = -1; TN = 6 - (-1) = 7.
  assert.equal(params.supporting[0].tn, 7);
});

test('Defending receives inversions from every Supporting Roll', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 3]] }, { bonusPenaltyList: [['A', 1]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }],
  });
  // Effective [('B',+2),('A',-3),('A',-1)]; per-Type A keeps -3.
  // Net = +2 - 3 = -1; TN = 7.
  assert.equal(params.opposing[0].tn, 7);
});

test('Equal opposing bonuses cancel: +2 attacker vs +2 defender both land at TN 6', () => {
  // The combat scenario: each side has a +2 Competency. Propagation inverts
  // the opponent's +2 onto each roll, so each nets to 0 and stays at Base TN 6.
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['Competency', 2]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2]] }],
  });
  assert.equal(params.supporting[0].tn, 6);
  assert.equal(params.opposing[0].tn, 6);
});

test('previewParameters returns the propagated bonusPenaltyList for display', () => {
  const params = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Competency', 2]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2]] }],
  });
  // Attacker roll: own +2, plus the inverted defender +2 => -2.
  assert.deepEqual(params.supporting[0].bonusPenaltyList, [['Competency', 2], ['Competency', -2]]);
  assert.equal(params.supporting[0].tn, 6);
});

test('Non-lead Supporting Rolls receive only the Defender inversion', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 5]] }, { bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }],
  });
  // Second Supporting effective [('B',-2)]; Net = -2; TN = 6 - (-2) = 8.
  assert.equal(params.supporting[1].tn, 8);
});

test('Non-lead Opposing Rolls receive only the Initiator inversion', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['A', 3]] }],
    opposing: [{ bonusPenaltyList: [['B', 2]] }, { bonusPenaltyList: [] }],
  });
  // Non-lead Opposing effective [('A',-3)]; Net = -3; TN = 6 - (-3) = 9.
  assert.equal(params.opposing[1].tn, 9);
});
