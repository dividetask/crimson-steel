import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';
import { TierMismatch } from '../../public/js/tierMismatch.js';
import { SequenceRng } from '../../public/js/rng.js';

// Spread (area effect): one caster Supporting Roll opposed by N independent
// Opposing Rolls (each caught creature's Save), resolved per-creature.
// check_resolution_design.md → Spread Check.

test('the initiating Roll takes Ascendancy against every Opposer', () => {
  const out = TierMismatch.apply({
    supporting: [{ tier: 3, bonusPenaltyList: [] }],
    opposing: [{ tier: 1, bonusPenaltyList: [] }, { tier: 3, bonusPenaltyList: [] }],
  });
  // Caster (Tier 3): +4 vs the Tier-1 Opposer, nothing vs the Tier-3 one.
  assert.deepEqual(out.supporting[0].bonusPenaltyList, [['Ascendancy', 4]]);
  // Each Opposer vs the caster: the Tier-1 gets -4, the Tier-3 gets nothing.
  assert.deepEqual(out.opposing[0].bonusPenaltyList, [['Ascendancy', -4]]);
  assert.deepEqual(out.opposing[1].bonusPenaltyList, []);
});

test('prepare propagates bonuses both ways for an area cast', () => {
  // The caster's Inherent reaches the Opposer — relabeled Ascendancy as it
  // crosses; the Opposer's Competency reaches the caster (bidirectional); and
  // each also gets its Tier Mismatch Ascendancy versus the other.
  const prepared = CheckResolution.prepare({
    spread: true,
    supporting: [{ tier: 2, bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ tier: 1, bonusPenaltyList: [['Competency', 3]] }],
  });
  assert.deepEqual(prepared.supporting[0].bonusPenaltyList,
    [['Inherent', 2], ['Competency', -3], ['Ascendancy', 2]]);
  // The crossed Inherent arrives as Ascendancy (-2), and the Tier Mismatch
  // Ascendancy (-2) is added on top.
  assert.deepEqual(prepared.opposing[0].bonusPenaltyList,
    [['Competency', 3], ['Ascendancy', -2], ['Ascendancy', -2]]);
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
  assert.equal(res.degreeOfSuccess, undefined);
});
