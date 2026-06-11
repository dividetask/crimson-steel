import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';
import { SequenceRng } from '../../public/js/sequenceRng.js';

// Spread (area effect): one caster Supporting Roll opposed by N independent
// Opposing Rolls (each caught creature's Save), resolved per-creature.
// check_resolution_design.md → Spread Check.

test('each caught creature measures its Inherent against the caster', () => {
  const prepared = CheckResolution.previewParameters({
    spread: true,
    supporting: [{ bonusPenaltyList: [['Inherent', 3]] }],
    opposing: [
      { bonusPenaltyList: [['Inherent', 1]] },
      { bonusPenaltyList: [['Inherent', 3]] },
    ],
  });
  // The caster receives every Opposer's Inherent; the strongest (-3) matches
  // its own +3, so the caster gets no Ascendancy.
  assert.deepEqual(prepared.supporting[0].bonusPenaltyList,
    [['Inherent', 3], ['Inherent', -1], ['Inherent', -3]]);
  // The weaker Opposer is two points behind the caster: -4 Ascendancy.
  assert.deepEqual(prepared.opposing[0].bonusPenaltyList,
    [['Inherent', 1], ['Inherent', -3], ['Ascendancy', -4]]);
  // The equal Opposer balances: no Ascendancy.
  assert.deepEqual(prepared.opposing[1].bonusPenaltyList,
    [['Inherent', 3], ['Inherent', -3]]);
});

test('prepare propagates bonuses both ways for an area cast', () => {
  // Bidirectional: the caster's Inherent reaches the Opposer (keeping its
  // name), the Opposer's Competency and Inherent reach the caster, and each
  // Roll then derives its Ascendancy from its own Inherent imbalance.
  const prepared = CheckResolution.previewParameters({
    spread: true,
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ bonusPenaltyList: [['Competency', 3], ['Inherent', 1]] }],
  });
  assert.deepEqual(prepared.supporting[0].bonusPenaltyList,
    [['Inherent', 2], ['Competency', -3], ['Inherent', -1], ['Ascendancy', 2]]);
  assert.deepEqual(prepared.opposing[0].bonusPenaltyList,
    [['Competency', 3], ['Inherent', 1], ['Inherent', -2], ['Ascendancy', -2]]);
});

test('resolveCheck spread nets the caster against each Opposer independently', () => {
  // caster 2 dice [8,8] -> +2; opposer1 1 die [8] -> +1; opposer2 1 die [1] -> -1.
  const rng = new SequenceRng([8, 8, 8, 1]);
  const res = CheckResolution.resolveCheck({
    spread: true,
    supporting: [{ diceCount: 2, bonusPenaltyList: [] }],
    opposing: [{ diceCount: 1, bonusPenaltyList: [] }, { diceCount: 1, bonusPenaltyList: [] }],
  }, rng);
  assert.equal(res.spread, true);
  assert.equal(res.opposingResults[0].degreeOfSuccess, 1); // supportTotal 2 - 1
  assert.equal(res.opposingResults[1].degreeOfSuccess, 3); // supportTotal 2 - (-1)
  assert.equal(res.degreeOfSuccess, undefined);
});
