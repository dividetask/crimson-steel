import { DiceConfig } from './config.js';

// Translate Skill Prowess into Roll inputs.
//
// Each full Dice Count Range of prowess produces one point of
// bonus/penalty; the leftover fills diceCap above the Minimum Dice Count.
// Uses floor division (toward negative infinity) and an explicit
// remainder so negative prowess wraps correctly — language `%` would not.
export class Prowess {
  static translate(prowess, config = DiceConfig.default()) {
    const range = config.diceCountRange;
    const bonusPenalty = Math.floor(prowess / range);
    const remainder = prowess - bonusPenalty * range;
    const diceCap = config.minimumDiceCount + remainder;
    return { diceCap, bonusPenalty };
  }
}
