import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Classifier } from '../../public/js/classifier.js';

// docs/common/dice_resolution/dice_resolution_tests.md
// "Classify a value against outcome thresholds"

test('A value at or above Default Success Threshold is a success', () => {
  assert.equal(Classifier.classify(2, true), 'success');
  assert.equal(Classifier.classify(5, true), 'success');
});

test('A value at exactly Default Fumble Threshold negated is a fumble', () => {
  assert.equal(Classifier.classify(-2, true), 'fumble');
});

test('A value between the two thresholds is a failure', () => {
  assert.equal(Classifier.classify(0, true), 'failure');
});

test('A negative value just shy of the Fumble Threshold is a failure', () => {
  assert.equal(Classifier.classify(-1, true), 'failure');
});

test('can_fumble = false suppresses the Fumble outcome', () => {
  assert.equal(Classifier.classify(-5, false), 'failure');
});

test('can_fumble = false still allows Success', () => {
  assert.equal(Classifier.classify(3, false), 'success');
});
