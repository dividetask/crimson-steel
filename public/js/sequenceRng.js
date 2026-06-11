// Deterministic Rng for tests, the test-side counterpart of RandomRng
// (randomRng.js) on the random-source seam: the resolution pipeline asks an
// Rng for each die, and tests feed exact dice patterns here (the test docs
// state the *rolled* values as input rather than relying on randomness).
//
// Returns queued values in order. rollDie pops the next value; the dieSize
// argument is ignored (the caller pre-decided the value). Throws if drained,
// which surfaces a test that rolled more dice than expected.

export class SequenceRng {
  constructor(values = []) {
    this.values = values.slice();
    this.index = 0;
  }

  rollDie() {
    if (this.index >= this.values.length) {
      throw new Error('SequenceRng exhausted: more dice requested than queued');
    }
    return this.values[this.index++];
  }

  rollDice(count) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(this.rollDie());
    return out;
  }
}
