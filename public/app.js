// Entry point for the Status-page stubs. Wires document-level event
// delegation to the UI controllers. All dice math lives in the Dice /
// Check Resolution modules under /js; the controllers under /js/ui drive
// the DOM.
import { RollController } from './js/ui/rollController.js';
import { RollsWrapper } from './js/ui/rollsWrapper.js';
import { StepMachine } from './js/ui/stepMachine.js';
import { SavePreview } from './js/ui/savePreview.js';

document.addEventListener('click', function (e) {
  const badge = e.target.closest('.mod-badge');
  if (badge) {
    badge.classList.add('show-tip');
    if (badge._tipTimer) clearTimeout(badge._tipTimer);
    badge._tipTimer = setTimeout(function () {
      badge.classList.remove('show-tip');
    }, 3000);
    return;
  }

  const rollBtn = e.target.closest('.btn-roll-all');
  if (rollBtn) {
    const wrapper = rollBtn.closest('.rolls-wrapper');
    if (wrapper) RollController.rollAll(wrapper);
    return;
  }

  if (e.target.closest('.btn-confirm-all')) {
    const save = e.target.closest('.save-resolution');
    if (save) RollsWrapper.confirmAllInSave(save);
    return;
  }

  const confirmBtn = e.target.closest('.btn-confirm');
  if (confirmBtn) {
    const wrap = confirmBtn.closest('.rolls-wrapper');
    if (wrap) RollsWrapper.collapse(wrap);
    return;
  }

  const changeBtn = e.target.closest('.btn-rolls-change');
  if (changeBtn) {
    const wrap2 = changeBtn.closest('.rolls-wrapper');
    if (wrap2) RollsWrapper.expand(wrap2);
    return;
  }

  const lockBtn = e.target.closest('.lock-btn');
  if (lockBtn) {
    lockBtn.classList.toggle('locked');
    return;
  }

  const modBtn = e.target.closest('.cr-mod-btn');
  if (modBtn) {
    StepMachine.handleModClick(modBtn);
    return;
  }

  const stepNone = e.target.closest('.cr-step-none');
  if (stepNone) {
    StepMachine.handleStepNone(stepNone);
    return;
  }

  const stepChange = e.target.closest('.cr-step-change');
  if (stepChange) {
    StepMachine.handleStepChange(stepChange);
    return;
  }

  const saveConfirm = e.target.closest('.btn-save-confirm');
  if (saveConfirm) {
    SavePreview.handleConfirm(saveConfirm);
    return;
  }
});

document.addEventListener('change', function (e) {
  SavePreview.syncFromResultInput(e.target);
});

(function () {
  function makeOverlay(extraClass) {
    var overlay = document.createElement('div');
    overlay.className = 'ce-modal ' + extraClass;
    var close = document.createElement('button');
    close.type = 'button';
    close.className = 'ce-modal-close';
    close.setAttribute('aria-label', 'Close');
    close.innerHTML = '&times;';
    overlay.appendChild(close);

    function dismiss() {
      overlay.remove();
      document.removeEventListener('keydown', escHandler);
      document.body.classList.remove('ce-modal-open');
    }
    function escHandler(e) { if (e.key === 'Escape') dismiss(); }

    close.addEventListener('click', dismiss);
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) dismiss();
    });
    document.addEventListener('keydown', escHandler);
    document.body.classList.add('ce-modal-open');
    document.body.appendChild(overlay);
    return overlay;
  }

  function openImageLightbox(src) {
    var overlay = makeOverlay('ce-modal-image-modal');
    var stage = document.createElement('div');
    stage.className = 'ce-modal-image-stage';
    var img = document.createElement('img');
    img.src = src;
    img.alt = '';
    img.className = 'ce-modal-image';
    img.draggable = false;
    stage.appendChild(img);

    var hint = document.createElement('div');
    hint.className = 'ce-modal-image-hint';
    hint.textContent = 'Scroll or pinch to zoom · drag to pan · double-click to reset · Esc to close';
    overlay.appendChild(hint);

    overlay.insertBefore(stage, overlay.firstChild);

    var scale = 1, tx = 0, ty = 0;
    var pointers = new Map();
    var dragStart = null;
    var pinchStart = null;

    function apply() {
      img.style.transform =
        'translate(' + tx.toFixed(2) + 'px, ' + ty.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ')';
    }
    apply();

    function reset() { scale = 1; tx = 0; ty = 0; apply(); }

    stage.addEventListener('wheel', function (e) {
      e.preventDefault();
      var delta = -e.deltaY * 0.0015;
      var next = Math.max(0.1, Math.min(20, scale * (1 + delta)));
      var rect = img.getBoundingClientRect();
      var cx = e.clientX - (rect.left + rect.width / 2);
      var cy = e.clientY - (rect.top + rect.height / 2);
      tx -= cx * (next / scale - 1);
      ty -= cy * (next / scale - 1);
      scale = next;
      apply();
    }, { passive: false });

    stage.addEventListener('dblclick', reset);

    stage.addEventListener('pointerdown', function (e) {
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      stage.setPointerCapture(e.pointerId);

      if (pointers.size === 1) {
        dragStart = { x: e.clientX, y: e.clientY, tx: tx, ty: ty };
      } else if (pointers.size === 2) {
        var pts = Array.from(pointers.values());
        var dx = pts[0].x - pts[1].x;
        var dy = pts[0].y - pts[1].y;
        pinchStart = {
          dist: Math.hypot(dx, dy),
          scale: scale,
          midX: (pts[0].x + pts[1].x) / 2,
          midY: (pts[0].y + pts[1].y) / 2,
          tx: tx, ty: ty
        };
        dragStart = null;
      }
    });

    stage.addEventListener('pointermove', function (e) {
      if (!pointers.has(e.pointerId)) return;
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

      if (pointers.size === 1 && dragStart) {
        tx = dragStart.tx + (e.clientX - dragStart.x);
        ty = dragStart.ty + (e.clientY - dragStart.y);
        apply();
      } else if (pointers.size === 2 && pinchStart) {
        var pts = Array.from(pointers.values());
        var dx = pts[0].x - pts[1].x;
        var dy = pts[0].y - pts[1].y;
        var dist = Math.hypot(dx, dy);
        scale = Math.max(0.1, Math.min(20, pinchStart.scale * (dist / pinchStart.dist)));
        apply();
      }
    });

    function release(e) {
      pointers.delete(e.pointerId);
      if (pointers.size < 2) pinchStart = null;
      if (pointers.size === 0) dragStart = null;
    }
    stage.addEventListener('pointerup', release);
    stage.addEventListener('pointercancel', release);
  }

  function openTextModal(card) {
    var overlay = makeOverlay('ce-modal-text-modal');
    var stage = document.createElement('div');
    stage.className = 'ce-modal-text-stage';

    var titleEl = card.querySelector('.ce-title');
    if (titleEl) {
      var title = document.createElement('div');
      title.className = 'ce-modal-text-title ' + (titleEl.className || '');
      title.innerHTML = titleEl.innerHTML;
      stage.appendChild(title);
    }
    var bodySrc = card.querySelector('.ce-body');
    if (bodySrc) {
      var clone = bodySrc.cloneNode(true);
      clone.removeAttribute('data-text-modal');
      clone.removeAttribute('tabindex');
      clone.removeAttribute('role');
      clone.style.height = 'auto';
      clone.style.overflow = 'visible';
      clone.style.cursor = 'auto';
      clone.style.background = 'transparent';
      stage.appendChild(clone);
    }
    overlay.insertBefore(stage, overlay.firstChild);
  }

  document.addEventListener('click', function (e) {
    var img = e.target.closest('[data-lightbox="1"]');
    if (img) {
      e.preventDefault();
      var src = img.tagName === 'IMG' ? img.getAttribute('src') : img.getAttribute('href');
      openImageLightbox(src);
      return;
    }
    var body = e.target.closest('[data-text-modal="1"]');
    if (body) {
      var card = body.closest('.ce-card');
      if (card) {
        e.preventDefault();
        openTextModal(card);
      }
    }
  });

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    var body = e.target.closest && e.target.closest('[data-text-modal="1"]');
    if (!body) return;
    e.preventDefault();
    var card = body.closest('.ce-card');
    if (card) openTextModal(card);
  });

  // -- Roster Sidebar: <details> open/closed persistence ---------------
  //
  // Each group's open state lives in localStorage under
  // `cs-roster-group:<data-group-key>`. We restore on load and write
  // on toggle.
  var ROSTER_STORAGE_PREFIX = 'cs-roster-group:';

  function restoreRosterGroups() {
    var groups = document.querySelectorAll('.cs-roster-sidebar .cs-roster-group');
    groups.forEach(function (g) {
      var key = g.getAttribute('data-group-key');
      if (!key) return;
      var stored = null;
      try { stored = localStorage.getItem(ROSTER_STORAGE_PREFIX + key); } catch (e) {}
      if (stored === 'open') {
        g.setAttribute('open', '');
      } else if (stored === 'closed') {
        g.removeAttribute('open');
      }
    });
  }

  document.addEventListener('DOMContentLoaded', restoreRosterGroups);
  // Also run immediately in case the script tag is at the bottom and
  // DOMContentLoaded already fired.
  if (document.readyState === 'interactive' || document.readyState === 'complete') {
    restoreRosterGroups();
  }

  document.addEventListener('toggle', function (e) {
    var g = e.target;
    if (!g.classList || !g.classList.contains('cs-roster-group')) return;
    var key = g.getAttribute('data-group-key');
    if (!key) return;
    try {
      localStorage.setItem(ROSTER_STORAGE_PREFIX + key, g.open ? 'open' : 'closed');
    } catch (e2) { /* localStorage unavailable */ }
  }, true);

  // -- Roster Sidebar: Encounter mutations -----------------------------
  //
  // creatures_roster_sidebar_stub.md / encounter_design.md.
  //
  //  Active/Absent toggle (Players + NPCs) — POST /encounter/set_pc_active
  //   or /encounter/set_npc_active.
  //  + button (Creature Template row) — POST /encounter/spawn_and_add;
  //   spawns a fresh Creature from the template and adds it as a Combatant.
  //  − button (spawned-instance row) — POST /encounter/delete_creature;
  //   removes the Combatant(s) and deletes the Creature record.
  //
  // After any mutation we re-fetch the server-rendered sidebar fragment
  // so the inline "(N)" count and the spawned-instance rows update from
  // the source of truth, then restore the collapse state.

  function postForm(url, body) {
    var fd = new FormData();
    Object.keys(body).forEach(function (k) { fd.append(k, body[k]); });
    return fetch(url, { method: 'POST', body: fd })
      .then(function (r) { return r.json().catch(function () { return {}; }); });
  }

  function currentSheetParams() {
    var qs = new URLSearchParams(window.location.search);
    var creatureId = qs.get('creature_id') || '';
    var detail = qs.get('detail') === 'full' ? 'full' : 'minimal';
    return { creatureId: creatureId, detail: detail };
  }

  function refreshSidebar() {
    var sidebar = document.querySelector('.cs-roster-sidebar');
    if (!sidebar) return Promise.resolve();
    var p = currentSheetParams();
    return fetch('/encounter/roster_sidebar?creature_id=' + encodeURIComponent(p.creatureId) + '&detail=' + p.detail, {
      headers: { 'Accept': 'text/html' }
    })
      .then(function (r) { return r.text(); })
      .then(function (html) {
        var current = document.querySelector('.cs-roster-sidebar');
        if (current) {
          current.outerHTML = html;
          restoreRosterGroups();
        }
      })
      .catch(function () { /* leave the sidebar as-is on failure */ });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-active-toggle');
    if (!btn) return;
    e.preventDefault();
    var creatureId = btn.getAttribute('data-creature-id');
    var kind       = btn.getAttribute('data-roster-kind');
    if (!creatureId || (kind !== 'pc' && kind !== 'npc')) return;
    var nextActive = !btn.classList.contains('cs-player-active');
    var path = kind === 'pc' ? '/encounter/set_pc_active' : '/encounter/set_npc_active';
    postForm(path, { creature_id: creatureId, active: nextActive ? 'true' : 'false' })
      .then(refreshSidebar);
  });

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-roster-add');
    if (!btn) return;
    e.preventDefault();
    var templateId = btn.getAttribute('data-template-id') || btn.getAttribute('data-creature-id');
    if (!templateId) return;
    postForm('/encounter/spawn_and_add', { template_id: templateId }).then(refreshSidebar);
  });

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-roster-delete');
    if (!btn) return;
    e.preventDefault();
    var creatureId = btn.getAttribute('data-creature-id');
    if (!creatureId) return;
    postForm('/encounter/delete_creature', { creature_id: creatureId }).then(refreshSidebar);
  });

  // -- Encounter Roll Result panel -------------------------------------
  //
  // creatures_random_encounter_roll_result_stub.md: clicking the Roll button
  // on a sidebar Random Encounter Table row OR on the result panel itself
  // rolls the table, spawns the Creatures, adds them to the roster, and
  // renders the result panel above the main sheet. The sidebar is then
  // refreshed so the new spawned-instance rows appear under their templates.
  function fetchEncounterRoll(tableId) {
    var slot = document.getElementById('random-encounter-roll-result');
    if (!slot) return;
    fetch('/random_encounters/roll/' + encodeURIComponent(tableId), {
      headers: { 'Accept': 'text/html' }
    })
      .then(function (r) { return r.text(); })
      .then(function (html) { slot.innerHTML = html; return refreshSidebar(); })
      .catch(function () { /* leave previous panel in place */ });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-random-encounter-roll-btn');
    if (!btn) return;
    e.preventDefault();
    var tableId = btn.getAttribute('data-table-id');
    if (!tableId) return;
    fetchEncounterRoll(tableId);
  });

  // -- Combat Tracker: double-click to edit Initiative (DM only) -------
  //
  // encounter_initiative_stub.md. Double-clicking an Initiative cell
  // swaps it for a text input with Set / Cancel. The server parses the
  // value (dropping invalid characters, sorting the rest) and the
  // reload re-sorts the tracker, moving the Combatant to its new slot.
  document.addEventListener('dblclick', function (e) {
    var cell = e.target.closest && e.target.closest('.initiative-init-editable');
    if (!cell || cell.querySelector('input')) return;
    var combatantId = cell.getAttribute('data-combatant-id');
    if (!combatantId) return;
    var original = cell.innerHTML;
    var current  = cell.getAttribute('data-init') || '';

    cell.innerHTML = '';
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'initiative-init-input';
    input.value = current;
    input.size = 5;
    var set = document.createElement('button');
    set.type = 'button'; set.className = 'ce-btn ce-btn-tight'; set.textContent = 'Set';
    var cancel = document.createElement('button');
    cancel.type = 'button'; cancel.className = 'ce-btn ce-btn-tight'; cancel.textContent = 'Cancel';
    cell.appendChild(input); cell.appendChild(set); cell.appendChild(cancel);
    input.focus(); input.select();

    function restore() { cell.innerHTML = original; }
    function commit() {
      postForm('/encounter/set_initiative', { combatant_id: combatantId, value: input.value })
        .then(function () { window.location.reload(); })
        .catch(restore);
    }
    cancel.addEventListener('click', restore);
    set.addEventListener('click', commit);
    input.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter') { ev.preventDefault(); commit(); }
      else if (ev.key === 'Escape') { ev.preventDefault(); restore(); }
    });
  });
})();
