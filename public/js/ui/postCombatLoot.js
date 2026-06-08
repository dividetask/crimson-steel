// Post-Combat Cleanup (equipment_post_combat_creatures_stub.md): keep the
// combined-loot preview in sync with the Loot/Ignore toggles. Each row
// carries its items in data-loot (JSON) and a data-loot-table flag; the
// preview aggregates the items of every row still set to Loot (its loot
// checkbox unchecked — checked means Ignore). The server renders the
// default (all rows Loot); this refines it as the DM toggles.
export class PostCombatLoot {
  static initAll() {
    document.querySelectorAll('.pcc-form').forEach((f) => PostCombatLoot._wire(f));
  }

  static _wire(form) {
    if (form.dataset.pccWired) return;
    form.dataset.pccWired = '1';
    form.addEventListener('change', (e) => {
      if (e.target.matches('input[name^="loot_"]')) PostCombatLoot._recompute(form);
    });
    PostCombatLoot._recompute(form);
  }

  static _recompute(form) {
    const out = form.querySelector('.pcc-loot-list');
    if (!out) return;
    const totals = new Map();
    let random = false;
    form.querySelectorAll('.pcc-row').forEach((row) => {
      const box = row.querySelector('input[name^="loot_"]');
      if (box && box.checked) return; // checked = Ignore
      let items = [];
      try { items = JSON.parse(row.dataset.loot || '[]'); } catch (e) { /* skip */ }
      items.forEach((it) => totals.set(it.name, (totals.get(it.name) || 0) + it.quantity));
      if (row.dataset.lootTable === '1') random = true;
    });

    let html = '';
    totals.forEach((qty, name) => {
      html += '<li>' + (qty > 1 ? qty + '× ' : '') + PostCombatLoot._esc(name) + '</li>';
    });
    if (random) html += '<li class="pcc-loot-random">+ random loot</li>';
    if (!html) html = '<li class="pcc-loot-none">Nothing</li>';
    out.innerHTML = html;
  }

  static _esc(s) {
    const d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }
}
