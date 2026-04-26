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
    var typeSel       = card.querySelector('.notes-map-arrow-type');
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

    // ----- Zoom ----------------------------------------------------

    var zoomKey = 'notes_map_zoom/' + mapId;
    var zoom = 1;
    function applyZoom() {
      var visW = baseW / zoom;
      var visH = baseH / zoom;
      var offX = (baseW - visW) / 2;
      var offY = (baseH - visH) / 2;
      svg.setAttribute('viewBox', offX + ' ' + offY + ' ' + visW + ' ' + visH);
    }
    try {
      var savedZoom = window.localStorage && parseFloat(localStorage.getItem(zoomKey));
      if (savedZoom && savedZoom > 0) zoom = savedZoom;
    } catch (e) {}
    applyZoom();

    zoomBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var act = btn.getAttribute('data-zoom');
        if      (act === 'in')    zoom = Math.min(zoom * 1.5, 8);
        else if (act === 'out')   zoom = Math.max(zoom / 1.5, 0.25);
        else                      zoom = 1;
        try { if (window.localStorage) localStorage.setItem(zoomKey, zoom); } catch (e) {}
        applyZoom();
      });
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
      var type = typeSel ? typeSel.value : 'attack';
      var fields = { map_id: mapId, type: type };
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
    function startDrag(obj, evt) {
      var t = (obj.getAttribute('transform') || '').match(/translate\(([^,]+),([^)]+)\)/);
      drag = {
        obj: obj,
        objId: obj.getAttribute('data-object-id'),
        startX: t ? parseFloat(t[1]) : 0,
        startY: t ? parseFloat(t[2]) : 0,
        startPt: vboxPoint(svg, evt)
      };
      obj.classList.add('dragging');
      evt.preventDefault();
    }
    function dragMove(evt) {
      if (!drag) return;
      var p = vboxPoint(svg, evt);
      var x = drag.startX + (p.x - drag.startPt.x);
      var y = drag.startY + (p.y - drag.startPt.y);
      drag.obj.setAttribute('transform', 'translate(' + x.toFixed(1) + ',' + y.toFixed(1) + ')');
      drag.endX = x; drag.endY = y;
    }
    function dragEnd() {
      if (!drag) return;
      var d = drag; drag = null;
      d.obj.classList.remove('dragging');
      if (d.endX === undefined) return; // pure click — no movement
      pushOp({
        kind: 'move_object',
        object_id: d.objId,
        x: parseFloat(d.endX.toFixed(1)),
        y: parseFloat(d.endY.toFixed(1))
      }, d.obj);
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

    // ----- Add-shape (drag to draw, batched) ----------------------

    var shape = null;
    function startShape(p) {
      var kindSel = card.querySelector('.notes-map-shape-kind');
      var kind    = kindSel ? kindSel.value : 'rect';
      var preview;
      if (kind === 'rect') {
        preview = svgEl('rect', { class: 'notes-map-shape-preview', x: p.x, y: p.y, width: 0, height: 0 });
      } else {
        preview = svgEl('circle', { class: 'notes-map-shape-preview', cx: p.x, cy: p.y, r: 0 });
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
        var dx = p.x - shape.sx, dy = p.y - shape.sy;
        shape.preview.setAttribute('r', Math.sqrt(dx*dx + dy*dy));
      }
    }
    function commitShape() {
      if (!shape) return;
      var s = shape; shape = null;
      var op;
      if (s.kind === 'rect') {
        var w = Math.abs(s.ex - s.sx), h = Math.abs(s.ey - s.sy);
        if (w < 4 || h < 4) { s.preview.remove(); return; }
        op = {
          kind: 'add_shape', shape_kind: 'rect',
          x: parseFloat(((s.sx + s.ex) / 2).toFixed(1)),
          y: parseFloat(((s.sy + s.ey) / 2).toFixed(1)),
          w: parseFloat(w.toFixed(1)),
          h: parseFloat(h.toFixed(1))
        };
      } else {
        var dx = s.ex - s.sx, dy = s.ey - s.sy;
        var r  = Math.sqrt(dx*dx + dy*dy);
        if (r < 4) { s.preview.remove(); return; }
        op = {
          kind: 'add_shape', shape_kind: 'circle',
          x: parseFloat(s.sx.toFixed(1)),
          y: parseFloat(s.sy.toFixed(1)),
          r: parseFloat(r.toFixed(1))
        };
      }
      // Promote the preview into a "pending" rendered shape.
      s.preview.classList.remove('notes-map-shape-preview');
      s.preview.classList.add('pending-op');
      pushOp(op, s.preview);
    }

    // ----- Token mouse handling (decide based on tool) ------------

    svg.querySelectorAll('.notes-map-object').forEach(function (obj) {
      obj.addEventListener('mousedown', function (e) {
        if (currentTool() !== 'move') return;
        startDrag(obj, e);
      });
      obj.addEventListener('click', function (e) {
        var tool = currentTool();
        e.stopPropagation();
        if (tool === 'arrow') {
          pickArrowEndpoint({ kind: 'object', id: obj.getAttribute('data-object-id') }, obj);
        }
      });
    });

    // ----- SVG (empty-space) mouse handling -----------------------

    svg.addEventListener('mousedown', function (e) {
      if (e.target.closest('.notes-map-object')) return;
      if (e.target.closest('.notes-map-arrow-remove')) return;
      if (currentTool() !== 'add-shape') return;
      startShape(vboxPoint(svg, e));
      e.preventDefault();
    });
    svg.addEventListener('mousemove', function (e) {
      if (drag)  dragMove(e);
      if (shape) updateShape(vboxPoint(svg, e));
    });
    document.addEventListener('mouseup', function () {
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
