import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';
import { SequenceRng } from '../../public/js/rng.js';

// Spread (area effect): one caster Supporting Roll opposed by N independent
// Opposing Rolls (each caught creature's Save), resolved per-creature.
// check_resolution_design.md → Spread Check.

test('prepareSpread inverts caster bonuses onto each Opposer, never the reverse', () => {
  const out = CheckResolution.prepareSpread({
    supporting: [{ bonusPenaltyList: [['Competency', 2]] }],
    opposing: [{ bonusPenaltyList: [] }, { bonusPenaltyList: [['Morale', 1]] }],
  });
  // The caster keeps its own bonuses; the Opposers never pool onto it.
  assert.deepEqual(out.supporting[0].bonusPenaltyList, [['Competency', 2]]);
  assert.deepEqual(out.opposing[0].bonusPenaltyList, [['Competency', -2]]);
  assert.deepEqual(out.opposing[1].bonusPenaltyList, [['Morale', 1], ['Competency', -2]]);
});

test('prepareSpread adds each Opposer its Ascendancy versus the caster', () => {
  const out = CheckResolution.prepareSpread({
    supporting: [{ tier: 3, bonusPenaltyList: [] }],
    opposing: [{ tier: 1, bonusPenaltyList: [] }],
  });
  assert.deepEqual(out.opposing[0].bonusPenaltyList, [['Ascendancy', -4]]);
});

test('resolveCheck spread nets the caster against each Opposer independently', () => {
  // caster 2 dice [7,7] -> +2; opposer1 1 die [7] -> +1; opposer2 1 die [1] -> -1.
  const rng = new SequenceRng([7, 7, 7, 1]);
  const res = CheckResolution.resolveCheck({
    spread: true,
    supporting: [{ diceCount: 2, bonusPenaltyList: [] }],
    opposing: [{ diceCount: 1, bonusPenaltyList: [] }, { diceCount: 1, bonusPenaltyList: [] }],
  }, rng);
  assert.equal(res.spread, true);
  assert.equal(res.opposingResults[0].degreeOfSuccess, 1); // supportTotal 2 - 1
  assert.equal(res.opposingResults[1].degreeOfSuccess, 3); // supportTotal 2 - (-1)
  // No single Check-level Degree of Success in a Spread.
  assert.equal(res.degreeOfSuccess, undefined);
});
