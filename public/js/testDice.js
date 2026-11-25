// Test mode only (CRIMSON_TEST_DICE=1, added by views/layout.erb): the DM's
// browser takes its dice from the server's scripted queue (lib/test_dice.rb)
// so one queue covers server and browser rolls in the order they happen.
// The resolution pipeline needs a die synchronously, hence the sync request.
import { RandomRng } from '/js/randomRng.js';

RandomRng.prototype.rollDie = function (dieSize) {
  const xhr = new XMLHttpRequest();
  xhr.open('GET', `/test/dice/next?size=${dieSize}`, false);
  xhr.send();
  if (xhr.status !== 200) throw new Error(`test dice: ${xhr.responseText}`);
  return JSON.parse(xhr.responseText).face;
};
