import { CONFIG_DATA } from './configData.js';

// Dice Resolution configuration.
//
// The values from dice_resolution_config.yaml arrive via configData.js, a
// file generated from that YAML at server startup (see
// lib/dice_resolution/config_js_generator.rb) — the YAML stays the single
// source of truth. failure_modifier / critical_modifier are per-Roll
// design defaults, not config values, so they live here. Tests construct
// DiceConfig with overrides to exercise other values.
export class DiceConfig {
  constructor(overrides = {}) {
    const base = {
      ...CONFIG_DATA,
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
