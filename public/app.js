(function () {
  'use strict';

  function rollDie(dieSize) {
    return 1 + Math.floor(Math.random() * dieSize);
  }

  function rollDice(count, dieSize) {
    var out = [];
    for (var i = 0; i < count; i++) out.push(rollDie(dieSize));
    return out;
  }

  function applyReroll(current, sign, count, max, tn, dieSize) {
    var changes = new Array(current.length).fill(null);
    var indexed = current.map(function (v, i) { return { v: v, i: i }; });
    var candidates;
    if (sign === 'pos') {
      candidates = indexed.filter(function (d) { return d.v < tn; })
                          .sort(function (a, b) { return a.v - b.v; });
    } else {
      candidates = indexed.filter(function (d) { return d.v >= tn; })
                          .sort(function (a, b) { return b.v - a.v; });
    }
    var n = max ? candidates.length : count;
    candidates.slice(0, n).forEach(function (d) {
      changes[d.i] = rollDie(dieSize);
    });
    return changes;
  }

  function applyNudge(current, sign, count, max, tn, dieSize) {
    var changes = new Array(current.length).fill(null);
    var indexed = current.map(function (v, i) { return { v: v, i: i }; });
    if (sign === 'pos') {
      var below = indexed.filter(function (d) { return d.v < tn; })
                         .sort(function (a, b) { return b.v - a.v; });
      if (below.length > 0) {
        var t = below[0];
        changes[t.i] = Math.min(dieSize, t.v + count);
      }
    } else {
      var above = indexed.filter(function (d) { return d.v >= tn && d.v !== dieSize; })
                         .sort(function (a, b) { return a.v - b.v; });
      if (above.length > 0) {
        var u = above[0];
        changes[u.i] = Math.max(1, u.v - count);
      }
    }
    return changes;
  }

  function mergeChanges(current, changes) {
    return current.map(function (v, i) {
      return changes[i] === null || changes[i] === undefined ? v : changes[i];
    });
  }

  function dieClass(value, tn, dieSize) {
    if (value === null || value === undefined) return 'empty';
    if (value === 1) return 'fail';
    if (value === dieSize) return 'crit';
    if (value >= tn) return 'success';
    return 'neutral';
  }

  function renderDice(values, tn, dieSize) {
    if (!values || values.length === 0) {
      return '<span class="dice-placeholder">[ &mdash; ]</span>';
    }
    var inner = values.map(function (v) {
      if (v === null || v === undefined) {
        return '<span class="die empty">&nbsp;</span>';
      }
      return '<span class="die ' + dieClass(v, tn, dieSize) + '">' + v + '</span>';
    }).join(', ');
    return '[ ' + inner + ' ]';
  }

  function rollGroup(group) {
    var config = JSON.parse(group.dataset.config);
    var dieSize = config.die_size;
    var tn = config.tn;

    var initial = rollDice(config.dice_count, dieSize);
    var current = initial.slice();

    var initialCell = group.querySelector('.row-initial .dice-cell');
    if (initialCell) initialCell.innerHTML = renderDice(initial, tn, dieSize);

    if (config.reroll) {
      var rerollChanges = applyReroll(
        current, config.reroll.sign, config.reroll.count,
        config.reroll.max, tn, dieSize
      );
      current = mergeChanges(current, rerollChanges);
      var rerollCell = group.querySelector('.row-reroll .dice-cell');
      if (rerollCell) rerollCell.innerHTML = renderDice(rerollChanges, tn, dieSize);
    }
    if (config.nudge) {
      var nudgeChanges = applyNudge(
        current, config.nudge.sign, config.nudge.count,
        config.nudge.max, tn, dieSize
      );
      current = mergeChanges(current, nudgeChanges);
      var nudgeCell = group.querySelector('.row-nudge .dice-cell');
      if (nudgeCell) nudgeCell.innerHTML = renderDice(nudgeChanges, tn, dieSize);
    }
  }

  function rollAll(wrapper) {
    wrapper.querySelectorAll('tbody.roll-group').forEach(function (group) {
      if (group.querySelector('.lock-btn.locked')) return;
      rollGroup(group);
    });
  }

  document.addEventListener('click', function (e) {
    var badge = e.target.closest('.mod-badge');
    if (badge) {
      badge.classList.add('show-tip');
      if (badge._tipTimer) clearTimeout(badge._tipTimer);
      badge._tipTimer = setTimeout(function () {
        badge.classList.remove('show-tip');
      }, 3000);
      return;
    }

    var rollBtn = e.target.closest('.btn-roll-all');
    if (rollBtn) {
      var wrapper = rollBtn.closest('.rolls-wrapper');
      if (wrapper) rollAll(wrapper);
      return;
    }

    if (e.target.closest('.btn-confirm-all')) {
      // No-op: parent stubs capture the output.
      return;
    }

    var lockBtn = e.target.closest('.lock-btn');
    if (lockBtn) {
      lockBtn.classList.toggle('locked');
      return;
    }

    var rollSaveBtn = e.target.closest('.btn-roll-save');
    if (rollSaveBtn) {
      // Stub: surface a placeholder DoIS in the Successes override.
      // A real wiring would call the server to roll via Dice Resolution.
      var row = rollSaveBtn.closest('.affliction-save-row');
      if (row) {
        var input = row.querySelector('.successes-input');
        if (input) input.value = Math.max(0, Math.floor(Math.random() * 4));
      }
      return;
    }
  });
})();
