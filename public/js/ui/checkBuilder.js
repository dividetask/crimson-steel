// Check Resolution Builder (check_resolution_builder_stub.md).
//
// A domain-agnostic, parameter-driven wizard. The host precomputes a full
// "builder" blob (rolls + ordered steps, each option carrying a patch that
// mutates the embedded Rolls) and renders this stub; the builder runs the
// entire flow client-side — it never calls back into the host — and emits a
// single `check:confirmed` CustomEvent carrying the picked choices and the
// resolved per-Roll Successes. The host listens for that and acts on it.
//
// Blob shape (read from the `.check-builder` element's data-builder):
//   { title, stub_id,
//     rolls: [ { id, side, creature_name, roll_name, die_size, tn,
//                starting_value, dice_count, excluded? } ],
//     steps: [ { key, label,
//                options?: [opt],                 // static options
//                options_by?: [stepKey,...],      // choice-dependent options
//                options_map?: { "k1|k2": [opt] } // keyed by prior choices' `key`
//              } ] }
//   opt = { value, label, key?, group?, disabled?, patch }
//   patch = { set_dice:[{id,count}], set_tn:[{id,tn,starting_value}],
//             set_name:[{id,creature_name?,roll_name?}],
//             set_excluded:[{id,excluded}],
//             set_reroll:[{id,sign,count,label}|{id,clear:true}],
//             set_nudge:[{id,sign,count,label}|{id,clear:true}] }
//
// The dice table itself (and Roll All / Confirm All) is the standard Check
// Resolution Stub; this builder only drives the steps above it, then reveals
// it. Roll All / Confirm All are handled by the shared RollController /
// RollsWrapper already wired at the document level.
export class CheckBuilder {
  static ensureLoaded(root) {
    if (!root || root.dataset.cbLoaded) return;
    root.dataset.cbLoaded = '1';
    let blob;
    try { blob = JSON.parse(root.dataset.builder); } catch (e) { return; }

    root._cb = {
      blob,
      steps: blob.steps || [],
      choices: {},     // stepKey -> { value, label, key }
      index: 0         // index into the visible step sequence
    };
    CheckBuilder._bind(root);
    CheckBuilder._activate(root);
  }

  static _bind(root) {
    root.addEventListener('click', (e) => {
      const opt = e.target.closest && e.target.closest('.cb-opt');
      if (opt && root.contains(opt) && !opt.disabled) { CheckBuilder._pick(root, opt); return; }
      const chg = e.target.closest && e.target.closest('.cb-change');
      if (chg && root.contains(chg)) { CheckBuilder._change(root, chg.dataset.step); return; }
    });
    // The shared Confirm collapses the dice table; we surface the result the
    // moment it does, reading the per-Roll values out of the table.
    root.addEventListener('click', (e) => {
      if (e.target.closest && e.target.closest('.btn-confirm')) CheckBuilder._confirm(root);
    });
  }

  // ----- step lifecycle -----

  // Resolve the option list for a step given the choices made so far. A
  // step with no resolvable options (empty list) is skipped silently.
  static _optionsFor(root, step) {
    if (step.options) return step.options;
    if (step.options_by && step.options_map) {
      const key = step.options_by.map((k) => (root._cb.choices[k] ? root._cb.choices[k].key : '')).join('|');
      return step.options_map[key] || [];
    }
    return [];
  }

  // Show the first not-yet-complete step that has options; if none remain,
  // reveal the dice table + Roll All / Confirm All.
  static _activate(root) {
    const cb = root._cb;
    while (cb.index < cb.steps.length) {
      const step = cb.steps[cb.index];
      const opts = CheckBuilder._optionsFor(root, step);
      if (opts.length === 0) { cb.index++; continue; }   // skip empty step
      CheckBuilder._renderStep(root, step, opts);
      return;
    }
    CheckBuilder._renderReady(root);
  }

  static _pick(root, optEl) {
    const cb = root._cb;
    const step = cb.steps[cb.index];
    const opts = CheckBuilder._optionsFor(root, step);
    const opt = opts.find((o) => String(o.value) === optEl.dataset.value);
    if (!opt) return;
    cb.choices[step.key] = { value: opt.value, label: opt.label, key: opt.key != null ? opt.key : opt.value };
    CheckBuilder._applyPatch(root, opt.patch);
    CheckBuilder._summarize(root, step, optEl.dataset.summary || stripTags(opt.label));
    cb.index++;
    CheckBuilder._activate(root);
  }

  // Re-open a completed step; rewind every later step (clear their choices
  // and summaries) so the DM re-walks from here, and re-collapse the table.
  static _change(root, stepKey) {
    const cb = root._cb;
    const target = cb.steps.findIndex((s) => s.key === stepKey);
    if (target < 0) return;
    for (let i = target; i < cb.steps.length; i++) {
      delete cb.choices[cb.steps[i].key];
      const sum = root.querySelector('.cb-summary[data-step="' + cb.steps[i].key + '"]');
      if (sum) sum.remove();
    }
    RollsWrapperExpand(root);
    cb.index = target;
    CheckBuilder._activate(root);
  }

  // ----- patch application (mutates the embedded roll-groups) -----

  static _applyPatch(root, patch) {
    if (!patch) return;
    (patch.set_dice || []).forEach((p) => CheckBuilder._mutateConfig(root, p.id, (c) => { c.dice_count = p.count; }));
    (patch.set_tn || []).forEach((p) => CheckBuilder._mutateConfig(root, p.id, (c) => {
      c.tn = p.tn; if (p.starting_value != null) c.starting_value = p.starting_value;
    }));
    (patch.set_reroll || []).forEach((p) => CheckBuilder._mutateConfig(root, p.id, (c) => {
      c.reroll = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max };
    }));
    (patch.set_nudge || []).forEach((p) => CheckBuilder._mutateConfig(root, p.id, (c) => {
      c.nudge = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max };
    }));
    (patch.set_name || []).forEach((p) => CheckBuilder._setName(root, p));
    (patch.set_excluded || []).forEach((p) => CheckBuilder._setExcluded(root, p.id, p.excluded));
  }

  static _group(root, id) { return root.querySelector('.roll-group[data-roll-id="' + id + '"]'); }

  static _mutateConfig(root, id, fn) {
    const g = CheckBuilder._group(root, id);
    if (!g) return;
    let cfg; try { cfg = JSON.parse(g.dataset.config); } catch (e) { return; }
    fn(cfg);
    g.dataset.config = JSON.stringify(cfg);
    // Reflect the new dice count / TN in the un-rolled placeholder + params line.
    const params = g.querySelector('.params');
    if (params) params.textContent = cfg.dice_count + ' dice @ TN ' + cfg.tn +
      (cfg.starting_value > 0 ? ', R+' + cfg.starting_value : cfg.starting_value < 0 ? ', R-' + Math.abs(cfg.starting_value) : '');
  }

  static _setName(root, p) {
    const g = CheckBuilder._group(root, p.id);
    if (!g) return;
    if (p.creature_name != null) { const el = g.querySelector('.creature-name'); if (el) el.textContent = p.creature_name; }
    if (p.roll_name != null) { const el = g.querySelector('.roll-name'); if (el) el.innerHTML = '<em>(' + p.roll_name + ')</em>'; }
  }

  // Excluded rolls are hidden and dropped from the confirmed payload (a
  // declared "none" defense, an unused ally reaction, …).
  static _setExcluded(root, id, excluded) {
    const g = CheckBuilder._group(root, id);
    if (!g) return;
    g.classList.toggle('roll-group-excluded', !!excluded);
    g.hidden = !!excluded;
  }

  // ----- rendering -----

  static _renderStep(root, step, opts) {
    const actions = root.querySelector('.rolls-actions');
    const grouped = opts.some((o) => o.group);
    let body;
    if (grouped) {
      const groups = {};
      const order = [];
      opts.forEach((o) => { const k = o.group || ''; if (!(k in groups)) { groups[k] = []; order.push(k); } groups[k].push(o); });
      body = order.map((k) =>
        `<div class="cb-group"><span class="cb-group-label">${k}</span>` +
        `<span class="cb-group-opts">${groups[k].map(optButton).join('')}</span></div>`).join('');
    } else {
      body = `<span class="cb-opts">${opts.map(optButton).join('')}</span>`;
    }
    actions.innerHTML = `<span class="cb-step-label">${step.label}</span> ${body}`;
  }

  // All steps done: hand the header back to Roll All / Confirm All and show
  // the dice table.
  static _renderReady(root) {
    const actions = root.querySelector('.rolls-actions');
    actions.innerHTML =
      '<button type="button" class="btn-roll-all">Roll All</button>' +
      '<button type="button" class="btn-confirm">Confirm</button>';
    const table = root.querySelector('.roll-table');
    if (table) table.hidden = false;
    root.dataset.state = 'active';
  }

  static _summarize(root, step, valueText) {
    const stack = root.querySelector('.cb-summaries');
    if (!stack) return;
    const existing = root.querySelector('.cb-summary[data-step="' + step.key + '"]');
    if (existing) existing.remove();
    const row = document.createElement('div');
    row.className = 'cb-summary';
    row.dataset.step = step.key;
    row.innerHTML = `<span class="cb-summary-label">${step.label}</span>` +
      `<span class="cb-summary-value">${valueText}</span>` +
      `<button type="button" class="cb-change" data-step="${step.key}">change</button>`;
    stack.appendChild(row);
  }

  // ----- confirm -----

  static _confirm(root) {
    const cb = root._cb;
    const rolls = [];
    root.querySelectorAll('.roll-group').forEach((g) => {
      if (g.classList.contains('roll-group-excluded')) return;
      let cfg = {}; try { cfg = JSON.parse(g.dataset.config); } catch (e) { /* keep defaults */ }
      const inputs = g.querySelectorAll('.result-input');
      rolls.push({
        id: g.dataset.rollId,
        side: g.dataset.side,
        successes: inputs[0] ? parseInt(inputs[0].value, 10) || 0 : 0,
        crits: inputs[1] ? parseInt(inputs[1].value, 10) || 0 : 0,
        dice_count: cfg.dice_count
      });
    });
    const choices = {};
    Object.keys(cb.choices).forEach((k) => { choices[k] = cb.choices[k].value; });
    root.dispatchEvent(new CustomEvent('check:confirmed', { bubbles: true, detail: { choices, rolls } }));
  }
}

function optButton(o) {
  return `<button type="button" class="ta-opt cb-opt" data-value="${o.value}"` +
    (o.disabled ? ' disabled' : '') + `>${o.label}</button>`;
}
function stripTags(s) { return String(s).replace(/<[^>]*>/g, '').trim(); }

// Re-expand the shared Rolls wrapper on Change (mirrors RollsWrapper.expand
// without importing it, since the builder may rewind before any collapse).
function RollsWrapperExpand(root) {
  root.dataset.state = 'active';
  const table = root.querySelector('.roll-table'); if (table) table.hidden = false;
  const results = root.querySelector('.rolls-results'); if (results) results.hidden = true;
}
