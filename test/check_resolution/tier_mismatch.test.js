import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TierMismatch } from '../../public/js/tierMismatch.js';
import { CheckResolution } from '../../public/js/check.js';

// encounter_design.md -> Tier Mismatch (the Ascendancy / Check half).

test('ascendancyModifier is a Bonus when the actor out-Tiers the opponent', () => {
  assert.deepEqual(TierMismatch.ascendancyModifier(3, 1), ['Ascendancy', 4]);
});

test('ascendancyModifier is a Penalty when the actor is out-Tiered', () => {
  assert.deepEqual(TierMismatch.ascendancyModifier(1, 3), ['Ascendancy', -4]);
});

test('ascendancyModifier is null at equal Tier or when a tier is absent', () => {
  assert.equal(TierMismatch.ascendancyModifier(2, 2), null);
  assert.equal(TierMismatch.ascendancyModifier(undefined, 2), null);
  assert.equal(TierMismatch.ascendancyModifier(2, null), null);
});

test('ascendancyModifier treats Tier 0 as 0.5 and floors the magnitude', () => {
  // delta = 1 - 0.5 = 0.5 -> 2 * 0.5 = 1
  assert.deepEqual(TierMismatch.ascendancyModifier(1, 0), ['Ascendancy', 1]);
  assert.deepEqual(TierMismatch.ascendancyModifier(0, 1), ['Ascendancy', -1]);
});

test('apply appends each side its Ascendancy against the opposing primary Roll', () => {
  const check = {
    supporting: [{ tier: 3, bonusPenaltyList: [] }],
    opposing: [{ tier: 1, bonusPenaltyList: [] }],
  };
  const out = TierMismatch.apply(check);
  assert.deepEqual(out.supporting[0].bonusPenaltyList, [['Ascendancy', 4]]);
  assert.deepEqual(out.opposing[0].bonusPenaltyList, [['Ascendancy', -4]]);
});

test('apply is a no-op when Rolls carry no tier', () => {
  const check = { supporting: [{ bonusPenaltyList: [] }], opposing: [{ bonusPenaltyList: [] }] };
  const out = TierMismatch.apply(check);
  assert.deepEqual(out.supporting[0].bonusPenaltyList, []);
  assert.deepEqual(out.opposing[0].bonusPenaltyList, []);
});

test('Ascendancy flows through Check Resolution into the TN (not double-propagated)', () => {
  // A Tier-2 attacker vs a Tier-1 defender: the attacker gets +2 Ascendancy
  // (TN 6 -> 4) and the defender -2 (TN 6 -> 8). The defender's Penalty is NOT
  // inverted back onto the attacker (Tier Mismatch runs after Propagation), so
  // the attacker's TN stays 4 rather than dropping further.
  const params = CheckResolution.computeParameters({
    supporting: [{ tier: 2, bonusPenaltyList: [] }],
    opposing: [{ tier: 1, bonusPenaltyList: [] }],
  });
  assert.equal(params.supporting[0].tn, 4); // 6 - 2
  assert.equal(params.opposing[0].tn, 8);   // 6 + 2
});
