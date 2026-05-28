import { DiceConfig } from './config.js';

const FALLBACK_ENCODING = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// ASCII encoding of a dice list, sorted descending. Monotonic: a higher
// die value maps to a higher character, so two strings compared lexically
// reproduce a die-by-die comparison of the underlying lists.
//
// Values 1–9 emit '1'–'9'; values 10+ index into the configured
// encoding. If the configured encoding is too short to cover every value
// above 9 (length < Die Size − 9), it is replaced wholesale with A–Z.
export class DiceResultString {
  static encode(values, config = DiceConfig.default()) {
    let encoding = config.diceResultStringEncoding;
    if (encoding.length < config.dieSize - 9) {
      encoding = FALLBACK_ENCODING;
    }

    return values
      .slice()
      .sort((a, b) => b - a)
      .map((v) => (v <= 9 ? String(v) : encoding[v - 10]))
      .join('');
  }
}
