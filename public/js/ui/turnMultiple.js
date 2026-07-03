import { renderCheckNet, logCheckRolls } from './checkRoll.js';

// DM Page — "Multiple" group action (out-of-combat).
//
// A group of Characters (anyone on Initiative) acts together: every selected
// Character rolls the Skill (Supporting) and every selected target rolls the
// opposed Skill (Opposing), through the Check Resolution Stub. The result shows
// the best-vs-worst pairings (worst Supporting vs best Opposing, and best vs
// worst), each netted; Confirm logs every roll. Character / target selection
// uses the shared _creature_multiselect partial.
export class TurnMultiple {
  static ensureLoaded(container) {
    if (!container || container.dataset.tmLoaded) return;
    container.dataset.tmLoaded = '1';
    container._actors = new Set();
    container._targets = new Set();

    container.addEventListener('click', (e) => TurnMultiple._onClick(container, e));
    container.addEventListener('change', (e) => {
      if (e.target.closest && e.target.closest('.result-input')) TurnMultiple._net(container);
    });
  }

  static _step(container, key) { return container.querySelector('.dm-mult-step[data-mult-step="' + key + '"]'); }
  static _show(container, key) { const s = TurnMultiple._step(container, key); if (s) s.hidden = false; }

  static _onClick(container, e) {
    const t = e.target;
    const opt = t.closest && t.closest('.ms-opt');
    if (opt && container.contains(opt)) { return TurnMultiple._toggle(container, opt); }
    if (t.closest && t.closest('.dm-mult-next')) { return TurnMultiple._show(container, 'mode'); }
    const mode = t.closest && t.closest('.dm-mult-mode');
    if (mode) { return TurnMultiple._mode(container, mode.getAttribute('data-mode')); }
    const skill = t.closest && t.closest('.dm-mult-skill');
    if (skill) { return TurnMultiple._skill(container, skill); }
    if (t.closest && t.closest('.dm-mult-roll')) { return TurnMultiple._roll(container); }
    const itemConfirm = t.closest && t.closest('.dm-mult-item-confirm');
    if (itemConfirm) { return TurnMultiple._useItem(container, itemConfirm.getAttribute('data-item')); }
    const item = t.closest && t.closest('.dm-mult-item');
    if (item) { return TurnMultiple._previewItem(container, item); }
    if (t.closest && t.closest('.btn-confirm')) { setTimeout(() => logCheckRolls(container.querySelector('.dm-mult-result')), 0); }
  }

  static _actorQuery(container) {
    return Array.from(container._actors).map((id) => 'actors[]=' + encodeURIComponent(id)).join('&');
  }

  static _mode(container, mode) {
    if (mode === 'skill') { TurnMultiple._show(container, 'skill'); return; }
    const box = TurnMultiple._step(container, 'items');
    box.hidden = false;
    box.innerHTML = '<p class="ta-attack-loading">Loading items…</p>';
    fetch('/dm/multiple/items?' + TurnMultiple._actorQuery(container), { headers: { Accept: 'text/html' } })
      .then((r) => r.text()).then((html) => { box.innerHTML = html; })
      .catch(() => { box.innerHTML = '<p class="ta-warn">Could not load items.</p>'; });
  }

  // Picking an Item shows a confirm preview (the Magic Toxicity each selected
  // Character will take) — it is not applied until Confirm is pushed.
  static _previewItem(container, btn) {
    const itemType = btn.getAttribute('data-item');
    container.querySelectorAll('.dm-mult-item').forEach((b) => b.classList.toggle('cb-opt-selected', b === btn));
    const box = container.querySelector('.dm-mult-item-preview');
    if (!box) return;
    box.innerHTML = '<p class="ta-attack-loading">Loading…</p>';
    fetch('/dm/multiple/item_preview?item_type=' + encodeURIComponent(itemType) + '&' + TurnMultiple._actorQuery(container),
      { headers: { Accept: 'text/html' } })
      .then((r) => r.text()).then((html) => { box.innerHTML = html; })
      .catch(() => { box.innerHTML = '<p class="ta-warn">Could not load the preview.</p>'; });
  }

  // Confirm: apply the Item to every selected Character (self, no roll) and
  // subtract one from each, then show what was used.
  static _useItem(container, itemType) {
    const box = container.querySelector('.dm-mult-item-preview');
    fetch('/dm/multiple/use_item', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ item_type: itemType, actors: Array.from(container._actors) })
    })
      .then((r) => r.json()).then((res) => {
        const lines = (res && res.results || []).map((x) => x.name + ' used ' + x.item).join('<br>');
        if (box) box.innerHTML = '<div class="dm-mult-net">' + (lines || 'No one carried that item.') + '</div>';
      })
      .catch(() => { if (box) box.innerHTML = '<p class="ta-warn">Could not use the item.</p>'; });
  }

  static _toggle(container, btn) {
    const set = btn.getAttribute('data-ms-group') === 'targets' ? container._targets : container._actors;
    const id = btn.getAttribute('data-id');
    if (set.has(id)) { set.delete(id); btn.classList.remove('cb-opt-selected'); }
    else { set.add(id); btn.classList.add('cb-opt-selected'); }
    const next = container.querySelector('.dm-mult-next');
    if (next) next.disabled = container._actors.size === 0;
  }

  static _skill(container, btn) {
    container._skill = btn.getAttribute('data-skill');
    container.querySelectorAll('.dm-mult-skill').forEach((b) => b.classList.toggle('cb-opt-selected', b === btn));
    TurnMultiple._show(container, 'targets');
  }

  static _roll(container) {
    if (!container._skill || container._actors.size === 0) return;
    const res = container.querySelector('.dm-mult-result');
    res.innerHTML = '<p class="ta-attack-loading">Loading roll…</p>';
    let q = Array.from(container._actors).map((id) => 'actors[]=' + encodeURIComponent(id)).join('&') +
            '&skill=' + encodeURIComponent(container._skill);
    container._targets.forEach((id) => { q += '&targets[]=' + encodeURIComponent(id); });
    fetch('/dm/skill_check?' + q, { headers: { Accept: 'text/html' } })
      .then((r) => (r.ok ? r.text() : Promise.reject()))
      .then((html) => { res.innerHTML = html + '<div class="dm-mult-net" hidden></div>'; })
      .catch(() => { res.innerHTML = '<p class="ta-warn">Could not roll the check.</p>'; });
  }

  static _net(container) {
    renderCheckNet(container.querySelector('.dm-mult-result'), container.querySelector('.dm-mult-net'));
  }
}
