// Shared behaviour for the reusable roll_stub partial.
//
// Each rendered stub registers its configuration in window.rollStubConfigs
// under its unique stub id. The Roll button POSTs to /roll_stub/roll; the
// server rolls the original dice, freezes them under a token in the
// session, and returns the original plus a nullable `changes` array
// (positions that have been modified on the server's working copy).
//
// Luck buttons POST /roll_stub/reroll with a signed reroll_count; insight
// buttons POST /roll_stub/nudge with a signed nudge_amount. Each click
// re-rolls/re-nudges against the current working copy, so pressing a
// button repeatedly keeps searching for a result the DM likes. The
// original "Rolled:" row never changes; only the "Modified:" row and the
// success total update.
//
// The Confirm button does not submit anything by itself — instead it
// dispatches a `rollstub:confirm` CustomEvent on the stub's root element.
// Parent stubs that embed this one listen for that event and capture the
// success value from event.detail.
(function() {
  function cfg(stubId) {
    return (window.rollStubConfigs || {})[stubId];
  }

  function diceEl(stubId) {
    return document.getElementById('roll-stub-dice-' + stubId);
  }

  function inputEl(stubId) {
    return document.getElementById('roll-stub-input-' + stubId);
  }

  function rootEl(stubId) {
    return document.querySelector('[data-stub-id="' + stubId + '"]');
  }

  function modButtons(stubId) {
    var root = rootEl(stubId);
    if (!root) return [];
    return root.querySelectorAll('.roll-stub-mod');
  }

  function setModsEnabled(stubId, enabled) {
    modButtons(stubId).forEach(function(btn) { btn.disabled = !enabled; });
  }

  function formatOutcome(successes) {
    if (successes >= 0) {
      return successes + ' success' + (successes === 1 ? '' : 'es');
    }
    var failures = -successes;
    return failures + ' failure' + (failures === 1 ? '' : 's');
  }

  function dieSpan(value, tn, dieSize) {
    var cls = 'die';
    if (value === dieSize) cls += ' die-crit';
    else if (value === 1) cls += ' die-fumble';
    else if (value >= tn) cls += ' die-success';
    else cls += ' die-miss';
    return '<span class="' + cls + '">' + value + '</span>';
  }

  // Placeholder for a position that has not been modified since the
  // initial roll. Keeps positional alignment with the original row.
  function dieBlank() {
    return '<span class="die die-blank">&nbsp;</span>';
  }

  function joinDice(pieces) {
    return '[' + pieces.join(', ') + ']';
  }

  // Render the ordered row stack returned by the server. Row 0 shows
  // every die; each subsequent row shows only the positions that
  // differ from the row directly above, with unchanged positions as
  // transparent placeholders so the columns stay aligned. The
  // "→ N successes" summary lives on the bottom row. Starting value
  // annotation is no longer rendered here — the stub's header already
  // shows it up-front.
  function renderRows(stubId, rows, tn, dieSize, successes) {
    var el = diceEl(stubId);
    if (!el) return;
    var html = '';
    rows.forEach(function(row, idx) {
      var prev = idx === 0 ? null : rows[idx - 1].dice;
      var pieces = row.dice.map(function(d, i) {
        if (prev !== null && d === prev[i]) return dieBlank();
        return dieSpan(d, tn, dieSize);
      });
      var isLast = idx === rows.length - 1;
      html += '<div class="roll-line">' +
        '<span class="roll-label">' + row.label + ':</span> ' +
        joinDice(pieces);
      if (isLast) html += ' → ' + formatOutcome(successes);
      html += '</div>';
    });
    el.innerHTML = html;
  }

  function applyResult(stubId, data) {
    var c = cfg(stubId);
    if (!c) return;
    c.token = data.token;
    var input = inputEl(stubId);
    if (input) input.value = data.successes;
    renderRows(stubId, data.rows, data.tn, 10, data.successes);
    setModsEnabled(stubId, !!c.token);
  }

  function postForm(url, params) {
    var body = new URLSearchParams();
    Object.keys(params).forEach(function(k) { body.append(k, params[k]); });
    return fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    }).then(function(r) {
      if (!r.ok) throw new Error('request failed: ' + r.status);
      return r.json();
    });
  }

  window.rollStubRoll = function(stubId) {
    var c = cfg(stubId);
    if (!c) return;
    postForm('/roll_stub/roll', {
      dice_count: c.diceCount,
      tn: c.tn,
      starting_value: c.startingValue
    }).then(function(data) { applyResult(stubId, data); });
  };

  window.rollStubReroll = function(stubId, rerollCount) {
    var c = cfg(stubId);
    if (!c || !c.token) return;
    postForm('/roll_stub/reroll', {
      token: c.token,
      reroll_count: rerollCount
    }).then(function(data) { applyResult(stubId, data); });
  };

  window.rollStubNudge = function(stubId, nudgeAmount) {
    var c = cfg(stubId);
    if (!c || !c.token) return;
    postForm('/roll_stub/nudge', {
      token: c.token,
      nudge_amount: nudgeAmount
    }).then(function(data) { applyResult(stubId, data); });
  };

  window.rollStubConfirm = function(stubId) {
    var root = rootEl(stubId);
    var input = inputEl(stubId);
    if (!root || !input) return;
    root.dispatchEvent(new CustomEvent('rollstub:confirm', {
      bubbles: true,
      detail: { stubId: stubId, value: input.value }
    }));
  };
})();
