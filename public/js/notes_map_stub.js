// notes_map_stub — interactive bits for the maps. Wires up two flows
// per <figure.notes-map-card>:
//   1. Click two object tokens → POST /scene/draw_arrow with the
//      currently-selected arrow type. Page reloads so the new arrow
//      shows up for everyone.
//   2. (DM only) Pick a kind + label, click "Click map to place",
//      then click on the SVG → POST /scene/add_object with viewBox
//      coordinates.

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
    Object.keys(fields).forEach(function (k) { fd.append(k, fields[k]); });
    return fetch(url, { method: 'POST', body: fd, credentials: 'same-origin' });
  }

  function setupCard(card) {
    var svg     = card.querySelector('svg.notes-map-svg[data-interactive="1"]');
    if (!svg) return;
    var mapId   = card.getAttribute('data-map-id');
    var typeSel = card.querySelector('.notes-map-arrow-type');
    var status  = card.querySelector('.notes-map-arrow-status');

    // --- Arrow drawing -----------------------------------------------
    var firstId = null;

    function clearSelection() {
      svg.querySelectorAll('.notes-map-object.selected').forEach(function (o) {
        o.classList.remove('selected');
      });
      firstId = null;
    }

    svg.querySelectorAll('.notes-map-object').forEach(function (obj) {
      obj.addEventListener('click', function (e) {
        // Ignore object clicks while in "place new object" mode.
        if (svg.dataset.placeMode === '1') return;
        e.stopPropagation();
        var id = obj.getAttribute('data-object-id');
        if (!firstId) {
          firstId = id;
          obj.classList.add('selected');
          if (status) status.textContent = 'Pick the destination token (or click again to cancel).';
          return;
        }
        if (firstId === id) {
          clearSelection();
          if (status) status.textContent = 'Click two tokens to draw an arrow.';
          return;
        }
        var type = typeSel ? typeSel.value : 'attack';
        if (status) status.textContent = 'Drawing…';
        postForm('/scene/draw_arrow', {
          map_id: mapId, from: firstId, to: id, type: type
        }).then(function (r) {
          if (!r.ok) throw new Error('draw_arrow failed: ' + r.status);
          window.location.reload();
        }).catch(function (err) {
          if (status) status.textContent = err.message;
          clearSelection();
        });
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
