import { CheckResolution } from '../check.js';

// Check Resolution Builder (check_resolution_builder_stub.md).
//
// A domain-agnostic, parameter-driven wizard. It reuses the Save Resolution
// stub's markup + CSS: the active step's controls live in the Rolls header,
// completed steps become thin `.step-summary` rows (each with a ↶ Change), and
// the active step's `.step-body` shows its option buttons (.cr-mod-btn). The
// host precomputes the whole blob; the builder runs client-side and emits a
// single `check:confirmed` CustomEvent with the picked choices + resolved
// per-Roll Successes. It never calls back into the host.
//
// Blob (read from the `.check-builder` element's data-builder):
//   { title, stub_id,
//     rolls: [ { id, side, creature_name, roll_name, die_size, tn,
//                starting_value, dice_count, excluded? } ],
//     steps: [ { key, label,
//                options?: [opt],                 // static (server-rendered)
//                options_by?: [stepKey,...],      // choice-dependent
//                options_map?: { "k1|k2": [opt] } // keyed by prior choices' `key`
//              } ] }
//   opt = { value, label, key?, group?, summary?, disabled?, patch }
//   patch = { set_dice:[{id,count}], set_tn:[{id,tn,starting_value}],
//             set_name:[{id,creature_name?,roll_name?}],
//             set_excluded:[{id,excluded}],
//             set_reroll:[{id,sign,count}|{id,clear:true}],
//             set_nudge:[{id,sign,count}|{id,clear:true}] }
export class CheckBuilder {
  static ensureLoaded(root) {
    if (!root || root.dataset.cbLoaded) return;
    root.dataset.cbLoaded = '1';
    let blob;
    try { blob = JSON.parse(root.dataset.builder); } catch (e) { return; }
    root._cb = { steps: blob.steps || [], choices: {} };
    CheckBuilder._bind(root);
    // The server rendered the first step active; nothing to do until a pick.
  }

  static _bind(root) {
    root.addEventListener('click', (e) => {
      const opt = e.target.closest && e.target.closest('.cb-opt');
      if (opt && root.contains(opt) && !opt.disabled) return CheckBuilder._pick(root, opt);
      const chg = e.target.closest && e.target.closest('.cr-step-change');
      if (chg && root.contains(chg) && chg.dataset.step) return CheckBuilder._change(root, chg.dataset.step);
      const conf = e.target.closest && e.target.closest('.btn-confirm');
      if (conf && root.contains(conf)) return CheckBuilder._confirm(root);
    });
  }

  // ----- step lifecycle -----

  static _index(root, key) { return root._cb.steps.findIndex((s) => s.key === key); }

  static _optionsFor(root, step) {
    if (step.options) return step.options;
    if (step.options_by && step.options_map) {
      const k = step.options_by.map((s) => (root._cb.choices[s] ? root._cb.choices[s].key : '')).join('|');
      return step.options_map[k] || [];
    }
    return [];
  }

  static _ctrl(root, key) { return root.querySelector('.step-controls[data-step="' + key + '"]'); }
  static _body(root, key) { return root.querySelector('.step-body[data-step="' + key + '"]'); }
  static _sumRow(root, key) { return root.querySelector('.step-summary[data-step="' + key + '"]'); }
  static _setState(root, key, state) {
    const c = CheckBuilder._ctrl(root, key); if (c) c.dataset.state = state;
    const b = CheckBuilder._body(root, key); if (b) b.dataset.state = state;
  }

  static _pick(root, optEl) {
    const cb = root._cb;
    const key = optEl.dataset.step;
    const step = cb.steps[CheckBuilder._index(root, key)];
    if (!step) return;
    const opt = CheckBuilder._optionsFor(root, step).find((o) => String(o.value) === optEl.dataset.value);
    if (!opt) return;
    cb.choices[key] = { value: opt.value, label: opt.label, key: opt.key != null ? opt.key : opt.value };
    CheckBuilder._applyPatch(root, opt.patch);
    CheckBuilder._setState(root, key, 'complete');
    const sum = CheckBuilder._sumRow(root, key);
    if (sum) {
      const v = sum.querySelector('.step-summary-value');
      if (v) v.textContent = opt.summary || stripTags(opt.label);
      sum.hidden = false;
    }
    CheckBuilder._activateFrom(root, CheckBuilder._index(root, key) + 1);
  }

  // Show the first not-yet-complete step from `idx` that has options (rendering
  // a choice-dependent body in JS); if none remain, reveal the dice table.
  static _activateFrom(root, idx) {
    const cb = root._cb;
    let i = idx;
    while (i < cb.steps.length) {
      const step = cb.steps[i];
      const opts = CheckBuilder._optionsFor(root, step);
      if (opts.length === 0) { CheckBuilder._setState(root, step.key, 'complete'); i++; continue; }
      if (!step.options) { const b = CheckBuilder._body(root, step.key); if (b) b.innerHTML = CheckBuilder._optsHtml(step.key, opts); }
      CheckBuilder._setState(root, step.key, 'active');
      return;
    }
    CheckBuilder._setState(root, '__dice', 'active');
    // All steps resolved — show the final propagated TNs before the DM rolls.
    CheckBuilder._previewTns(root);
  }

  // Re-open a completed step; rewind every later step (clear choices, hide
  // summaries, clear choice-dependent bodies) and re-collapse the dice table.
  static _change(root, key) {
    const cb = root._cb;
    const ti = CheckBuilder._index(root, key);
    if (ti < 0) return;
    for (let i = ti; i < cb.steps.length; i++) {
      const sk = cb.steps[i].key;
      delete cb.choices[sk];
      const sum = CheckBuilder._sumRow(root, sk);
      if (sum) { sum.hidden = true; const v = sum.querySelector('.step-summary-value'); if (v) v.textContent = ''; }
      CheckBuilder._setState(root, sk, 'pending');
      if (i > ti && !cb.steps[i].options) { const b = CheckBuilder._body(root, sk); if (b) b.innerHTML = ''; }
    }
    CheckBuilder._setState(root, '__dice', 'pending');
    const results = root.querySelector('.rolls-results'); if (results) results.hidden = true;
    root.dataset.state = 'building';
    CheckBuilder._activateFrom(root, ti);
  }

  static _optsHtml(stepKey, opts) {
    const groups = {};
    const order = [];
    opts.forEach((o) => { const g = o.group || ''; if (!(g in groups)) { groups[g] = []; order.push(g); } groups[g].push(o); });
    return order.map((g) => '<div class="cb-line">' + groups[g].map((o) => CheckBuilder._btn(stepKey, o)).join(' ') + '</div>').join('');
  }
  // An `info` option is non-interactive descriptive text (e.g. the TN
  // Bonus/Penalty breakdown shown after a group's buttons), not a choice.
  static _btn(stepKey, o) {
    if (o.kind === 'info') return '<span class="cb-bonus-note">' + o.label + '</span>';
    return '<button type="button" class="cr-mod-btn cb-opt" data-step="' + stepKey + '" data-value="' +
      esc(String(o.value)) + '"' + (o.disabled ? ' disabled' : '') + '>' + o.label + '</button>';
  }

  // ----- patch application (mutates the embedded roll-groups by id) -----

  static _applyPatch(root, patch) {
    if (!patch) return;
    (patch.set_dice || []).forEach((p) => CheckBuilder._mutate(root, p.id, (c) => { c.dice_count = p.count; }));
    (patch.set_speed || []).forEach((p) => CheckBuilder._mutate(root, p.id, (c) => { c.speed = p.speed; }));
    // Set a Roll's own Bonus/Penalty list. The TN is NOT set here — it is
    // computed by Check Resolution at roll time (after cross-side propagation).
    (patch.set_bpl || []).forEach((p) => CheckBuilder._mutate(root, p.id, (c) => { c.bonus_penalty_list = p.bonus_penalty_list || []; }));
    (patch.set_reroll || []).forEach((p) => CheckBuilder._mutate(root, p.id, (c) => { c.reroll = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max }; }));
    (patch.set_nudge || []).forEach((p) => CheckBuilder._mutate(root, p.id, (c) => { c.nudge = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max }; }));
    (patch.set_name || []).forEach((p) => CheckBuilder._setName(root, p));
    (patch.set_excluded || []).forEach((p) => CheckBuilder._setExcluded(root, p.id, p.excluded));
    // Re-preview every Roll's TN through Check Resolution so each row reflects
    // the propagated math after any change.
    CheckBuilder._previewTns(root);
  }

  static _group(root, id) { return root.querySelector('.roll-group[data-roll-id="' + id + '"]'); }

  static _mutate(root, id, fn) {
    const g = CheckBuilder._group(root, id);
    if (!g) return;
    let cfg; try { cfg = JSON.parse(g.dataset.config); } catch (e) { return; }
    fn(cfg);
    g.dataset.config = JSON.stringify(cfg);
  }

  // Ask Check Resolution to compute each Roll's TN (after cross-side
  // propagation) and reflect it in the params line + the character-cell TN
  // tooltip. The builder never computes a TN itself.
  static _previewTns(root) {
    const groups = Array.from(root.querySelectorAll('.roll-group'))
      .filter((g) => !g.classList.contains('roll-group-excluded'));
    const rollFor = (g) => {
      let c; try { c = JSON.parse(g.dataset.config); } catch (e) { return null; }
      return { _g: g, side: g.dataset.side, baseTn: c.base_tn,
               bonusPenaltyList: c.bonus_penalty_list || [], startingContribution: 0 };
    };
    const supporting = groups.filter((g) => g.dataset.side === 'supporting').map(rollFor);
    const opposing   = groups.filter((g) => g.dataset.side === 'opposing').map(rollFor);
    // baseTn isn't a TnComputation input (it uses the config's Base TN); our
    // rolls all share the configured Base TN, so previewParameters is correct.
    const preview = CheckResolution.previewParameters({ supporting, opposing });
    const applyOne = (roll, res) => {
      if (!roll || !res) return;
      CheckBuilder._renderTn(roll._g, roll.baseTn, res);
      let c; try { c = JSON.parse(roll._g.dataset.config); } catch (e) { return; }
      c.tn = res.tn; c.starting_value = res.startingValue;
      roll._g.dataset.config = JSON.stringify(c);
    };
    supporting.forEach((r, i) => applyOne(r, preview.supporting[i]));
    opposing.forEach((r, i) => applyOne(r, preview.opposing[i]));
  }

  // Render the params line and the TN computation tooltip for one Roll.
  // Display convention: a Bonus lowers the TN, so it shows as a negative term
  // ("−2 Competency"); a Penalty raises it, shown as positive ("+1 …").
  static _renderTn(g, baseTn, res) {
    const cfg = (() => { try { return JSON.parse(g.dataset.config); } catch (e) { return {}; } })();
    const params = g.querySelector('.params');
    if (params) params.textContent = cfg.dice_count + ' dice @ TN ' + res.tn +
      (res.startingValue > 0 ? ', R+' + res.startingValue : res.startingValue < 0 ? ', R-' + Math.abs(res.startingValue) : '');
    if (baseTn == null) return;
    // Each entry's TN influence is the negation of its magnitude.
    const terms = (res.bonusPenaltyList || []).map((m) => {
      const infl = -m[1];
      return (infl >= 0 ? '+' : '−') + Math.abs(infl) + ' ' + m[0];
    });
    const txt = baseTn + (terms.length ? ' ' + terms.join(' ') : '') + ' = TN ' + res.tn;
    const name = g.querySelector('.creature-name');
    if (!name) return;
    name.classList.add('has-tn-tip');
    name.setAttribute('tabindex', '0');
    name.setAttribute('data-tn-tip', txt);
    let tip = name.querySelector('.tn-tip');
    if (!tip) { tip = document.createElement('span'); tip.className = 'tn-tip'; name.appendChild(tip); }
    tip.textContent = txt;
  }

  static _setName(root, p) {
    const g = CheckBuilder._group(root, p.id);
    if (!g) return;
    if (p.creature_name != null) { const el = g.querySelector('.creature-name'); if (el) el.textContent = p.creature_name; }
    if (p.roll_name != null) { const el = g.querySelector('.roll-name'); if (el) el.innerHTML = '<em>(' + p.roll_name + ')</em>'; }
  }

  static _setExcluded(root, id, excluded) {
    const g = CheckBuilder._group(root, id);
    if (!g) return;
    g.classList.toggle('roll-group-excluded', !!excluded);
    g.hidden = !!excluded;
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
        dice_count: cfg.dice_count,
        speed: cfg.speed
      });
    });
    const choices = {};
    Object.keys(cb.choices).forEach((k) => { choices[k] = cb.choices[k].value; });
    // Net Degree of Success = Supporting Successes − Opposing Successes —
    // shown in the collapsed results in place of per-Roll Successes/Crits.
    const net = rolls.reduce((acc, r) => acc + (r.side === 'opposing' ? -r.successes : r.successes), 0);
    const netEl = root.querySelector('.cb-net');
    if (netEl) netEl.textContent = 'Net Degree of Success ' + net + '.';
    root.dispatchEvent(new CustomEvent('check:confirmed', { bubbles: true, detail: { choices, rolls } }));
  }
}

function esc(s) { return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }
function stripTags(s) { return String(s).replace(/<[^>]*>/g, '').trim(); }
