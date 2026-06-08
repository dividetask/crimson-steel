// Shared helper for the Turn Action panel: surface an action's Commit button
// in the action menu's confirm slot (the top-right of the stub), so the DM
// confirms a rolled Attack / Cast without reaching down to the result. The
// slotted button is a proxy — app.js routes its click to the real Commit
// button rendered in the result (see the `.ta-commit-proxy` handler).
export function placeCommitProxy(container, label) {
  const panel = container.closest && container.closest('.turn-action');
  const slot = panel && panel.querySelector('.ta-confirm-slot');
  if (!slot) return;
  const safe = String(label).replace(/[&<>"]/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]
  ));
  slot.innerHTML = '<button type="button" class="ce-btn ta-commit-proxy">' + safe + '</button>';
}
