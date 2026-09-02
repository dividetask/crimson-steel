// Random source seam (production).
//
// The resolution pipeline never calls Math.random directly — it asks an Rng
// for each die. Production uses RandomRng; tests use SequenceRng
// (sequenceRng.js) to feed exact dice patterns.
//
// A browser test cannot swap the class out — the page constructs its own
// RandomRng deep inside the Roll Controller — so RandomRng itself reads a
// queue of scripted values when one is armed on the window. Production
// never arms it, and it is not enough to override Math.random from the
// test: the Atlas uses Math.random for SVG ids and would eat the dice.
//
//   window.__scriptedDice = [9, 8, 3, 7, 2];   // armed by a browser test
//
// Values are taken in order. If the page asks for more dice than the test
// queued, the extra dice are random and __scriptedDiceExhausted is set, so
// the test can fail loudly instead of quietly going non-deterministic.

export class RandomRng {
  rollDie(dieSize) {
    const queue = globalThis.__scriptedDice;
    if (Array.isArray(queue)) {
      if (queue.length) return queue.shift();
      globalThis.__scriptedDiceExhausted = true;
    }
    return 1 + Math.floor(Math.random() * dieSize);
  }

  rollDice(count, dieSize) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(this.rollDie(dieSize));
    return out;
  }
}
