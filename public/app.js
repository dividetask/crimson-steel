// Entry point for the Status-page stubs. Wires document-level event
// delegation to the UI controllers. All dice math lives in the Dice /
// Check Resolution modules under /js; the controllers under /js/ui drive
// the DOM.
import { RollController } from './js/ui/rollController.js';
import { RollsWrapper } from './js/ui/rollsWrapper.js';
import { StepMachine } from './js/ui/stepMachine.js';
import { SavePreview } from './js/ui/savePreview.js';
import { TurnAttack } from './js/ui/turnAttack.js';
import { AtlasMap } from './js/ui/atlasMap.js';
import { TurnCast } from './js/ui/turnCast.js';
import { TurnItem } from './js/ui/turnItem.js';
import { TurnSkill } from './js/ui/turnSkill.js';
import { TurnMultiple } from './js/ui/turnMultiple.js';
import { ActionBuilder } from './js/ui/actionBuilder.js';
import { TurnMove } from './js/ui/turnMove.js';
import { TurnSpecial } from './js/ui/turnSpecial.js';
import { LootPile } from './js/ui/lootPile.js';
import { PostCombatLoot } from './js/ui/postCombatLoot.js';
import { UrgentActions } from './js/ui/urgentActions.js';
import { DiceRenderer } from './js/ui/diceRenderer.js';
import { CompactRoll } from './js/ui/compactRoll.js';

// Loot Pile: confirm the DM's Delete Pile before it submits.
document.addEventListener('submit', function (e) {
  LootPile.handleConfirmSubmit(e);
});

document.addEventListener('click', function (e) {
  // Minimal-sheet Attribute popup (Check / Save / untrained Dice Cap +
  // Bonus). Hover / keyboard focus reveal it via CSS; a click toggles a
  // sticky open state (so it works on touch and stays put). Any click
  // closes popups on other Attribute cells.
  const attrCell = e.target.closest('.cs-attr-has-pop');
  document.querySelectorAll('.cs-attr-has-pop.cs-pop-open').forEach(function (c) {
    if (c !== attrCell) c.classList.remove('cs-pop-open');
  });
  if (attrCell) {
    attrCell.classList.toggle('cs-pop-open');
    return;
  }

  // Log page: clicking a TN cell toggles a sticky popup with the TN math.
  const tnCell = e.target.closest('.log-tn-has-pop');
  document.querySelectorAll('.log-tn-has-pop.log-tn-open').forEach(function (c) {
    if (c !== tnCell) c.classList.remove('log-tn-open');
  });
  if (tnCell) {
    tnCell.classList.toggle('log-tn-open');
    return;
  }

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
  // Urgent Actions: toggle a Creature's save block, and refresh its Summary
  // line when one of its saves changes.
  if (e.target.closest('.ua-toggle')) UrgentActions.handleToggle(e.target);
  if (e.target.closest('.urgent-actions')) UrgentActions.refreshFrom(e.target);
});

// Hovering an Attribute cell dismisses any click-stuck popup on the
// other Attribute cells, so only one Attribute popup is ever visible at
// a time (the hovered one shows via CSS :hover).
document.addEventListener('mouseover', function (e) {
  const cell = e.target.closest('.cs-attr-has-pop');
  if (!cell) return;
  document.querySelectorAll('.cs-attr-has-pop.cs-pop-open').forEach(function (c) {
    if (c !== cell) c.classList.remove('cs-pop-open');
  });
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

  // Inventory ritual book: clicking "(N rituals)" opens a scrollable
  // modal listing the inscribed rituals. The list markup lives in a
  // hidden .inv-ritual-source div on the same card.
  function openRitualModal(trigger) {
    var source = trigger.parentElement &&
      trigger.parentElement.querySelector('.inv-ritual-source');
    if (!source) return;
    var overlay = makeOverlay('ce-modal-text-modal');
    var stage = document.createElement('div');
    stage.className = 'ce-modal-text-stage';
    stage.innerHTML = source.innerHTML;
    overlay.insertBefore(stage, overlay.firstChild);
  }

  document.addEventListener('click', function (e) {
    // Explicit Expand buttons (notes / images). Real <button> elements
    // fire a click on tap in every browser, so these work even where a
    // tap on the card/image itself does not (older / touch browsers).
    var expandImgBtn = e.target.closest('[data-expand-image="1"]');
    if (expandImgBtn) {
      e.preventDefault();
      var imgWrap = expandImgBtn.closest('.ce-content') || expandImgBtn.parentElement;
      var targetImg = imgWrap && imgWrap.querySelector('[data-lightbox="1"]');
      // currentSrc reflects the <picture> the browser actually chose (WebP on
      // modern browsers, the JPG/PNG fallback on older ones).
      if (targetImg) openImageLightbox(targetImg.currentSrc || targetImg.getAttribute('src'));
      return;
    }
    var expandNoteBtn = e.target.closest('[data-expand-note="1"]');
    if (expandNoteBtn) {
      e.preventDefault();
      var noteCard = expandNoteBtn.closest('.ce-card');
      if (noteCard) openTextModal(noteCard);
      return;
    }

    var img = e.target.closest('[data-lightbox="1"]');
    if (img) {
      e.preventDefault();
      var src = img.tagName === 'IMG' ? (img.currentSrc || img.getAttribute('src')) : img.getAttribute('href');
      openImageLightbox(src);
      return;
    }
    var ritual = e.target.closest('[data-ritual-modal="1"]');
    if (ritual) {
      e.preventDefault();
      openRitualModal(ritual);
      return;
    }
    // A click anywhere on an expandable note / creature-reference card opens
    // the full-text modal — so tapping the title, the card, or the body text
    // all enlarge the note. Image clicks (the lightbox, handled above) and the
    // edit/footer controls are excluded so they keep their own behavior.
    var card = e.target.closest('.ce-card.ce-expandable');
    if (card && !e.target.closest('.ce-foot, a, button, input, textarea, select, label, summary')) {
      e.preventDefault();
      openTextModal(card);
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

  // -- Character Sheet: spell descriptions + Skill list / Skill Roll ----
  //
  // creatures_minimal_stub.md. Clicking a spell name opens its description;
  // clicking the "Skills" heading opens the full Skill list; clicking a Roll
  // button there opens the Roll Resolution Stub for that Skill. Each is a
  // server-rendered fragment dropped into a modal popup (reusing makeOverlay).
  function openFragmentModal(html, extraClass) {
    var overlay = makeOverlay('ce-modal-text-modal' + (extraClass ? ' ' + extraClass : ''));
    var stage = document.createElement('div');
    stage.className = 'ce-modal-text-stage';
    stage.innerHTML = html;
    overlay.insertBefore(stage, overlay.firstChild);
    return overlay;
  }

  function fetchIntoModal(url, extraClass) {
    fetch(url, { headers: { 'Accept': 'text/html' } })
      .then(function (r) { return r.text(); })
      .then(function (html) { openFragmentModal(html, extraClass); })
      .catch(function () { /* leave the page as-is on failure */ });
  }

  document.addEventListener('click', function (e) {
    var spell = e.target.closest && e.target.closest('.cs-spell-link');
    if (spell) {
      e.preventDefault();
      var name = spell.getAttribute('data-spell-name') || spell.textContent.trim();
      fetchIntoModal('/spell-detail?name=' + encodeURIComponent(name), 'cs-spell-modal');
      return;
    }
    var school = e.target.closest && e.target.closest('.cs-school-link');
    if (school) {
      e.preventDefault();
      var sk = school.getAttribute('data-school');
      if (sk) fetchIntoModal('/spell-school?name=' + encodeURIComponent(sk), 'cs-school-modal');
      return;
    }
    var klass = e.target.closest && e.target.closest('.cs-class-link');
    if (klass) {
      e.preventDefault();
      var ckey = klass.getAttribute('data-class-key');
      if (ckey) fetchIntoModal('/class-detail?name=' + encodeURIComponent(ckey), 'cs-class-modal');
      return;
    }
    var skillsTitle = e.target.closest && e.target.closest('.cs-skills-title');
    if (skillsTitle) {
      e.preventDefault();
      var cid = skillsTitle.getAttribute('data-creature-id');
      if (cid) fetchIntoModal('/skills-panel?creature_id=' + encodeURIComponent(cid), 'cs-skills-modal');
      return;
    }
    var rollBtn = e.target.closest && e.target.closest('.cs-skill-roll-btn');
    if (rollBtn) {
      e.preventDefault();
      var rcid = rollBtn.getAttribute('data-creature-id');
      var key  = rollBtn.getAttribute('data-skill-key');
      var group = rollBtn.closest('.cs-skill-group');
      var panel = rollBtn.closest('.cs-skills-panel');
      var slotRow = group && group.querySelector('.cs-skill-roll-row');
      var slot = slotRow && slotRow.querySelector('.cs-skill-roll-slot');
      if (!rcid || !key || !slot) return;
      // Only one Skill's roll is shown at a time — hide/clear any others.
      if (panel) {
        panel.querySelectorAll('.cs-skill-roll-row').forEach(function (row) {
          if (row === slotRow) return;
          row.hidden = true;
          var other = row.querySelector('.cs-skill-roll-slot');
          if (other) other.innerHTML = '';
        });
      }
      // The Roll button IS the roll: fetch the compact stub, reveal it inline
      // beneath the Skill row, and roll it immediately (which POSTs to the Log).
      fetch('/skill-roll?creature_id=' + encodeURIComponent(rcid) +
            '&key=' + encodeURIComponent(key), { headers: { 'Accept': 'text/html' } })
        .then(function (r) { return r.text(); })
        .then(function (html) {
          slot.innerHTML = html;
          slotRow.hidden = false;
          var compact = slot.querySelector('.compact-roll');
          if (compact) CompactRoll.roll(compact);
        })
        .catch(function () { /* leave the row as-is on failure */ });
      return;
    }
  });

  // Keyboard activation for the "Skills" heading (it is a role="button").
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    var skillsTitle = e.target.closest && e.target.closest('.cs-skills-title');
    if (!skillsTitle) return;
    e.preventDefault();
    var cid = skillsTitle.getAttribute('data-creature-id');
    if (cid) fetchIntoModal('/skills-panel?creature_id=' + encodeURIComponent(cid), 'cs-skills-modal');
  });

  // -- Roster Sidebar: <details> open/closed persistence ---------------
  //
  // Groups default to collapsed. A group's open state is remembered while
  // the DM navigates, but only for the current server run: the key is
  // scoped by the server's boot id (data-boot-id on the sidebar) and held
  // in sessionStorage, so a server restart (new boot id) reverts every
  // group to collapsed.
  function rosterStorageKey(key) {
    var aside = document.querySelector('.cs-roster-sidebar');
    var bootId = aside ? (aside.getAttribute('data-boot-id') || '') : '';
    return 'cs-roster-group:' + bootId + ':' + key;
  }

  function restoreRosterGroups() {
    var groups = document.querySelectorAll('.cs-roster-sidebar .cs-roster-group');
    groups.forEach(function (g) {
      var key = g.getAttribute('data-group-key');
      if (!key) return;
      var stored = null;
      try { stored = sessionStorage.getItem(rosterStorageKey(key)); } catch (e) {}
      // Default collapsed; only an explicit 'open' from this server run re-expands.
      if (stored === 'open') g.setAttribute('open', '');
      else g.removeAttribute('open');
    });
  }

  document.addEventListener('DOMContentLoaded', restoreRosterGroups);
  document.addEventListener('DOMContentLoaded', AtlasMap.initAll);
  document.addEventListener('DOMContentLoaded', LootPile.initAll);
  document.addEventListener('DOMContentLoaded', PostCombatLoot.initAll);
  // Also run immediately in case the script tag is at the bottom and
  // DOMContentLoaded already fired.
  if (document.readyState === 'interactive' || document.readyState === 'complete') {
    restoreRosterGroups();
    AtlasMap.initAll();
    LootPile.initAll();
    PostCombatLoot.initAll();
  }

  document.addEventListener('toggle', function (e) {
    var g = e.target;
    if (!g.classList || !g.classList.contains('cs-roster-group')) return;
    var key = g.getAttribute('data-group-key');
    if (!key) return;
    try {
      sessionStorage.setItem(rosterStorageKey(key), g.open ? 'open' : 'closed');
    } catch (e2) { /* sessionStorage unavailable */ }
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

  // Guard a mutating roster button against double-fire: a rapid double-click
  // on the small +/− buttons would otherwise spawn (or delete) twice. Claim
  // the button (disabling it so a second click can't dispatch) until the
  // request settles; refreshSidebar replaces the row, but release anyway in
  // case the request failed and the button is still on the page.
  function claimButton(btn) {
    if (btn.disabled || btn.dataset.busy === '1') return false;
    btn.dataset.busy = '1';
    btn.disabled = true;
    return true;
  }

  function releaseButton(btn) {
    btn.disabled = false;
    delete btn.dataset.busy;
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-roster-add');
    if (!btn) return;
    e.preventDefault();
    var templateId = btn.getAttribute('data-template-id') || btn.getAttribute('data-creature-id');
    if (!templateId) return;
    if (!claimButton(btn)) return;
    postForm('/encounter/spawn_and_add', { template_id: templateId })
      .then(refreshSidebar)
      .finally(function () { releaseButton(btn); });
  });

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-roster-delete');
    if (!btn) return;
    e.preventDefault();
    var creatureId = btn.getAttribute('data-creature-id');
    if (!creatureId) return;
    if (!claimButton(btn)) return;
    postForm('/encounter/delete_creature', { creature_id: creatureId })
      .then(refreshSidebar)
      .finally(function () { releaseButton(btn); });
  });

  // -- Encounter Roll Result panel -------------------------------------
  //
  // creatures_random_encounter_roll_result_stub.md: clicking the Roll button
  // on a sidebar Random Encounter Table row OR on the result panel itself
  // rolls the table, spawns the Creatures, adds them to the roster, and
  // renders the result panel above the main sheet. The sidebar is then
  // refreshed so the new spawned-instance rows appear under their templates.
  function fetchEncounterRoll(tableId, btn) {
    var slot = document.getElementById('random-encounter-roll-result');
    if (!slot) { if (btn) releaseButton(btn); return; }
    fetch('/random_encounters/roll/' + encodeURIComponent(tableId), {
      headers: { 'Accept': 'text/html' }
    })
      .then(function (r) { return r.text(); })
      .then(function (html) { slot.innerHTML = html; return refreshSidebar(); })
      .catch(function () { /* leave previous panel in place */ })
      .finally(function () { if (btn) releaseButton(btn); });
  }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.cs-random-encounter-roll-btn');
    if (!btn) return;
    e.preventDefault();
    var tableId = btn.getAttribute('data-table-id');
    if (!tableId) return;
    if (!claimButton(btn)) return;
    fetchEncounterRoll(tableId, btn);
  });

  // -- Turn Action panel: grouped action buttons ----------------------
  //
  // turn_action_stub.md. The actions are grouped under Main / Bonus / Free
  // Action headers. Clicking a generic action button (.ta-menu-btn) opens
  // that action's pane below; each pane POSTs on its own Submit. Special
  // Ability buttons are handled separately by TurnSpecial (delegated from the
  // wrapping .ta-special), which is wired eagerly on load below.

  // Collapse the category groups to the selected-action row: show the chosen
  // action's label, clear the confirm slot (no Commit ready yet). Shared with
  // TurnSpecial via the exported helper on window (see turnSpecial.js).
  function selectTurnAction(panel, label) {
    // Stash the chosen action's name; each host folds it into its builder as the
    // first step row (mountActionRow). Collapse the category menu.
    panel.dataset.actionLabel = label;
    var slot = panel.querySelector('.ta-confirm-slot');
    if (slot) slot.innerHTML = '';
    panel.classList.add('ta-has-selection');
  }
  window.__taSelectAction = selectTurnAction;

  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.ta-menu-btn');
    if (!btn) return;
    var panel = btn.closest('.turn-action');
    if (!panel) return;
    var key = btn.getAttribute('data-ta-action');
    panel.querySelectorAll('.ta-menu-btn').forEach(function (b) {
      b.classList.toggle('ta-selected', b === btn);
    });
    panel.querySelectorAll('.ta-pane').forEach(function (p) {
      p.classList.toggle('ta-pane-active', p.getAttribute('data-ta-pane') === key);
    });
    // Collapse the category groups to the selected-action row (the action's
    // name + a Change button); the action's Commit button surfaces in the
    // row's confirm slot once the roll is ready.
    selectTurnAction(panel, btn.textContent.trim());
    // Lazily build the Attack flow the first time its pane is opened.
    if (key === 'attack') {
      var container = panel.querySelector('.ta-pane[data-ta-pane="attack"] .ta-attack');
      if (container) TurnAttack.ensureLoaded(container);
    }
    // Active Spells: each channelled Spell has its own button/pane (key
    // "active_spell:<index>"). Opening the pane presents its concentration
    // options (Attack / End) first — reset to that step, hiding any attack
    // flow left open from a previous visit. The Attack option lazily loads
    // the strike builder (see the .ta-conc-attack handler below).
    if (key.indexOf('active_spell:') === 0) {
      var concPane = panel.querySelector('.ta-pane[data-ta-pane="' + key + '"]');
      if (concPane) {
        var opts = concPane.querySelector('.ta-conc-options');
        var atkHost = concPane.querySelector('.ta-active-spells');
        if (opts) opts.hidden = false;
        if (atkHost) atkHost.hidden = true;
      }
    }
    // Lazily build the Cast flow the first time its pane is opened.
    if (key === 'cast') {
      var castContainer = panel.querySelector('.ta-cast');
      if (castContainer) TurnCast.ensureLoaded(castContainer);
    }
    // Move renders its (editable) Combat-Pool result block on open.
    if (key === 'move') {
      var moveContainer = panel.querySelector('.ta-move');
      if (moveContainer) TurnMove.ensureLoaded(moveContainer);
    }
    // Lazily build the Item (Potion / Scroll) flow the first time it is opened.
    if (key === 'item') {
      var itemContainer = panel.querySelector('.ta-item');
      if (itemContainer) TurnItem.ensureLoaded(itemContainer);
    }
    // Skill (out-of-combat only): wire the Skill / target picker.
    if (key === 'skill') {
      var skillContainer = panel.querySelector('.ta-skill');
      if (skillContainer) TurnSkill.ensureLoaded(skillContainer);
    }
  });

  // Active Spells → Attack: reveal and lazily build the strike flow for the
  // channelled Spell whose options step this button belongs to. (End is a
  // plain confirm-guarded <form> POST, handled by LootPile.handleConfirmSubmit.)
  document.addEventListener('click', function (e) {
    var atkOpt = e.target.closest && e.target.closest('.ta-conc-attack');
    if (!atkOpt) return;
    var conc = atkOpt.closest('.ta-conc');
    if (!conc) return;
    var opts = conc.querySelector('.ta-conc-options');
    var atkHost = conc.querySelector('.ta-active-spells');
    if (opts) opts.hidden = true;
    if (atkHost) { atkHost.hidden = false; TurnAttack.ensureLoaded(atkHost); }
  });

  // Change (in the selected-action row): re-open the category menu and clear
  // the open action — its pane, any Special result, and the confirm slot.
  document.addEventListener('click', function (e) {
    var chg = e.target.closest && e.target.closest('.ta-change');
    if (!chg) return;
    var panel = chg.closest('.turn-action');
    if (!panel) return;
    panel.classList.remove('ta-has-selection');
    panel.querySelectorAll('.ta-menu-btn').forEach(function (b) { b.classList.remove('ta-selected'); });
    panel.querySelectorAll('.ta-pane').forEach(function (p) { p.classList.remove('ta-pane-active'); });
    panel.querySelectorAll('.ta-special-opt').forEach(function (b) { b.classList.remove('cr-mod-selected'); });
    var result = panel.querySelector('.ta-special-result');
    if (result) { result.hidden = true; result.innerHTML = ''; }
    panel.querySelectorAll('.ta-confirm-slot').forEach(function (s) { s.innerHTML = ''; });
    // Restart each already-loaded builder from its first step, so re-selecting
    // the same action asks its first question again (which Spell / which Item)
    // instead of resuming where the abandoned attempt left off.
    panel.querySelectorAll('.action-builder').forEach(function (b) { ActionBuilder.reset(b); });
  });

  // The Commit button mirrored into the selected-action row's confirm slot is
  // a proxy: clicking it triggers the active pane's real Commit (so the DM
  // confirms from the top of the stub without reaching down to the result).
  document.addEventListener('click', function (e) {
    var proxy = e.target.closest && e.target.closest('.ta-commit-proxy');
    if (!proxy) return;
    e.preventDefault();
    var panel = proxy.closest('.turn-action');
    var real = panel && panel.querySelector('.ta-pane.ta-pane-active .ar-commit');
    if (real) real.click();
  });

  // Wire each turn panel's Special Ability buttons up front — they now live in
  // the action menu (no separate Special pane to open), so TurnSpecial must
  // delegate from the .ta-special wrapper as soon as the panel renders.
  document.querySelectorAll('.turn-action .ta-special').forEach(function (el) {
    TurnSpecial.ensureLoaded(el);
  });

  // DM Page — out-of-combat actions: pick a Character to run the Turn Action
  // panel for them. The panel is fetched over JS and mounted below the picker
  // so selecting a Character never reloads the page. The picker buttons carry
  // no selected state; the mounted panel shows whose turn it is.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest && e.target.closest('.dm-actor-btn');
    if (!btn) return;
    var slot = document.getElementById('dm-actor-panel');
    if (!slot) return;
    var id = btn.getAttribute('data-actor-id');
    slot.innerHTML = '<p class="ta-attack-loading">Loading actions…</p>';
    fetch('/dm/actor_panel?actor_id=' + encodeURIComponent(id), { headers: { Accept: 'text/html' } })
      .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
      .then(function (html) {
        slot.innerHTML = html;
        // The mounted panel's Special Ability buttons need TurnSpecial wired;
        // its menu / Item / Cast controllers are document-delegated already.
        slot.querySelectorAll('.turn-action .ta-special').forEach(function (el) {
          TurnSpecial.ensureLoaded(el);
        });
      })
      .catch(function () { slot.innerHTML = '<p class="ta-warn">Could not load the actions.</p>'; });
  });

  // DM Page — the "Multiple" group action: mount the group selection panel in
  // the same slot (a group of Characters acting together, skill or item).
  document.addEventListener('click', function (e) {
    if (!(e.target.closest && e.target.closest('.dm-multiple-btn'))) return;
    var slot = document.getElementById('dm-actor-panel');
    if (!slot) return;
    slot.innerHTML = '<p class="ta-attack-loading">Loading…</p>';
    fetch('/dm/multiple', { headers: { Accept: 'text/html' } })
      .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
      .then(function (html) {
        slot.innerHTML = html;
        var panel = slot.querySelector('.dm-multiple');
        if (panel) TurnMultiple.ensureLoaded(panel);
      })
      .catch(function () { slot.innerHTML = '<p class="ta-warn">Could not load the group action.</p>'; });
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

// Affliction relief (per-creature stub): "Roll all rounds" previews the
// alternating Constitution save + Heal channels until the Affliction clears,
// then "Confirm & apply" re-runs the same RNG seed on the live state.
(function () {
  function cardData(card) {
    var sel = card.querySelector('.ar-affliction');
    var aiders = [];
    card.querySelectorAll('.ar-aider').forEach(function (row) {
      var on = row.querySelector('.ar-aider-on');
      if (!on || !on.checked) return;
      var tier = row.querySelector('.ar-aider-tier');
      aiders.push({ creature_id: parseInt(row.getAttribute('data-aider'), 10),
                    tier: tier ? parseInt(tier.value, 10) : 0 });
    });
    return { combatant_id: card.getAttribute('data-combatant'),
             affliction: sel ? sel.value : '', aiders: aiders };
  }

  function run(params) {
    var body = Object.keys(params).map(function (k) {
      return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
    }).join('&');
    return fetch('/encounter/resolve_affliction_run', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body
    }).then(function (r) { return r.json(); });
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function dice(roll) {
    if (!roll || !roll.values) return '';
    return DiceRenderer.renderDice(roll.values, roll.tn, roll.die_size, roll.starting, 'shown');
  }

  function rollLine(r) {
    var succ = r.successes + ' success' + (Math.abs(r.successes) === 1 ? '' : 'es');
    var pot = 'potency ' + r.potency_before + '→' + r.potency_after;
    var dmg = (r.kind === 'save' && r.damage > 0) ? ', ' + r.damage + ' minor damage' : '';
    return '<div class="ar-roll-line"><span class="ar-actor">' + esc(r.actor) + '</span> ' +
      dice(r.roll) + ', ' + succ + ', ' + pot + dmg + '</div>';
  }

  function renderResult(card, data) {
    var res = data.result || {};
    var rounds = (res.log || []).map(function (e) {
      var lines = (e.rolls || []).map(rollLine).join('');
      return '<div class="ar-round"><div class="ar-round-h">Round ' + e.round + '</div>' + lines + '</div>';
    }).join('');
    var hp = res.hp_damage || {};
    var hpStr = ['minor', 'moderate', 'major'].filter(function (s) { return hp[s] > 0; })
      .map(function (s) { return hp[s] + ' ' + s; }).join(', ') || 'none';
    var manaStr = Object.keys(res.aider_mana || {})
      .map(function (k) { return res.aider_mana[k] + ' mana'; }).join(', ');
    var outcome = res.died ? 'Died' : (res.cleared ? 'Cleared' : 'Not cleared (cap reached)');
    var finalLine = (res.max_hp && res.final_hp !== null && res.final_hp !== undefined)
      ? '<div class="ar-final' + (res.final_hp <= 0 ? ' ar-died' : '') + '">Final HP ' +
        res.final_hp + '/' + res.max_hp + '</div>'
      : '';
    var box = card.querySelector('.ar-result');
    box.innerHTML = '<div class="ar-rounds">' + rounds + '</div>' +
      '<div class="ar-totals' + (res.died ? ' ar-died' : '') + '">' + outcome +
      ' in ' + res.rounds + ' rounds · HP taken: ' + hpStr +
      (manaStr ? ' · ' + manaStr : '') + '</div>' + finalLine;
    box.hidden = false;
  }

  document.addEventListener('click', function (e) {
    var roll = e.target.closest('.ar-roll');
    if (roll) {
      var card = roll.closest('.ar-card'); if (!card) return;
      var d = cardData(card);
      roll.disabled = true; roll.textContent = 'Rolling…';
      run({ combatant_id: d.combatant_id, affliction: d.affliction,
            aiders: JSON.stringify(d.aiders), commit: 'false' })
        .then(function (data) {
          roll.disabled = false; roll.textContent = 'Roll all rounds';
          if (!data || !data.ok) return;
          renderResult(card, data);
          var c = card.querySelector('.ar-confirm');
          c.hidden = false; c.setAttribute('data-seed', data.seed);
        })
        .catch(function () { roll.disabled = false; roll.textContent = 'Roll all rounds'; });
      return;
    }
    var confirm = e.target.closest('.ar-confirm');
    if (confirm) {
      var card2 = confirm.closest('.ar-card'); if (!card2) return;
      var d2 = cardData(card2);
      confirm.disabled = true; confirm.textContent = 'Applying…';
      run({ combatant_id: d2.combatant_id, affliction: d2.affliction,
            aiders: JSON.stringify(d2.aiders), commit: 'true',
            seed: confirm.getAttribute('data-seed') })
        .then(function () { window.location.reload(); })
        .catch(function () { confirm.disabled = false; confirm.textContent = 'Confirm & apply'; });
    }
  });
})();
