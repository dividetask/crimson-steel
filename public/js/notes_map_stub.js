// notes_map_stub — interactive bits for the maps. Wires up three
// flows per <figure.notes-map-card>:
//   1. Pick an arrow type, click two points → POST /scene/draw_arrow.
//      Each click is either on a token (snap to that object) or on
//      empty SVG space (use viewBox coordinates).
//   2. Click the small ✕ at an arrow's midpoint → POST
//      /scene/remove_arrow. Only rendered for the arrow's owner or
//      the DM, so the click is allowed by definition.
//   3. (DM only) Pick a kind + label, click "Click map to place",
//      then click the SVG → POST /scene/add_object.
// Page reloads after each mutation so all viewers stay in sync.

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
    var typeSel = card.querySelector('.notes-map-arrow-type');
    var status  = card.querySelector('.notes-map-arrow-status');

    // --- Arrow drawing (token or free coords) -----------------------
    // pendingEndpoint: { kind: 'object'|'point', id?, x?, y? } or null.
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

    function commitSecondEndpoint(ep) {
      var type = typeSel ? typeSel.value : 'attack';
      var fields = { map_id: mapId, type: type };
      Object.assign(fields, fieldsForEndpoint('from', pending));
      Object.assign(fields, fieldsForEndpoint('to', ep));
      setStatus('Drawing…');
      postForm('/scene/draw_arrow', fields).then(function (r) {
        if (!r.ok) throw new Error('draw_arrow failed: ' + r.status);
        window.location.reload();
      }).catch(function (err) {
        setStatus(err.message);
        clearPending();
      });
    }

    function pickEndpoint(ep, sourceEl) {
      if (!pending) {
        pending = ep;
        if (ep.kind === 'object' && sourceEl) sourceEl.classList.add('selected');
        else if (ep.kind === 'point') drawPendingMarker(ep.x, ep.y);
        setStatus('Pick the destination (token or empty space). Click the same spot to cancel.');
        return;
      }
      // Cancel if the same endpoint is picked twice.
      if (pending.kind === 'object' && ep.kind === 'object' && pending.id === ep.id) {
        clearPending();
        setStatus('Click two points (token or empty space) to draw an arrow.');
        return;
      }
      commitSecondEndpoint(ep);
    }

    // Token clicks: stop propagation so the SVG handler doesn't also
    // treat them as empty-space clicks.
    svg.querySelectorAll('.notes-map-object').forEach(function (obj) {
      obj.addEventListener('click', function (e) {
        if (svg.dataset.placeMode === '1') return;
        e.stopPropagation();
        pickEndpoint({ kind: 'object', id: obj.getAttribute('data-object-id') }, obj);
      });
    });

    // Empty-space clicks on the SVG itself become coordinate
    // endpoints. The DM "place new object" flow reuses the same
    // listener, so check placeMode first.
    svg.addEventListener('click', function (e) {
      if (svg.dataset.placeMode === '1') return; // handled below
      // If the click landed on an arrow's remove button it bubbled
      // here after its own handler ran; ignore.
      if (e.target.closest('.notes-map-arrow-remove')) return;
      var p = vboxPoint(svg, e);
      pickEndpoint({ kind: 'point', x: p.x, y: p.y }, null);
    });

    // --- Per-arrow remove ✕ -----------------------------------------
    svg.querySelectorAll('.notes-map-arrow-remove').forEach(function (btn) {
      btn.style.cursor = 'pointer';
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var arrowId = btn.getAttribute('data-arrow-id');
        postForm('/scene/remove_arrow', { map_id: mapId, arrow_id: arrowId })
          .then(function (r) {
            if (!r.ok) throw new Error('remove_arrow failed: ' + r.status);
            window.location.reload();
          })
          .catch(function (err) { setStatus(err.message); });
      });
    });

    // --- DM: place new object ---------------------------------------
    var addForm  = card.querySelector('.notes-map-add-form');
    var placeBtn = card.querySelector('.notes-map-place-btn');
    var addStat  = card.querySelector('.notes-map-add-status');
    if (!addForm || !placeBtn) return;

    placeBtn.addEventListener('click', function () {
      var labelInput = addForm.querySelector('input[name="label"]');
      if (!labelInput.value.trim()) {
        labelInput.focus();
        if (addStat) addStat.textContent = 'Type a label first.';
        return;
      }
      // Cancel any pending arrow draw — these two flows are
      // mutually exclusive.
      clearPending();
      svg.dataset.placeMode = '1';
      svg.classList.add('place-mode');
      if (addStat) addStat.textContent = 'Click on the map to place.';
    });

    svg.addEventListener('click', function (e) {
      if (svg.dataset.placeMode !== '1') return;
      var p = vboxPoint(svg, e);
      addForm.querySelector('.notes-map-add-x').value = p.x.toFixed(1);
      addForm.querySelector('.notes-map-add-y').value = p.y.toFixed(1);
      svg.dataset.placeMode = '0';
      svg.classList.remove('place-mode');
      addForm.submit();
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
