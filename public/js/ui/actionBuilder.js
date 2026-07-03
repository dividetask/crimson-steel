import { CheckResolution } from '../check.js';
import { RollRows } from './rollRows.js';

// Action Builder (action_builder_stub.md).
//
// A domain-agnostic, parameter-driven wizard for composing an action — an
// Attack, a Cast, or a Special. It owns the step flow only; it **composes in
// the Check Resolution roll table** (the shared roll stub embedded as the
// terminal `__dice` step) and shows its *Roll All* affordance **only when a
// step actually rolls dice**. A no-roll flow (a buff Cast, a reservoir pour)
// never mounts that affordance — the DM just confirms.
//
// It reuses the Save Resolution stub's markup + CSS: the active step's controls
// live in the Rolls header, completed steps become thin `.step-summary` rows
// (each with a ↶ Change), and the active step's `.step-body` shows its option
// buttons (.cr-mod-btn). The host precomputes the whole blob; the builder runs
// client-side and emits a single `action:confirmed` CustomEvent with the picked
// choices + resolved per-Roll Successes. It never calls back into the host.
//
// Blob (read from the `.action-builder` element's data-builder):
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
export class ActionBuilder {
  static ensureLoaded(root) {
    if (!root || root.dataset.cbLoaded) return;
    root.dataset.cbLoaded = '1';
    let blob;
    try { blob = JSON.parse(root.dataset.builder); } catch (e) { return; }
    root._cb = { steps: blob.steps || [], choices: {} };
    ActionBuilder._bind(root);
    // The server rendered the first step active; nothing to do until a pick.
  }

  static _bind(root) {
    root.addEventListener('click', (e) => {
      // The Damage Rider stub (a nested .rolls-wrapper injected into our results
      // block after Confirm) carries its own .btn-confirm / .cr-step-change; its
      // controls are driven by the dice engine + turnAttack.js, so ignore clicks
      // that originate inside it — otherwise the rider's Confirm would re-fire
      // the attack's own Confirm.
      if (e.target.closest && e.target.closest('.ta-rider-stub')) return;
      const opt = e.target.closest && e.target.closest('.cb-opt');
      if (opt && root.contains(opt) && !opt.disabled) return ActionBuilder._pick(root, opt);
      const chg = e.target.closest && e.target.closest('.cr-step-change');
      if (chg && root.contains(chg) && chg.dataset.step) return ActionBuilder._change(root, chg.dataset.step);
      const conf = e.target.closest && e.target.closest('.btn-confirm');
      if (conf && root.contains(conf)) return ActionBuilder._confirm(root);
    });
  }

  // ----- step lifecycle -----

  static _index(root, key) { return root._cb.steps.findIndex((s) => s.key === key); }

  static _optionsFor(root, step) {
    if (step.dynamic === 'luck') return []; // luck steps render their own table
    if (step.options) return step.options;
    if (step.options_by && step.options_map) {
      const k = step.options_by.map((s) => (root._cb.choices[s] ? root._cb.choices[s].key : '')).join('|');
      return step.options_map[k] || [];
    }
    return [];
  }

  // ----- Luck steps (one per source: a Bard's Reservoir or the DM's pool) -----
  //
  // Each Luck step is a table: rows are the in-play Rolls, columns are Bardic
  // Inspiration (a bonus — reroll low dice) and, when the source may impose
  // one, Unsettling Words (a penalty — reroll high dice). Per Roll the source
  // can spend up to min(its Luck, that Roll's dice). Picks across all Luck
  // steps are aggregated per Roll: bonuses/penalties do not stack (only the
  // highest of each takes effect), matching the dice engine's reroll slots.

  // Build the active Luck step's body. Returns { html, any } where `any` is
  // false when no in-play Roll can take this source's Luck (the step is then
  // skipped).
  static _luckBody(root, step) {
    const src = (step.luck || {}).source || {};
    const targets = (step.luck || {}).targets || [];
    const diceOf = (id) => {
      const g = ActionBuilder._group(root, id);
      if (!g || g.classList.contains('roll-group-excluded') || g.hidden) return 0;
      try { return JSON.parse(g.dataset.config).dice_count || 0; } catch (e) { return 0; }
    };
    let any = false;
    const rows = [];
    targets.forEach((t) => {
      const cap = Math.min(src.amount || 0, diceOf(t.roll_id));
      if (cap <= 0) return;
      any = true;
      const rl = ActionBuilder._rollLabel(root, t.roll_id) || t.label || t.roll_id;
      // Unsettling Words (penalty) column first, right-aligned and descending
      // (−cap … −1) so the smallest penalty sits next to the smallest bonus —
      // a continuous number line. Bardic Inspiration (bonus) column second.
      let penCell = '';
      if (src.penalty) {
        const pen = [];
        for (let n = cap; n >= 1; n--) pen.push(ActionBuilder._luckBtn(step.key, src.sid, 'neg', n, t.roll_id));
        penCell = '<td class="cb-luck-cell cb-luck-penalty">' + pen.join(' ') + '</td>';
      }
      const bonus = [];
      for (let n = 1; n <= cap; n++) bonus.push(ActionBuilder._luckBtn(step.key, src.sid, 'pos', n, t.roll_id));
      rows.push('<tr><td class="cb-luck-roll">' + esc(rl) + '</td>' + penCell +
                '<td class="cb-luck-cell">' + bonus.join(' ') + '</td></tr>');
    });
    const head = '<tr><th>ROLL</th>' +
                 (src.penalty ? '<th class="cb-luck-penalty">UNSETTLING WORDS</th>' : '') +
                 '<th>BARDIC INSPIRATION</th></tr>';
    const html = '<div class="cb-luck-heading">' + esc(src.label || '') + '</div>' +
                 '<table class="cb-luck-table"><thead>' + head + '</thead><tbody>' + rows.join('') + '</tbody></table>';
    return { html: html, any: any };
  }

  static _luckBtn(stepKey, sid, sign, n, rollId) {
    const v = sid + '|' + sign + '|' + n + '|' + rollId;
    const cls = sign === 'pos' ? 'cb-luck-pos' : 'cb-luck-neg';
    return '<button type="button" class="cr-mod-btn cb-opt cb-luck-opt ' + cls + '" data-step="' + esc(stepKey) +
      '" data-value="' + esc(v) + '">' + (sign === 'pos' ? '+' : '−') + n + '</button>';
  }

  // Resolve a Roll's display label from its group (the roll-name, else the
  // creature name) for the Luck table's ROLL column.
  static _rollLabel(root, rollId) {
    const g = ActionBuilder._group(root, rollId);
    if (!g) return null;
    const rn = g.querySelector('.roll-name');
    if (rn) { const t = rn.textContent.replace(/[()]/g, '').trim(); if (t) return t; }
    const cn = g.querySelector('.creature-name');
    return cn ? nameOnly(cn) : null;
  }

  // Record this Luck step's pick (a cell button, or the "No luck" header
  // quick-pick), re-aggregate every Roll's Luck, and advance.
  static _pickLuck(root, step, optEl) {
    const cb = root._cb;
    const key = step.key;
    const value = optEl.dataset.value;          // "sid|none" | "sid|sign|count|roll"
    const parts = String(value).split('|');
    let summary, label, choice = null;
    if (parts[1] === 'none' || parts.length < 4) {
      label = 'No luck';
      summary = (step.heading || 'Luck') + ': No luck';
    } else {
      choice = { roll_id: parts[3], sign: parts[1], count: parseInt(parts[2], 10) || 0 };
      const rl = ActionBuilder._rollLabel(root, choice.roll_id) || choice.roll_id;
      label = (choice.sign === 'pos' ? '+' : '−') + choice.count + ' ' + rl;
      summary = (step.heading || 'Luck') + ': ' + label;
    }
    (cb.luck || (cb.luck = {}))[key] = choice;
    cb.choices[key] = { value: value, label: label, key: value };
    ActionBuilder._recomputeLuck(root);
    const body = ActionBuilder._body(root, key);
    if (body) body.querySelectorAll('.cb-luck-opt').forEach((b) => b.classList.toggle('cr-mod-selected', b.dataset.value === value));
    ActionBuilder._setState(root, key, 'complete');
    const sum = ActionBuilder._sumRow(root, key);
    if (sum) { const v = sum.querySelector('.step-summary-value'); if (v) v.textContent = summary; sum.hidden = false; }
    ActionBuilder._activateFrom(root, ActionBuilder._index(root, key) + 1);
  }

  // Compose all Luck picks into each Roll's reroll modifiers (data only — the
  // application is Roll Resolution's job). Per Roll: positive_reroll = max
  // bonus, negative_reroll = max penalty (no stacking, per the TN per-Type
  // rule). The Dice Resolution engine applies both slots in one pass, rerolling
  // each die at most once.
  static _recomputeLuck(root) {
    const agg = {};
    Object.keys(root._cb.luck || {}).forEach((k) => {
      const ch = root._cb.luck[k];
      if (!ch) return;
      const a = agg[ch.roll_id] || (agg[ch.roll_id] = { pos: 0, neg: 0 });
      if (ch.sign === 'pos') a.pos = Math.max(a.pos, ch.count);
      else a.neg = Math.max(a.neg, ch.count);
    });
    root.querySelectorAll('.roll-group').forEach((g) => {
      const id = g.dataset.rollId;
      let c; try { c = JSON.parse(g.dataset.config); } catch (e) { return; }
      const a = agg[id];
      if (a && a.pos) c.positive_reroll = { count: a.pos, max: false }; else delete c.positive_reroll;
      if (a && a.neg) c.negative_reroll = { count: a.neg, max: false }; else delete c.negative_reroll;
      g.dataset.config = JSON.stringify(c);
      // Show the composed Luck reroll as a modifier badge row (the same
      // dynamic mechanism the Save stub uses); Roll Resolution fills its dice
      // cell on Roll All. "−2 +3" reads penalty then bonus.
      const parts = [];
      if (a && a.neg) parts.push('−' + a.neg);
      if (a && a.pos) parts.push('+' + a.pos);
      RollRows.setModRow(g, '.row-reroll', 0, parts.join(' '), 'Luck');
    });
  }

  // The confirmed Luck spends, for a host's resolve payload: one entry per
  // source that picked a Roll. source_id is null for the DM.
  static luckSpends(choices) {
    const out = [];
    Object.keys(choices || {}).forEach((k) => {
      if (k.indexOf('luck:') !== 0) return;
      const parts = String(choices[k]).split('|');
      if (parts[1] === 'none' || parts.length < 4) return;
      out.push({ source_id: parts[0] === 'dm' ? null : parseInt(parts[0], 10),
                 sign: parts[1], amount: parseInt(parts[2], 10) || 0, roll_id: parts[3] });
    });
    return out;
  }

  static _ctrl(root, key) { return root.querySelector('.step-controls[data-step="' + key + '"]'); }
  static _body(root, key) { return root.querySelector('.step-body[data-step="' + key + '"]'); }
  static _sumRow(root, key) { return root.querySelector('.step-summary[data-step="' + key + '"]'); }
  static _setState(root, key, state) {
    const c = ActionBuilder._ctrl(root, key); if (c) c.dataset.state = state;
    const b = ActionBuilder._body(root, key); if (b) b.dataset.state = state;
  }

  // The number of creatures the current Spell may target via the multi-select
  // toggles (the Target step's `multi_map` keyed by the chosen Spell), or 0 for
  // a single-target / self / area Spell.
  static _multiMax(root, step) {
    if (!step || step.key !== 'target' || !step.multi_by || !step.multi_map) return 0;
    const k = step.multi_by.map((s) => (root._cb.choices[s] ? root._cb.choices[s].key : '')).join('|');
    return step.multi_map[k] || 0;
  }

  // Toggle one creature in a multi-target selection (blue = selected). The cap
  // is the Spell's resolved target count; a toggle past it is undone.
  static _toggleTarget(root, step, optEl, max) {
    optEl.classList.toggle('cb-opt-selected');
    const body = ActionBuilder._body(root, step.key);
    const sel = body ? Array.from(body.querySelectorAll('.cb-opt.cb-opt-selected')) : [];
    if (sel.length > max) { optEl.classList.remove('cb-opt-selected'); return; }
    const labels = sel.map((b) => stripTags(b.innerHTML)).join(', ');
    ActionBuilder._setSummaryText(root, 'target', labels || 'none');
  }

  // Finish a multi-target selection: list the chosen creatures as the Target,
  // hand them to the area machinery (per-creature Save Rolls, Defense skipped),
  // and advance to the dice. Reuses the area cast path end-to-end.
  static _multiDone(root, step) {
    const body = ActionBuilder._body(root, step.key);
    const sel = body ? Array.from(body.querySelectorAll('.cb-opt.cb-opt-selected')) : [];
    if (!sel.length) return;
    const hits = sel.map((b) => ({ combatant_id: parseInt(b.dataset.value, 10), label: stripTags(b.innerHTML) }));
    const names = hits.map((h) => h.label).join(', ');
    root._cb.choices[step.key] = { value: 'multi', key: 'multi', label: names };
    ActionBuilder._setState(root, step.key, 'complete');
    const sum = ActionBuilder._sumRow(root, step.key);
    if (sum) { const v = sum.querySelector('.step-summary-value'); if (v) v.textContent = names; sum.hidden = false; }
    document.dispatchEvent(new CustomEvent('cast:targets-selected', { detail: { hits } }));
    ActionBuilder._activateFrom(root, ActionBuilder._index(root, step.key) + 1);
  }

  static _pick(root, optEl) {
    const cb = root._cb;
    const key = optEl.dataset.step;
    const step = cb.steps[ActionBuilder._index(root, key)];
    if (!step) return;
    if (step.dynamic === 'luck') return ActionBuilder._pickLuck(root, step, optEl);
    // Multi-target Spell: the Target step toggles creatures instead of picking
    // one. A `data-multi-done` control finishes the selection.
    if (ActionBuilder._multiMax(root, step) > 1) {
      if (optEl.dataset.multiDone) return ActionBuilder._multiDone(root, step);
      return ActionBuilder._toggleTarget(root, step, optEl, ActionBuilder._multiMax(root, step));
    }
    const opt = ActionBuilder._optionsFor(root, step).find((o) => String(o.value) === optEl.dataset.value);
    if (!opt) return;
    cb.choices[key] = { value: opt.value, label: opt.label, key: opt.key != null ? opt.key : opt.value };
    ActionBuilder._applyPatch(root, opt.patch);
    // A Spell option carries whether casting it rolls a check. A no-roll Spell
    // (a buff, or a reservoir-channel like Shield of Faith) skips the Luck steps
    // — its dice are charged/poured, not rolled.
    if (opt.cast) cb.noRoll = !opt.cast.roll;
    // The resolved Spell name behind the chosen option (equals the value for a
    // known Spell; the underlying Spell for an Item whose option is keyed by the
    // Stack). Used by the area-placement Save fetch so it resolves the Spell.
    if (opt.spell_name != null) cb.spellName = opt.spell_name;
    // An area Spell's "Place on the map" option arms the Atlas; the actual
    // footprint (and the creatures it catches) come back via cast:area-placed.
    if (opt.place) {
      document.dispatchEvent(new CustomEvent('cast:arm-area', { detail: opt.place }));
    }
    ActionBuilder._setState(root, key, 'complete');
    // A row appears only for a choice the DM actively made and that the step
    // wants summarized — a `no_summary` step (e.g. the cast's Dice, which is a
    // resource shown in the result, not a "what" choice) leaves no row.
    const sum = ActionBuilder._sumRow(root, key);
    if (sum && !step.no_summary) {
      const v = sum.querySelector('.step-summary-value');
      if (v) v.textContent = opt.summary || stripTags(opt.label);
      sum.hidden = false;
    }
    ActionBuilder._activateFrom(root, ActionBuilder._index(root, key) + 1);
  }

  // Apply a forced (`auto`) option without a click. The DM made no choice here,
  // so it leaves no summary row (e.g. a Saving Throw always at full Dice Cap).
  static _applyAuto(root, step, opt) {
    const cb = root._cb;
    const key = step.key;
    cb.choices[key] = { value: opt.value, label: opt.label, key: opt.key != null ? opt.key : opt.value };
    ActionBuilder._applyPatch(root, opt.patch);
    ActionBuilder._setState(root, key, 'complete');
  }

  // Show the first not-yet-complete step from `idx` that has options (rendering
  // a choice-dependent body in JS); if none remain, reveal the dice table.
  static _activateFrom(root, idx) {
    const cb = root._cb;
    let i = idx;
    while (i < cb.steps.length) {
      const step = cb.steps[i];
      if (step.dynamic === 'luck') {
        // A no-roll cast (buff / reservoir-channel) rolls nothing, so Luck has
        // nothing to apply — skip every Luck step.
        if (cb.noRoll) { ActionBuilder._setState(root, step.key, 'complete'); i++; continue; }
        // One Luck step per source: render its table. If no in-play Roll can
        // take this source's Luck, there is nothing to ask — skip it.
        const lb = ActionBuilder._luckBody(root, step);
        if (!lb.any) { ActionBuilder._setState(root, step.key, 'complete'); i++; continue; }
        const b = ActionBuilder._body(root, step.key); if (b) b.innerHTML = lb.html;
        ActionBuilder._setState(root, step.key, 'active');
        return;
      }
      const opts = ActionBuilder._optionsFor(root, step);
      const interactive = opts.filter((o) => !o.header_only && o.kind !== 'info');
      if (interactive.length === 0) { ActionBuilder._setState(root, step.key, 'complete'); i++; continue; }
      // A single `auto` option has nothing to ask (e.g. a Saving Throw is always
      // full Dice Cap) — apply it and move on without rendering a button.
      if (interactive.length === 1 && interactive[0].auto) {
        ActionBuilder._applyAuto(root, step, interactive[0]); i++; continue;
      }
      if (!step.options) { const b = ActionBuilder._body(root, step.key); if (b) b.innerHTML = ActionBuilder._optsHtml(step.key, opts); }
      // A multi-target Target step toggles creatures (blue = selected) and ends
      // with a Done control that finishes the selection.
      if (ActionBuilder._multiMax(root, step) > 1) {
        const mb = ActionBuilder._body(root, step.key);
        if (mb && !mb.querySelector('[data-multi-done]')) {
          mb.insertAdjacentHTML('beforeend',
            '<div class="cb-line cb-multi-actions"><button type="button" class="cr-mod-btn cb-opt cb-multi-done" data-step="' +
            esc(step.key) + '" data-multi-done="1">Done</button></div>');
        }
      }
      ActionBuilder._renderDynHeader(root, step);
      ActionBuilder._setState(root, step.key, 'active');
      return;
    }
    ActionBuilder._setState(root, '__dice', 'active');
    const rollAll = root.querySelector('.btn-roll-all');
    const diceBody = root.querySelector('.step-body-dice');
    // All steps resolved — show the final propagated TNs.
    ActionBuilder._previewTns(root);
    if (cb.noRoll) {
      // A no-roll action (a buff Cast, a reservoir pour like Shield) rolls
      // nothing. Hide "Roll All" and the roll table, then auto-surface the
      // result details (detail.auto) — the blue title "Confirm" stays as the
      // single button and commits when clicked.
      if (rollAll) rollAll.hidden = true;
      if (diceBody) diceBody.hidden = true;
      ActionBuilder._confirm(root, { auto: true });
    } else {
      if (rollAll) rollAll.hidden = false;
      if (diceBody) diceBody.hidden = false;
    }
  }

  // Choice-dependent header quick-picks (e.g. one button per Defensive Action),
  // rendered into the step's header when it activates. Mirrors the static
  // `header_options` the server renders for choice-independent steps, but keyed
  // by prior choices like `options_map`. Rebuilt on each activation.
  static _renderDynHeader(root, step) {
    if (!step.header_options_by || !step.header_options_map) return;
    const ctrl = ActionBuilder._ctrl(root, step.key);
    if (!ctrl) return;
    ctrl.querySelectorAll('.cb-dyn').forEach((b) => b.remove());
    const k = step.header_options_by.map((s) => (root._cb.choices[s] ? root._cb.choices[s].key : '')).join('|');
    (step.header_options_map[k] || []).forEach((o) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'cr-mod-btn cb-opt cb-quick cb-dyn';
      btn.dataset.step = step.key;
      btn.dataset.value = String(o.value);
      if (o.disabled) btn.disabled = true;
      btn.textContent = o.label;
      ctrl.appendChild(btn);
    });
  }

  // Re-open a completed step; rewind every later step (clear choices, hide
  // summaries, clear choice-dependent bodies) and re-collapse the dice table.
  static _change(root, key) {
    const cb = root._cb;
    const ti = ActionBuilder._index(root, key);
    if (ti < 0) return;
    for (let i = ti; i < cb.steps.length; i++) {
      const sk = cb.steps[i].key;
      delete cb.choices[sk];
      if (cb.luck) delete cb.luck[sk];
      const sum = ActionBuilder._sumRow(root, sk);
      if (sum) { sum.hidden = true; const v = sum.querySelector('.step-summary-value'); if (v) v.textContent = ''; }
      ActionBuilder._setState(root, sk, 'pending');
      if (i > ti && !cb.steps[i].options) { const b = ActionBuilder._body(root, sk); if (b) b.innerHTML = ''; }
    }
    ActionBuilder._recomputeLuck(root);
    ActionBuilder._setState(root, '__dice', 'pending');
    const results = root.querySelector('.rolls-results'); if (results) results.hidden = true;
    // A post-Confirm collapse (RollsWrapper.collapse) hides the roll table and
    // the header's controls slot wholesale; re-opening a step from its summary
    // row must bring both back or the header quick-picks never reappear.
    const tbl = root.querySelector('.roll-table'); if (tbl) tbl.hidden = false;
    const acts = root.querySelector('.rolls-header .rolls-actions'); if (acts) acts.hidden = false;
    root.dataset.state = 'building';
    ActionBuilder._activateFrom(root, ti);
  }

  // Restart the whole flow from its first step (clearing every prior choice) —
  // used when the Turn Action panel's action-row Change re-opens the action
  // menu, so re-selecting the same action (e.g. Cast) asks the first question
  // (which Spell) again instead of resuming mid-flow. No-op before the builder
  // has loaded its steps.
  static reset(root) {
    if (!root || !root._cb || !root._cb.steps || !root._cb.steps.length) return;
    ActionBuilder._change(root, root._cb.steps[0].key);
  }

  static _optsHtml(stepKey, opts) {
    const groups = {};
    const order = [];
    opts.forEach((o) => { if (o.header_only) return; const g = o.group || ''; if (!(g in groups)) { groups[g] = []; order.push(g); } groups[g].push(o); });
    return order.map((g) => '<div class="cb-line">' + groups[g].map((o) => ActionBuilder._btn(stepKey, o)).join(' ') + '</div>').join('');
  }
  // An `info` option is non-interactive descriptive text (e.g. the TN
  // Bonus/Penalty breakdown shown after a group's buttons), not a choice.
  static _btn(stepKey, o) {
    if (o.kind === 'info') return '<span class="cb-bonus-note">' + o.label + '</span>';
    const cls = 'cr-mod-btn cb-opt' + (o.dying ? ' cb-opt-dying' : '');
    return '<button type="button" class="' + cls + '" data-step="' + stepKey + '" data-value="' +
      esc(String(o.value)) + '"' + (o.disabled ? ' disabled' : '') + '>' + o.label + '</button>';
  }

  // ----- area-spell placement (Spread Check) -----
  //
  // After the DM places an area Spell on the map, the caught creatures become
  // the Opposers: replace the placeholder Target Roll with one Save Roll per
  // creature (fetched from the server), mark the Check Spread, set the Target
  // summary to the affected names, and skip the (non-existent) Defense step.
  static areaPlaced(root, casterId, detail) {
    const cb = root._cb;
    if (!cb) return;
    cb.spread = true;

    const hits = detail.hits || [];
    const names = hits.length
      ? hits.map((h) => h.label || ('#' + h.combatant_id)).join(', ')
      : 'no creatures';
    ActionBuilder._setSummaryText(root, 'target', names);
    ActionBuilder._skipStep(root, 'defense');

    const params = new URLSearchParams();
    params.set('caster_id', casterId);
    params.set('spell', cb.spellName || (cb.choices.spell ? cb.choices.spell.value : ''));
    hits.forEach((h) => params.append('affected[]', h.combatant_id));
    fetch('/encounter/cast_area_rolls?' + params.toString(), { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        const table = root.querySelector('.roll-table');
        if (!table) return;
        // Drop the placeholder Target Roll and any prior Save Rolls, then add
        // the fresh per-creature Save Rolls.
        table.querySelectorAll('tbody.roll-group').forEach((g) => {
          const id = g.dataset.rollId || '';
          if (id === 'target' || id.indexOf('save-') === 0) g.remove();
        });
        table.insertAdjacentHTML('beforeend', html);
        ActionBuilder._previewTns(root);
      })
      .catch(() => {});
  }

  static _setSummaryText(root, key, text) {
    const sum = ActionBuilder._sumRow(root, key);
    if (!sum) return;
    const v = sum.querySelector('.step-summary-value');
    if (v) v.textContent = text;
    sum.hidden = false;
  }

  // Complete a step without showing it (area casts have no Defense step).
  static _skipStep(root, key) {
    const idx = ActionBuilder._index(root, key);
    if (idx < 0) return;
    root._cb.choices[key] = { value: 'skip', label: 'skip', key: 'skip' };
    ActionBuilder._setState(root, key, 'complete');
    const sum = ActionBuilder._sumRow(root, key);
    if (sum) sum.hidden = true;
    ActionBuilder._activateFrom(root, idx + 1);
  }

  // ----- patch application (mutates the embedded roll-groups by id) -----

  static _applyPatch(root, patch) {
    if (!patch) return;
    // Setting an absolute dice count clears any prior scale baseline (a fresh
    // weapon / dice choice is the new full count Better Lucky would halve).
    (patch.set_dice || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.dice_count = p.count; delete c._base_dice; }));
    // Scale a Roll's dice relative to its chosen count — Better Lucky Than
    // Good halves the attacker's dice (min 3). The pre-scale count is stashed
    // so picking a different defense (restore_dice) puts it back.
    (patch.scale_dice || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => {
      if (c._base_dice == null) c._base_dice = c.dice_count;
      const base = c._base_dice;
      const scaled = Math.floor(base * (p.num || 1) / (p.den || 1));
      c.dice_count = Math.min(base, Math.max(p.min || 1, scaled));
    }));
    // Undo a prior scale_dice (any defense other than the scaling Reaction
    // restores the attacker's full dice).
    (patch.restore_dice || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => {
      if (c._base_dice != null) { c.dice_count = c._base_dice; delete c._base_dice; }
    }));
    (patch.set_speed || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.speed = p.speed; }));
    // Set a Roll's own Bonus/Penalty list. The TN is NOT set here — it is
    // computed by Check Resolution at roll time (after cross-side propagation).
    (patch.set_bpl || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.bonus_penalty_list = p.bonus_penalty_list || []; }));
    // Bonus Types on this Roll that Check Resolution must NOT propagate to the
    // other side (e.g. a Dodge's Competency). Empty by default.
    (patch.set_no_propagate || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.no_propagate = p.types || []; }));
    (patch.set_reroll || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.reroll = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max }; }));
    (patch.set_nudge || []).forEach((p) => ActionBuilder._mutate(root, p.id, (c) => { c.nudge = p.clear ? null : { sign: p.sign, count: p.count, max: !!p.max }; }));
    (patch.set_name || []).forEach((p) => ActionBuilder._setName(root, p));
    (patch.set_excluded || []).forEach((p) => ActionBuilder._setExcluded(root, p.id, p.excluded));
    // Re-preview every Roll's TN through Check Resolution so each row reflects
    // the propagated math after any change.
    ActionBuilder._previewTns(root);
  }

  static _group(root, id) { return root.querySelector('.roll-group[data-roll-id="' + id + '"]'); }

  static _mutate(root, id, fn) {
    const g = ActionBuilder._group(root, id);
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
               bonusPenaltyList: c.bonus_penalty_list || [], noPropagate: c.no_propagate || [],
               startingContribution: 0 };
    };
    const supporting = groups.filter((g) => g.dataset.side === 'supporting').map(rollFor);
    const opposing   = groups.filter((g) => g.dataset.side === 'opposing').map(rollFor);
    // baseTn isn't a TnComputation input (it uses the config's Base TN); our
    // rolls all share the configured Base TN, so previewParameters is correct.
    // An area cast is a Spread Check (caster vs each independent Opposer).
    const spread = !!(root._cb && root._cb.spread);
    const preview = CheckResolution.previewParameters({ supporting, opposing, spread });
    const applyOne = (roll, res) => {
      if (!roll || !res) return;
      ActionBuilder._renderTn(roll._g, roll.baseTn, res);
      let c; try { c = JSON.parse(roll._g.dataset.config); } catch (e) { return; }
      c.tn = res.tn; c.starting_value = res.startingValue;
      roll._g.dataset.config = JSON.stringify(c);
    };
    supporting.forEach((r, i) => applyOne(r, preview.supporting[i]));
    opposing.forEach((r, i) => applyOne(r, preview.opposing[i]));
  }

  // Render the params line and the TN computation tooltip for one Roll. The
  // per-entry TN influence (a Bonus lowers the TN, a Penalty raises it) is
  // supplied by Dice Resolution via `res.contributions`; the builder only
  // formats it.
  static _renderTn(g, baseTn, res) {
    const cfg = (() => { try { return JSON.parse(g.dataset.config); } catch (e) { return {}; } })();
    const params = g.querySelector('.params');
    if (params) params.textContent = cfg.dice_count + ' dice @ TN ' + res.tn +
      (res.startingValue > 0 ? ', R+' + res.startingValue : res.startingValue < 0 ? ', R-' + Math.abs(res.startingValue) : '');
    if (baseTn == null) return;
    // Show each modifier with its natural sign and, when it has a source
    // (e.g. Flatfooted), that source in parentheses; Competency and other
    // plain modifiers show their Bonus Type.
    const terms = (res.contributions || []).map((c) => {
      const label = c.source ? '(' + c.source + ')' : c.type;
      return (c.value >= 0 ? '+' : '−') + Math.abs(c.value) + ' ' + label;
    });
    const txt = (terms.length ? terms.join(' ') + ' = ' : '') + 'TN ' + res.tn;
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
    const g = ActionBuilder._group(root, p.id);
    if (!g) return;
    if (p.creature_name != null) { const el = g.querySelector('.creature-name'); if (el) el.textContent = p.creature_name; }
    if (p.roll_name != null) { const el = g.querySelector('.roll-name'); if (el) el.innerHTML = '<em>(' + p.roll_name + ')</em>'; }
  }

  static _setExcluded(root, id, excluded) {
    const g = ActionBuilder._group(root, id);
    if (!g) return;
    g.classList.toggle('roll-group-excluded', !!excluded);
    g.hidden = !!excluded;
  }

  // ----- confirm -----

  static _confirm(root, opts) {
    opts = opts || {};
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
    // Net Degree of Success — Check Resolution owns the Supporting − Opposing
    // math; the builder only reads each Roll's DoIS from the table.
    const net = CheckResolution.degreeOfSuccess({
      supporting: rolls.filter((r) => r.side !== 'opposing').map((r) => r.successes),
      opposing: rolls.filter((r) => r.side === 'opposing').map((r) => r.successes),
    });
    // A no-roll action (a buff / reservoir pour) rolls nothing, so there is no
    // Net Degree of Success to report — leave the line empty rather than "0".
    const netEl = root.querySelector('.cb-net');
    if (netEl) netEl.textContent = cb.noRoll ? '' : ('Net Degree of Success ' + net + '.');
    // `auto`: the builder surfaced the result itself (a no-roll action reaching
    // the end) vs the DM clicking the title "Confirm" — the host uses it to
    // tell a details preview apart from the commit.
    root.dispatchEvent(new CustomEvent('action:confirmed', { bubbles: true, detail: { choices, rolls, noRoll: !!cb.noRoll, auto: !!opts.auto } }));
  }
}

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }
function stripTags(s) { return String(s).replace(/<[^>]*>/g, '').trim(); }

// The creature-name cell may contain a `.tn-tip` child span; read only its
// own text nodes so the TN tooltip text doesn't leak into the Luck label.
function nameOnly(el) {
  let t = '';
  el.childNodes.forEach((n) => { if (n.nodeType === 3) t += n.textContent; });
  return (t.trim() || el.textContent.trim());
}
