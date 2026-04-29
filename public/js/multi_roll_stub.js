// multi_roll_stub bundles N single roll_stubs into one panel. All the
// per-row interaction (Roll, Reroll Luck, Result/Crits inputs) lives
// in the child stubs themselves, so this file only wires the top-level
// Roll All and Confirm All buttons. Roll All triggers each child's
// Roll handler; Confirm All reads the children's editable Result/Crits
// inputs and emits a single `multiroll:confirm` event with one row
// per child, keyed by the configured roll key.
(function() {
  function cfg(stubId) { return (window.multiRollConfigs || {})[stubId]; }

  function rootEl(stubId) {
    return document.querySelector('.multi-roll-stub[data-stub-id="' + stubId + '"]');
  }

  function readInt(id) {
    var el = document.getElementById(id);
    if (!el) return null;
    var n = parseInt(el.value, 10);
    return isNaN(n) ? null : n;
  }

  window.multiRollRollAll = function(stubId) {
    var c = cfg(stubId);
    if (!c) return;
    c.childIds.forEach(function(id) {
      if (typeof window.rollStubRoll === 'function') window.rollStubRoll(id);
    });
  };

  window.multiRollConfirmAll = function(stubId) {
    var c = cfg(stubId);
    var root = rootEl(stubId);
    if (!c || !root) return;
    var rows = c.childIds.map(function(id, i) {
      return {
        key:       c.rollKeys[i],
        successes: readInt('roll-stub-result-' + id),
        criticals: readInt('roll-stub-crits-' + id)
      };
    });
    root.dispatchEvent(new CustomEvent('multiroll:confirm', {
      bubbles: true,
      detail: { stubId: stubId, rows: rows }
    }));
  };
})();
