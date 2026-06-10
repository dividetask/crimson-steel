import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CheckResolution } from '../../public/js/check.js';
import { SequenceRng } from '../../public/js/rng.js';

// docs/common/check_resolution/check_resolution_tests.md — "Resolve a Check".
//
// Each Roll below carries no Bonus/Penalty (so TN stays at the Base of 8
// and propagation is a no-op); dice are crafted to land on the DoIS each
// case names. At TN 8 an 8 is a Success (+1) and a 1 is a Failure (-1).

test('A solo Check produces a Degree of Success equal to its Roll DoIS', () => {
  const rng = new SequenceRng([8, 8, 8]); // +3
  const r = CheckResolution.resolveCheck({ supporting: [{ diceCount: 3 }], opposing: [] }, rng);
  assert.equal(r.degreeOfSuccess, 3);
  assert.equal(r.outcome, 'success');
});

test('An opposed Check subtracts Opposing DoIS', () => {
  const rng = new SequenceRng([8, 8, 8, 8, 8, /* opposing */ 8, 8]); // +5 vs +2
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 5 }], opposing: [{ diceCount: 2 }] },
    rng
  );
  assert.equal(r.degreeOfSuccess, 3);
  assert.equal(r.outcome, 'success');
});

test('Multiple Supporting Rolls aggregate', () => {
  const rng = new SequenceRng([8, 8, /* */ 8, /* */ 1]); // +2, +1, -1
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 2 }, { diceCount: 1 }, { diceCount: 1 }], opposing: [] },
    rng
  );
  assert.equal(r.degreeOfSuccess, 2);
  assert.equal(r.outcome, 'success');
});

test('Multiple Opposing Rolls aggregate', () => {
  const rng = new SequenceRng([8, 8, 8, 8, /* opposing */ 8, 8, /* */ 8, 8, 8]); // +4 vs (+2 + +3)
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 4 }], opposing: [{ diceCount: 2 }, { diceCount: 3 }] },
    rng
  );
  assert.equal(r.degreeOfSuccess, -1);
  assert.equal(r.outcome, 'failure');
});

test('A Check with strongly negative Degree of Success Fumbles', () => {
  const rng = new SequenceRng([1, 1, 1]); // -3
  const r = CheckResolution.resolveCheck({ supporting: [{ diceCount: 3 }], opposing: [] }, rng);
  assert.equal(r.degreeOfSuccess, -3);
  assert.equal(r.outcome, 'fumble');
});

test('Check-level Fumble fires regardless of per-Roll failure_modifier', () => {
  // failure_modifier = 0 means dice can't go negative, so the -3 comes from
  // a negative Starting Value. The Roll itself is a failure (never a
  // fumble), but the Check still Fumbles.
  const rng = new SequenceRng([3, 3, 3]); // neutral dice
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 3, failureModifier: 0, startingContribution: -3 }], opposing: [] },
    rng
  );
  assert.equal(r.degreeOfSuccess, -3);
  assert.equal(r.supportingResults[0].outcome, 'failure'); // the Roll cannot Fumble
  assert.equal(r.outcome, 'fumble'); // the Check can
});

test('An opposed Check that nets to zero is a failure', () => {
  const rng = new SequenceRng([8, 8, 8, /* opposing */ 8, 8, 8]); // +3 vs +3
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 3 }], opposing: [{ diceCount: 3 }] },
    rng
  );
  assert.equal(r.degreeOfSuccess, 0);
  assert.equal(r.outcome, 'failure');
});

test('Per-Roll results are returned alongside the aggregate', () => {
  const rng = new SequenceRng([8, 8, 8]);
  const r = CheckResolution.resolveCheck(
    { supporting: [{ diceCount: 1 }, { diceCount: 1 }], opposing: [{ diceCount: 1 }] },
    rng
  );
  assert.equal(r.supportingResults.length, 2);
  assert.equal(r.opposingResults.length, 1);
  for (const result of [...r.supportingResults, ...r.opposingResults]) {
    assert.ok('finalDice' in result);
    assert.ok('rerollChanges' in result);
    assert.ok('nudgeChanges' in result);
  }
});
