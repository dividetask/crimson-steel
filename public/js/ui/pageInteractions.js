// Standalone page interactions carried over from Version3: the image
// lightbox (Notes/Scene), the text-card modal, the Creatures roster
// expand/collapse groups, and encounter-roll fetching. Self-contained —
// no dependency on the dice/roll controllers. Runs on import.
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

  // -- Roster Sidebar: Player Active/Absent toggle ---------------------
  //
  // creatures_roster_sidebar_stub.md: Players have a single toggle
  // instead of +/- buttons. Click flips the state visually; persistence
  // wiring is out of scope until the Combat / Players-domain UI lands.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-player-toggle');
    if (!btn) return;
    var nowActive = btn.classList.contains('cs-player-active');
    if (nowActive) {
      btn.classList.remove('cs-player-active');
      btn.classList.add('cs-player-absent');
      btn.textContent = 'Absent';
      btn.setAttribute('aria-pressed', 'false');
      btn.title = 'Mark active';
      var row = btn.closest('.cs-roster-row');
      if (row) row.classList.add('cs-player-absent');
    } else {
      btn.classList.remove('cs-player-absent');
      btn.classList.add('cs-player-active');
      btn.textContent = 'Active';
      btn.setAttribute('aria-pressed', 'true');
      btn.title = 'Mark absent';
      var row2 = btn.closest('.cs-roster-row');
      if (row2) row2.classList.remove('cs-player-absent');
    }
  });

  // -- Encounter Roll Result panel -------------------------------------
  //
  // creatures_encounter_roll_result_stub.md: clicking the Roll button
  // on a sidebar Encounter Table row OR on the result panel itself
  // fetches a fresh roll and replaces the panel above the main sheet.
  // Combat / enemy-data-file side effects are not yet wired — the
  // server returns sample roll data and the panel just renders it.
  function fetchEncounterRoll(tableId) {
    var slot = document.getElementById('encounter-roll-result');
    if (!slot) return;
    fetch('/encounters/roll/' + encodeURIComponent(tableId), {
      headers: { 'Accept': 'text/html' }
    })
      .then(function (r) { return r.text(); })
      .then(function (html) { slot.innerHTML = html; })
      .catch(function () { /* leave previous panel in place */ });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-encounter-roll-btn');
    if (!btn) return;
    e.preventDefault();
    var tableId = btn.getAttribute('data-table-id');
    if (!tableId) return;
    fetchEncounterRoll(tableId);
  });
})();
