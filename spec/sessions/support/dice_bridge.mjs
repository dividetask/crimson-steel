// Scripted-dice bridge for the Session Tests (docs/project/session_tests.md).
//
// The browser is where dice are actually rolled: the Action Builder asks
// Check Resolution for each Roll's TN (after cross-side Propagation), the
// Roll Controller rolls the dice, and Scoring turns them into the
// Successes the page POSTs back. A Session Test scripts the dice instead
// of rolling them, but runs them through *these same modules* so a
// scenario's Successes are exactly what the DM would have seen.
//
// Protocol: one JSON request per line on stdin, one JSON response per
// line on stdout.
//
//   in  { "rolls": [ { "id", "side", "base_tn", "bonus_penalty_list",
//                      "no_propagate", "dice_count", "dice" } ],
//         "spread": false }
//   out { "ok": true, "rolls": { "<id>": { "tn", "starting_value",
//                                          "dois", "critical_count",
//                                          "outcome", "final_dice" } } }
//
// Mirrors public/js/ui/actionBuilder.js#_previewTns (TN) and
// public/js/ui/rollController.js#rollGroup (scoring). Reroll and Nudge are
// deliberately not applied — no scenario spends Luck yet; see the Gaps
// section of docs/project/session_tests.md.

import { createInterface } from 'node:readline';
import { CheckResolution } from '../../../public/js/check.js';
import { Scoring } from '../../../public/js/scoring.js';
import { DiceConfig } from '../../../public/js/config.js';

const config = DiceConfig.default();

function toRoll(spec) {
  return {
    _id: spec.id,
    _dice: spec.dice || [],
    _failureModifier: spec.failure_modifier,
    _criticalModifier: spec.critical_modifier,
    side: spec.side,
    baseTn: spec.base_tn,
    bonusPenaltyList: spec.bonus_penalty_list || [],
    noPropagate: spec.no_propagate || [],
    startingContribution: spec.starting_contribution || 0,
  };
}

function handle(request) {
  const rolls = (request.rolls || []).map(toRoll);
  const supporting = rolls.filter((r) => r.side !== 'opposing');
  const opposing = rolls.filter((r) => r.side === 'opposing');
  const preview = CheckResolution.previewParameters({
    supporting,
    opposing,
    spread: !!request.spread,
  });

  const out = {};
  const collect = (list, results) => {
    list.forEach((roll, i) => {
      const res = results[i];
      if (!res) return;
      const failureModifier =
        roll._failureModifier != null ? roll._failureModifier : config.defaultFailureModifier;
      const criticalModifier =
        roll._criticalModifier != null ? roll._criticalModifier : config.defaultCriticalModifier;
      const score = Scoring.score(
        roll._dice,
        {
          tn: res.tn,
          startingValue: res.startingValue,
          failureModifier,
          criticalModifier,
        },
        config,
      );
      out[roll._id] = {
        tn: res.tn,
        starting_value: res.startingValue,
        dois: score.dois,
        critical_count: score.criticalCount,
        outcome: score.outcome,
        final_dice: roll._dice,
      };
    });
  };
  collect(supporting, preview.supporting);
  collect(opposing, preview.opposing);
  return { ok: true, rolls: out };
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (line) => {
  if (!line.trim()) return;
  let response;
  try {
    response = handle(JSON.parse(line));
  } catch (err) {
    response = { ok: false, error: String((err && err.message) || err) };
  }
  process.stdout.write(JSON.stringify(response) + '\n');
});
