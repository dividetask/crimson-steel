// Client-side behaviour for the multi_roll_stub partial. Each row drives
// the same /roll_stub/{roll,reroll} endpoints used by the single-roll
// stub -- we keep one session token per row in the local config. The
// top-level Roll All button rolls every row that hasn't been rolled
// yet; per-row buttons roll/reroll just that row. Confirm All
// dispatches `multiroll:confirm` on the stub root with the per-row
// success counts so the parent stub (e.g. melee_attack_stub) can pick
// up where it left off.
(function() {
  function cfg(stubId) { return (window.multiRollConfigs || {})[stubId]; }

  function rootEl(stubId) {
    return document.querySelector('.multi-roll-stub[data-stub-id="' + stubId + '"]');
  }

  function rowOf(stubId, rowId) {
    var c = cfg(stubId);
    if (!c) return null;
    for (var i = 0; i < c.rows.length; i++) if (c.rows[i].rowId === rowId) return c.rows[i];
    return null;
  }

  function diceCell(rowId)   { return document.getElementById('multi-roll-dice-' + rowId); }
  function resultCell(rowId) { return document.getElementById('multi-roll-result-' + rowId); }

  function dieSpan(value, tn, dieSize) {
    var cls = 'die';
    if (value === dieSize) cls += ' die-crit';
    else if (value === 1)  cls += ' die-fumble';
    else if (value >= tn)  cls += ' die-success';
    else                   cls += ' die-miss';
    return '<span class="' + cls + '">' + value + '</span>';
  }

  function dieBlank() { return '<span class="die die-blank">&nbsp;</span>'; }

  function renderRows(rowId, data) {
    var el = diceCell(rowId);
    if (!el) return;
    var html = '';
    data.rows.forEach(function(row, idx) {
      var prev = idx === 0 ? null : data.rows[idx - 1].dice;
      var pieces = row.dice.map(function(d, i) {
        if (prev !== null && d === prev[i]) return dieBlank();
        return dieSpan(d, data.tn, 10);
      });
      html += '<div class="roll-line">' +
              '<span class="roll-label">' + row.label + ':</span> [' +
              pieces.join(', ') + ']</div>';
    });
    el.innerHTML = html;
  }

  function applyResult(stubId, rowId, data) {
    var row = rowOf(stubId, rowId);
    if (!row) return;
    row.token = data.token;
    row.successes = data.successes;
    row.criticals = data.criticals;
    renderRows(rowId, data);
    var rcell = resultCell(rowId);
    if (rcell) {
      var text = data.successes >= 0
        ? data.successes + ' success' + (data.successes === 1 ? '' : 'es')
        : (-data.successes) + ' failure' + (-data.successes === 1 ? '' : 's');
      if (data.criticals > 0) text += ' (' + data.criticals + ' crit)';
      rcell.textContent = text;
    }
    var tr = document.querySelector('[data-row-id="' + rowId + '"]');
    if (tr) {
      tr.querySelectorAll('.multi-roll-row-luck').forEach(function(b) { b.disabled = !row.token; });
    }
  }

  function postForm(url, params) {
    var body = new URLSearchParams();
    Object.keys(params).forEach(function(k) { body.append(k, params[k]); });
    return fetch(url, {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body.toString()
    }).then(function(r) {
      if (!r.ok) throw new Error('request failed: ' + r.status);
      return r.json();
    });
  }

  window.multiRollRow = function(stubId, rowId) {
    var row = rowOf(stubId, rowId);
    if (!row) return;
    postForm('/roll_stub/roll', {
      dice_count: row.diceCount, tn: row.tn, starting_value: row.startingValue
    }).then(function(data) { applyResult(stubId, rowId, data); });
  };

  window.multiRollReroll = function(stubId, rowId, count) {
    var row = rowOf(stubId, rowId);
    if (!row || !row.token) return;
    postForm('/roll_stub/reroll', { token: row.token, reroll_count: count })
      .then(function(data) { applyResult(stubId, rowId, data); });
  };

  // Roll every row -- including ones already rolled. Each click of
  // Roll All produces a fresh result for every row so the DM can keep
  // searching for one they like without manually clicking each Roll.
  window.multiRollRollAll = function(stubId) {
    var c = cfg(stubId);
    if (!c) return;
    c.rows.forEach(function(row) {
      window.multiRollRow(stubId, row.rowId);
    });
  };

  window.multiRollConfirm = function(stubId) {
    var c = cfg(stubId);
    var root = rootEl(stubId);
    if (!c || !root) return;
    root.dispatchEvent(new CustomEvent('multiroll:confirm', {
      bubbles: true,
      detail: {
        stubId: stubId,
        rows: c.rows.map(function(r) {
          return {
            key: r.key, label: r.label,
            diceCount: r.diceCount, tn: r.tn,
            successes: r.successes, criticals: r.criticals
          };
        })
      }
    }));
  };
})();
