// Shared helper for the Turn Action panel: surface an action's Commit button
// in the action menu's confirm slot (the top-right of the stub), so the DM
// confirms a rolled Attack / Cast without reaching down to the result. The
// slotted button is a proxy — app.js routes its click to the real Commit
// button rendered in the result (see the `.ta-commit-proxy` handler).
export function placeCommitProxy(container, label) {
  // The confirm slot lives in this action's own Action row (folded into its
  // builder / pane), so scope to the container — every pane now has one.
  const slot = container && container.querySelector && container.querySelector('.ta-confirm-slot');
  if (!slot) return;
  const safe = String(label).replace(/[&<>"]/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]
  ));
  slot.innerHTML = '<button type="button" class="ce-btn ta-commit-proxy">' + safe + '</button>';
}

// The "Action" row markup — the chosen action in the same pattern as the
// builder's step rows (an uppercase "Action" label, the action's name, a Change
// button that re-opens the action menu, and the confirm slot the Commit proxy
// lands in). Shared so builder actions (folded in) and builder-less ones
// (Move / Item) render the identical row.
export function actionRowHtml(label) {
  const safe = String(label == null ? '' : label).replace(/[&<>"]/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]
  ));
  // The confirm slot sits BEFORE the Change button so the Change stays flush at
  // the right edge — aligned with the step rows' Change buttons — whether or not
  // a Commit proxy is present.
  return '<div class="step-summary ta-action-row">' +
    '<span class="step-summary-label">Action</span>' +
    '<span class="step-summary-value ta-action-name">' + safe + '</span>' +
    '<span class="ta-confirm-slot"></span>' +
    '<button type="button" class="ta-change"><span class="cr-change-icon">↶</span> Change</button>' +
    '</div>';
}

// Fold the chosen action into the builder as the FIRST row of its step-summary
// list. Idempotent — updates the label if the row already exists.
export function mountActionRow(builderRoot, label) {
  if (!builderRoot) return;
  const summaries = builderRoot.querySelector('.step-summaries');
  if (!summaries) return;
  let row = summaries.querySelector('.ta-action-row');
  if (!row) {
    summaries.insertAdjacentHTML('afterbegin', actionRowHtml(label));
  } else {
    const name = row.querySelector('.ta-action-name');
    if (name) name.textContent = label || '';
  }
}

