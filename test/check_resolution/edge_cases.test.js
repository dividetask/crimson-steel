import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/check_resolution/check_resolution_tests.md — "Edge cases".
// The design leaves several of these as "validation unassigned"; these
// tests document the implementation's current (graceful) behavior.

test('Empty supporting list resolves without throwing', () => {
  // Design: invalid, validation unassigned. We document current behavior.
  const r = CheckResolution.resolveCheck({ supporting: [], opposing: [] }, new SequenceRng([]));
  assert.equal(r.degreeOfSuccess, 0);
  assert.equal(r.outcome, 'failure');
});

test('Single Supporting Roll, single Opposing Roll, both with no modifiers', () => {
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [] }],
    opposing: [{ bonusPenaltyList: [] }],
  });
  assert.equal(params.supporting[0].tn, 6); // Base TN, no propagation entries
  assert.equal(params.opposing[0].tn, 6);
});

test('A value_adjustment on the Supporting side nudges that Roll only', () => {
  const rng = new SequenceRng([5, 5, /* opposing */ 5, 5]);
  const r = CheckResolution.resolveCheck(
    {
      supporting: [{ diceCount: 2, valueAdjustment: { value: 1, max: false } }],
      opposing: [{ diceCount: 2 }],
    },
    rng
  );
  // Supporting Roll nudged one die; Opposing Roll untouched.
  assert.deepEqual(r.supportingResults[0].nudgeChanges, [6, null]);
  assert.deepEqual(r.opposingResults[0].nudgeChanges, [null, null]);
  assert.deepEqual(r.opposingResults[0].finalDice, [5, 5]);
});
