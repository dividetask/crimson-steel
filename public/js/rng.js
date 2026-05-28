// Random source seam.
//
// The resolution pipeline never calls Math.random directly — it asks an
// Rng for each die. Production uses RandomRng; tests use SequenceRng to
// feed exact dice patterns (the test docs state the *rolled* values as
// input rather than relying on randomness).

export class RandomRng {
  rollDie(dieSize) {
    return 1 + Math.floor(Math.random() * dieSize);
  }

  rollDice(count, dieSize) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(this.rollDie(dieSize));
    return out;
  }
}

// Returns queued values in order. rollDie pops the next value; the
// dieSize argument is ignored (the caller pre-decided the value). Throws
// if drained, which surfaces a test that rolled more dice than expected.
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
