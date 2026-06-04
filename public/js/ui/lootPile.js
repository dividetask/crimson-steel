// Loot Pile stub (equipment_loot_pile_stub.md). The stub's actions are
// plain <form> submits (Loot / Claim / Give / Delete Pile via formaction),
// so the only behavior needed here is a confirm guard for the DM's
// destructive "Delete Pile" button — keyed off the clicked submit button's
// data-confirm so the other buttons in the same form submit freely.
export class LootPile {
  static initAll() { /* nothing to wire up-front */ }

  static handleConfirmSubmit(e) {
    const btn = e.submitter;
    const message = btn && btn.getAttribute && btn.getAttribute('data-confirm');
    if (message && !window.confirm(message)) e.preventDefault();
  }
}
