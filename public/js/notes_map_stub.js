// notes_map_stub — interactivity for the maps. Each
// <figure.notes-map-card> wires up:
//
//   * a side toolbar (DM only) with View / Arrow / Move / Add object /
//     Add shape and three zoom buttons. Click a button to switch
//     tool; the active tool drives all mouse handling.
//   * arrow drawing (immediate POST → reload) — players draw on their
//     own turn, DMs anytime via the Arrow tool.
//   * per-arrow ✕ to remove (owner or DM only).
//   * DM editing tools (Move / Add object / Add shape) which queue
//     ops client-side and render them with a "pending" style. A
//     Save (N) button posts the queue to /scene/batch; Discard
//     reloads the page from server state.
//   * zoom in / out / reset by manipulating the SVG viewBox.
//
// Tool selection and zoom level persist in localStorage per map id.

(function () {
  'use strict';

  // ----- Helpers ----------------------------------------------------

  function vboxPoint(svg, evt) {
    var pt = svg.createSVGPoint();
    pt.x = evt.clientX;
    pt.y = evt.clientY;
    var ctm = svg.getScreenCTM();
    if (!ctm) return { x: 0, y: 0 };
    var loc = pt.matrixTransform(ctm.inverse());
    return { x: loc.x, y: loc.y };
  }

  function postForm(url, fields) {
    var fd = new FormData();
    Object.keys(fields).forEach(function (k) {
      if (fields[k] !== null && fields[k] !== undefined) fd.append(k, fields[k]);
    });
    return fetch(url, { method: 'POST', body: fd, credentials: 'same-origin' });
  }

  function postJson(url, body) {
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
  }

  function svgEl(name, attrs) {
    var ns = 'http://www.w3.org/2000/svg';
    var el = document.createElementNS(ns, name);
    Object.keys(attrs || {}).forEach(function (k) { el.setAttribute(k, attrs[k]); });
    return el;
  }

  // ----- Per-card setup --------------------------------------------

  function setupCard(card) {
    var svg = card.querySelector('svg.notes-map-svg[data-interactive="1"]');
    if (!svg) return;
    var mapId   = card.getAttribute('data-map-id');
    var dmView  = card.getAttribute('data-dm-view') === '1';
    var canDraw = card.getAttribute('data-can-draw') === '1';
    var baseW   = parseFloat(card.getAttribute('data-base-w'));
    var baseH   = parseFloat(card.getAttribute('data-base-h'));

    var toolBtns      = card.querySelectorAll('.notes-map-tool-btn');
    var zoomBtns      = card.querySelectorAll('.notes-map-zoom-btn');
    var arrowBtns     = card.querySelectorAll('.notes-map-arrow-btn');
    var status        = card.querySelector('.notes-map-arrow-status');
    var pendingBar    = card.querySelector('.notes-map-pending');
    var pendingCount  = card.querySelector('.notes-map-pending-count');
    var saveBtn       = card.querySelector('.notes-map-save-btn');
    var discardBtn    = card.querySelector('.notes-map-discard-btn');

    var pendingOps = [];

    // ----- Tool selection ------------------------------------------

    var toolKey = 'notes_map_tool/' + mapId;
    function setActiveTool(tool) {
      svg.dataset.tool = tool;
      svg.classList.toggle('crosshair-mode',
        tool === 'add-object' || tool === 'add-shape');
      svg.classList.toggle('move-mode', tool === 'move');
      toolBtns.forEach(function (b) {
        b.classList.toggle('active', b.getAttribute('data-tool') === tool);
      });
      // Per-tool inline panels (in .notes-map-controls): show only
      // the matching one. The arrow controls are also tool-tagged
      // and only visible while the Arrow tool is active.
      card.querySelectorAll('.notes-map-controls [data-tool]').forEach(function (el) {
        el.hidden = (el.getAttribute('data-tool') !== tool);
      });
      clearPendingPick();
    }

    function currentTool() {
      // DM has buttons; players default to "arrow" when on turn,
      // "view" otherwise.
      if (toolBtns.length) return svg.dataset.tool || 'view';
      return canDraw ? 'arrow' : 'view';
    }

    if (toolBtns.length) {
      var saved = null;
      try { saved = window.localStorage && localStorage.getItem(toolKey); } catch (e) {}
      var initial = saved && Array.from(toolBtns).some(function (b) {
        return b.getAttribute('data-tool') === saved;
      }) ? saved : 'view';
      setActiveTool(initial);

      toolBtns.forEach(function (btn) {
        btn.addEventListener('click', function () {
          var t = btn.getAttribute('data-tool');
          try { if (window.localStorage) localStorage.setItem(toolKey, t); } catch (e) {}
          setActiveTool(t);
        });
      });
    }

    // ----- Zoom + pan ---------------------------------------------
    //
    // The viewBox is computed from (centerX, centerY, zoom). The
    // View tool's gestures move (centerX, centerY) and adjust zoom:
    //   - drag       → pan
    //   - dbl-click  → zoom in centered on the click point
    //   - right-click→ zoom out centered on the click point
    // The zoom buttons in the toolbar still work too.

    var viewKey = 'notes_map_view/' + mapId;
    var zoom = 1;
    var center = { x: baseW / 2, y: baseH / 2 };
    try {
      var savedView = window.localStorage && JSON.parse(localStorage.getItem(viewKey) || 'null');
      if (savedView && savedView.zoom > 0) {
        zoom = savedView.zoom;
        if (typeof savedView.cx === 'number') center.x = savedView.cx;
        if (typeof savedView.cy === 'number') center.y = savedView.cy;
      }
    } catch (e) {}
    function persistView() {
      try {
        if (window.localStorage) localStorage.setItem(viewKey, JSON.stringify({
          zoom: zoom, cx: center.x, cy: center.y
        }));
      } catch (e) {}
    }
    function applyView() {
      var visW = baseW / zoom;
      var visH = baseH / zoom;
      svg.setAttribute('viewBox',
        (center.x - visW / 2) + ' ' + (center.y - visH / 2) + ' ' + visW + ' ' + visH);
    }
    function zoomAt(x, y, factor) {
      var newZoom = Math.max(0.25, Math.min(8, zoom * factor));
      // Anchor zoom around (x, y) so the click point stays under
      // the cursor — shift center toward the click.
      center.x = x - (x - center.x) * (zoom / newZoom);
      center.y = y - (y - center.y) * (zoom / newZoom);
      zoom = newZoom;
      applyView();
      persistView();
    }
    applyView();

    zoomBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var act = btn.getAttribute('data-zoom');
        if      (act === 'in')    zoomAt(center.x, center.y, 1.5);
        else if (act === 'out')   zoomAt(center.x, center.y, 1 / 1.5);
        else { zoom = 1; center = { x: baseW / 2, y: baseH / 2 }; applyView(); persistView(); }
      });
    });

    // Pan + zoom gestures attached to View tool. Pan tracks screen-
    // pixel deltas converted to viewBox units via the bounding rect
    // (vboxPoint can't be used during a pan because the viewBox
    // moves under it on every frame).
    var pan = null;
    svg.addEventListener('mousedown', function (e) {
      if (currentTool() !== 'view') return;
      if (e.button !== 0) return;
      // Don't start a pan from a click that landed on a token,
      // shape, icon, or arrow ✕ — those have their own handlers.
      if (e.target.closest('.notes-map-object, .notes-map-shape, .notes-map-icon, .notes-map-arrow-remove')) return;
      var rect = svg.getBoundingClientRect();
      var pxPerVbX = rect.width  / (baseW / zoom);
      var pxPerVbY = rect.height / (baseH / zoom);
      pan = {
        startCenter: { x: center.x, y: center.y },
        startClient: { x: e.clientX, y: e.clientY },
        pxPerVbX: pxPerVbX, pxPerVbY: pxPerVbY,
        moved: false
      };
      svg.classList.add('panning');
      e.preventDefault();
    });
    svg.addEventListener('dblclick', function (e) {
      if (currentTool() !== 'view') return;
      var p = vboxPoint(svg, e);
      zoomAt(p.x, p.y, 1.5);
      e.preventDefault();
    });
    svg.addEventListener('contextmenu', function (e) {
      if (currentTool() !== 'view') return;
      var p = vboxPoint(svg, e);
      zoomAt(p.x, p.y, 1 / 1.5);
      e.preventDefault();
    });

    // ----- Pending-ops queue --------------------------------------

    function refreshPendingBar() {
      if (!pendingBar) return;
      pendingBar.hidden = pendingOps.length === 0;
      if (pendingCount) {
        pendingCount.textContent = pendingOps.length + ' pending change' +
          (pendingOps.length === 1 ? '' : 's');
      }
    }

    function pushOp(op, optimisticEl) {
      pendingOps.push(op);
      if (optimisticEl) optimisticEl.classList.add('pending-op');
      refreshPendingBar();
    }

    if (saveBtn) {
      saveBtn.addEventListener('click', function () {
        if (!pendingOps.length) return;
        saveBtn.disabled = true;
        postJson('/scene/batch', { map_id: mapId, ops: pendingOps })
          .then(function (r) {
            if (!r.ok) throw new Error('batch ' + r.status);
            window.location.reload();
          })
          .catch(function (err) {
            saveBtn.disabled = false;
            if (status) status.textContent = err.message;
          });
      });
    }
    if (discardBtn) {
      discardBtn.addEventListener('click', function () {
        if (!pendingOps.length) return;
        if (!confirm('Discard all pending changes?')) return;
        pendingOps = [];
        window.location.reload();
      });
    }

    // ----- Arrow type buttons (and DM hold-down "Move" flyout) ----

    var ARROW_TYPES = {
      'attack':         { color: '#c62828', label: 'Attack' },
      'move-hurry':     { color: '#ef6c00', label: 'Move (hurry)' },
      'move-sneak':     { color: '#6a1b9a', label: 'Move (sneak)' },
      'move-carefully': { color: '#2e7d32', label: 'Move (carefully)' }
    };
    var MOVE_VARIANTS = ['move-hurry', 'move-sneak', 'move-carefully'];

    var typeKey      = 'notes_map_arrow_type/' + mapId;
    var moveVarKey   = 'notes_map_move_variant/' + mapId;
    var arrowType    = 'attack';
    var moveVariant  = 'move-hurry';

    try {
      var sv = window.localStorage && localStorage.getItem(typeKey);
      if (sv && ARROW_TYPES[sv]) arrowType = sv;
      var sm = window.localStorage && localStorage.getItem(moveVarKey);
      if (sm && MOVE_VARIANTS.indexOf(sm) >= 0) moveVariant = sm;
    } catch (e) {}

    function arrowTypeForButton(btn) {
      // The DM "Move" group button reflects the active variant.
      if (btn.getAttribute('data-arrow-group') === 'move') return moveVariant;
      return btn.getAttribute('data-arrow-type');
    }

    function refreshArrowButtons() {
      arrowBtns.forEach(function (b) {
        var t = arrowTypeForButton(b);
        var st = ARROW_TYPES[t];
        if (st) b.style.setProperty('--arrow-color', st.color);
        b.classList.toggle('active', t === arrowType);
      });
    }

    function setArrowType(t) {
      if (!ARROW_TYPES[t]) return;
      arrowType = t;
      try { if (window.localStorage) localStorage.setItem(typeKey, t); } catch (e) {}
      if (MOVE_VARIANTS.indexOf(t) >= 0) {
        moveVariant = t;
        try { if (window.localStorage) localStorage.setItem(moveVarKey, t); } catch (e) {}
        // Reflect the chosen variant on the DM "Move" button so its
        // next click uses the same variant without re-opening the
        // flyout.
        arrowBtns.forEach(function (b) {
          if (b.getAttribute('data-arrow-group') === 'move') {
            b.setAttribute('data-arrow-type', t);
          }
        });
      }
      refreshArrowButtons();
    }

    refreshArrowButtons();

    // Photoshop-style hold-down menu on .notes-map-arrow-move-group:
    //   - quick click → use current variant
    //   - long press (>=350ms) → flyout with the three variants
    //   - mouseup over a flyout item → select that variant
    var FLYOUT_DELAY = 350;
    var moveFlyout = null;
    function openMoveFlyout(btn) {
      closeMoveFlyout();
      moveFlyout = document.createElement('div');
      moveFlyout.className = 'notes-map-arrow-flyout';
      MOVE_VARIANTS.forEach(function (t) {
        var item = document.createElement('button');
        item.type = 'button';
        item.className = 'notes-map-arrow-flyout-item';
        item.setAttribute('data-arrow-type', t);
        item.style.setProperty('--arrow-color', ARROW_TYPES[t].color);
        item.textContent = ARROW_TYPES[t].label;
        moveFlyout.appendChild(item);
      });
      btn.parentNode.appendChild(moveFlyout);
      moveFlyout.addEventListener('mouseup', function (e) {
        var item = e.target.closest('.notes-map-arrow-flyout-item');
        if (item) setArrowType(item.getAttribute('data-arrow-type'));
        closeMoveFlyout();
      });
    }
    function closeMoveFlyout() {
      if (moveFlyout && moveFlyout.parentNode) moveFlyout.parentNode.removeChild(moveFlyout);
      moveFlyout = null;
    }

    function activateArrowTool() {
      // Switch to the arrow tool whenever an arrow type is picked,
      // so players (no toolbar) and DMs alike can go from
      // navigation straight into drawing.
      try { if (window.localStorage) localStorage.setItem(toolKey, 'arrow'); } catch (e) {}
      setActiveTool('arrow');
    }

    arrowBtns.forEach(function (btn) {
      var holdTimer = null;
      var fired = false;

      btn.addEventListener('mousedown', function () {
        if (btn.getAttribute('data-arrow-group') !== 'move') return;
        fired = false;
        holdTimer = setTimeout(function () { fired = true; openMoveFlyout(btn); }, FLYOUT_DELAY);
      });
      btn.addEventListener('mouseup', function () {
        if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
        if (!fired) {
          setArrowType(arrowTypeForButton(btn));
          activateArrowTool();
        }
      });
      btn.addEventListener('mouseleave', function () {
        if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
      });
      btn.addEventListener('click', function (e) {
        // Suppress the synthetic click that follows a flyout-mouseup
        // (the flyout's `mouseup` already updated the variant).
        if (fired) e.preventDefault();
      });
    });

    document.addEventListener('mousedown', function (e) {
      if (!moveFlyout) return;
      if (!e.target.closest('.notes-map-arrow-flyout') &&
          !e.target.closest('.notes-map-arrow-move-group')) {
        closeMoveFlyout();
      }
    });

    // ----- Arrow drawing (immediate POST) -------------------------

    var pendingPick = null;
    var pickMarker  = null;

    function clearPendingPick() {
      svg.querySelectorAll('.notes-map-object.selected').forEach(function (o) {
        o.classList.remove('selected');
      });
      if (pickMarker && pickMarker.parentNode) pickMarker.parentNode.removeChild(pickMarker);
      pickMarker  = null;
      pendingPick = null;
    }

    function setStatus(text) { if (status) status.textContent = text; }

    function fieldsForEndpoint(prefix, ep) {
      var out = {};
      if (ep.kind === 'object') out[prefix + '_id'] = ep.id;
      else { out[prefix + '_x'] = ep.x.toFixed(1); out[prefix + '_y'] = ep.y.toFixed(1); }
      return out;
    }

    function commitArrow(ep) {
      var fields = { map_id: mapId, type: arrowType };
      Object.assign(fields, fieldsForEndpoint('from', pendingPick));
      Object.assign(fields, fieldsForEndpoint('to', ep));
      setStatus('Drawing…');
      postForm('/scene/draw_arrow', fields).then(function (r) {
        if (!r.ok) throw new Error('draw_arrow ' + r.status);
        window.location.reload();
      }).catch(function (err) {
        setStatus(err.message);
        clearPendingPick();
      });
    }

    function pickArrowEndpoint(ep, sourceEl) {
      if (!pendingPick) {
        pendingPick = ep;
        if (ep.kind === 'object' && sourceEl) sourceEl.classList.add('selected');
        else if (ep.kind === 'point') {
          pickMarker = svgEl('circle', {
            class: 'notes-map-pending-point',
            cx: ep.x, cy: ep.y, r: 5
          });
          svg.appendChild(pickMarker);
        }
        setStatus('Pick the destination (token or empty space). Click the same spot to cancel.');
        return;
      }
      if (pendingPick.kind === 'object' && ep.kind === 'object' && pendingPick.id === ep.id) {
        clearPendingPick();
        setStatus('Click two points (token or empty) to draw an arrow.');
        return;
      }
      commitArrow(ep);
    }

    // ----- Move tool (drag tokens, batched) -----------------------

    var drag = null;
    function dragMove(evt) {
      if (!drag) return;
      var p = vboxPoint(svg, evt);
      var x = drag.startX + (p.x - drag.startPt.x);
      var y = drag.startY + (p.y - drag.startPt.y);
      drag.spec.write(x, y);
      drag.endX = x; drag.endY = y;
    }
    function dragEnd() {
      if (!drag) return;
      var d = drag; drag = null;
      d.el.classList.remove('dragging');
      if (d.endX === undefined) return; // pure click — no movement
      var op = {
        kind: d.spec.moveOp,
        x: parseFloat(d.endX.toFixed(1)),
        y: parseFloat(d.endY.toFixed(1))
      };
      op[d.spec.idKey] = d.elId;
      pushOp(op, d.el);
    }

    // ----- Add-object (click to place, batched) -------------------

    function addObjectAt(p) {
      var kindSel  = card.querySelector('.notes-map-add-kind');
      var labelInp = card.querySelector('.notes-map-add-label');
      var kind     = kindSel ? kindSel.value : 'pc';
      var label    = labelInp ? labelInp.value.trim() : '';
      var glyph    = renderObjectGlyph(svg, kind, p.x, p.y, label);
      pushOp({
        kind: 'add_object',
        object_kind: kind,
        label: label,
        x: parseFloat(p.x.toFixed(1)),
        y: parseFloat(p.y.toFixed(1))
      }, glyph);
    }

    // ----- Add-shape (drag to draw or click for default size) -----
    //
    // Rect: drag from corner to corner; click without drag → 50x50.
    // Ellipse: drag horizontally for rx, vertically for ry (drag is
    // measured from the click point); click without drag → rx=ry=25.

    var DEFAULT_RECT_W = 50, DEFAULT_RECT_H = 50;
    var DEFAULT_ELLIPSE_RX = 25, DEFAULT_ELLIPSE_RY = 25;

    var shape = null;
    function startShape(p) {
      var kindSel = card.querySelector('.notes-map-shape-kind');
      var kind    = kindSel ? kindSel.value : 'rect';
      var preview;
      if (kind === 'rect') {
        preview = svgEl('rect', { class: 'notes-map-shape-preview', x: p.x, y: p.y, width: 0, height: 0 });
      } else {
        preview = svgEl('ellipse', { class: 'notes-map-shape-preview', cx: p.x, cy: p.y, rx: 0, ry: 0 });
      }
      svg.appendChild(preview);
      shape = { kind: kind, sx: p.x, sy: p.y, ex: p.x, ey: p.y, preview: preview };
    }
    function updateShape(p) {
      if (!shape) return;
      shape.ex = p.x; shape.ey = p.y;
      if (shape.kind === 'rect') {
        var x = Math.min(shape.sx, p.x);
        var y = Math.min(shape.sy, p.y);
        shape.preview.setAttribute('x', x);
        shape.preview.setAttribute('y', y);
        shape.preview.setAttribute('width',  Math.abs(p.x - shape.sx));
        shape.preview.setAttribute('height', Math.abs(p.y - shape.sy));
      } else {
        shape.preview.setAttribute('rx', Math.abs(p.x - shape.sx));
        shape.preview.setAttribute('ry', Math.abs(p.y - shape.sy));
      }
    }
    function commitShape() {
      if (!shape) return;
      var s = shape; shape = null;
      var op;
      if (s.kind === 'rect') {
        var w = Math.abs(s.ex - s.sx), h = Math.abs(s.ey - s.sy);
        var defaulted = (w < 4 && h < 4);
        if (defaulted) { w = DEFAULT_RECT_W; h = DEFAULT_RECT_H; }
        var cx = defaulted ? s.sx : (s.sx + s.ex) / 2;
        var cy = defaulted ? s.sy : (s.sy + s.ey) / 2;
        // Update the preview to reflect the committed dims.
        s.preview.setAttribute('x', cx - w / 2);
        s.preview.setAttribute('y', cy - h / 2);
        s.preview.setAttribute('width',  w);
        s.preview.setAttribute('height', h);
        op = {
          kind: 'add_shape', shape_kind: 'rect',
          x: parseFloat(cx.toFixed(1)),
          y: parseFloat(cy.toFixed(1)),
          w: parseFloat(w.toFixed(1)),
          h: parseFloat(h.toFixed(1))
        };
      } else {
        var rx = Math.abs(s.ex - s.sx), ry = Math.abs(s.ey - s.sy);
        if (rx < 4 && ry < 4) { rx = DEFAULT_ELLIPSE_RX; ry = DEFAULT_ELLIPSE_RY; }
        s.preview.setAttribute('cx', s.sx);
        s.preview.setAttribute('cy', s.sy);
        s.preview.setAttribute('rx', rx);
        s.preview.setAttribute('ry', ry);
        op = {
          kind: 'add_shape', shape_kind: 'ellipse',
          x: parseFloat(s.sx.toFixed(1)),
          y: parseFloat(s.sy.toFixed(1)),
          rx: parseFloat(rx.toFixed(1)),
          ry: parseFloat(ry.toFixed(1))
        };
      }
      // Promote the preview into a "pending" rendered shape.
      s.preview.classList.remove('notes-map-shape-preview');
      s.preview.classList.add('pending-op');
      pushOp(op, s.preview);
    }

    // ----- Add-icon (DM emoji palette → click on map) --------------

    var pickedIcon = null;
    card.querySelectorAll('.notes-map-icon-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        pickedIcon = btn.getAttribute('data-glyph');
        card.querySelectorAll('.notes-map-icon-btn.active').forEach(function (b) {
          b.classList.remove('active');
        });
        btn.classList.add('active');
        var statusEl = card.querySelector('.notes-map-icon-status');
        if (statusEl) statusEl.textContent = 'Click on the map to place ' + pickedIcon + '.';
      });
    });

    function placeIconAt(p) {
      if (!pickedIcon) {
        var statusEl = card.querySelector('.notes-map-icon-status');
        if (statusEl) statusEl.textContent = 'Pick an icon first.';
        return;
      }
      var t = svgEl('text', {
        class: 'notes-map-icon',
        x: p.x.toFixed(1), y: p.y.toFixed(1),
        'text-anchor': 'middle', 'dominant-baseline': 'central',
        'font-size': 28
      });
      t.textContent = pickedIcon;
      svg.appendChild(t);
      pushOp({
        kind: 'add_icon',
        glyph: pickedIcon,
        x: parseFloat(p.x.toFixed(1)),
        y: parseFloat(p.y.toFixed(1))
      }, t);
    }

    // ----- Element mouse handling (decide based on tool) ----------
    //
    // Same flow for tokens, shapes, and icons — just different
    // attributes drive the move/delete op kinds. The `moveSpec`
    // describes how to read the element's current x/y (from
    // transform vs explicit attrs) and which op kinds to emit.

    function moveSpecFor(el) {
      if (el.classList.contains('notes-map-object')) {
        return {
          kind: 'object',
          idAttr: 'data-object-id',
          read: function () { var t = (el.getAttribute('transform') || '').match(/translate\(([^,]+),([^)]+)\)/); return t ? [parseFloat(t[1]), parseFloat(t[2])] : [0, 0]; },
          write: function (x, y) { el.setAttribute('transform', 'translate(' + x.toFixed(1) + ',' + y.toFixed(1) + ')'); },
          moveOp: 'move_object', deleteOp: 'delete_object', idKey: 'object_id'
        };
      }
      if (el.classList.contains('notes-map-shape')) {
        return {
          kind: 'shape',
          idAttr: 'data-shape-id',
          read: function () { var t = (el.getAttribute('transform') || '').match(/translate\(([^,]+),([^)]+)\)/); return t ? [parseFloat(t[1]), parseFloat(t[2])] : [0, 0]; },
          write: function (x, y) { el.setAttribute('transform', 'translate(' + x.toFixed(1) + ',' + y.toFixed(1) + ')'); },
          moveOp: 'move_shape', deleteOp: 'delete_shape', idKey: 'shape_id'
        };
      }
      if (el.classList.contains('notes-map-icon')) {
        return {
          kind: 'icon',
          idAttr: 'data-icon-id',
          read: function () { return [parseFloat(el.getAttribute('x')), parseFloat(el.getAttribute('y'))]; },
          write: function (x, y) { el.setAttribute('x', x.toFixed(1)); el.setAttribute('y', y.toFixed(1)); },
          moveOp: 'move_icon', deleteOp: 'delete_icon', idKey: 'icon_id'
        };
      }
      return null;
    }

    function startElementDrag(el, evt) {
      var spec = moveSpecFor(el); if (!spec) return;
      var xy = spec.read();
      drag = {
        el: el, spec: spec,
        elId: el.getAttribute(spec.idAttr),
        startX: xy[0], startY: xy[1],
        startPt: vboxPoint(svg, evt)
      };
      el.classList.add('dragging');
      evt.preventDefault();
    }

    function bindElementHandlers(el) {
      el.addEventListener('mousedown', function (e) {
        if (currentTool() !== 'move') return;
        startElementDrag(el, e);
      });
      el.addEventListener('click', function (e) {
        var tool = currentTool();
        e.stopPropagation();
        if (tool === 'arrow' && el.classList.contains('notes-map-object')) {
          pickArrowEndpoint({ kind: 'object', id: el.getAttribute('data-object-id') }, el);
        } else if (tool === 'delete') {
          var spec = moveSpecFor(el); if (!spec) return;
          var idVal = el.getAttribute(spec.idAttr); if (!idVal) return;
          var op = { kind: spec.deleteOp };
          op[spec.idKey] = idVal;
          el.classList.add('pending-delete');
          pushOp(op, el);
        }
      });
    }

    svg.querySelectorAll('.notes-map-object, .notes-map-shape, .notes-map-icon').forEach(bindElementHandlers);

    // ----- SVG (empty-space) mouse handling -----------------------

    svg.addEventListener('mousedown', function (e) {
      if (e.target.closest('.notes-map-object')) return;
      if (e.target.closest('.notes-map-arrow-remove')) return;
      if (currentTool() !== 'add-shape') return;
      startShape(vboxPoint(svg, e));
      e.preventDefault();
    });
    svg.addEventListener('mousemove', function (e) {
      if (pan) {
        var dx = (e.clientX - pan.startClient.x) / pan.pxPerVbX;
        var dy = (e.clientY - pan.startClient.y) / pan.pxPerVbY;
        if (Math.abs(dx) + Math.abs(dy) > 1) pan.moved = true;
        center.x = pan.startCenter.x - dx;
        center.y = pan.startCenter.y - dy;
        applyView();
      }
      if (drag)  dragMove(e);
      if (shape) updateShape(vboxPoint(svg, e));
    });
    document.addEventListener('mouseup', function () {
      if (pan) {
        svg.classList.remove('panning');
        if (pan.moved) persistView();
        pan = null;
      }
      if (drag)  dragEnd();
      if (shape) commitShape();
    });

    svg.addEventListener('click', function (e) {
      if (e.target.closest('.notes-map-object')) return;
      if (e.target.closest('.notes-map-arrow-remove')) return;
      var tool = currentTool();
      if (tool === 'arrow') {
        var p = vboxPoint(svg, e);
        pickArrowEndpoint({ kind: 'point', x: p.x, y: p.y }, null);
      } else if (tool === 'add-object') {
        addObjectAt(vboxPoint(svg, e));
      } else if (tool === 'add-icon') {
        placeIconAt(vboxPoint(svg, e));
      }
    });

    // ----- Per-arrow ✕ -------------------------------------------

    svg.querySelectorAll('.notes-map-arrow-remove').forEach(function (btn) {
      btn.style.cursor = 'pointer';
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var arrowId = btn.getAttribute('data-arrow-id');
        postForm('/scene/remove_arrow', { map_id: mapId, arrow_id: arrowId })
          .then(function (r) {
            if (!r.ok) throw new Error('remove_arrow ' + r.status);
            window.location.reload();
          })
          .catch(function (err) { setStatus(err.message); });
      });
    });
  }

  // ----- Optimistic glyph rendering (for new objects) -------------

  // Match the server-side glyph palette in stubs/notes_map_stub.rb.
  var KIND_STYLE = {
    pc:       { fill: '#577a99', stroke: '#1d3a5b', glyph: 'circle' },
    npc:      { fill: '#9e9e9e', stroke: '#424242', glyph: 'circle' },
    enemy:    { fill: '#a04848', stroke: '#5e1818', glyph: 'circle' },
    scenery:  { fill: '#9c7a4a', stroke: '#5d4520', glyph: 'rect'   },
    door:     { fill: '#5d4037', stroke: '#2e1c14', glyph: 'rect'   },
    trap:     { fill: '#ffb300', stroke: '#7b5e00', glyph: 'triangle' },
    hazard:   { fill: '#e53935', stroke: '#7b1c1c', glyph: 'triangle' },
    treasure: { fill: '#fdd835', stroke: '#9c7a00', glyph: 'diamond' }
  };

  function renderObjectGlyph(svg, kind, x, y, label) {
    var s = KIND_STYLE[kind] || KIND_STYLE.pc;
    var g = svgEl('g', {
      class: 'notes-map-object notes-map-object-' + kind,
      transform: 'translate(' + x.toFixed(1) + ',' + y.toFixed(1) + ')'
    });
    var primitive;
    if (s.glyph === 'rect') {
      primitive = svgEl('rect', { x: -14, y: -10, width: 28, height: 20, fill: s.fill, stroke: s.stroke, 'stroke-width': 1.5 });
    } else if (s.glyph === 'triangle') {
      primitive = svgEl('polygon', { points: '0,-11 10,8 -10,8', fill: s.fill, stroke: s.stroke, 'stroke-width': 1.5 });
    } else if (s.glyph === 'diamond') {
      primitive = svgEl('polygon', { points: '0,-11 11,0 0,11 -11,0', fill: s.fill, stroke: s.stroke, 'stroke-width': 1.5 });
    } else {
      primitive = svgEl('circle', { r: 9, fill: s.fill, stroke: s.stroke, 'stroke-width': 1.5 });
    }
    g.appendChild(primitive);
    if (label) {
      var t = svgEl('text', {
        x: 0, y: -14, 'text-anchor': 'middle',
        'font-family': 'Arial,sans-serif', 'font-size': 9, fill: '#333'
      });
      t.textContent = label;
      g.appendChild(t);
    }
    svg.appendChild(g);
    return g;
  }

  function init() {
    document.querySelectorAll('.notes-map-card').forEach(setupCard);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
