import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RollAndSort } from '../../public/js/rollAndSort.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/check_resolution/check_resolution_tests.md — "Roll and Sort"

test('Sort produces a permutation index', () => {
  // Dice Result Strings come out as "986", "987", "984".
  const rng = new SequenceRng([9, 8, 6, /* */ 9, 8, 7, /* */ 9, 8, 4]);
  const r = RollAndSort.run([{ diceCount: 3 }, { diceCount: 3 }, { diceCount: 3 }], rng);
  assert.deepEqual(r.order, [1, 0, 2]);
});

test('Ties break by original list index', () => {
  const rng = new SequenceRng([7, 5, 4, 7, 5, 4, 7, 5, 4]); // all "754"
  const r = RollAndSort.run([{ diceCount: 3 }, { diceCount: 3 }, { diceCount: 3 }], rng);
  assert.deepEqual(r.order, [0, 1, 2]);
});

test('Roll and Sort skips propagation entirely', () => {
  // bonus_penalty_list is present but must be ignored — only dice order.
  const rng = new SequenceRng([5, /* */ 9]);
  const r = RollAndSort.run(
    [
      { diceCount: 1, bonusPenaltyList: [['A', 5]] },
      { diceCount: 1, bonusPenaltyList: [['B', -5]] },
    ],
    rng
  );
  assert.deepEqual(r.order, [1, 0]); // "9" > "5"
});
