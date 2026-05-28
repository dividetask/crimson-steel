import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Roll } from '../../public/js/roll.js';
import { TnComputation } from '../../public/js/tnComputation.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/dice_resolution/dice_resolution_tests.md
// "Resolve a Roll with a Target Number"

test('A Roll with no modifiers and middling dice', () => {
  const rng = new SequenceRng([6, 6, 5, 1, 3, 7]);
  const r = Roll.resolveWithTn({ diceCount: 6 }, rng);
  assert.equal(r.tn, 6);
  assert.equal(r.startingValue, 0);
  assert.equal(r.dois, 2);
  assert.equal(r.criticalCount, 0);
  assert.equal(r.outcome, 'success');
});

// TN computation — exercised directly (no dice needed).

test('Bonus and Penalty stacking', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', 3], ['A', 1], ['A', -2], ['B', 2]],
  });
  assert.equal(tn, 3);
  assert.equal(startingValue, 0);
});

test('Bonus overflow into Starting Successes', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', 5]],
    startingContribution: 1,
  });
  assert.equal(tn, 3);
  assert.equal(startingValue, 3);
});

test('Penalty overflow into Starting Failures', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', -5]],
    startingContribution: 0,
  });
  assert.equal(tn, 9);
  assert.equal(startingValue, -2);
});

test('Bonus and Penalty cancel out', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', 20], ['B', -20]],
  });
  assert.equal(tn, 6);
  assert.equal(startingValue, 0);
});

test('A Critical Success replaces the regular Success', () => {
  const rng = new SequenceRng([10]);
  const r = Roll.resolveWithTn({ diceCount: 1, criticalModifier: 2 }, rng);
  // The single crit contributes +2 (not +3). DoIS = 0 + 2.
  assert.equal(r.dois, 2);
  assert.equal(r.criticalCount, 1);
});

// NOTE: the test doc says "dice that produce DoIS = -5" with
// failure_modifier = 0. With failure_modifier = 0 a 1 contributes 0, so
// dice alone cannot produce a negative DoIS — the negative value must come
// from Starting Value. We model that here. The rule under test (a Roll
// that ignores Failures cannot Fumble) holds regardless of the source.
test('A Roll that ignores Failures cannot Fumble', () => {
  const rng = new SequenceRng([3, 3, 3]); // neutral dice, contribute 0
  const r = Roll.resolveWithTn({ diceCount: 3, failureModifier: 0, startingContribution: -5 }, rng);
  assert.equal(r.dois, -5);
  assert.equal(r.outcome, 'failure'); // not 'fumble'
});

test('A reroll changes a Failure into a Success', () => {
  const rng = new SequenceRng([1, 4, 5, 5, 5, 5, 8]); // initial + 1 reroll value
  const r = Roll.resolveWithTn({ diceCount: 6, positiveReroll: { count: 1, max: false } }, rng);
  assert.deepEqual(r.finalDice, [8, 4, 5, 5, 5, 5]);
  assert.deepEqual(r.rerollChanges, [8, null, null, null, null, null]);
});

test('A nudge promotes a near-Success', () => {
  const rng = new SequenceRng([5, 5, 5, 5, 5, 1]);
  const r = Roll.resolveWithTn(
    { diceCount: 6, failureModifier: 0, valueAdjustment: { value: 1, max: false } },
    rng
  );
  assert.deepEqual(r.nudgeChanges, [6, null, null, null, null, null]);
});

test('Tied delta with a Failure prefers the lower-starting die', () => {
  const rng = new SequenceRng([5, 5, 5, 5, 5, 1]);
  const r = Roll.resolveWithTn(
    { diceCount: 6, failureModifier: -1, valueAdjustment: { value: 1, max: false } },
    rng
  );
  assert.deepEqual(r.nudgeChanges, [null, null, null, null, null, 2]);
});

test('Max-mode nudge shifts every die', () => {
  const rng = new SequenceRng([3, 5, 9, 10]);
  const r = Roll.resolveWithTn({ diceCount: 4, valueAdjustment: { value: 1, max: true } }, rng);
  assert.deepEqual(r.finalDice, [4, 6, 10, 10]);
});

test('Reroll changes report per-position rerolled values', () => {
  const rng = new SequenceRng([1, 4, 6, 7, 8]);
  const r = Roll.resolveWithTn({ diceCount: 4, positiveReroll: { count: 1, max: false } }, rng);
  assert.deepEqual(r.rerollChanges, [8, null, null, null]);
});

test('Nudge changes report only the affected position', () => {
  const rng = new SequenceRng([5, 5, 5, 1]);
  const r = Roll.resolveWithTn(
    { diceCount: 4, failureModifier: -1, valueAdjustment: { value: 1, max: false } },
    rng
  );
  assert.deepEqual(r.nudgeChanges, [null, null, null, 2]);
});
