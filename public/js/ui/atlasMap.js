// Atlas map canvas controller (atlas_stub.md).
//
// Renders the Map Image (or a blank, gridded canvas) with Annotations and
// Token icons overlaid, supports click-drag pan and scroll/​button zoom
// (clamped to the config's Minimum/Maximum Zoom), and wires the DM toolbar.
//
// Drawing tools (atlas_stub.md → Drawing tools): a tool is a mode. While a
// draw tool is active, canvas gestures create Atlas Annotations instead of
// panning. Players get the Arrow tool only; the DM gets Arrow, Shape
// (rect/ellipse), and Text. Each drawing commits via /atlas/add_annotation.
//
// Combat integrations: in Select mode the DM drags a Token to move it, or
// clicks it (while the Attack pane is open) to target that Combatant. A Cast's
// "Place on the map" arms a spell-area footprint; once dropped it stays
// draggable so the caster can re-aim it — moving it recomputes which creatures
// it catches — until the cast is committed.

const BASE_CELL = 28;          // CSS px per Map Unit at zoom factor 1.0.
const SVG_NS = 'http://www.w3.org/2000/svg';
const XLINK_NS = 'http://www.w3.org/1999/xlink';
const ENC = (s) => encodeURIComponent(s);

// An SVG <pattern> wrapping one image sized to a shape's bounding box, so a
// Zone shape filled with url(#id) shows the image clipped to the shape.
function zonePattern(id, x, y, w, h, href) {
  const pat = document.createElementNS(SVG_NS, 'pattern');
  pat.setAttribute('id', id);
  pat.setAttribute('patternUnits', 'userSpaceOnUse');
  pat.setAttribute('x', x); pat.setAttribute('y', y);
  pat.setAttribute('width', w); pat.setAttribute('height', h);
  // A translucent purple backing under the texture: keeps a committed Zone as
  // visible as the (solid-purple) placement preview even when the texture is
  // sparse / transparent or fails to load.
  const back = document.createElementNS(SVG_NS, 'rect');
  back.setAttribute('x', x); back.setAttribute('y', y);
  back.setAttribute('width', w); back.setAttribute('height', h);
  back.setAttribute('fill', 'rgba(128, 90, 213, 0.30)');
  pat.appendChild(back);
  const img = document.createElementNS(SVG_NS, 'image');
  img.setAttribute('x', x); img.setAttribute('y', y);
  img.setAttribute('width', w); img.setAttribute('height', h);
  img.setAttribute('preserveAspectRatio', 'xMidYMid slice');
  img.setAttributeNS(XLINK_NS, 'href', href);
  img.setAttribute('href', href);
  pat.appendChild(img);
  return pat;
}

export const AtlasMap = {
  initAll() {
    document.querySelectorAll('.atlas-stub').forEach((section) => {
      if (section.dataset.atlasLoaded) return;
      section.dataset.atlasLoaded = '1';
      new AtlasCanvas(section).start();
    });
  }
};

class AtlasCanvas {
  constructor(section) {
    this.section = section;
    this.viewer = section.dataset.viewer;
    this.minZoom = parseFloat(section.dataset.minZoom) || 0.1;
    this.maxZoom = parseFloat(section.dataset.maxZoom) || 32;
    this.initialZoom = parseFloat(section.dataset.initialZoom) || 1;
    this.viewport = section.querySelector('.atlas-viewport');
    this.snapshot = parseJSON(this.viewport.dataset.snapshot) || {};
    this.zoom = clamp(this.initialZoom, this.minZoom, this.maxZoom);
    this.panX = 0;
    this.panY = 0;
    this.tool = 'select';
    this.placing = null;   // creature_id armed for placement, or null
    this.placingArea = null; // {shape, size} armed for spell-area placement
    this._placedArea = null; // {x, y, area} dropped (un-committed) footprint, draggable
  }

  start() {
    this.render();
    this.recenter();
    this.bindToolbar();
    this.bindCanvas();
    // Esc cancels an armed placement.
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Escape') return;
      if (this.placing) this.clearPlacing();
      if (this.placingArea) { this.placingArea = null; this.hidePlaceHint(); }
    });
    // The cast panel arms spell-area placement; we drop a local preview and
    // report the caught creatures back (nothing is persisted until commit).
    document.addEventListener('cast:arm-area', (e) => this.armArea(e.detail || {}));
    // A viewport resize changes the cover fit — re-clamp zoom and pan so the
    // Map keeps filling the viewport with no off-Map space showing.
    window.addEventListener('resize', () => {
      if (!this.world) return;
      this.zoom = this.clampZoom(this.zoom);
      this.clampPan();
      this.applyTransform();
    });
  }

  // The color for the next drawing: a tool's fixed color (e.g. the players'
  // Attack=red / Move=blue buttons) when set, else the DM's color picker.
  color() {
    if (this._toolColor) return this._toolColor;
    const el = this.section.querySelector('.atlas-color');
    return (el && el.value) || '#4aa3ff';
  }

  // ----- rendering -----

  render() {
    const map = this.snapshot.map;
    this.viewport.innerHTML = '';
    if (!map) {
      const p = document.createElement('p');
      p.className = 'atlas-empty';
      p.textContent = 'No active map';
      this.viewport.appendChild(p);
      this.world = null;
      return;
    }
    this.world = document.createElement('div');
    this.world.className = 'atlas-world';

    const w = (map.width || 40) * BASE_CELL;
    const h = (map.height || 30) * BASE_CELL;
    const bg = document.createElement('div');
    bg.className = 'atlas-bg';
    bg.style.width = w + 'px';
    bg.style.height = h + 'px';
    if (map.image) bg.style.backgroundImage = 'url("' + map.image + '")';
    this.world.appendChild(bg);

    // Grid as explicit geometry (an SVG path), not a repeating-gradient
    // background. A CSS gradient is rasterised once and then scaled by the
    // world's zoom transform, which makes its periodic 1px lines alias against
    // the device pixel grid — some lines drop out at certain zooms. Drawn as
    // lines, every line is painted individually; its stroke is re-pinned to
    // ~1 screen px on each zoom (see updateGridStroke / applyTransform).
    this.gridPath = null;
    if (map.grid && map.grid.type === 'square') {
      this.world.appendChild(this.buildGridLayer(w, h, map));
    }

    // Zones (spell areas / hazards) sit above the grid but below tokens.
    this.world.appendChild(this.buildZoneLayer(w, h));

    this.annLayer = this.buildAnnotationLayer(w, h);
    this.world.appendChild(this.annLayer);

    (this.snapshot.tokens || []).forEach((t) => this.world.appendChild(this.tokenEl(t)));
    this.viewport.appendChild(this.world);
    this.applyTransform();
  }

  // A full-map SVG of square-grid lines, aligned to the Grid Origin. One path
  // holds every line; positions are exact integers so the geometry is crisp,
  // and the stroke width is kept ~1 screen px by updateGridStroke.
  buildGridLayer(w, h, map) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'atlas-grid');
    svg.setAttribute('width', w);
    svg.setAttribute('height', h);
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
    const ox = ((map.grid.origin && map.grid.origin[0]) || 0) * BASE_CELL;
    const oy = ((map.grid.origin && map.grid.origin[1]) || 0) * BASE_CELL;
    const startX = (((ox % BASE_CELL) + BASE_CELL) % BASE_CELL);
    const startY = (((oy % BASE_CELL) + BASE_CELL) % BASE_CELL);
    let d = '';
    for (let x = startX; x <= w + 0.5; x += BASE_CELL) { const px = Math.round(x); d += 'M' + px + ' 0V' + h; }
    for (let y = startY; y <= h + 0.5; y += BASE_CELL) { const py = Math.round(y); d += 'M0 ' + py + 'H' + w; }
    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('class', 'atlas-grid-line');
    path.setAttribute('d', d);
    path.setAttribute('fill', 'none');
    path.setAttribute('stroke', 'rgba(255,255,255,0.18)');
    svg.appendChild(path);
    this.gridPath = path;
    this.updateGridStroke();
    return svg;
  }

  // Keep grid lines ~1 device pixel wide at any zoom. The lines live inside the
  // world, which the transform scales by `zoom`, so a stroke of 1/zoom user
  // units paints as a single pixel after that scale — independent of zoom.
  updateGridStroke() {
    if (this.gridPath) this.gridPath.setAttribute('stroke-width', String(1 / this.zoom));
  }

  // SVG layer of Zones (spell areas / hazards). A circle's `size` is its radius
  // in Map Units; a square's `size` is its side. Both center on the anchor cell.
  buildZoneLayer(w, h) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'atlas-zones');
    svg.setAttribute('width', w);
    svg.setAttribute('height', h);
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
    const defs = document.createElementNS(SVG_NS, 'defs');
    svg.appendChild(defs);
    (this.snapshot.zones || []).forEach((z) => {
      const el = this.zoneEl(z, defs);
      if (el) svg.appendChild(el);
    });
    return svg;
  }

  // A Zone shape. A `texture` fills it with /images/zones/<texture>.png clipped
  // to the shape (via an SVG pattern); without one it falls back to the solid
  // purple fill from CSS. The image fill is set inline so it wins over the CSS.
  zoneEl(z, defs) {
    const a = z.anchor || {};
    const cx = ((a.x || 0) + 0.5) * BASE_CELL;
    const cy = ((a.y || 0) + 0.5) * BASE_CELL;
    const size = (z.size || 0) * BASE_CELL;
    let el, bx, by, bw, bh;
    if (z.shape === 'square') {
      bx = cx - size / 2; by = cy - size / 2; bw = bh = size;
      el = document.createElementNS(SVG_NS, 'rect');
      el.setAttribute('x', bx); el.setAttribute('y', by);
      el.setAttribute('width', bw); el.setAttribute('height', bh);
    } else {
      // circle (default); line / cone rendering is deferred.
      bx = cx - size; by = cy - size; bw = bh = size * 2;
      el = document.createElementNS(SVG_NS, 'circle');
      el.setAttribute('cx', cx); el.setAttribute('cy', cy); el.setAttribute('r', size);
    }
    el.setAttribute('class', 'atlas-zone');
    if (z.id != null) el.dataset.zoneId = z.id;
    if (z.texture && defs) {
      const pid = 'zone-tex-' + (z.id != null ? z.id : Math.random().toString(36).slice(2));
      defs.appendChild(zonePattern(pid, bx, by, bw, bh, '/images/zones/' + z.texture));
      el.classList.add('atlas-zone-textured');
      el.style.fill = 'url(#' + pid + ')';
    }
    return el;
  }

  buildAnnotationLayer(w, h) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'atlas-annotations');
    svg.setAttribute('width', w);
    svg.setAttribute('height', h);
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
    const defs = document.createElementNS(SVG_NS, 'defs');
    svg.appendChild(defs);
    svg._defs = defs;
    (this.snapshot.annotations || []).forEach((a) => {
      const el = this.annotationEl(svg, a);
      if (el) svg.appendChild(el);
    });
    return svg;
  }

  // Build the SVG element for one Annotation (world px = unit * BASE_CELL).
  annotationEl(svg, a, idSuffix) {
    const color = a.color || '#4aa3ff';
    const pts = (a.points || []).map((p) => [p[0] * BASE_CELL, p[1] * BASE_CELL]);
    if (a.type === 'arrow' && pts.length >= 2) {
      const mid = 'atlas-ah-' + (idSuffix != null ? idSuffix : a.id);
      const marker = svgEl('marker', { id: mid, markerWidth: 10, markerHeight: 10, refX: 8, refY: 5,
        orient: 'auto', markerUnits: 'userSpaceOnUse' });
      marker.appendChild(svgEl('path', { d: 'M0,0 L10,5 L0,10 z', fill: color }));
      svg._defs.appendChild(marker);
      return svgEl('line', { x1: pts[0][0], y1: pts[0][1], x2: pts[1][0], y2: pts[1][1],
        stroke: color, 'stroke-width': 3, 'stroke-linecap': 'round',
        'marker-end': 'url(#' + mid + ')', class: 'atlas-annotation' });
    }
    if (a.type === 'shape' && pts.length >= 2) {
      const x0 = Math.min(pts[0][0], pts[1][0]); const y0 = Math.min(pts[0][1], pts[1][1]);
      const w = Math.abs(pts[1][0] - pts[0][0]); const h = Math.abs(pts[1][1] - pts[0][1]);
      // Solid fill (not a translucent wash).
      const attrs = { fill: color, 'fill-opacity': 1, stroke: color, 'stroke-width': 1, class: 'atlas-annotation' };
      if (a.shape_kind === 'ellipse') {
        return svgEl('ellipse', Object.assign(attrs, { cx: x0 + w / 2, cy: y0 + h / 2, rx: w / 2, ry: h / 2 }));
      }
      return svgEl('rect', Object.assign(attrs, { x: x0, y: y0, width: w, height: h }));
    }
    if (a.type === 'text' && pts.length >= 1) {
      const t = svgEl('text', { x: pts[0][0], y: pts[0][1], fill: color, 'font-size': 16,
        'font-weight': 700, class: 'atlas-annotation atlas-annotation-text' });
      t.textContent = a.text || '';
      return t;
    }
    return null;
  }

  tokenEl(t) {
    const el = document.createElement('div');
    const tier = (t.tier === null || t.tier === undefined) ? 'unknown' : t.tier;
    el.className = 'atlas-token atlas-tier-' + tier +
      (t.hidden ? ' atlas-token-hidden' : '') +
      (t.acting ? ' atlas-token-acting' : (t.combatant_id != null ? ' atlas-token-combatant' : ''));
    el.style.left = (t.x * BASE_CELL) + 'px';
    el.style.top = (t.y * BASE_CELL) + 'px';
    el.style.width = (t.size * BASE_CELL) + 'px';
    el.style.height = (t.size * BASE_CELL) + 'px';
    el.dataset.tokenId = t.id;
    el.dataset.creatureId = t.creature_id;
    if (t.combatant_id != null) el.dataset.combatantId = t.combatant_id;
    el._token = t;
    if (t.image) {
      const img = document.createElement('img');
      img.className = 'atlas-token-img';
      img.src = t.image; img.alt = t.label;
      // If the icon fails to load, fall back to the `?` marker.
      img.addEventListener('error', () => { img.remove(); el.classList.add('atlas-token-noicon'); el.appendChild(qmark()); });
      el.appendChild(img);
    } else {
      // No icon — a `?` marker (atlas_stub.md).
      el.classList.add('atlas-token-noicon');
      el.appendChild(qmark());
    }
    return el;
  }

  applyTransform() {
    if (!this.world) return;
    this.world.style.transform =
      'translate(' + this.panX + 'px, ' + this.panY + 'px) scale(' + this.zoom + ')';
    this.updateGridStroke();
    const label = this.section.querySelector('.atlas-zoom-label');
    if (label) label.textContent = Math.round(this.zoom * 100) + '%';
  }

  // ----- pan & zoom -----
  //
  // The view is bounded: you can never zoom out far enough to shrink the Map
  // below the viewport, and panning can never reveal empty space beyond a Map
  // edge. Both rules fall out of a "cover" fit — the Map always covers the
  // viewport on both axes — enforced by minZoomLimit() (the zoom floor) and
  // clampPan() (the pan range).

  // The smallest zoom at which the Map still fully covers the viewport on both
  // axes; zooming out past this would show off-Map space, which we forbid. It
  // is the larger of the two axis ratios.
  coverZoom() {
    const map = this.snapshot.map;
    if (!map) return this.minZoom;
    const worldW = (map.width || 40) * BASE_CELL;
    const worldH = (map.height || 30) * BASE_CELL;
    const vw = this.viewport.clientWidth;
    const vh = this.viewport.clientHeight;
    if (!worldW || !worldH || !vw || !vh) return this.minZoom;
    return Math.max(vw / worldW, vh / worldH);
  }

  // The effective zoom floor: never below the cover fit (so the Map always
  // fills the viewport), honoring the config's own floor when it is tighter,
  // and capped at the maximum so the range stays valid for a tiny Map.
  minZoomLimit() {
    return Math.min(this.maxZoom, Math.max(this.minZoom, this.coverZoom()));
  }

  clampZoom(z) { return clamp(z, this.minZoomLimit(), this.maxZoom); }

  // Pin the pan so no viewport edge falls outside the Map. With cover enforced
  // both displayed extents are ≥ the viewport, so each axis clamps into a valid
  // range; an axis that is (degenerately) smaller is centered.
  clampPan() {
    const map = this.snapshot.map;
    if (!map) return;
    const dispW = (map.width || 40) * BASE_CELL * this.zoom;
    const dispH = (map.height || 30) * BASE_CELL * this.zoom;
    const vw = this.viewport.clientWidth;
    const vh = this.viewport.clientHeight;
    this.panX = dispW >= vw ? clamp(this.panX, vw - dispW, 0) : (vw - dispW) / 2;
    this.panY = dispH >= vh ? clamp(this.panY, vh - dispH, 0) : (vh - dispH) / 2;
  }

  recenter() {
    const map = this.snapshot.map;
    if (!map || !this.world) return;
    this.zoom = this.clampZoom(this.zoom);
    const w = (map.width || 40) * BASE_CELL * this.zoom;
    const h = (map.height || 30) * BASE_CELL * this.zoom;
    this.panX = (this.viewport.clientWidth - w) / 2;
    this.panY = (this.viewport.clientHeight - h) / 2;
    this.clampPan();
    this.applyTransform();
  }

  resetView() {
    this.zoom = this.clampZoom(this.initialZoom);
    this.recenter();
  }

  zoomAround(factor, sx, sy) {
    const next = this.clampZoom(this.zoom * factor);
    if (next === this.zoom) return;
    const wx = (sx - this.panX) / this.zoom;
    const wy = (sy - this.panY) / this.zoom;
    this.zoom = next;
    this.panX = sx - wx * this.zoom;
    this.panY = sy - wy * this.zoom;
    this.clampPan();
    this.applyTransform();
  }

  // Screen (client) coordinates → Map Units.
  toUnits(clientX, clientY) {
    const r = this.viewport.getBoundingClientRect();
    return [
      (clientX - r.left - this.panX) / (this.zoom * BASE_CELL),
      (clientY - r.top - this.panY) / (this.zoom * BASE_CELL)
    ];
  }

  bindCanvas() {
    this.viewport.addEventListener('wheel', (e) => {
      if (!this.world) return;
      e.preventDefault();
      const r = this.viewport.getBoundingClientRect();
      this.zoomAround(e.deltaY < 0 ? 1.1 : 1 / 1.1, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });

    this.viewport.addEventListener('pointerdown', (e) => {
      if (!this.world) return;
      // Placing a spell area: drop the footprint at the clicked cell (local).
      if (this.placingArea) return this.placeArea(e);
      // Placing a Combatant: drop / drag the new Token to the clicked cell.
      if (this.placing) return this.beginPlace(e);
      if (this.tool !== 'select') {
        if (this.tool === 'text') return this.beginText(e);
        return this.beginDraw(e);
      }
      // A dropped-but-uncommitted spell footprint can be dragged to re-aim it.
      if (this._placedArea && e.target.closest && e.target.closest('.atlas-zone-preview')) {
        return this.beginAreaDrag(e);
      }
      const tokenEl = e.target.closest('.atlas-token');
      if (tokenEl && this.viewer === 'dm') return this.beginTokenDrag(e, tokenEl);
      this.beginPan(e);
    });

    this.viewport.addEventListener('pointermove', (e) => {
      if (this.placing || this.tool !== 'select') return; // suppress tooltip while placing/drawing
      const tokenEl = e.target.closest('.atlas-token');
      if (tokenEl && tokenEl._token) this.showTip(tokenEl._token, e);
      else this.hideTip();
    });
    this.viewport.addEventListener('pointerleave', () => this.hideTip());
  }

  beginPan(e) {
    e.preventDefault();
    this.hideTip();
    this.viewport.classList.add('atlas-panning');
    const start = { x: e.clientX, y: e.clientY, panX: this.panX, panY: this.panY };
    this.viewport.setPointerCapture(e.pointerId);
    const onMove = (ev) => {
      this.panX = start.panX + (ev.clientX - start.x);
      this.panY = start.panY + (ev.clientY - start.y);
      this.clampPan();
      this.applyTransform();
    };
    const onUp = () => {
      this.viewport.classList.remove('atlas-panning');
      this.viewport.removeEventListener('pointermove', onMove);
      this.viewport.removeEventListener('pointerup', onUp);
    };
    this.viewport.addEventListener('pointermove', onMove);
    this.viewport.addEventListener('pointerup', onUp);
  }

  beginTokenDrag(e, tokenEl) {
    e.preventDefault();
    this.hideTip();
    const start = { x: e.clientX, y: e.clientY };
    const origin = { left: parseFloat(tokenEl.style.left), top: parseFloat(tokenEl.style.top) };
    let moved = false;
    tokenEl.setPointerCapture(e.pointerId);
    const onMove = (ev) => {
      const dx = ev.clientX - start.x; const dy = ev.clientY - start.y;
      if (Math.abs(dx) > 4 || Math.abs(dy) > 4) moved = true;
      if (moved) {
        tokenEl.style.left = (origin.left + dx / this.zoom) + 'px';
        tokenEl.style.top = (origin.top + dy / this.zoom) + 'px';
      }
    };
    const onUp = () => {
      tokenEl.removeEventListener('pointermove', onMove);
      tokenEl.removeEventListener('pointerup', onUp);
      if (moved) {
        const x = Math.round(parseFloat(tokenEl.style.left) / BASE_CELL);
        const y = Math.round(parseFloat(tokenEl.style.top) / BASE_CELL);
        this.postRender('/atlas/move_token', { token_id: tokenEl.dataset.tokenId, x, y });
      } else {
        this.target(tokenEl);
      }
    };
    tokenEl.addEventListener('pointermove', onMove);
    tokenEl.addEventListener('pointerup', onUp);
  }

  // ----- drawing (Annotations) -----

  // Snap a Map-Unit point to the nearest Grid corner (integer cell boundary,
  // offset by the Grid Origin). Used for shapes so rectangles/ellipses align
  // to cells; arrows are drawn freely.
  snapToCorner(p) {
    const grid = this.snapshot.map && this.snapshot.map.grid;
    const ox = (grid && grid.origin && grid.origin[0]) || 0;
    const oy = (grid && grid.origin && grid.origin[1]) || 0;
    return [Math.round(p[0] - ox) + ox, Math.round(p[1] - oy) + oy];
  }

  // Drag-to-draw for arrow / rect / ellipse, with a live preview element.
  beginDraw(e) {
    e.preventDefault();
    this.hideTip();
    const type = this.tool === 'arrow' ? 'arrow' : 'shape';
    const shapeKind = this.tool === 'rect' ? 'rect' : (this.tool === 'ellipse' ? 'ellipse' : null);
    const snap = (p) => (type === 'shape' ? this.snapToCorner(p) : p);
    const start = snap(this.toUnits(e.clientX, e.clientY));
    const preview = { type, shape_kind: shapeKind, color: this.color(), points: [start, start] };
    let el = this.annotationEl(this.annLayer, preview, 'preview');
    if (el) this.annLayer.appendChild(el);
    this.viewport.setPointerCapture(e.pointerId);

    const onMove = (ev) => {
      preview.points[1] = snap(this.toUnits(ev.clientX, ev.clientY));
      const next = this.annotationEl(this.annLayer, preview, 'preview');
      if (next && el) { this.annLayer.replaceChild(next, el); el = next; }
    };
    const onUp = (ev) => {
      this.viewport.removeEventListener('pointermove', onMove);
      this.viewport.removeEventListener('pointerup', onUp);
      const end = snap(this.toUnits(ev.clientX, ev.clientY));
      // For a shape, require a non-zero cell span; an arrow needs a small drag.
      const span = type === 'shape'
        ? (Math.abs(end[0] - start[0]) >= 1 && Math.abs(end[1] - start[1]) >= 1)
        : (Math.hypot(end[0] - start[0], end[1] - start[1]) >= 0.2);
      if (!span) { this.render(); return; } // too small — discard preview
      this.postDraw({ type, shape_kind: shapeKind, color: this.color(), points: [start, end] });
    };
    this.viewport.addEventListener('pointermove', onMove);
    this.viewport.addEventListener('pointerup', onUp);
  }

  // Text tool: drop an inline input at the click point (no browser prompt);
  // Enter / blur commits, Escape cancels.
  beginText(e) {
    e.preventDefault();
    const r = this.viewport.getBoundingClientRect();
    const sx = e.clientX - r.left; const sy = e.clientY - r.top;
    const at = this.toUnits(e.clientX, e.clientY);
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'atlas-text-input';
    input.placeholder = 'Label…';
    input.style.left = sx + 'px';
    input.style.top = sy + 'px';
    input.style.color = this.color();
    this.viewport.appendChild(input);
    input.focus();
    let done = false;
    const finish = (commit) => {
      if (done) return; done = true;
      const text = input.value.trim();
      input.remove();
      if (commit && text) this.postDraw({ type: 'text', color: this.color(), points: [at], text });
    };
    input.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter') { ev.preventDefault(); finish(true); }
      else if (ev.key === 'Escape') { ev.preventDefault(); finish(false); }
    });
    input.addEventListener('blur', () => finish(true));
  }

  // ----- click-to-target (turn_action_stub.md → Attack) -----

  target(tokenEl) {
    const combatantId = tokenEl.dataset.combatantId;
    if (combatantId == null || combatantId === '') return;
    const builder = document.querySelector('.turn-action .ta-attack .action-builder');
    if (!builder) return;
    const summary = builder.querySelector('.step-summary[data-step="target"]');
    if (summary && !summary.hidden) {
      const chg = summary.querySelector('.cr-step-change');
      if (chg) chg.click();
    }
    const opt = builder.querySelector('.cb-opt[data-step="target"][data-value="' + combatantId + '"]');
    if (opt && !opt.disabled) { opt.click(); builder.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); }
  }

  // ----- hover tooltip (atlas_token_tooltip.md) -----

  showTip(t, e) {
    let tip = this._tip;
    if (!tip) { tip = document.createElement('div'); tip.className = 'atlas-tooltip'; document.body.appendChild(tip); this._tip = tip; }
    const tierClass = (t.tier === null || t.tier === undefined) ? '' : 'tier-' + t.tier;
    let parts;
    if (t.unknown) {
      parts = ['<div class="atlas-tt-name">Unknown creature (#' + esc(t.creature_id) + ')</div>'];
    } else {
      parts = ['<div class="atlas-tt-name ' + tierClass + '">' + esc(t.label) + '</div>'];
      if (t.subtitle) parts.push('<div class="atlas-tt-sub">' + esc(t.subtitle) + '</div>');
      if (t.combatant_id != null) {
        const init = t.initiative ? 'Init ' + esc(t.initiative) : 'In initiative';
        parts.push('<div class="atlas-tt-status">' + init +
          (t.acting ? ' <span class="atlas-tt-badge">Acting now</span>' : '') + '</div>');
      }
    }
    tip.innerHTML = parts.join('');
    tip.hidden = false;
    tip.style.left = (e.clientX + 14) + 'px';
    tip.style.top = (e.clientY + 14) + 'px';
  }

  hideTip() { if (this._tip) this._tip.hidden = true; }

  // ----- toolbar -----

  bindToolbar() {
    const q = (sel) => this.section.querySelector(sel);
    const on = (sel, ev, fn) => { const el = q(sel); if (el) el.addEventListener(ev, fn); };

    on('.atlas-zoom-in', 'click', () => this.zoomAround(1.2, this.viewport.clientWidth / 2, this.viewport.clientHeight / 2));
    on('.atlas-zoom-out', 'click', () => this.zoomAround(1 / 1.2, this.viewport.clientWidth / 2, this.viewport.clientHeight / 2));
    on('.atlas-reset-view', 'click', () => this.resetView());
    on('.atlas-recenter', 'click', () => this.recenter());

    // Drawing tools (both roles; the server gates which tools are rendered).
    this.section.querySelectorAll('.atlas-tool').forEach((btn) => {
      btn.addEventListener('click', () => {
        if (btn.disabled) return;
        this.tool = btn.dataset.tool;
        this._toolColor = btn.dataset.color || null;  // fixed color per tool, if any
        this.section.querySelectorAll('.atlas-tool').forEach((b) =>
          b.classList.toggle('atlas-tool-active', b === btn));
        this.viewport.classList.toggle('atlas-drawing', this.tool !== 'select');
      });
    });
    on('.atlas-clear-drawings', 'click', () => {
      if (!window.confirm('Clear ' + (this.viewer === 'dm' ? 'all drawings' : 'your arrows') + ' on this map?')) return;
      this.postRender('/atlas/clear_annotations', {});
    });

    if (this.viewer !== 'dm') return;

    const panels = Array.from(this.section.querySelectorAll('.atlas-form-panel, .atlas-place-panel'));
    const togglePanel = (sel) => {
      const target = this.section.querySelector(sel);
      panels.forEach((p) => { if (p !== target) p.hidden = true; });
      if (target) target.hidden = !target.hidden;
      return target;
    };
    const fields = (panel) => ({
      name: panel.querySelector('.atlas-f-name'),
      width: panel.querySelector('.atlas-f-width'),
      height: panel.querySelector('.atlas-f-height')
    });

    on('.atlas-map-picker', 'change', (e) => {
      const opt = e.target.selectedOptions[0];
      const id = e.target.value;
      if (!id) return;
      if (opt && opt.dataset.archived) { window.location = '/encounter?map=' + ENC(id); return; }
      this.postReload('/atlas/set_active_map', { map_id: id }, '/encounter');
    });

    on('.atlas-add-map', 'click', () => {
      const panel = togglePanel('.atlas-add-panel');
      if (panel && !panel.hidden) { const f = fields(panel); f.name.value = ''; f.width.value = ''; f.height.value = ''; f.name.focus(); }
    });
    on('.atlas-add-submit', 'click', () => {
      const f = fields(this.section.querySelector('.atlas-add-panel'));
      if (!f.name.value.trim()) { f.name.focus(); return; }
      this.postReload('/atlas/add_map', { name: f.name.value.trim(), width: f.width.value, height: f.height.value }, '/encounter');
    });
    on('.atlas-edit-map', 'click', () => { togglePanel('.atlas-edit-panel'); });
    on('.atlas-edit-submit', 'click', (e) => {
      const f = fields(this.section.querySelector('.atlas-edit-panel'));
      if (!f.name.value.trim()) { f.name.focus(); return; }
      this.postReload('/atlas/edit_map',
        { map_id: e.target.dataset.mapId, name: f.name.value.trim(), width: f.width.value, height: f.height.value }, null);
    });
    this.section.querySelectorAll('.atlas-form-cancel').forEach((b) =>
      b.addEventListener('click', () => panels.forEach((p) => { p.hidden = true; })));

    on('.atlas-archive-map', 'click', (e) => {
      if (!window.confirm('Archive this map? It will be hidden from the default list.')) return;
      this.postReload('/atlas/archive_map', { map_id: e.target.dataset.mapId }, '/encounter');
    });
    on('.atlas-unarchive-map', 'click', (e) => {
      this.postReload('/atlas/unarchive_map', { map_id: e.target.dataset.mapId, activate: 'true' }, '/encounter');
    });
    on('.atlas-delete-map', 'click', (e) => {
      if (!window.confirm('Delete this map and all its tokens? This cannot be undone.')) return;
      this.postReload('/atlas/delete_map', { map_id: e.target.dataset.mapId }, '/encounter');
    });

    on('.atlas-clear-btn', 'click', () => {
      if (!window.confirm('Remove every token on this map?')) return;
      this.postRender('/atlas/clear_tokens', {});
    });

    const panel = this.section.querySelector('.atlas-place-panel');
    on('.atlas-place-toggle', 'click', () => { togglePanel('.atlas-place-panel'); });
    if (panel) {
      panel.addEventListener('click', (e) => {
        const chip = e.target.closest('.atlas-place-chip');
        if (!chip) return;
        panel.hidden = true;
        // Arm placement: the DM then clicks (or drags) on the map to drop the
        // Token at the chosen cell, rather than auto-dropping at the center.
        this.armPlace(chip.dataset.creatureId, chip.textContent.trim());
      });
    }
  }

  // ----- placing a Combatant's Token -----

  armPlace(creatureId, name) {
    this.placing = creatureId;
    this.tool = 'select';
    this.section.querySelectorAll('.atlas-tool').forEach((b) =>
      b.classList.toggle('atlas-tool-active', b.dataset.tool === 'select'));
    this.viewport.classList.remove('atlas-drawing');
    this.viewport.classList.add('atlas-placing');
    this.showPlaceHint('Click the map to place ' + (name || 'token') + ' — Esc to cancel');
  }

  clearPlacing() {
    this.placing = null;
    this.viewport.classList.remove('atlas-placing');
    this.hidePlaceHint();
    if (this._ghost) { this._ghost.remove(); this._ghost = null; }
  }

  // ----- placing a spell area (local preview only) -----

  armArea(detail) {
    if (!this.world) return;
    this.placingArea = { shape: (detail.shape || 'circle'), size: parseInt(detail.size, 10) || 0 };
    this.placing = null;
    this.tool = 'select';
    this.viewport.classList.add('atlas-placing');
    this.showPlaceHint('Click the map to place the spell effect — Esc to cancel');
  }

  placeArea(e) {
    e.preventDefault();
    const u = this.toUnits(e.clientX, e.clientY);
    // Anchor to the cell under the cursor (floor), so the footprint centers on
    // the clicked cell rather than snapping to the nearest grid line (which
    // could land the effect half a cell — or a whole cell — away).
    const x = Math.floor(u[0]);
    const y = Math.floor(u[1]);
    const area = this.placingArea;
    this.placingArea = null;
    this.viewport.classList.remove('atlas-placing');
    // Keep the footprint live and draggable until the cast is committed, so the
    // caster can re-aim it; each move re-reports the caught creatures.
    this._placedArea = { x: x, y: y, area: area };
    this.renderAreaPreview(x, y, area);
    this.showPlaceHint('Drag the spell effect to re-aim it before confirming');
    this.emitAreaPlaced();
  }

  // Recompute the creatures the current footprint catches and report them to
  // the cast panel (nothing is persisted until the cast is committed).
  emitAreaPlaced() {
    const p = this._placedArea;
    if (!p) return;
    const hits = this.tokensInArea(p.x, p.y, p.area);
    document.dispatchEvent(new CustomEvent('cast:area-placed', {
      detail: { x: p.x, y: p.y, shape: p.area.shape, size: p.area.size, hits: hits }
    }));
  }

  // Drag a dropped (un-committed) spell footprint to a new cell. The preview
  // follows the pointer snapped to Grid cells; releasing on a new cell
  // recomputes the caught creatures and re-reports them to the cast panel.
  beginAreaDrag(e) {
    e.preventDefault();
    this.hideTip();
    const area = this._placedArea.area;
    const startX = this._placedArea.x;
    const startY = this._placedArea.y;
    const moveTo = (cx, cy) => {
      const u = this.toUnits(cx, cy);
      const x = Math.floor(u[0]);
      const y = Math.floor(u[1]);
      if (x === this._placedArea.x && y === this._placedArea.y) return;
      this._placedArea.x = x;
      this._placedArea.y = y;
      this.renderAreaPreview(x, y, area);
    };
    this.viewport.setPointerCapture(e.pointerId);
    const onMove = (ev) => moveTo(ev.clientX, ev.clientY);
    const onUp = (ev) => {
      this.viewport.removeEventListener('pointermove', onMove);
      this.viewport.removeEventListener('pointerup', onUp);
      moveTo(ev.clientX, ev.clientY);
      // Only re-report (and re-fetch Save Rolls) when the footprint actually moved.
      if (this._placedArea.x !== startX || this._placedArea.y !== startY) this.emitAreaPlaced();
    };
    this.viewport.addEventListener('pointermove', onMove);
    this.viewport.addEventListener('pointerup', onUp);
  }

  // A local-only preview of the footprint (purple), cleared on the next place
  // or when the canvas re-renders from a fresh snapshot.
  renderAreaPreview(x, y, area) {
    if (this._areaPreview) this._areaPreview.remove();
    const map = this.snapshot.map || {};
    const w = (map.width || 40) * BASE_CELL;
    const h = (map.height || 30) * BASE_CELL;
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'atlas-zones atlas-zone-preview');
    svg.setAttribute('width', w); svg.setAttribute('height', h);
    svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
    const el = this.zoneEl({ anchor: { x: x, y: y }, shape: area.shape, size: area.size });
    if (el) svg.appendChild(el);
    this.world.appendChild(svg);
    this._areaPreview = svg;
  }

  // Combatant Tokens whose center lies within the footprint centered on the
  // clicked cell. circle: distance <= size (radius in cells); square: size on
  // a side. Only Tokens tied to a Combatant are reported (the cast resolves by
  // Combatant id).
  tokensInArea(x, y, area) {
    const acx = x + 0.5;
    const acy = y + 0.5;
    const r = area.size;
    const out = [];
    (this.snapshot.tokens || []).forEach((t) => {
      if (t.combatant_id == null) return;
      const tcx = (t.x || 0) + (t.size || 1) / 2;
      const tcy = (t.y || 0) + (t.size || 1) / 2;
      let inside;
      if (area.shape === 'square') {
        inside = Math.abs(tcx - acx) <= r / 2 && Math.abs(tcy - acy) <= r / 2;
      } else {
        const dx = tcx - acx, dy = tcy - acy;
        inside = Math.sqrt(dx * dx + dy * dy) <= r;
      }
      if (inside) out.push({ combatant_id: t.combatant_id, creature_id: t.creature_id, label: t.label });
    });
    return out;
  }

  // Drop / drag the new Token: a ghost follows the pointer (snapped to cells);
  // release commits *Place Token* at that cell.
  beginPlace(e) {
    e.preventDefault();
    const creatureId = this.placing;
    const ghost = document.createElement('div');
    ghost.className = 'atlas-token atlas-token-ghost';
    ghost.style.width = BASE_CELL + 'px';
    ghost.style.height = BASE_CELL + 'px';
    this.world.appendChild(ghost);
    this._ghost = ghost;
    const moveGhost = (cx, cy) => {
      const u = this.toUnits(cx, cy);
      ghost.style.left = (Math.round(u[0]) * BASE_CELL) + 'px';
      ghost.style.top = (Math.round(u[1]) * BASE_CELL) + 'px';
    };
    moveGhost(e.clientX, e.clientY);
    this.viewport.setPointerCapture(e.pointerId);
    const onMove = (ev) => moveGhost(ev.clientX, ev.clientY);
    const onUp = (ev) => {
      this.viewport.removeEventListener('pointermove', onMove);
      this.viewport.removeEventListener('pointerup', onUp);
      const u = this.toUnits(ev.clientX, ev.clientY);
      this.clearPlacing();
      this.postRender('/atlas/place_token', { creature_id: creatureId, x: Math.round(u[0]), y: Math.round(u[1]) });
    };
    this.viewport.addEventListener('pointermove', onMove);
    this.viewport.addEventListener('pointerup', onUp);
  }

  showPlaceHint(text) {
    let hint = this.section.querySelector('.atlas-place-armed');
    if (!hint) {
      hint = document.createElement('div');
      hint.className = 'atlas-place-armed';
      this.viewport.appendChild(hint);
    }
    hint.textContent = text;
    hint.hidden = false;
  }

  hidePlaceHint() {
    const hint = this.section.querySelector('.atlas-place-armed');
    if (hint) hint.hidden = true;
  }

  // ----- requests -----

  postRender(url, body) {
    formPost(url, body).then((res) => {
      if (res && res.snapshot) { this.snapshot = res.snapshot; this.render(); this.applyTransform(); }
    });
  }

  // JSON-bodied draw mutation; re-render the canvas from the returned snapshot.
  postDraw(obj) {
    fetch('/atlas/add_annotation', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(obj) })
      .then((r) => r.json().catch(() => null))
      .then((res) => {
        if (res && res.snapshot) { this.snapshot = res.snapshot; this.render(); this.applyTransform(); }
        else this.render(); // drop the preview on failure
      })
      .catch(() => this.render());
  }

  postReload(url, body, target) {
    formPost(url, body).then(() => { window.location = target || window.location.href; });
  }
}

function formPost(url, body) {
  const fd = new FormData();
  Object.keys(body).forEach((k) => fd.append(k, body[k]));
  return fetch(url, { method: 'POST', body: fd })
    .then((r) => r.json().catch(() => null))
    .catch(() => null);
}

function svgEl(name, attrs) {
  const el = document.createElementNS(SVG_NS, name);
  Object.keys(attrs).forEach((k) => el.setAttribute(k, attrs[k]));
  return el;
}

// The `?` marker shown when a Token has no icon.
function qmark() {
  const span = document.createElement('span');
  span.className = 'atlas-token-qmark';
  span.textContent = '?';
  return span;
}

function parseJSON(s) { try { return JSON.parse(s); } catch (e) { return null; } }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
