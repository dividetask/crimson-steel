// Shared behaviour for the reusable roll_stub partial.
//
// Two buttons drive each stub: "Roll" rolls fresh dice and immediately
// chains the configured luck reroll and insight nudge so the player
// sees the final adjusted result in one click; "Reroll Luck" only
// re-applies luck (against the original dice) and re-applies insight
// on top, since insight depends on whatever row is above it.
//
// The rendered layout has three slots — Initial, Luck, Insight — each
// living in its own dedicated cell. The server returns the rows in
// canonical order; we route each one to its slot by label and clear
// any slot the server omitted.
//
// Confirm dispatches a `rollstub:confirm` CustomEvent on the stub
// root; detail.successes and detail.criticals come from the editable
// inputs so the DM can override the computed values before handing
// them off to the embedding feature.
(function() {
  // Look up (and lazily hydrate) a stub's config. The partial encodes
  // the per-stub settings into a data-config attribute on the <tr>
  // root rather than emitting an inline <script>, so the row can live
  // inside a parent <table> without HTML5 foster-parenting moving the
  // script tag elsewhere in the DOM.
  function cfg(stubId) {
    window.rollStubConfigs = window.rollStubConfigs || {};
    var c = window.rollStubConfigs[stubId];
    if (c) return c;
    var el = rootEl(stubId);
    if (!el) return null;
    var raw = el.getAttribute('data-config');
    if (!raw) return null;
    try { c = JSON.parse(raw); } catch (e) { return null; }
    window.rollStubConfigs[stubId] = c;
    return c;
  }

  function rootEl(stubId) {
    return document.querySelector('.roll-stub[data-stub-id="' + stubId + '"]');
  }

  function slotEl(stubId, label) {
    return document.getElementById('roll-stub-row-' + label + '-' + stubId);
  }

  function resultEl(stubId) {
    return document.getElementById('roll-stub-result-' + stubId);
  }

  function critsEl(stubId) {
    return document.getElementById('roll-stub-crits-' + stubId);
  }

  function rerollButton(stubId) {
    return document.getElementById('roll-stub-reroll-luck-' + stubId);
  }

  function dieSpan(value, tn, dieSize) {
    var cls = 'die';
    if (value === dieSize) cls += ' die-crit';
    else if (value === 1) cls += ' die-fumble';
    else if (value >= tn) cls += ' die-success';
    else cls += ' die-miss';
    return '<span class="' + cls + '">' + value + '</span>';
  }

  // Same-width transparent placeholder so unchanged positions in
  // Luck/Insight rows line up under the Initial dice.
  function dieBlank() {
    return '<span class="die die-blank">&nbsp;</span>';
  }

  function renderDice(dice, prev, tn) {
    var pieces = dice.map(function(d, i) {
      if (prev && d === prev[i]) return dieBlank();
      return dieSpan(d, tn, 10);
    });
    return '[' + pieces.join(', ') + ']';
  }

  function applyResult(stubId, data) {
    var c = cfg(stubId);
    if (!c) return;
    c.token = data.token;

    var byLabel = {};
    data.rows.forEach(function(r) { byLabel[r.label.toLowerCase()] = r.dice; });

    var initialDice = byLabel.initial || null;
    var luckDice    = byLabel.luck    || null;
    var insightDice = byLabel.insight || null;

    var initialSlot = slotEl(stubId, 'initial');
    if (initialSlot) {
      initialSlot.innerHTML = initialDice ? renderDice(initialDice, null, data.tn) : '';
    }

    var luckSlot = slotEl(stubId, 'luck');
    if (luckSlot) {
      luckSlot.innerHTML = luckDice ? renderDice(luckDice, initialDice, data.tn) : '';
    }

    var insightSlot = slotEl(stubId, 'insight');
    if (insightSlot) {
      var insightPrev = luckDice || initialDice;
      insightSlot.innerHTML = insightDice ? renderDice(insightDice, insightPrev, data.tn) : '';
    }

    var result = resultEl(stubId);
    if (result) result.value = data.successes;
    var crits = critsEl(stubId);
    if (crits) crits.value = data.criticals;

    var rb = rerollButton(stubId);
    if (rb) rb.disabled = !c.token;
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

  // After the initial roll (or a luck reroll) we chain the configured
  // luck/insight follow-ups so the displayed dice reflect every
  // adjustment the stub knows about. Each promise resolves to the
  // server's response payload, which carries the token forward.
  function chainLuck(c, data) {
    if (c.luckAmount === 0) return Promise.resolve(data);
    return postForm('/roll_stub/reroll', {
      token: data.token,
      reroll_count: c.luckAmount
    });
  }

  function chainInsight(c, data) {
    if (c.insightAmount === 0) return Promise.resolve(data);
    return postForm('/roll_stub/nudge', {
      token: data.token,
      nudge_amount: c.insightAmount
    });
  }

  window.rollStubRoll = function(stubId) {
    var c = cfg(stubId);
    if (!c) return;
    return postForm('/roll_stub/roll', {
      dice_count: c.diceCount,
      tn: c.tn,
      starting_value: c.startingValue
    })
      .then(function(d) { return chainLuck(c, d); })
      .then(function(d) { return chainInsight(c, d); })
      .then(function(d) { applyResult(stubId, d); });
  };

  window.rollStubRerollLuck = function(stubId) {
    var c = cfg(stubId);
    if (!c || !c.token) return;
    return postForm('/roll_stub/reroll', {
      token: c.token,
      reroll_count: c.luckAmount
    })
      .then(function(d) { return chainInsight(c, d); })
      .then(function(d) { applyResult(stubId, d); });
  };

  window.rollStubConfirm = function(stubId) {
    var root = rootEl(stubId);
    if (!root) return;
    var result = resultEl(stubId);
    var crits = critsEl(stubId);
    root.dispatchEvent(new CustomEvent('rollstub:confirm', {
      bubbles: true,
      detail: {
        stubId: stubId,
        successes: result ? parseInt(result.value, 10) : null,
        criticals: crits ? parseInt(crits.value, 10) : null
      }
    }));
  };
})();
