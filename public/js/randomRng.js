// Random source seam (production).
//
// The resolution pipeline never calls Math.random directly — it asks an Rng
// for each die. Production uses RandomRng; tests use SequenceRng
// (sequenceRng.js) to feed exact dice patterns.

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
