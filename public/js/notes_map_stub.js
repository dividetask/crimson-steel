// notes_map_stub — tool-driven interactivity for the maps.
//
// Each <figure.notes-map-card> has a tool picker (DM only). The
// active tool decides what clicks/drags do:
//   view        — clicks do nothing (DM default)
//   arrow       — click two points (token or empty) → POST draw_arrow
//   move        — drag a token → POST move_object on release
//   add-object  — pick kind+label, click on map → POST add_object
//   add-shape   — pick shape kind, click on map → POST add_shape
//
// Players don't get a tool picker; their tool is implicitly "arrow"
// when their card is flagged data-can-draw="1" (i.e. it's their
// turn), and the click handlers no-op otherwise.
//
// Per-arrow ✕ buttons are wired separately and always work for the
// drawing player or the DM (the partial only renders the ✕ for
// those viewers).

(function () {
  'use strict';

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

  function setupCard(card) {
    var svg = card.querySelector('svg.notes-map-svg[data-interactive="1"]');
    if (!svg) return;
    var mapId   = card.getAttribute('data-map-id');
    var dmView  = card.getAttribute('data-dm-view') === '1';
    var canDraw = card.getAttribute('data-can-draw') === '1';

    var toolSel = card.querySelector('.notes-map-tool');
    var typeSel = card.querySelector('.notes-map-arrow-type');
    var status  = card.querySelector('.notes-map-arrow-status');

    function currentTool() {
      if (toolSel) return toolSel.value;
      // No picker → players drawing arrows on their turn.
      return canDraw ? 'arrow' : 'view';
    }

    function syncToolPanels(tool) {
      svg.dataset.tool = tool;
      svg.classList.toggle('crosshair-mode',
        tool === 'add-object' || tool === 'add-shape');
      svg.classList.toggle('move-mode', tool === 'move');
      // Show/hide the per-tool DM panels.
      card.querySelectorAll('[data-tool]').forEach(function (el) {
        el.hidden = (el.getAttribute('data-tool') !== tool);
      });
      // Arrow-type picker is only useful in arrow mode for DMs;
      // keep it visible for players (it's their only tool).
      var arrowControls = card.querySelector('.notes-map-arrow-controls[data-dm-only="1"]');
      if (arrowControls) arrowControls.hidden = (tool !== 'arrow');
    }

    if (toolSel) {
      toolSel.addEventListener('change', function () {
        clearPending();
        syncToolPanels(toolSel.value);
      });
      syncToolPanels(toolSel.value);
    }

    // --- Arrow drawing ----------------------------------------------
    var pending = null;
    var marker  = null;

    function clearPending() {
      svg.querySelectorAll('.notes-map-object.selected').forEach(function (o) {
        o.classList.remove('selected');
      });
      if (marker && marker.parentNode) marker.parentNode.removeChild(marker);
      marker  = null;
      pending = null;
    }

    function drawPendingMarker(x, y) {
      var ns = 'http://www.w3.org/2000/svg';
      marker = document.createElementNS(ns, 'circle');
      marker.setAttribute('class', 'notes-map-pending-point');
      marker.setAttribute('cx', x);
      marker.setAttribute('cy', y);
      marker.setAttribute('r', 5);
      svg.appendChild(marker);
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
      Object.assign(fields, fieldsForEndpoint('from', pending));
      Object.assign(fields, fieldsForEndpoint('to', ep));
      setStatus('Drawing…');
      postForm('/scene/draw_arrow', fields).then(function (r) {
        if (!r.ok) throw new Error('draw_arrow ' + r.status);
        window.location.reload();
      }).catch(function (err) {
        setStatus(err.message);
        clearPending();
      });
    }

    function pickArrowEndpoint(ep, sourceEl) {
      if (!pending) {
        pending = ep;
        if (ep.kind === 'object' && sourceEl) sourceEl.classList.add('selected');
        else if (ep.kind === 'point')         drawPendingMarker(ep.x, ep.y);
        setStatus('Pick the destination (token or empty space). Click the same spot to cancel.');
        return;
      }
      if (pending.kind === 'object' && ep.kind === 'object' && pending.id === ep.id) {
        clearPending();
        setStatus('Click two points (token or empty space) to draw an arrow.');
        return;
      }
      commitArrow(ep);
    }

    // --- Object drag-to-move ----------------------------------------
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
      if (d.endX === undefined) return; // pure click, no movement
      postForm('/scene/move_object', {
        map_id: mapId, object_id: d.objId,
        x: d.endX.toFixed(1), y: d.endY.toFixed(1)
      }).then(function (r) {
        if (!r.ok) throw new Error('move_object ' + r.status);
        window.location.reload();
      }).catch(function (err) { setStatus && setStatus(err.message); });
    }

    // --- Token clicks (decide based on tool) ------------------------
    svg.querySelectorAll('.notes-map-object').forEach(function (obj) {
      obj.addEventListener('mousedown', function (e) {
        if (currentTool() !== 'move') return;
        startDrag(obj, e);
      });
      obj.addEventListener('click', function (e) {
        var tool = currentTool();
        if (tool !== 'arrow') { e.stopPropagation(); return; }
        e.stopPropagation();
        pickArrowEndpoint({ kind: 'object', id: obj.getAttribute('data-object-id') }, obj);
      });
    });

    // While dragging, follow the mouse on the SVG itself.
    svg.addEventListener('mousemove', dragMove);
    document.addEventListener('mouseup', dragEnd);

    // --- SVG (empty-space) clicks ----------------------------------
    svg.addEventListener('click', function (e) {
      if (e.target.closest('.notes-map-object'))         return; // handled
      if (e.target.closest('.notes-map-arrow-remove'))   return; // handled
      var tool = currentTool();
      var p = vboxPoint(svg, e);

      if (tool === 'arrow') {
        pickArrowEndpoint({ kind: 'point', x: p.x, y: p.y }, null);
      } else if (tool === 'add-object') {
        var addForm = card.querySelector('.notes-map-add-form');
        if (!addForm) return;
        var label = addForm.querySelector('input[name="label"]');
        if (!label.value.trim()) { label.focus(); return; }
        addForm.querySelector('.notes-map-add-x').value = p.x.toFixed(1);
        addForm.querySelector('.notes-map-add-y').value = p.y.toFixed(1);
        addForm.submit();
      } else if (tool === 'add-shape') {
        var shapeForm = card.querySelector('.notes-map-shape-form');
        if (!shapeForm) return;
        shapeForm.querySelector('.notes-map-shape-x').value = p.x.toFixed(1);
        shapeForm.querySelector('.notes-map-shape-y').value = p.y.toFixed(1);
        shapeForm.submit();
      }
    });

    // --- Per-arrow ✕ ------------------------------------------------
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

  function init() {
    document.querySelectorAll('.notes-map-card').forEach(setupCard);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
