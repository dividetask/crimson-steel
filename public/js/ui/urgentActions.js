// Urgent Actions panel (conditions_bulk_affliction_stub.md). Two jobs, both
// pure DOM — the dice math and the per-save Confirm live in the Conditions
// Save Resolution Stub / SavePreview, and the bulk End Turn is a plain form
// POST:
//   1. "Show actions for" checkboxes toggle each Creature's save block.
//   2. The Summary line for a Creature is rewritten once one of its saves is
//      rolled, so the DM reads the previewed outcome before pressing End Turn.
export class UrgentActions {
  // A "Show actions for" checkbox changed: show/hide that Creature's group.
  static handleToggle(target) {
    const cb = target.closest('.ua-toggle');
    if (!cb) return;
    const panel = cb.closest('.urgent-actions');
    if (!panel) return;
    const id = cb.getAttribute('data-combatant');
    const group = panel.querySelector('.ua-group[data-combatant="' + id + '"]');
    if (group) group.classList.toggle('ua-hidden', !cb.checked);
  }

  // A save inside the panel changed (Roll All populated dice, or the DM
  // typed a DoIS / overrode a preview field): refresh that Creature's
  // Summary line from the live state of its save stubs.
  static refreshFrom(target) {
    const group = target.closest('.ua-group');
    if (!group) return;
    const panel = group.closest('.urgent-actions');
    if (!panel) return;
    const id = group.getAttribute('data-combatant');
    const line = panel.querySelector('.ua-summary-line[data-combatant="' + id + '"] .ua-summary-text');
    if (!line) return;

    const parts = [];
    group.querySelectorAll('.save-resolution').forEach(function (save) {
      const text = UrgentActions.saveSummary(save);
      if (text) parts.push(text);
    });
    if (parts.length) line.textContent = parts.join('; ');
  }

  // One save's contribution to the Summary line. Returns the pre-roll
  // "<Category> (potency N)" until the save has been rolled, then the
  // previewed outcome "<Category>: <effect>, potency <before>→<after>".
  static saveSummary(save) {
    let data;
    try { data = JSON.parse(save.dataset.preview || '{}'); } catch (e) { data = {}; }
    const category = UrgentActions.category(save);
    const before = data.potency_before;

    const netInput = save.querySelector('.sp-net-mag');
    const potInput = save.querySelector('.sp-new-potency');
    const rolled = netInput && netInput.value !== '' && potInput && potInput.value !== '';
    if (!rolled) {
      return category + ' (potency ' + (before == null ? '?' : before) + ')';
    }

    const netMag = parseInt(netInput.value, 10) || 0;
    const newPot = parseInt(potInput.value, 10);
    const effect = UrgentActions.effectText(data.effect || {}, netMag);
    return category + ': ' + effect + ', potency ' + before + '→' + newPot;
  }

  // The Affliction Category, read off the save stub's header title
  // ("<Category> Save (Potency N) - <Name>").
  static category(save) {
    const title = save.querySelector('.rolls-header .rolls-title, .rolls-header h3, .rolls-title');
    const text = (title ? title.textContent : '') || '';
    const m = text.match(/^(.*?)\s+Save\b/);
    return m ? m[1].trim() : 'Save';
  }

  // Human-readable effect for a previewed Net Magnitude.
  static effectText(effect, netMag) {
    if (netMag <= 0) return 'saved';
    const sev = effect.severity ? effect.severity + ' ' : '';
    switch (effect.kind) {
      case 'hit_point_damage': return netMag + ' ' + sev + 'damage';
      case 'ability_damage':   return netMag + ' ' + sev + String(effect.attribute || '').toUpperCase() + ' damage';
      case 'named_effect':     return effect.name || 'effect';
      default:                 return netMag + ' magnitude';
    }
  }
}
