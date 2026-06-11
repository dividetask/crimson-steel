import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Roll } from '../../public/js/roll.js';
import { DiceResultString } from '../../public/js/diceResultString.js';
import { DiceConfig } from '../../public/js/config.js';
import { SequenceRng } from '../../public/js/sequenceRng.js';

// docs/common/dice_resolution/dice_resolution_tests.md
// "Resolve a Roll without a Target Number"

test('Ordering-only roll', () => {
  const rng = new SequenceRng([8, 5, 7, 2, 9, 4]);
  const r = Roll.resolveWithoutTn({ diceCount: 6 }, rng);
  assert.deepEqual(r.finalDice, [8, 5, 7, 2, 9, 4]);
  assert.equal(r.diceResultString, '987542');
});

test('Reroll uses bottom-quartile threshold for positive', () => {
  // threshold = floor(10/4)+1 = 3, so only 1s and 2s are eligible.
  const rng = new SequenceRng([1, 2, 3, 4, 5, 6, 9, 9]); // initial + 2 reroll values
  const r = Roll.resolveWithoutTn({ diceCount: 6, positiveReroll: { count: 3, max: false } }, rng);
  assert.notEqual(r.rerollChanges[0], null); // the 1
  assert.notEqual(r.rerollChanges[1], null); // the 2
  assert.equal(r.rerollChanges[2], null); // the 3 stays untouched
  assert.equal(r.rerollChanges[3], null);
  assert.equal(r.rerollChanges[4], null);
  assert.equal(r.rerollChanges[5], null);
});

test('Reroll uses top-quartile threshold for negative', () => {
  // threshold = 10 - floor(10/4) = 8, so 8/9/10 are eligible.
  const rng = new SequenceRng([6, 7, 8, 9, 10, 5, 1, 1, 1]); // initial + 3 reroll values
  const r = Roll.resolveWithoutTn({ diceCount: 6, negativeReroll: { count: 3, max: false } }, rng);
  assert.equal(r.rerollChanges[0], null); // 6
  assert.equal(r.rerollChanges[1], null); // 7
  assert.notEqual(r.rerollChanges[2], null); // 8
  assert.notEqual(r.rerollChanges[3], null); // 9
  assert.notEqual(r.rerollChanges[4], null); // 10
  assert.equal(r.rerollChanges[5], null); // 5
});

test('Nudge favors making a Critical Success', () => {
  const rng = new SequenceRng([8, 9, 6, 4]);
  const r = Roll.resolveWithoutTn({ diceCount: 4, valueAdjustment: { value: 1, max: false } }, rng);
  assert.deepEqual(r.nudgeChanges, [null, 10, null, null]);
  assert.deepEqual(r.finalDice, [8, 10, 6, 4]);
});

test('Nudge tied closeness picks the die furthest from the extreme', () => {
  const rng = new SequenceRng([7, 9]);
  const r = Roll.resolveWithoutTn({ diceCount: 2, valueAdjustment: { value: 3, max: false } }, rng);
  assert.deepEqual(r.finalDice, [10, 9]);
});

test('Dice Result String encoding falls back to letters when configured encoding is too short', () => {
  const config = new DiceConfig({ dieSize: 12, diceResultStringEncoding: 'X' });
  assert.equal(DiceResultString.encode([12, 11, 10, 9], config), 'CBA9');
});
