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
  // Inherent Penalty); the +2 Competency is held back. The attacker has no
  // Inherent of its own (Tier 0 reads as 0.5), so it takes a -1 Ascendancy.
  // Net = -2; TN = 8 + 2 = 10, clamped to the Maximum TN 9.
  assert.equal(params.supporting[0].tn, 9);
  // Defender keeps BOTH its own Bonuses, and its +1 Inherent against the
  // Tier-0 attacker gains a +1 Ascendancy (net +4 → TN 4).
  assert.equal(params.opposing[0].tn, 4);
});

test('without noPropagate the same Competency crosses and raises the attacker TN', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [['Competency', 2], ['Inherent', 1]] }],
  });
  // Everything crosses: Competency -2, Inherent -1, plus the derived -1
  // Ascendancy (Tier 0 vs Tier 1) → net -4; TN = 8 + 4 = 12, clamped to the
  // Maximum TN 9.
  assert.equal(params.supporting[0].tn, 9);
});
