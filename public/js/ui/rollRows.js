// Shared dynamic modifier-row rendering for the Roll table.
//
// Roll modifiers (reroll / mass-reroll / nudge / Luck) are composed
// client-side, so their badge rows above the dice are created in JS — not
// server-seeded. Both the Save Resolution stub (stepMachine.js) and the Action
// Builder (actionBuilder.js) use this so the behaviour is identical
// wherever the Roll stub is mounted. The Roll's `.row-initial` carries the
// rowspanned cells (character / result / lock); this keeps their rowspan in
// sync as modifier rows come and go.
export class RollRows {
  // Add, update, or remove a modifier row on `group` (a tbody.roll-group).
  //   rowClass — the row's class selector, e.g. '.row-reroll'.
  //   col      — which modifier column the badge sits in: 0 = first (reroll),
  //              1 = second (nudge).
  //   badgeText — the badge label; falsy removes the row.
  //   tooltip  — optional badge tooltip.
  static setModRow(group, rowClass, col, badgeText, tooltip) {
    const cls = rowClass.replace(/^\./, '');
    const row = group.querySelector(rowClass);
    if (!badgeText) {
      if (row) { row.remove(); RollRows.reflowRowspan(group); }
      return;
    }
    if (row) {
      const badge = row.querySelector('.mod-badge');
      if (badge) { badge.textContent = badgeText; badge.setAttribute('data-tooltip', tooltip || ''); }
      return;
    }
    const tr = document.createElement('tr');
    tr.className = 'modifier-row ' + cls;
    const badgeHtml = '<span class="mod-badge ' + (col === 1 ? 'mod-nudge' : 'mod-reroll') +
      '" data-tooltip="' + (tooltip || '') + '"></span>';
    tr.innerHTML = '<td class="mod-cell">' + (col === 0 ? badgeHtml : '') + '</td>' +
                   '<td class="mod-cell">' + (col === 1 ? badgeHtml : '') + '</td>' +
                   '<td class="dice-cell"></td>';
    // Set the text via textContent so badgeText is never interpreted as HTML.
    tr.querySelector('.mod-badge').textContent = badgeText;
    group.appendChild(tr);
    RollRows.reflowRowspan(group);
  }

  // Re-span the Roll's `.row-initial` cells across every row in the group.
  static reflowRowspan(group) {
    const n = group.querySelectorAll('tr').length;
    const initial = group.querySelector('.row-initial');
    if (!initial) return;
    initial.querySelectorAll('td[rowspan]').forEach((td) => td.setAttribute('rowspan', String(n)));
  }
}
