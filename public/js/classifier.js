import { DiceConfig } from './config.js';

// Classify a signed value into a Roll/Check Outcome using the configured
// Default Success and Default Fumble Thresholds.
//
//   fumble  — canFumble && value <= -Default Fumble Threshold
//   success — value >= Default Success Threshold
//   failure — otherwise (including exactly zero)
//
// Scoring calls this with canFumble = (failure_modifier !== 0). Check
// resolution always passes canFumble = true.
export class Classifier {
  static classify(value, canFumble, config = DiceConfig.default()) {
    if (canFumble && value <= -config.defaultFumbleThreshold) return 'fumble';
    if (value >= config.defaultSuccessThreshold) return 'success';
    return 'failure';
  }
}
