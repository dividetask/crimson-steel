import { ActionBuilder } from './actionBuilder.js';
import { DiceRenderer } from './diceRenderer.js';

// The DM's builders, live on the players' phones (docs/project/action_flow.md).
//
// About once a second, every Attack / Cast / Item / Ability builder on screen
// sends the server its state: the step it is on (with its options), its
// choices, and once the dice are up, every Roll (POST /encounter/live/sync).
// The server turns that into prompts on the phones:
//
//  - A step that is a player's choice (the target's Defense, an ally's
//    Shield, a Bard's Luck) appears on that player's phone. Their answer is
//    picked here by itself; picking it here first makes the phone prompt go
//    away (the builder moves on).
//  - A Roll that belongs to a player with a phone is theirs to roll: its row
//    is locked (Roll All leaves it alone) and shows where it stands, with
//    "Roll for …" (the DM rolls it, seen only here) and "Approve" (shares it
//    with the players). A player's roll replaces a DM roll not yet approved.
//  - Every other Roll is rolled by Roll All as usual; Confirm shares them.
//
// A builder that is hidden (another action picked) tells the server once, so
// its prompts leave the phones.
const SYNC_MS = 1200;
const PANES = { '.ta-attack': 'attack', '.ta-cast': 'cast', '.ta-item': 'item', '.ta-special': 'special' };
const ANY_PANE = Object.keys(PANES).join(', ');

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }
function stripTags(s) { return String(s == null ? '' : s).replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').trim(); }
function textOnly(el) {
  if (!el) return '';
  let t = '';
  el.childNodes.forEach((n) => { if (n.nodeType === 3) t += n.textContent; });
  return (t.trim() || el.textContent.trim());
}
function cfgOf(g) { try { return JSON.parse(g.dataset.config); } catch (e) { return {}; } }

function containerOf(root) { return root.closest(ANY_PANE); }
function kindOf(container) {
  for (const sel of Object.keys(PANES)) if (container.matches(sel)) return PANES[sel];
  return 'attack';
}
function visible(root) { return !!(root.offsetParent && root._cb && root._cb.steps && root._cb.steps.length); }

// The builder's own Rolls (a Damage Rider's nested table is not part of it).
function rollGroups(root) {
  return Array.from(root.querySelectorAll('tbody.roll-group'))
    .filter((g) => !g.closest('.ta-rider-stub'));
}
function inPlay(g) { return !g.classList.contains('roll-group-excluded') && !g.hidden; }

function activeStep(root) {
  return root._cb.steps.find((s) => root.querySelector('.step-controls[data-step="' + CSS.escape(s.key) + '"][data-state="active"], .step-body[data-step="' + CSS.escape(s.key) + '"][data-state="active"]'));
}
// The dice are up — and stay up after Confirm, while the Damage Riders are
// rolled (turnAttack.js marks the dice step complete then).
function diceUp(root) {
  return !!root.querySelector('.step-controls[data-step="__dice"][data-state="active"], .step-controls[data-step="__dice"][data-state="complete"]');
}

function stepState(root, step) {
  if (step.dynamic === 'luck') {
    const src = (step.luck || {}).source || {};
    const targets = ((step.luck || {}).targets || []).map((t) => {
      const g = root.querySelector('.roll-group[data-roll-id="' + CSS.escape(t.roll_id) + '"]');
      const dice = g && inPlay(g) ? (cfgOf(g).dice_count || 0) : 0;
      // "Garroth Vask's Attack", "Wolf's Dodge".
      const who = g ? textOnly(g.querySelector('.creature-name')) : '';
      const what = g && g.querySelector('.roll-name') ? g.querySelector('.roll-name').textContent.replace(/[()]/g, '').trim() : '';
      const label = who && who !== '—' && what ? who + '’s ' + what : (ActionBuilder._rollLabel(root, t.roll_id) || t.label || t.roll_id);
      return { roll_id: t.roll_id, label, cap: Math.min(src.amount || 0, dice) };
    });
    return { key: step.key, luck: { source: src, targets } };
  }
  let header = step.header_options || [];
  if (step.header_options_by && step.header_options_map) {
    const k = step.header_options_by.map((s) => (root._cb.choices[s] ? root._cb.choices[s].key : '')).join('|');
    header = step.header_options_map[k] || [];
  }
  const body = ActionBuilder._optionsFor(root, step).filter((o) => !o.header_only && o.kind !== 'info');
  const options = header.concat(body).map((o) => ({
    value: o.value, label: stripTags(o.label), summary: stripTags(o.summary || o.label),
    group: o.group, disabled: !!o.disabled,
  }));
  return { key: step.key, options };
}

function rollsState(root) {
  return rollGroups(root).filter(inPlay).map((g) => {
    const c = cfgOf(g);
    return {
      id: g.dataset.rollId, side: g.dataset.side,
      creature_name: textOnly(g.querySelector('.creature-name')),
      roll_name: (g.querySelector('.roll-name') ? g.querySelector('.roll-name').textContent : '').replace(/[()]/g, '').trim(),
      dice_count: c.dice_count, tn: c.tn, starting_value: c.starting_value || 0, speed: c.speed,
      positive_reroll: c.positive_reroll ? c.positive_reroll.count : 0,
      negative_reroll: c.negative_reroll ? c.negative_reroll.count : 0,
      bonus_penalty_list: c.bonus_penalty_list || [],
    };
  });
}

function actionLabel(container, kind, choices) {
  if (kind === 'special') return container._ability || '';
  const c = kind === 'attack' ? choices.action : choices.spell;
  return c ? stripTags(c.label).split(' — ')[0] : '';
}

function state(root, container) {
  const kind = kindOf(container);
  const panel = container.closest('.turn-action');
  const choices = {};
  Object.keys(root._cb.choices || {}).forEach((k) => { choices[k] = root._cb.choices[k].value; });
  const step = activeStep(root);
  const tgt = String(choices.target || '');
  return {
    flow_id: container.dataset.flowId || null, kind,
    actor_id: panel ? parseInt(panel.dataset.combatantId, 10) : null,
    choices, target_id: /^\d+$/.test(tgt) ? parseInt(tgt, 10) : null,
    action_label: actionLabel(container, kind, root._cb.choices || {}),
    step: step ? stepState(root, step) : null,
    rolls: diceUp(root) ? rollsState(root) : null,
  };
}

function post(url, body) {
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                      body: JSON.stringify(body || {}) }).then((r) => r.json()).catch(() => null);
}

// --- Applying the server's answer --------------------------------------------

function applyAnswer(root, answer) {
  if (!answer) return;
  const step = activeStep(root);
  if (!step || step.key !== answer.step) return;
  const sel = '.cb-opt[data-step="' + CSS.escape(answer.step) + '"][data-value="' + CSS.escape(String(answer.value)) + '"]';
  const btn = Array.from(root.querySelectorAll(sel)).find((b) => !b.disabled);
  if (btn) btn.click();
}

function lrRow(g) {
  let row = g.querySelector('tr.lr-row');
  if (!row) {
    row = document.createElement('tr');
    row.className = 'lr-row';
    row.innerHTML = '<td colspan="20" class="lr-cell"></td>';
    g.appendChild(row);
  }
  return row.querySelector('.lr-cell');
}

function fillDice(g, r) {
  const c = cfgOf(g);
  const tn = c.tn;
  const sv = c.starting_value || 0;
  const size = c.die_size || 10;
  const initial = g.querySelector('.row-initial .dice-cell');
  const reroll = g.querySelector('.row-reroll .dice-cell');
  const inputs = g.querySelectorAll('.result-input');
  if (r.final) {
    if (initial) initial.innerHTML = DiceRenderer.renderDice(r.dice || r.final, tn, size, sv);
    if (reroll) reroll.innerHTML = r.rerolled && r.rerolled.some((x) => x != null)
      ? DiceRenderer.renderDice(r.rerolled, tn, size, sv, 'spacer') : '';
    if (inputs[0]) inputs[0].value = r.successes;
    if (inputs[1]) inputs[1].value = r.crits;
    g.dataset.rolledDice = JSON.stringify(r.final);
    g.dataset.lrFilled = '1';
  } else if (g.dataset.lrFilled) {
    if (initial) initial.innerHTML = '';
    if (reroll) reroll.innerHTML = '';
    if (inputs[0]) inputs[0].value = '';
    if (inputs[1]) inputs[1].value = '';
    delete g.dataset.rolledDice;
    delete g.dataset.lrFilled;
  }
}

function applyRolls(root, flowId, rolls) {
  rollGroups(root).forEach((g) => {
    const r = rolls && rolls[g.dataset.rollId];
    if (!r || !r.claimed) {
      const row = g.querySelector('tr.lr-row');
      if (row) row.remove();
      delete g.dataset.lrSig;
      return;
    }
    const sig = JSON.stringify(r);
    if (g.dataset.lrSig === sig) return;
    g.dataset.lrSig = sig;
    // A player's Roll: Roll All leaves it to them (or to "Roll for …").
    const lock = g.querySelector('.lock-btn');
    if (lock) lock.classList.add('locked');
    fillDice(g, r);
    const who = esc(r.owner);
    let status;
    if (r.status === 'approved') status = 'Shared with the players.';
    else if (r.status === 'submitted' && r.by === 'player') status = who + ' rolled on their phone. Only you can see it until you approve.';
    else if (r.status === 'submitted') status = 'You rolled for ' + who + '. Only you can see it; roll again or approve. ' + who + ' may still roll on their phone instead.';
    else status = 'Waiting for ' + who + ' to roll on their phone.';
    const buttons = r.status === 'approved' ? '' :
      '<button type="button" class="af-btn lr-roll" data-flow-id="' + esc(flowId) + '" data-task-id="' + esc(r.task_id) + '">' +
        (r.status === 'submitted' && r.by === 'dm' ? 'Roll again' : 'Roll for ' + who) + '</button>' +
      (r.status === 'submitted'
        ? ' <button type="button" class="af-btn af-primary lr-approve" data-flow-id="' + esc(flowId) + '" data-task-id="' + esc(r.task_id) + '">Approve</button>'
        : '');
    lrRow(g).innerHTML = '<span class="lr-phone">📱</span> <span class="lr-status">' + status + '</span> ' + buttons;
  });
}

function stepNote(root, res) {
  // "Waiting on <player>'s phone" under a step the player may answer.
  root.querySelectorAll('.lr-step-note').forEach((n) => n.remove());
  const step = activeStep(root);
  if (!step || !res.waiting_on) return;
  const body = root.querySelector('.step-body[data-step="' + CSS.escape(step.key) + '"]') ||
               root.querySelector('.step-controls[data-step="' + CSS.escape(step.key) + '"]');
  if (!body) return;
  const p = document.createElement('p');
  p.className = 'lr-step-note';
  p.textContent = '📱 Waiting on ' + res.waiting_on + '’s phone, or choose for them here.';
  body.prepend(p);
}

// --- The loop -------------------------------------------------------------------

function syncOne(root) {
  const container = containerOf(root);
  if (!container || root._lrBusy) return;
  const shown = visible(root);
  if (!shown) {
    // Hidden: tell the server once, so its prompts leave the phones.
    if (container.dataset.flowId && !root._lrIdle) {
      root._lrIdle = true;
      post('/encounter/live/sync', { flow_id: container.dataset.flowId, idle: true }).then((res) => {
        if (res && res.status && res.status !== 'active') delete container.dataset.flowId;
      });
    }
    return;
  }
  root._lrIdle = false;
  root._lrBusy = true;
  post('/encounter/live/sync', state(root, container)).then((res) => {
    root._lrBusy = false;
    if (!res || res.ok === false) return;
    if (res.flow_id) container.dataset.flowId = res.flow_id;
    applyRolls(root, res.flow_id, res.rolls);
    stepNote(root, res);
    applyAnswer(root, res.answer);
  });
}

function tick() {
  document.querySelectorAll('.turn-action .action-builder').forEach(syncOne);
}

document.addEventListener('click', (e) => {
  const b = e.target.closest && e.target.closest('.lr-roll, .lr-approve');
  if (!b) return;
  e.preventDefault();
  const what = b.classList.contains('lr-roll') ? 'roll' : 'approve';
  b.disabled = true;
  post('/encounter/live/' + encodeURIComponent(b.dataset.flowId) + '/rolls/' + encodeURIComponent(b.dataset.taskId) + '/' + what)
    .then((res) => {
      const root = b.closest('.action-builder');
      if (res && res.ok !== false && root) applyRolls(root, res.flow_id, res.rolls);
      else b.disabled = false;
    });
});

// Confirm shares every Roll with the players: the claimed ones that have
// dice, and those Roll All rolled here.
document.addEventListener('action:confirmed', (e) => {
  if (e.detail && e.detail.auto) return;
  const root = e.target.closest && e.target.closest('.action-builder');
  const container = root && containerOf(root);
  if (!container || !container.dataset.flowId) return;
  const rolls = {};
  rollGroups(root).filter(inPlay).forEach((g) => {
    if (g.dataset.lrSig || !g.dataset.rolledDice) return; // claimed: the server has its dice
    let fin; try { fin = JSON.parse(g.dataset.rolledDice); } catch (err) { return; }
    let initial = fin; let rerolled = null;
    try { if (g.dataset.rolledInitial) initial = JSON.parse(g.dataset.rolledInitial); } catch (err) { /* keep */ }
    try { if (g.dataset.rolledRerolled) rerolled = JSON.parse(g.dataset.rolledRerolled); } catch (err) { /* keep */ }
    rolls[g.dataset.rollId] = { dice: initial, rerolled, final: fin };
  });
  post('/encounter/live/' + encodeURIComponent(container.dataset.flowId) + '/share', { rolls })
    .then((res) => { if (res && res.ok !== false) applyRolls(root, res.flow_id, res.rolls); });
});

// A fresh page has no builder open yet: drop what the last page's builders
// were asking the phones, then start syncing.
post('/encounter/live/reset').then(() => {
  setInterval(tick, SYNC_MS);
  tick();
});
// Back from a background tab (where timers run slowly): catch up at once.
document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });
