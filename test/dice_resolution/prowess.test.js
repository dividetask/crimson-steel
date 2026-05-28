import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Prowess } from '../../public/js/prowess.js';

// docs/common/dice_resolution/dice_resolution_tests.md
// "Translate Skill Prowess into Roll inputs"
//
// The test doc prose says "dice_count"; the design's return field is
// dice_cap (the maximum dice the Creature may spend). We assert diceCap.

test('Prowess of zero gives the minimum', () => {
  assert.deepEqual(Prowess.translate(0), { diceCap: 6, bonusPenalty: 0 });
});

test('Prowess fitting within a single Range cycle', () => {
  assert.deepEqual(Prowess.translate(3), { diceCap: 9, bonusPenalty: 0 });
});

test('Prowess at exactly one full cycle', () => {
  assert.deepEqual(Prowess.translate(5), { diceCap: 6, bonusPenalty: 1 });
});

test('Prowess overflowing into a Bonus with leftover', () => {
  assert.deepEqual(Prowess.translate(7), { diceCap: 8, bonusPenalty: 1 });
});

test('Prowess at two full cycles', () => {
  assert.deepEqual(Prowess.translate(10), { diceCap: 6, bonusPenalty: 2 });
});

test('Negative Prowess wraps to maximum dice', () => {
  assert.deepEqual(Prowess.translate(-1), { diceCap: 10, bonusPenalty: -1 });
});

test('Negative Prowess with leftover', () => {
  assert.deepEqual(Prowess.translate(-2), { diceCap: 9, bonusPenalty: -1 });
});
