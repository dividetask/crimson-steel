// start_of_turn_stub: Per-turn pipeline preview + confirm.
//
// Each per-affliction row is a child roll_stub (bare_row mode under one
// shared <table>). All UX for rolling and applying Luck / Insight lives
// in roll_stub itself; this file only:
//
//   - Reads each child's editable Result (successes) and Crits inputs.
//   - Builds a JSON bundle for the form's hidden field on submit.
//   - Renders a local preview of the start-of-turn pipeline so the
//     player can see what's about to change before pressing Confirm.
//
// The server route /combat/start_of_turn is the source of truth — the
// preview here mirrors the same formula the route uses (severity_per_
// success * successes for the severity move, halve-for-acid, etc.) but
// is purely informational.
(function() {
  function cfg(stubId) { return (window.startOfTurnConfigs || {})[stubId]; }

  function readInt(id) {
    var el = document.getElementById(id);
    if (!el) return 0;
    var n = parseInt(el.value, 10);
    return isNaN(n) ? 0 : n;
  }

  function gatherRolls(stubId) {
    var c = cfg(stubId);
    if (!c) return [];
    return c.childIds.map(function(id, i) {
      var s = readInt('roll-stub-result-' + id);
      var crits = readInt('roll-stub-crits-' + id);
      return {
        affliction: c.afflictionNames[i],
        successes:  Math.max(0, s),
        failures:   Math.max(0, -s),
        criticals:  crits,
        severity_before: c.severities[i]
      };
    });
  }

  function buildPreview(stubId) {
    var c = cfg(stubId);
    if (!c) return '(stub config missing)';
    var rolls = gatherRolls(stubId);
    var lines = [];

    var newPool = c.actionDiceMax;
    var lineDice = 'Action Dice  : reset to ' + c.actionDiceMax;
    if (c.shock > 0) {
      newPool = Math.max(0, c.actionDiceMax - c.shock);
      lineDice += ', less ' + c.shock + ' shock = ' + newPool;
    }
    lines.push(lineDice);

    if (c.shock > 0) lines.push('Shock        : ' + c.shock + ' -> 0');
    if (c.acidAfterHalve > 0) {
      lines.push('Acid Counter : halves; deals ' + c.acidAfterHalve + ' minor HP damage');
    }

    if (rolls.length === 0) {
      lines.push('Afflictions  : (none)');
    } else {
      lines.push('Afflictions:');
      rolls.forEach(function(r) {
        // Per-success severity drop is per-affliction (config-driven on
        // the server). The preview shows the count of successes / failures
        // the player rolled and lets the server settle the exact delta.
        var note = '  - ' + r.affliction + ' (sev ' + r.severity_before + '): ' +
                   r.successes + ' successes, ' + r.failures + ' failures' +
                   (r.criticals ? ', ' + r.criticals + ' crit' : '');
        lines.push(note);
      });
    }

    return lines.join('\n');
  }

  window.startOfTurnPreview = function(stubId) {
    var pre = document.getElementById('start-of-turn-preview-' + stubId);
    if (pre) pre.textContent = buildPreview(stubId);
  };

  window.startOfTurnPrepareSubmit = function(stubId) {
    var hidden = document.getElementById('start-of-turn-rolls-' + stubId);
    if (hidden) hidden.value = JSON.stringify(gatherRolls(stubId));
    return true;
  };
})();
