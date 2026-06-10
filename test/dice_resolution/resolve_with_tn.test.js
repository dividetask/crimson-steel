import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Roll } from '../../public/js/roll.js';
import { TnComputation } from '../../public/js/tnComputation.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/dice_resolution/dice_resolution_tests.md
// "Resolve a Roll with a Target Number"

test('A Roll with no modifiers and middling dice', () => {
  const rng = new SequenceRng([8, 8, 5, 1, 3, 9]);
  const r = Roll.resolveWithTn({ diceCount: 6 }, rng);
  assert.equal(r.tn, 8);
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
  assert.equal(tn, 5);
  assert.equal(startingValue, 0);
});

test('Bonus overflow into Starting Successes', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', 7]],
    startingContribution: 1,
  });
  // 8 - 7 = 1, clamped to the Minimum TN 3; the 2-point overflow becomes
  // Starting Successes on top of the contribution.
  assert.equal(tn, 3);
  assert.equal(startingValue, 3);
});

test('Penalty overflow into Starting Failures', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', -5]],
    startingContribution: 0,
  });
  // 8 + 5 = 13, clamped to the Maximum TN 9; the 4-point overflow becomes
  // Starting Failures.
  assert.equal(tn, 9);
  assert.equal(startingValue, -4);
});

test('Bonus and Penalty cancel out', () => {
  const { tn, startingValue } = TnComputation.compute({
    bonusPenaltyList: [['A', 20], ['B', -20]],
  });
  assert.equal(tn, 8);
  assert.equal(startingValue, 0);
});

test('A Critical Success replaces the regular Success', () => {
  const rng = new SequenceRng([10]);
  const r = Roll.resolveWithTn({ diceCount: 1, criticalModifier: 2 }, rng);
  // The single crit contributes +2 (not +3). DoIS = 0 + 2.
  assert.equal(r.dois, 2);
  assert.equal(r.criticalCount, 1);
});

test('A Roll that ignores Failures cannot Fumble', () => {
  // Six 1s are worth -6 at the default failure_modifier (a Fumble); with
  // failure_modifier = 0 they contribute nothing, so DoIS stays at 0.
  const rng = new SequenceRng([1, 1, 1, 1, 1, 1]);
  const r = Roll.resolveWithTn({ diceCount: 6, failureModifier: 0 }, rng);
  assert.equal(r.dois, 0);
  assert.equal(r.outcome, 'failure'); // not 'fumble'
});

test('A negative Starting Value cannot Fumble a Roll that ignores Failures', () => {
  // The only way DoIS goes negative when failure_modifier = 0 is via a
  // negative Starting Value. The Fumble check is still suppressed.
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
  const rng = new SequenceRng([7, 5, 5, 5, 5, 1]);
  const r = Roll.resolveWithTn(
    { diceCount: 6, failureModifier: 0, valueAdjustment: { value: 1, max: false } },
    rng
  );
  assert.deepEqual(r.nudgeChanges, [8, null, null, null, null, null]);
});

test('Tied delta with a Failure prefers the lower-starting die', () => {
  const rng = new SequenceRng([5, 5, 5, 5, 5, 1]);
  const r = Roll.resolveWithTn(
    { diceCount: 6, failureModifier: -1, valueAdjustment: { value: 1, max: false } },
    rng
  );
  assert.deepEqual(r.nudgeChanges, [null, null, null, null, null, 2]);
});

test('A tied nudge prefers creating a Critical Success', () => {
  // 9->10 (Success->Crit) and 5->6 (Neutral->Success) both add +1 to DoIS;
  // the Crit wins the tie even though the 5 started lower.
  const rng = new SequenceRng([9, 5]);
  const r = Roll.resolveWithTn({ diceCount: 2, valueAdjustment: { value: 1, max: false } }, rng);
  assert.deepEqual(r.nudgeChanges, [10, null]);
});

test('Max-mode nudge shifts every die', () => {
  const rng = new SequenceRng([3, 5, 9, 10]);
  const r = Roll.resolveWithTn({ diceCount: 4, valueAdjustment: { value: 1, max: true } }, rng);
  assert.deepEqual(r.finalDice, [4, 6, 10, 10]);
  // Max mode records every die, including the clamped 10 — no nulls.
  assert.deepEqual(r.nudgeChanges, [4, 6, 10, 10]);
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
