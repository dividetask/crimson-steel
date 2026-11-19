import { DiceRenderer } from './diceRenderer.js';

// Player actions panel (views/_action_flows.erb, docs/project/action_flow.md).
//
//  - Refreshes itself every few seconds so players' answers appear without a
//    page reload (skipped while the DM is using one of its menus).
//  - "Open in … builder": opens the acting Combatant's Attack / Cast / Item
//    pane (or presses the Ability's button), then
//    replays every choice in the builder (the same buttons the DM would press)
//    and fills each Roll's Result / Crits with the dice rolled on the phones.
//    The DM checks it and presses Confirm, then Commit, exactly as usual; the
//    builder's payload carries the flow id so the commit closes the flow.
const PANEL = '#action-flows';
const REFRESH_MS = 3000;

function refresh() {
  const panel = document.querySelector(PANEL);
  if (!panel) return;
  if (panel.contains(document.activeElement) && document.activeElement !== document.body) return;
  fetch('/encounter/flows_panel', { headers: { Accept: 'text/html' } })
    .then((r) => (r.ok ? r.text() : null))
    .then((html) => {
      if (html == null) return;
      const cur = document.querySelector(PANEL);
      if (!cur || cur.contains(document.activeElement) && document.activeElement !== document.body) return;
      const tmp = document.createElement('div');
      tmp.innerHTML = html;
      const next = tmp.querySelector(PANEL);
      if (next && next.innerHTML !== cur.innerHTML) cur.innerHTML = next.innerHTML;
    })
    .catch(() => { /* try again next tick */ });
}

function waitFor(fn, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const tick = () => {
      const v = fn();
      if (v) return resolve(v);
      if (Date.now() - started > timeoutMs) return reject(new Error('timed out'));
      setTimeout(tick, 100);
    };
    tick();
  });
}

function note(container, text, warn) {
  let el = container.querySelector('.af-prefill-note');
  if (!el) {
    el = document.createElement('p');
    el.className = 'af-prefill-note';
    container.prepend(el);
  }
  el.textContent = text;
  el.classList.toggle('af-prefill-warn', !!warn);
}

// Where each kind of action lives on the turn panel.
const PANES = {
  attack: { action: 'attack', container: '.ta-pane[data-ta-pane="attack"] .ta-attack' },
  cast:   { action: 'cast',   container: '.ta-cast' },
  item:   { action: 'item',   container: '.ta-item' },
  special: { container: '.ta-special' },
};

async function openBuilder(flowId) {
  const res = await fetch('/encounter/flows/' + encodeURIComponent(flowId) + '/prefill').then((r) => r.json()).catch(() => null);
  if (!res || res.ok === false) { alert('This action is no longer available.'); return; }
  const kind = res.kind || 'attack';
  const pane = PANES[kind] || PANES.attack;
  const panel = document.querySelector('.turn-action[data-combatant-id="' + res.actor_id + '"]');
  if (!panel) { alert('Open the acting Combatant’s turn first.'); return; }
  const container = panel.querySelector(pane.container);
  if (!container) { alert('That action is not available on this turn panel.'); return; }
  container.dataset.flowId = flowId;

  if (kind === 'special') {
    // An Ability is a button in the action menu: press it. A channeled one
    // (Bardic Performance) then loads its builder; any other shows its summary
    // and Confirm.
    const opt = Array.from(panel.querySelectorAll('.ta-special-opt')).find((b) => b.dataset.ability === res.ability);
    if (!opt || opt.disabled) { alert(res.ability + ' is not available right now.'); return; }
    opt.click();
    container.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (!res.choices.length) { note(container, 'Approved on the player’s phone. Check it, then press Confirm.', false); return; }
  } else {
    const btn = panel.querySelector('.ta-menu-btn[data-ta-action="' + pane.action + '"]');
    if (!btn) { alert('That action is not available on this turn panel.'); return; }
    btn.click();
  }

  let root;
  try {
    root = await waitFor(() => {
      const b = container.querySelector('.action-builder');
      return b && b._cb && b._cb.steps && b._cb.steps.length ? b : null;
    });
  } catch (e) { alert('The builder did not load.'); return; }
  container.scrollIntoView({ behavior: 'smooth', block: 'start' });

  // Replay the choices in builder order. Each press activates the next step,
  // so the following step's buttons exist by the time it is pressed. A step
  // the builder applied by itself (a Saving Throw, a self-target) is skipped.
  const missed = [];
  for (const [step, value] of res.choices) {
    const done = root._cb.choices && root._cb.choices[step];
    if (done && String(done.value) === String(value)) continue;
    const sel = '.cb-opt[data-step="' + CSS.escape(step) + '"][data-value="' + CSS.escape(String(value)) + '"]';
    const b = Array.from(root.querySelectorAll(sel)).find((x) => !x.disabled);
    if (!b) { missed.push(step); continue; }
    b.click();
    // A multi-target Spell toggles targets; finish the (single) selection.
    const multiDone = root.querySelector('.cb-multi-done[data-step="' + CSS.escape(step) + '"]');
    if (multiDone) multiDone.click();
  }

  // Fill each Roll with the phone's dice and the server-scored Result / Crits.
  // A multi-target Spell's target Roll is that creature's Save row (save-<id>).
  Object.entries(res.rolls || {}).forEach(([rollId, r]) => {
    let g = root.querySelector('.roll-group[data-roll-id="' + CSS.escape(rollId) + '"]');
    if (!g && rollId === 'target') g = root.querySelector('.roll-group[data-roll-id^="save-"]');
    if (!g) { missed.push('roll ' + rollId); return; }
    const inputs = g.querySelectorAll('.result-input');
    if (inputs[0]) inputs[0].value = r.successes;
    if (inputs[1]) inputs[1].value = r.crits;
    const cell = g.querySelector('.row-initial .dice-cell');
    if (cell && Array.isArray(r.final)) cell.innerHTML = DiceRenderer.renderDice(r.final, r.tn, 10, r.starting_value || 0);
    const lock = g.querySelector('.lock-btn');
    if (lock && !lock.classList.contains('locked')) lock.click(); // keep Roll All from replacing the phone dice
  });

  const area = res.choices.some(([k, v]) => k === 'target' && v === 'place');
  if (missed.length) {
    note(container, 'Filled in from the players’ phones, except: ' + missed.join(', ') +
      ' (an option changed since — choose it by hand). Then Confirm and Commit.', true);
  } else if (area) {
    note(container, 'Spell and dice filled in. Place it on the map; the creatures caught in it roll their saves here. Then Confirm and Commit.', false);
  } else {
    note(container, 'Filled in from the players’ phones. Check it, then press Confirm and Commit.', false);
  }
}

document.addEventListener('click', (e) => {
  const b = e.target.closest && e.target.closest('.af-open-builder');
  if (!b) return;
  e.preventDefault();
  openBuilder(b.dataset.flowId);
});

if (document.querySelector(PANEL)) setInterval(refresh, REFRESH_MS);
