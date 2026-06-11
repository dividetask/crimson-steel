import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Ascendancy } from '../../public/js/ascendancy.js';
import { CheckResolution } from '../../public/js/check.js';

// dice_resolution_design.md → Ascendancy. Derived per Roll during TN
// computation (Roll Resolution), from the gap between the Roll's strongest
// Inherent Bonus and its strongest Inherent Penalty: ['Ascendancy', 2 × gap].
// The gate: a Roll derives Ascendancy only when it carries an Inherent
// Penalty (value <= 0; a 0 counts). A lone Inherent Bonus — no opposing
// creature — or balanced Inherents add nothing. Rolls carry no `tier`; the
// Inherent entries are the only input. `previewParameters` surfaces the
// derived entry on each Roll's bonusPenaltyList; bare `prepare` only
// propagates.

test('modifier amplifies an Inherent surplus into an Ascendancy Bonus', () => {
  assert.deepEqual(Ascendancy.modifier([['Inherent', 2], ['Inherent', -1]]), ['Ascendancy', 2]);
});

test('modifier amplifies an Inherent deficit into an Ascendancy Penalty', () => {
  assert.deepEqual(Ascendancy.modifier([['Inherent', 1], ['Inherent', -3]]), ['Ascendancy', -4]);
});

test('modifier is null when the Inherents balance or are absent', () => {
  assert.equal(Ascendancy.modifier([['Inherent', 2], ['Inherent', -2]]), null);
  assert.equal(Ascendancy.modifier([['Competency', 3]]), null);
  assert.equal(Ascendancy.modifier([]), null);
  assert.equal(Ascendancy.modifier(undefined), null);
});

test('modifier compares only the strongest Bonus and strongest Penalty (per-Type stacking)', () => {
  // Own +2 vs crossed -3 and -1: only the -3 counts. Gap -1 → -2.
  assert.deepEqual(
    Ascendancy.modifier([['Inherent', 2], ['Inherent', -3], ['Inherent', -1]]),
    ['Ascendancy', -2]);
});

test('a wide Inherent gap scales: +1 vs +4 is a ±6 pair', () => {
  assert.deepEqual(Ascendancy.modifier([['Inherent', 1], ['Inherent', -4]]), ['Ascendancy', -6]);
  assert.deepEqual(Ascendancy.modifier([['Inherent', 4], ['Inherent', -1]]), ['Ascendancy', 6]);
});

test('the gate requires an Inherent Penalty; a lone Bonus derives nothing', () => {
  // A lone Inherent Bonus has no opposing creature → no Ascendancy.
  assert.equal(Ascendancy.modifier([['Inherent', 1]]), null);
  assert.equal(Ascendancy.modifier([['Inherent', 2]]), null);
});

test('a zero side of the comparison reads as 0.5 (Tier 0)', () => {
  // A crossed -1 alone is a Tier-0 Roll (its own absent Bonus reads 0.5)
  // facing a Tier 1: gap 0.5 - 1 = -0.5 → floor(2 × 0.5) = 1.
  assert.deepEqual(Ascendancy.modifier([['Inherent', -1]]), ['Ascendancy', -1]);
  assert.deepEqual(Ascendancy.modifier([['Inherent', -2]]), ['Ascendancy', -3]);
  // A +0 Inherent Penalty (the injected Tier-0 opponent) fires the gate, its
  // 0 read as 0.5: Tier 2 vs Tier 0 → gap 2 - 0.5 = 1.5 → floor(3) = 3.
  assert.deepEqual(Ascendancy.modifier([['Inherent', 2], ['Inherent', 0]]), ['Ascendancy', 3]);
  assert.deepEqual(Ascendancy.modifier([['Inherent', 1], ['Inherent', 0]]), ['Ascendancy', 1]);
});

// ---- Worked examples (check_resolution_tests.md → Ascendancy) ----
// Adam initiates, Ben supports, Dawn defends, Carol opposes alongside Dawn.

test('equal Inherents on every Roll produce no Ascendancy anywhere', () => {
  const prepared = CheckResolution.previewParameters({
    supporting: [
      { bonusPenaltyList: [['Inherent', 2]] }, // Adam
      { bonusPenaltyList: [['Inherent', 2]] }, // Ben
    ],
    opposing: [
      { bonusPenaltyList: [['Inherent', 2]] }, // Dawn (defending)
      { bonusPenaltyList: [['Inherent', 2]] }, // Carol
    ],
  });
  const all = prepared.supporting.concat(prepared.opposing);
  for (const roll of all) {
    assert.equal(roll.bonusPenaltyList.some(([type]) => type === 'Ascendancy'), false);
  }
});

test('a one-point Inherent edge yields a ±2 Ascendancy pair', () => {
  // Adam (Inherent +2) initiates against Dawn (Inherent +1) defending.
  const prepared = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 1]] }],
  });
  // Adam: his own +2 Inherent, Dawn's crossed as a -1 Inherent Penalty, and
  // the surplus amplified into a +2 Ascendancy Bonus.
  assert.deepEqual(prepared.supporting[0].bonusPenaltyList,
    [['Inherent', 2], ['Inherent', -1], ['Ascendancy', 2]]);
  // Dawn gets the mirror image.
  assert.deepEqual(prepared.opposing[0].bonusPenaltyList,
    [['Inherent', 1], ['Inherent', -2], ['Ascendancy', -2]]);
});

test('with several opponents each Roll measures against the strongest crossing', () => {
  // Adam (+2) initiates; Dawn (+1) defends and Carol (+3) opposes alongside.
  const prepared = CheckResolution.previewParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }], // Adam
    opposing: [
      { bonusPenaltyList: [['Inherent', 1]] }, // Dawn (defending)
      { bonusPenaltyList: [['Inherent', 3]] }, // Carol
    ],
  });
  // Adam receives every Opposer's Inherent; only Carol's -3 counts against
  // his +2 (per-Type stacking), so he takes a -2 Ascendancy Penalty.
  assert.deepEqual(prepared.supporting[0].bonusPenaltyList,
    [['Inherent', 2], ['Inherent', -1], ['Inherent', -3], ['Ascendancy', -2]]);
  // Dawn (defending) receives Adam's +2: deficit of 1 → -2 Ascendancy.
  assert.deepEqual(prepared.opposing[0].bonusPenaltyList,
    [['Inherent', 1], ['Inherent', -2], ['Ascendancy', -2]]);
  // Carol (other Opposer) receives the Initiator's +2: surplus of 1 → +2.
  assert.deepEqual(prepared.opposing[1].bonusPenaltyList,
    [['Inherent', 3], ['Inherent', -2], ['Ascendancy', 2]]);
});

test('Ascendancy flows through Check Resolution into the TN (not double-propagated)', () => {
  // Inherent +2 attacker vs Inherent +1 defender. Attacker net:
  // +2 - 1 + 2 = +3 → TN 8 - 3 = 5. Defender net: +1 - 2 - 2 = -3 →
  // TN 8 + 3 = 11 clamps to the Maximum TN 9; the overflow becomes
  // Starting Failures (-2).
  const params = CheckResolution.computeParameters({
    supporting: [{ bonusPenaltyList: [['Inherent', 2]] }],
    opposing: [{ bonusPenaltyList: [['Inherent', 1]] }],
  });
  assert.equal(params.supporting[0].tn, 5);
  assert.equal(params.opposing[0].tn, 9);
  assert.equal(params.opposing[0].startingValue, -2);
});
