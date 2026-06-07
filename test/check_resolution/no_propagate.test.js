import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';

// A Roll's optional `noPropagate` field lists Bonus Types that stay on its own
// side and do NOT cross to the opponent (e.g. a Dodge's Competency helps the
// dodger's own Roll but must not penalize the attacker). Every other Bonus —
// including the Tier Inherent (which crosses as Ascendancy) — still propagates.

test('a noPropagate Bonus Type does not cross sides; others still do', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2], ['Inherent', 1]], noPropagate: ['Competency'] }],
  });
  // Attacker (supporting): only the defender's Inherent crosses (relabeled
  // Ascendancy, inverted to -1). The +2 Competency is held back.
  // Net = -1; TN = 6 - (-1) = 7.
  assert.equal(params.supporting[0].tn, 7);
  // Defender keeps BOTH its own Bonuses on its own Roll (net +3 → TN 3).
  assert.equal(params.opposing[0].tn, 3);
});

test('without noPropagate the same Competency crosses and raises the attacker TN', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2], ['Inherent', 1]] }],
  });
  // Both cross: Competency -2 and Ascendancy -1 → net -3; TN = 6 - (-3) = 9.
  assert.equal(params.supporting[0].tn, 9);
});
