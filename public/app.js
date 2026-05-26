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
    var rerolledMask = new Array(initial.length).fill(false);

    var initialCell = group.querySelector('.row-initial .dice-cell');
    if (initialCell) initialCell.innerHTML = renderDice(initial, tn, dieSize);

    if (config.reroll) {
      var rerollChanges = applyReroll(
        current, config.reroll.sign, config.reroll.count,
        config.reroll.max, tn, dieSize, rerolledMask
      );
      current = mergeChanges(current, rerollChanges);
      var rerollCell = group.querySelector('.row-reroll .dice-cell');
      if (rerollCell) rerollCell.innerHTML = renderDice(rerollChanges, tn, dieSize);
    }
    if (config.mass_reroll) {
      var massChanges = applyReroll(
        current, config.mass_reroll.sign, 0, true, tn, dieSize, rerolledMask
      );
      current = mergeChanges(current, massChanges);
      var massCell = group.querySelector('.row-mass-reroll .dice-cell');
      if (massCell) massCell.innerHTML = renderDice(massChanges, tn, dieSize);
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

    // DoIS = (successes ≥ TN) − (failures = 1). A crit (rolled value
    // equals die size) counts as TWO successes. The DM can override
    // either input afterwards.
    var dois = 0;
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
