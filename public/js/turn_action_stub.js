// Turn Action stub: clicking a left-column button shows the
// matching right-column panel. All panels are present on page
// load; we just toggle .is-active.
(function () {
  'use strict';

  function activatePanel(stub, key) {
    stub.querySelectorAll('.turn-action-menu-btn').forEach(function (btn) {
      btn.classList.toggle('is-active', btn.dataset.panel === key);
    });
    stub.querySelectorAll('.turn-action-panel').forEach(function (panel) {
      panel.classList.toggle('is-active', panel.dataset.panel === key);
    });
  }

  function init(stub) {
    stub.querySelectorAll('.turn-action-menu-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        activatePanel(stub, btn.dataset.panel);
      });
    });
  }

  document.querySelectorAll('.turn-action-stub').forEach(init);
})();
