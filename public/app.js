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

  function applyReroll(current, sign, count, max, tn, dieSize, rerolledMask) {
    var changes = new Array(current.length).fill(null);
    var indexed = current.map(function (v, i) { return { v: v, i: i }; });
    var candidates;
    if (sign === 'pos') {
      candidates = indexed.filter(function (d) { return d.v < tn && !(rerolledMask && rerolledMask[d.i]); })
                          .sort(function (a, b) { return a.v - b.v; });
    } else {
      candidates = indexed.filter(function (d) { return d.v >= tn && !(rerolledMask && rerolledMask[d.i]); })
                          .sort(function (a, b) { return b.v - a.v; });
    }
    var n = max ? candidates.length : count;
    candidates.slice(0, n).forEach(function (d) {
      changes[d.i] = rollDie(dieSize);
      if (rerolledMask) rerolledMask[d.i] = true;
    });
    return changes;
  }

  // Nudge targeting (Standard mode).
  //
  // Score every die by the contribution change the nudge would
  // produce — post-shift values clamp to [1, Die Size] — then pick
  // the highest-value candidate in this priority order:
  //
  //   1. Largest absolute change in DoIS contribution (Fail → non-
  //      Fail, Neutral → Success / Crit, Success → Crit; or the
  //      reverse for a negative nudge).
  //   2. Tiebreak: largest absolute change in critical_count.
  //      This makes "Success → Crit" win over "Neutral → Success"
  //      when their DoIS deltas tie (both +1 on the standard scoring,
  //      but Success → Crit also adds to critical_count). Negative
  //      nudges prefer removing a Crit on the same tiebreak.
  //   3. Tiebreak: the die that started lowest (positive nudge) or
  //      highest (negative nudge) wins — per the standard-mode rule
  //      in dice_resolution_design.md.
  //   4. Tiebreak: lowest index.
  //
  // Rerolled dice are normal candidates (the rerolled value is just
  // the current value). The only no-op is when every die is already
  // at the sign's extreme — Die Size for positive, 1 for negative.
  function applyNudge(current, sign, count, max, tn, dieSize) {
    var changes = new Array(current.length).fill(null);

    function contribution(v) {
      if (v === 1) return -1;
      if (v === dieSize) return 2;
      if (v >= tn) return 1;
      return 0;
    }

    var shift = sign === 'pos' ? count : -count;
    var extreme = sign === 'pos' ? dieSize : 1;

    if (current.every(function (v) { return v === extreme; })) {
      return changes;
    }

    var candidates = current.map(function (v, i) {
      var newV = Math.max(1, Math.min(dieSize, v + shift));
      var doisDelta = contribution(newV) - contribution(v);
      var critDelta = (newV === dieSize ? 1 : 0) - (v === dieSize ? 1 : 0);
      return { v: v, i: i, newV: newV, doisDelta: doisDelta, critDelta: critDelta };
    });

    if (sign === 'pos') {
      candidates.sort(function (a, b) {
        if (b.doisDelta !== a.doisDelta) return b.doisDelta - a.doisDelta;
        if (b.critDelta !== a.critDelta) return b.critDelta - a.critDelta;
        if (a.v !== b.v) return a.v - b.v;
        return a.i - b.i;
      });
    } else {
      candidates.sort(function (a, b) {
        if (a.doisDelta !== b.doisDelta) return a.doisDelta - b.doisDelta;
        if (a.critDelta !== b.critDelta) return a.critDelta - b.critDelta;
        if (a.v !== b.v) return b.v - a.v;
        return a.i - b.i;
      });
    }

    var target = candidates[0];
    changes[target.i] = target.newV;
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

  // Starting Successes / Failures render as small filled squares
  // before the rolled dice on the *initial* row. Modifier rows
  // (reroll / mass_reroll / nudge) reserve the same horizontal
  // space via invisible spacers so each die column stays aligned
  // with the initial row above it — without the spacers, position N
  // in a modifier row would land under position N − |starting_value|
  // of the initial row.
  function renderStartingSquares(startingValue, mode) {
    if (!startingValue) return '';
    var abs = Math.abs(startingValue);
    var cls = startingValue > 0 ? 'success' : 'fail';
    var spacer = mode === 'spacer' ? ' starting-spacer' : '';
    var out = '';
    for (var i = 0; i < abs; i++) {
      out += '<span class="die ' + cls + ' starting-die' + spacer + '">&nbsp;</span>';
    }
    return out + ' ';
  }

  // `startingValue` is optional; pass a non-zero value on every row
  // of a Roll that carries one. `mode` is 'shown' on the initial row
  // (squares render in color) and 'spacer' on modifier rows (squares
  // take width but are invisible).
  function renderDice(values, tn, dieSize, startingValue, mode) {
    var starting = renderStartingSquares(startingValue, mode || 'shown');
    if (!values || values.length === 0) {
      return '<span class="dice-placeholder">[ ' + starting + '&mdash; ]</span>';
    }
    var inner = values.map(function (v) {
      if (v === null || v === undefined) {
        return '<span class="die empty">&nbsp;</span>';
      }
      return '<span class="die ' + dieClass(v, tn, dieSize) + '">' + v + '</span>';
    }).join(', ');
    return '[ ' + starting + inner + ' ]';
  }

  function rollGroup(group) {
    var config = JSON.parse(group.dataset.config);
    var dieSize = config.die_size;
    var tn = config.tn;
    var startingValue = parseInt(config.starting_value, 10) || 0;

    var initial = rollDice(config.dice_count, dieSize);
    var current = initial.slice();
    var rerolledMask = new Array(initial.length).fill(false);

    var initialCell = group.querySelector('.row-initial .dice-cell');
    if (initialCell) initialCell.innerHTML = renderDice(initial, tn, dieSize, startingValue);

    if (config.reroll) {
      var rerollChanges = applyReroll(
        current, config.reroll.sign, config.reroll.count,
        config.reroll.max, tn, dieSize, rerolledMask
      );
      current = mergeChanges(current, rerollChanges);
      var rerollCell = group.querySelector('.row-reroll .dice-cell');
      if (rerollCell) rerollCell.innerHTML = renderDice(rerollChanges, tn, dieSize, startingValue, 'spacer');
    }
    if (config.mass_reroll) {
      var massChanges = applyReroll(
        current, config.mass_reroll.sign, 0, true, tn, dieSize, rerolledMask
      );
      current = mergeChanges(current, massChanges);
      var massCell = group.querySelector('.row-mass-reroll .dice-cell');
      if (massCell) massCell.innerHTML = renderDice(massChanges, tn, dieSize, startingValue, 'spacer');
    }
    if (config.nudge) {
      var nudgeChanges = applyNudge(
        current, config.nudge.sign, config.nudge.count,
        config.nudge.max, tn, dieSize
      );
      current = mergeChanges(current, nudgeChanges);
      var nudgeCell = group.querySelector('.row-nudge .dice-cell');
      if (nudgeCell) nudgeCell.innerHTML = renderDice(nudgeChanges, tn, dieSize, startingValue, 'spacer');
    }

    // DoIS = starting_value + (successes ≥ TN) − (failures = 1). A
    // crit (rolled value equals die size) counts as TWO successes.
    // The DM can override either input afterwards.
    var dois = startingValue;
    var crits = 0;
    current.forEach(function (v) {
      if (v == null) return;
      if (v === 1) {
        dois -= 1;
      } else if (v === dieSize) {
        dois += 2;
        crits += 1;
      } else if (v >= tn) {
        dois += 1;
      }
    });
    var inputs = group.querySelectorAll('.result-input');
    if (inputs[0]) {
      inputs[0].value = dois;
      inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
    }
    if (inputs[1]) inputs[1].value = crits;
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
      var save = e.target.closest('.save-resolution');
      if (save) {
        handleConfirmAllInSave(save);
      }
      return;
    }

    var confirmBtn = e.target.closest('.btn-confirm');
    if (confirmBtn) {
      var wrap = confirmBtn.closest('.rolls-wrapper');
      if (wrap) collapseRollsWrapper(wrap);
      return;
    }

    var changeBtn = e.target.closest('.btn-rolls-change');
    if (changeBtn) {
      var wrap2 = changeBtn.closest('.rolls-wrapper');
      if (wrap2) expandRollsWrapper(wrap2);
      return;
    }

    var lockBtn = e.target.closest('.lock-btn');
    if (lockBtn) {
      lockBtn.classList.toggle('locked');
      return;
    }

    var modBtn = e.target.closest('.cr-mod-btn');
    if (modBtn) {
      handleModClick(modBtn);
      return;
    }

    var stepNone = e.target.closest('.cr-step-none');
    if (stepNone) {
      handleStepNone(stepNone);
      return;
    }

    var stepChange = e.target.closest('.cr-step-change');
    if (stepChange) {
      handleStepChange(stepChange);
      return;
    }

    var saveConfirm = e.target.closest('.btn-save-confirm');
    if (saveConfirm) {
      handleSaveConfirm(saveConfirm);
      return;
    }
  });

  // === Save Resolution / Builder step machine ===

  // The save-resolution wrapper hosts a chain of step-controls inside
  // `.rolls-actions`. One step is active at a time. Below the header
  // sits a stack of step-summaries (one per non-check step) and the
  // dice table. The table stays hidden via [data-roll-state="pending"]
  // until the check step becomes active.

  function handleModClick(btn) {
    var save = btn.closest('.save-resolution');
    if (!save) return;
    // Magnitude buttons now live in the active step's body, not the
    // header's step-controls slot. The body carries data-step too.
    var stepEl = btn.closest('.step-body') || btn.closest('.step-controls');
    if (!stepEl) return;
    var kind = stepEl.dataset.step;
    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      applyRollModifier(btn);
    }
    var label = btn.dataset.label || '';
    var signLabel = btn.textContent.trim();
    completeStep(save, kind, signLabel + (label ? ' ' + label : ''));
  }

  function applyRollModifier(btn) {
    var rollIdx = parseInt(btn.dataset.rollIdx, 10);
    var kind    = btn.dataset.kind;
    var sign    = btn.dataset.sign;
    var count   = btn.dataset.count ? parseInt(btn.dataset.count, 10) : null;
    var label   = btn.dataset.label;

    var save = btn.closest('.save-resolution');
    if (!save) return;
    var groups = save.querySelectorAll('tbody.roll-group');
    var group = groups[rollIdx];
    if (!group) return;

    var cfg = JSON.parse(group.dataset.config);
    if (kind === 'mass_reroll') {
      cfg.mass_reroll = { sign: sign };
    } else {
      cfg[kind] = { sign: sign, count: count, max: false };
    }
    group.dataset.config = JSON.stringify(cfg);
    updateModBadge(group, kind, cfg[kind], label);
  }

  function clearRollModifier(save, kind) {
    save.querySelectorAll('tbody.roll-group').forEach(function (group) {
      var cfg = JSON.parse(group.dataset.config);
      cfg[kind] = null;
      group.dataset.config = JSON.stringify(cfg);
      updateModBadge(group, kind, null, '');
    });
  }

  function updateModBadge(group, kind, mod, label) {
    var rowClass = kind === 'reroll' ? '.row-reroll' :
                   kind === 'mass_reroll' ? '.row-mass-reroll' : '.row-nudge';
    var existingRow = group.querySelector(rowClass);
    if (!mod) {
      if (existingRow) existingRow.remove();
      reflowRowspan(group);
      return;
    }

    var badgeText;
    var badgeClass = kind === 'nudge' ? 'mod-nudge' : 'mod-reroll';
    var modColIdx  = kind === 'nudge' ? 1 : 0;
    var signCh = mod.sign === 'neg' ? '-' : '+';
    if (kind === 'mass_reroll') {
      badgeText = signCh + '*';
    } else {
      badgeText = signCh + mod.count;
    }

    if (existingRow) {
      var badge = existingRow.querySelector('.mod-badge');
      if (badge) {
        badge.textContent = badgeText;
        badge.setAttribute('data-tooltip', label || '');
      }
    } else {
      var tr = document.createElement('tr');
      tr.className = 'modifier-row ' + rowClass.slice(1);
      var modCellA = '<td class="mod-cell">' + (modColIdx === 0 ? '<span class="mod-badge ' + badgeClass + '" data-tooltip="' + (label || '') + '">' + badgeText + '</span>' : '') + '</td>';
      var modCellB = '<td class="mod-cell">' + (modColIdx === 1 ? '<span class="mod-badge ' + badgeClass + '" data-tooltip="' + (label || '') + '">' + badgeText + '</span>' : '') + '</td>';
      tr.innerHTML = modCellA + modCellB + '<td class="dice-cell"></td>';
      group.appendChild(tr);
    }
    reflowRowspan(group);
  }

  function completeStep(save, kind, summaryText) {
    if (!save || !kind) return;

    var ctrl = save.querySelector('.step-controls[data-step="' + kind + '"]');
    if (ctrl) ctrl.dataset.state = 'complete';
    var body = save.querySelector('.step-body[data-step="' + kind + '"]');
    if (body) body.dataset.state = 'complete';

    var summary = save.querySelector('.step-summary[data-step="' + kind + '"]');
    if (summary) {
      var v = summary.querySelector('.step-summary-value');
      if (v) v.textContent = summaryText;
      summary.hidden = false;
    }
    activateNextStep(save);
  }

  // === Roll Resolution collapse / expand ===

  function collapseRollsWrapper(wrapper) {
    var table = wrapper.querySelector(':scope > .roll-table') || wrapper.querySelector('.roll-table');
    if (!table) return;
    var groups = table.querySelectorAll('tbody.roll-group');
    groups.forEach(function (group, idx) {
      var inputs = group.querySelectorAll('.result-input');
      var dois = inputs[0] ? inputs[0].value : '0';
      var crits = inputs[1] ? inputs[1].value : '0';
      var row = wrapper.querySelector('.rolls-result-row[data-roll-idx="' + idx + '"]');
      if (row) {
        var v = row.querySelector('.rolls-result-value');
        if (v) v.textContent = 'Successes ' + dois + ', Crits ' + crits;
      }
    });
    wrapper.dataset.state = 'collapsed';
    table.hidden = true;
    var actions = wrapper.querySelector('.rolls-actions');
    if (actions) actions.hidden = true;
    var results = wrapper.querySelector('.rolls-results');
    if (results) results.hidden = false;
  }

  function expandRollsWrapper(wrapper) {
    wrapper.dataset.state = 'active';
    var table = wrapper.querySelector('.roll-table');
    if (table) table.hidden = false;
    var actions = wrapper.querySelector('.rolls-actions');
    if (actions) actions.hidden = false;
    var results = wrapper.querySelector('.rolls-results');
    if (results) results.hidden = true;
  }

  function handleConfirmAllInSave(save) {
    var diceCtrl = save.querySelector('.step-controls[data-step="dice"]');
    if (!diceCtrl || diceCtrl.dataset.state !== 'active') return;
    var inputs = save.querySelectorAll('.step-body-dice .result-input');
    var dois = inputs.length > 0 ? inputs[0].value : '0';
    var crits = inputs.length > 1 ? inputs[1].value : '0';
    var spDois = save.querySelector('.sp-dois');
    if (spDois) spDois.value = dois;
    completeStep(save, 'dice', 'Successes: ' + dois + '   Crits: ' + crits);
    recomputePreview(save);
  }

  function handleStepNone(btn) {
    var save = btn.closest('.save-resolution');
    if (!save) return;
    var kind = btn.dataset.step;
    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      clearRollModifier(save, kind);
    }
    completeStep(save, kind, '(none)');
  }

  function handleStepChange(btn) {
    var save = btn.closest('.save-resolution');
    if (!save) return;
    var kind = btn.dataset.step;

    if (kind === 'reroll' || kind === 'mass_reroll' || kind === 'nudge') {
      clearRollModifier(save, kind);
    }

    var thisCtrl = save.querySelector('.step-controls[data-step="' + kind + '"]');
    var thisBody = save.querySelector('.step-body[data-step="' + kind + '"]');
    var thisSumm = save.querySelector('.step-summary[data-step="' + kind + '"]');
    if (thisSumm) thisSumm.hidden = true;
    if (thisCtrl) thisCtrl.dataset.state = 'active';
    if (thisBody) thisBody.dataset.state = 'active';

    var chain = save.querySelectorAll('.step-controls');
    var rewind = false;
    chain.forEach(function (el) {
      if (rewind) {
        var sk = el.dataset.step;
        el.dataset.state = 'pending';
        var body = save.querySelector('.step-body[data-step="' + sk + '"]');
        if (body) body.dataset.state = 'pending';
        var summ = save.querySelector('.step-summary[data-step="' + sk + '"]');
        if (summ) summ.hidden = true;
        if (sk === 'reroll' || sk === 'mass_reroll' || sk === 'nudge') {
          clearRollModifier(save, sk);
        }
      }
      if (el === thisCtrl) rewind = true;
    });
  }

  function activateNextStep(save) {
    if (!save) return;
    var chain = save.querySelectorAll('.step-controls');
    for (var i = 0; i < chain.length; i++) {
      var el = chain[i];
      if (el.dataset.state === 'pending') {
        el.dataset.state = 'active';
        var kind = el.dataset.step;
        var body = save.querySelector('.step-body[data-step="' + kind + '"]');
        if (body) body.dataset.state = 'active';
        return;
      }
    }
  }

  function reflowRowspan(group) {
    var rows = group.querySelectorAll('tr');
    var n = rows.length;
    var initial = group.querySelector('.row-initial');
    if (!initial) return;
    initial.querySelectorAll('td[rowspan]').forEach(function (td) {
      td.setAttribute('rowspan', n);
    });
  }

  // Recompute the Conditions Save Resolution preview after Roll All
  // populates the dice. Listens for changes to the result-input (DoIS)
  // and recomputes Net Magnitude + effect amount + Potency delta.
  function recomputePreview(save) {
    var data = JSON.parse(save.dataset.preview);
    var disp = parseInt(save.querySelector('.sp-dois').value, 10) || 0;
    var successes = Math.max(0, disp);
    var failures  = Math.max(0, -disp);

    var divisor = data.potency_divisor;
    var potencyBefore = data.potency_before;
    var magnitude = 1 + Math.floor(potencyBefore / divisor);
    var netMagnitude = Math.max(0, magnitude - successes);

    save.querySelector('.sp-net-mag').value = netMagnitude;

    var amtInput = save.querySelector('.sp-effect-amount');
    if (amtInput) {
      if (data.effect.kind === 'named_effect') {
        amtInput.value = netMagnitude > 0 ? data.effect.name : '(none)';
      } else {
        amtInput.value = netMagnitude;
      }
    }

    // Potency evolution: -floor(decay) - floor(successes*per_success)
    //                    + floor(failures*per_failure)
    var rule = data.effect;
    var tier = data.creature_tier;
    function subTier(v) {
      if (v === 'tier' || v === '"tier"') return tier <= 0 ? 0.5 : tier;
      return Number(v);
    }
    // Affliction rule overrides aren't part of preview_data; this is a
    // rough preview using defaults (1, 1, "tier"). The DM can override
    // the New Potency input directly.
    var decay    = subTier('tier');
    var perS     = 1;
    var perF     = 1;
    var delta    = -Math.floor(decay) - Math.floor(successes * perS) + Math.floor(failures * perF);
    var newPot   = Math.max(0, potencyBefore + delta);
    save.querySelector('.sp-new-potency').value = newPot;

    var btn = save.querySelector('.btn-save-confirm');
    if (btn) btn.disabled = false;
  }

  // Wire each Save Resolution stub to recompute when its DoIS input
  // changes (which Roll All updates indirectly: it populates dice, the
  // DM types DoIS or accepts the dummy default). The result-input
  // inside the embedded Check Resolution Stub is the DoIS cell. We
  // listen to changes on the table inside the Save's builder.
  document.addEventListener('change', function (e) {
    var resultInput = e.target.closest('.result-input');
    if (!resultInput) return;
    var save = e.target.closest('.save-resolution');
    if (!save) return;
    var first = save.querySelector('.result-input');
    if (first) save.querySelector('.sp-dois').value = first.value;
    recomputePreview(save);
  });


  function handleSaveConfirm(btn) {
    var save = btn.closest('.save-resolution');
    if (!save) return;
    btn.disabled = true;
  }
})();

/* === Chronicle Entry — image lightbox & text modal ===
   Image lightbox: pan with mouse drag or single-finger touch, zoom
   with the mouse wheel or two-finger pinch, double-click resets.
   Text modal: shows the full untruncated body of the clicked card,
   scrollable, mirroring the GM-only background tint from the card. */
(function () {
  function makeOverlay(extraClass) {
    var overlay = document.createElement('div');
    overlay.className = 'ce-modal ' + extraClass;
    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'ce-modal-close';
    close.setAttribute('aria-label', 'Close');
    close.innerHTML = '&times;';
    overlay.appendChild(close);

    function dismiss() {
      overlay.remove();
      document.removeEventListener('keydown', escHandler);
      document.body.classList.remove('ce-modal-open');
    }
    function escHandler(e) { if (e.key === 'Escape') dismiss(); }

    close.addEventListener('click', dismiss);
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) dismiss();
    });
    document.addEventListener('keydown', escHandler);
    document.body.classList.add('ce-modal-open');
    document.body.appendChild(overlay);
    return overlay;
  }

  function openImageLightbox(src) {
    var overlay = makeOverlay('ce-modal-image-modal');
    var stage = document.createElement('div');
    stage.className = 'ce-modal-image-stage';
    var img = document.createElement('img');
    img.src = src;
    img.alt = '';
    img.className = 'ce-modal-image';
    img.draggable = false;
    stage.appendChild(img);

    var hint = document.createElement('div');
    hint.className = 'ce-modal-image-hint';
    hint.textContent = 'Scroll or pinch to zoom · drag to pan · double-click to reset · Esc to close';
    overlay.appendChild(hint);

    overlay.insertBefore(stage, overlay.firstChild);

    var scale = 1, tx = 0, ty = 0;
    var pointers = new Map();
    var dragStart = null;
    var pinchStart = null;

    function apply() {
      img.style.transform =
        'translate(' + tx.toFixed(2) + 'px, ' + ty.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ')';
    }
    apply();

    function reset() { scale = 1; tx = 0; ty = 0; apply(); }

    stage.addEventListener('wheel', function (e) {
      e.preventDefault();
      var delta = -e.deltaY * 0.0015;
      var next = Math.max(0.1, Math.min(20, scale * (1 + delta)));
      var rect = img.getBoundingClientRect();
      var cx = e.clientX - (rect.left + rect.width / 2);
      var cy = e.clientY - (rect.top + rect.height / 2);
      tx -= cx * (next / scale - 1);
      ty -= cy * (next / scale - 1);
      scale = next;
      apply();
    }, { passive: false });

    stage.addEventListener('dblclick', reset);

    stage.addEventListener('pointerdown', function (e) {
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      stage.setPointerCapture(e.pointerId);

      if (pointers.size === 1) {
        dragStart = { x: e.clientX, y: e.clientY, tx: tx, ty: ty };
      } else if (pointers.size === 2) {
        var pts = Array.from(pointers.values());
        var dx = pts[0].x - pts[1].x;
        var dy = pts[0].y - pts[1].y;
        pinchStart = {
          dist: Math.hypot(dx, dy),
          scale: scale,
          midX: (pts[0].x + pts[1].x) / 2,
          midY: (pts[0].y + pts[1].y) / 2,
          tx: tx, ty: ty
        };
        dragStart = null;
      }
    });

    stage.addEventListener('pointermove', function (e) {
      if (!pointers.has(e.pointerId)) return;
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

      if (pointers.size === 1 && dragStart) {
        tx = dragStart.tx + (e.clientX - dragStart.x);
        ty = dragStart.ty + (e.clientY - dragStart.y);
        apply();
      } else if (pointers.size === 2 && pinchStart) {
        var pts = Array.from(pointers.values());
        var dx = pts[0].x - pts[1].x;
        var dy = pts[0].y - pts[1].y;
        var dist = Math.hypot(dx, dy);
        scale = Math.max(0.1, Math.min(20, pinchStart.scale * (dist / pinchStart.dist)));
        apply();
      }
    });

    function release(e) {
      pointers.delete(e.pointerId);
      if (pointers.size < 2) pinchStart = null;
      if (pointers.size === 0) dragStart = null;
    }
    stage.addEventListener('pointerup', release);
    stage.addEventListener('pointercancel', release);
  }

  function openTextModal(card) {
    var overlay = makeOverlay('ce-modal-text-modal');
    var stage = document.createElement('div');
    stage.className = 'ce-modal-text-stage';

    var titleEl = card.querySelector('.ce-title');
    if (titleEl) {
      var title = document.createElement('div');
      title.className = 'ce-modal-text-title ' + (titleEl.className || '');
      title.innerHTML = titleEl.innerHTML;
      stage.appendChild(title);
    }
    var bodySrc = card.querySelector('.ce-body');
    if (bodySrc) {
      var clone = bodySrc.cloneNode(true);
      clone.removeAttribute('data-text-modal');
      clone.removeAttribute('tabindex');
      clone.removeAttribute('role');
      clone.style.height = 'auto';
      clone.style.overflow = 'visible';
      clone.style.cursor = 'auto';
      clone.style.background = 'transparent';
      stage.appendChild(clone);
    }
    overlay.insertBefore(stage, overlay.firstChild);
  }

  document.addEventListener('click', function (e) {
    var img = e.target.closest('[data-lightbox="1"]');
    if (img) {
      e.preventDefault();
      var src = img.tagName === 'IMG' ? img.getAttribute('src') : img.getAttribute('href');
      openImageLightbox(src);
      return;
    }
    var body = e.target.closest('[data-text-modal="1"]');
    if (body) {
      var card = body.closest('.ce-card');
      if (card) {
        e.preventDefault();
        openTextModal(card);
      }
    }
  });

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    var body = e.target.closest && e.target.closest('[data-text-modal="1"]');
    if (!body) return;
    e.preventDefault();
    var card = body.closest('.ce-card');
    if (card) openTextModal(card);
  });

  // -- Roster Sidebar: <details> open/closed persistence ---------------
  //
  // Each group's open state lives in localStorage under
  // `cs-roster-group:<data-group-key>`. We restore on load and write
  // on toggle.
  var ROSTER_STORAGE_PREFIX = 'cs-roster-group:';

  function restoreRosterGroups() {
    var groups = document.querySelectorAll('.cs-roster-sidebar .cs-roster-group');
    groups.forEach(function (g) {
      var key = g.getAttribute('data-group-key');
      if (!key) return;
      var stored = null;
      try { stored = localStorage.getItem(ROSTER_STORAGE_PREFIX + key); } catch (e) {}
      if (stored === 'open') {
        g.setAttribute('open', '');
      } else if (stored === 'closed') {
        g.removeAttribute('open');
      }
    });
  }

  document.addEventListener('DOMContentLoaded', restoreRosterGroups);
  // Also run immediately in case the script tag is at the bottom and
  // DOMContentLoaded already fired.
  if (document.readyState === 'interactive' || document.readyState === 'complete') {
    restoreRosterGroups();
  }

  document.addEventListener('toggle', function (e) {
    var g = e.target;
    if (!g.classList || !g.classList.contains('cs-roster-group')) return;
    var key = g.getAttribute('data-group-key');
    if (!key) return;
    try {
      localStorage.setItem(ROSTER_STORAGE_PREFIX + key, g.open ? 'open' : 'closed');
    } catch (e2) { /* localStorage unavailable */ }
  }, true);

  // -- Roster Sidebar: Player Active/Absent toggle ---------------------
  //
  // creatures_roster_sidebar_stub.md: Players have a single toggle
  // instead of +/- buttons. Click flips the state visually; persistence
  // wiring is out of scope until the Combat / Players-domain UI lands.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-player-toggle');
    if (!btn) return;
    var nowActive = btn.classList.contains('cs-player-active');
    if (nowActive) {
      btn.classList.remove('cs-player-active');
      btn.classList.add('cs-player-absent');
      btn.textContent = 'Absent';
      btn.setAttribute('aria-pressed', 'false');
      btn.title = 'Mark active';
      var row = btn.closest('.cs-roster-row');
      if (row) row.classList.add('cs-player-absent');
    } else {
      btn.classList.remove('cs-player-absent');
      btn.classList.add('cs-player-active');
      btn.textContent = 'Active';
      btn.setAttribute('aria-pressed', 'true');
      btn.title = 'Mark absent';
      var row2 = btn.closest('.cs-roster-row');
      if (row2) row2.classList.remove('cs-player-absent');
    }
  });

  // -- Encounter Roll Result panel -------------------------------------
  //
  // creatures_random_encounter_roll_result_stub.md: clicking the Roll button
  // on a sidebar Random Encounter Table row OR on the result panel itself
  // fetches a fresh roll and replaces the panel above the main sheet.
  // Combat / enemy-data-file side effects are not yet wired — the
  // server returns sample roll data and the panel just renders it.
  function fetchEncounterRoll(tableId) {
    var slot = document.getElementById('random-encounter-roll-result');
    if (!slot) return;
    fetch('/random_encounters/roll/' + encodeURIComponent(tableId), {
      headers: { 'Accept': 'text/html' }
    })
      .then(function (r) { return r.text(); })
      .then(function (html) { slot.innerHTML = html; })
      .catch(function () { /* leave previous panel in place */ });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-random-encounter-roll-btn');
    if (!btn) return;
    e.preventDefault();
    var tableId = btn.getAttribute('data-table-id');
    if (!tableId) return;
    fetchEncounterRoll(tableId);
  });
})();
