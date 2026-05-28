import { DiceConfig } from './config.js';

// Nudge (Value Adjustment): shift dice values by a signed amount.
//
// Max mode (max = true): every die shifts, each clamped independently.
// Standard mode (max = false): one die shifts — the one the nudge helps
// most. Targeting differs between the with-TN and without-TN pipelines
// (see the two entry points). A post-shift value that equals the
// pre-shift value (clamped at a boundary) is a no-op and records null.
//
// valueAdjustment is { value, max } or null. Returns a changes array the
// same length as `dice`.
export class Nudge {
  // With a TN: standard targeting picks the die whose DoIS contribution
  // changes most. Tie → die that started lowest (positive) / highest
  // (negative); still tied → lowest index.
  static applyWithTn(dice, valueAdjustment, { tn, failureModifier = -1, criticalModifier = 2 } = {}, config = DiceConfig.default()) {
    if (!valueAdjustment) return new Array(dice.length).fill(null);
    const { value, max } = valueAdjustment;
    if (max) return Nudge._applyMax(dice, value, config);

    const contribution = (v) => {
      if (v === config.dieSize) return criticalModifier;
      if (v === 1) return failureModifier;
      if (v >= tn) return 1;
      return 0;
    };

    const positive = value > 0;
    const scored = dice.map((v, i) => {
      const newV = Nudge._clamp(v + value, config);
      return { v, i, newV, delta: contribution(newV) - contribution(v) };
    });

    scored.sort((a, b) => {
      if (a.delta !== b.delta) return positive ? b.delta - a.delta : a.delta - b.delta;
      if (a.v !== b.v) return positive ? a.v - b.v : b.v - a.v;
      return a.i - b.i;
    });

    return Nudge._single(dice, scored[0]);
  }

  // Without a TN: standard targeting picks the die whose post-shift value
  // lands closest to Die Size (positive) or 1 (negative). Tie → die that
  // started furthest from that extreme; still tied → lowest index.
  static applyWithoutTn(dice, valueAdjustment, config = DiceConfig.default()) {
    if (!valueAdjustment) return new Array(dice.length).fill(null);
    const { value, max } = valueAdjustment;
    if (max) return Nudge._applyMax(dice, value, config);

    const positive = value > 0;
    const extreme = positive ? config.dieSize : 1;

    const scored = dice.map((v, i) => {
      const newV = Nudge._clamp(v + value, config);
      return { v, i, newV, distance: Math.abs(extreme - newV), fromExtreme: Math.abs(extreme - v) };
    });

    scored.sort((a, b) => {
      if (a.distance !== b.distance) return a.distance - b.distance; // closest first
      if (a.fromExtreme !== b.fromExtreme) return b.fromExtreme - a.fromExtreme; // furthest start first
      return a.i - b.i;
    });

    return Nudge._single(dice, scored[0]);
  }

  static _single(dice, target) {
    const changes = new Array(dice.length).fill(null);
    if (target && target.newV !== target.v) changes[target.i] = target.newV;
    return changes;
  }

  static _applyMax(dice, value, config) {
    return dice.map((v) => {
      const newV = Nudge._clamp(v + value, config);
      return newV === v ? null : newV;
    });
  }

  static _clamp(v, config) {
    return Math.max(1, Math.min(config.dieSize, v));
  }
}
