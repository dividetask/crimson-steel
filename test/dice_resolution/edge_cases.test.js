import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Roll } from '../../public/js/roll.js';
import { TnComputation } from '../../public/js/tnComputation.js';
import { Nudge } from '../../public/js/nudge.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/dice_resolution/dice_resolution_tests.md — "Edge cases"

test('Empty bonus_penalty_list', () => {
  const { tn, startingValue } = TnComputation.compute({ bonusPenaltyList: [], startingContribution: 0 });
  assert.equal(tn, 6); // Base Target Number
  assert.equal(startingValue, 0);
});

test('Reroll count exceeds eligible dice', () => {
  const rng = new SequenceRng([6, 6, 6, 6, 6, 6]); // all Successes at TN 6, no reroll values needed
  const r = Roll.resolveWithTn({ diceCount: 6, positiveReroll: { count: 5, max: false } }, rng);
  assert.deepEqual(r.rerollChanges, [null, null, null, null, null, null]);
});

test('Nudge at boundary', () => {
  const rng = new SequenceRng([10]);
  const r = Roll.resolveWithTn({ diceCount: 1, valueAdjustment: { value: 1, max: false } }, rng);
  // 10 + 1 clamps to 10, but the targeted die still records its value.
  assert.deepEqual(r.nudgeChanges, [10]);
});

test('Standalone nudge with no eligible improvement', () => {
  // One die is targeted (lowest index on a full tie) and records its
  // clamped value; the untargeted dice stay null.
  const changes = Nudge.applyWithoutTn([10, 10, 10], { value: 1, max: false });
  assert.deepEqual(changes, [10, null, null]);
});
