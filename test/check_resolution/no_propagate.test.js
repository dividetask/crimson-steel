import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';

// A Roll's optional `noPropagate` field lists Bonus Types that stay on its own
// side and do NOT cross to the opponent (e.g. a Dodge's Competency helps the
// dodger's own Roll but must not penalize the attacker). Every other Bonus —
// including the Tier Inherent — still propagates.

test('a noPropagate Bonus Type does not cross sides; others still do', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2], ['Inherent', 1]], noPropagate: ['Competency'] }],
  });
  // Attacker (supporting): only the defender's Inherent crosses (as a -1
  // Inherent Penalty); the +2 Competency is held back. The unanswered
  // deficit adds a -2 Ascendancy. Net = -3; TN = 8 + 3 = 11, clamped to the
  // Maximum TN 9.
  assert.equal(params.supporting[0].tn, 9);
  // Defender keeps BOTH its own Bonuses, and its unanswered +1 Inherent
  // gains a +2 Ascendancy (net +5 → TN 3, the Minimum).
  assert.equal(params.opposing[0].tn, 3);
});

test('without noPropagate the same Competency crosses and raises the attacker TN', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2], ['Inherent', 1]] }],
  });
  // Everything crosses: Competency -2, Inherent -1, plus the derived -2
  // Ascendancy → net -5; TN = 8 + 5 = 13, clamped to the Maximum TN 9.
  assert.equal(params.supporting[0].tn, 9);
});
