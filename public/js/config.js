// Dice Resolution configuration.
//
// Mirrors docs/common/dice_resolution/dice_resolution_config.yaml — that
// file is the source of truth. These defaults are duplicated here because
// the browser has no YAML loader; keep them in sync with the YAML by hand.
// Tests construct DiceConfig with overrides to exercise other values.
export class DiceConfig {
  constructor(overrides = {}) {
    const base = {
      dieSize: 10,
      diceResultStringEncoding: 'X',
      baseTargetNumber: 6,
      minimumTargetNumber: 3,
      maximumTargetNumber: 9,
      minimumDiceCount: 6,
      diceCountRange: 5,
      defaultSuccessThreshold: 2,
      defaultFumbleThreshold: 2,
      defaultFailureModifier: -1,
      defaultCriticalModifier: 2,
    };
    Object.assign(this, base, overrides);
  }

  get maximumDiceCount() {
    return this.minimumDiceCount + this.diceCountRange - 1;
  }

  static default() {
    return new DiceConfig();
  }
}
