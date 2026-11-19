// Player actions panel (views/_action_flows.erb, docs/project/action_flow.md).
//
//  - Refreshes itself when the server says something changed, so players'
//    requests appear without a page reload (skipped while the DM is using one of its menus).
//  - When the DM approves a player's request (data-open-now), or presses
//    "Open in … builder": opens the acting Combatant's Attack / Cast / Item
//    pane (or presses the Ability's button) exactly as if the DM had pressed
//    it, and replays the player's choices (the same buttons the DM would
//    press). From there the builder runs as usual, with the other players'
//    choices and dice coming from their phones (liveSync.js). The builder's
//    payload carries the flow id so the commit closes the flow.
const PANEL = '#action-flows';
const REFRESH_MS = 30000;

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
      openApproved();
    })
    .catch(() => { /* try again next tick */ });
}

// A request the DM just approved opens in the builder by itself, once.
const opened = new Set();
function openApproved() {
  document.querySelectorAll(PANEL + ' [data-open-now]').forEach((el) => {
    const id = el.dataset.flowId;
    if (!id || opened.has(id)) return;
    opened.add(id);
    openBuilder(id);
  });
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

// +quiet+: reopening on page load — no alerts when it cannot be done here.
async function openBuilder(flowId, quiet) {
  const res = await fetch('/encounter/flows/' + encodeURIComponent(flowId) + '/prefill').then((r) => r.json()).catch(() => null);
  if (!res || res.ok === false) { if (!quiet) alert('This action is no longer available.'); return false; }
  const kind = res.kind || 'attack';
  const pane = PANES[kind] || PANES.attack;
  const panel = document.querySelector('.turn-action[data-combatant-id="' + res.actor_id + '"]');
  if (!panel) { if (!quiet) alert('Open the acting Combatant’s turn first.'); return false; }
  const container = panel.querySelector(pane.container);
  if (!container) { if (!quiet) alert('That action is not available on this turn panel.'); return false; }
  container.dataset.flowId = flowId;

  if (kind === 'special') {
    // An Ability is a button in the action menu: press it. A channeled one
    // (Bardic Performance) then loads its builder; any other shows its summary
    // and Confirm.
    const opt = Array.from(panel.querySelectorAll('.ta-special-opt')).find((b) => b.dataset.ability === res.ability);
    if (!opt || opt.disabled) { if (!quiet) alert(res.ability + ' is not available right now.'); return false; }
    opt.click();
    container.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (!res.choices.length) { note(container, res.actor_name ? 'Requested by ' + res.actor_name + '. Check it, then press Confirm.' : 'Check it, then press Confirm.', false); return; }
  } else {
    const btn = panel.querySelector('.ta-menu-btn[data-ta-action="' + pane.action + '"]');
    if (!btn) { if (!quiet) alert('That action is not available on this turn panel.'); return false; }
    btn.click();
  }

  let root;
  try {
    root = await waitFor(() => {
      const b = container.querySelector('.action-builder');
      return b && b._cb && b._cb.steps && b._cb.steps.length ? b : null;
    });
  } catch (e) { if (!quiet) alert('The builder did not load.'); return false; }
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

  if (missed.length) {
    note(container, 'Filled in, except: ' + missed.join(', ') +
      ' (an option changed since — choose it by hand).', true);
  } else if (res.resumed) {
    note(container, 'Picked up where you left off. The players’ answers and dice are kept; roll any of your own dice again.', false);
  } else {
    note(container, 'Requested from the player’s phone. Continue as usual: the other players answer on their phones.', false);
  }
  return true;
}

// liveSync.js reopens the actions in progress when the page loads.
window.openFlowBuilder = openBuilder;

document.addEventListener('click', (e) => {
  const b = e.target.closest && e.target.closest('.af-open-builder');
  if (!b) return;
  e.preventDefault();
  openBuilder(b.dataset.flowId);
});

if (document.querySelector(PANEL)) {
  // Refreshed when the server says something changed (liveSync.js's
  // live-updates connection), with a slow fallback.
  document.addEventListener('live:changed', refresh);
  setInterval(refresh, REFRESH_MS);
  // After the page's own scripts (app.js) have bound the turn panel's buttons.
  if (document.readyState === 'complete') setTimeout(openApproved, 200);
  else window.addEventListener('load', () => setTimeout(openApproved, 200));
}
