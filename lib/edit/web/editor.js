/* Lotus image editor – the page: the crop frame on the picture, the dial, the Face Blur tab, the Convert tab. No framework, no
 * network except the editor's own server. The geometry (what a rectangle may do, what the finished picture is) is geometry.js,
 * hiding faces is blur.js, finding them is faces.js (in a worker, faces-worker.js).
 */
(function () {
  'use strict';

  var G = window.LotusGeometry, B = window.LotusBlur;
  var cfg = JSON.parse(document.getElementById('config').textContent);
  var T = cfg.strings;
  var base = location.pathname.replace(/[^/]*$/, '');            // '/<secret>/'
  var $ = function (id) { return document.getElementById(id); };
  var app = $('app'), stage = $('stage'), img = $('img'), frameEl = $('frame');

  // ── Texts ──
  function t(key) {
    var s = T[key] === undefined ? key : T[key], i = 1, a = arguments;
    return s.replace(/%s/g, function () { return i < a.length ? a[i++] : ''; });
  }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; }
  [].forEach.call(document.querySelectorAll('[data-t]'), function (e) { e.textContent = t(e.getAttribute('data-t')); });
  [].forEach.call(document.querySelectorAll('[data-title]'), function (e) { e.title = t('t_' + e.getAttribute('data-title')); });
  [].forEach.call(document.querySelectorAll('[data-label]'), function (e) { e.setAttribute('aria-label', t('t_' + e.getAttribute('data-label'))); });
  document.documentElement.lang = cfg.lang;

  // ── State ──
  var state = null;                                              // the geometry (set when the picture is loaded)
  var ui = {
    tab: 'crop', ratioKey: 'free', portrait: false, format: cfg.defaults.format, quality: cfg.defaults.quality, max: cfg.defaults.max,
    drag: null, dial: null, saved: [], cleanSig: null, busy: false, menu: false, plan: null, planFor: ''
  };
  var L = { k: 1, ox: 0, oy: 0 };                                // frame → stage: x · k + ox
  var queued = false;
  // Face Blur: the faces that were found (each hidden or left out), the lines drawn over the picture, and how they are hidden.
  // Every shape is in pixels of the picture as it was opened – it stays where it is when the picture is cropped or turned.
  var fb = { status: 'idle', error: '', faces: [], strokes: [], type: 'blur', strength: B.STRENGTH, drawing: false, brush: 1, ink: null };
  var VIEW_MAX = 2048;                                           // the copy the tabs show is at most this big
  var view = { clean: null, canvas: null, ctx: null, key: '' };
  var fbL = null;                                                // the Face Blur tab's view: picture → stage

  function formatOf(key) { for (var i = 0; i < cfg.formats.length; i++) if (cfg.formats[i].key === key) return cfg.formats[i]; return cfg.formats[0]; }
  function lossy() { return !!formatOf(ui.format).lossy; }
  function px(n) { return Math.round(n).toLocaleString(cfg.lang === 'en' ? 'en-US' : cfg.lang); }
  function dims(w, h) { return px(w) + ' × ' + px(h); }

  // ── Layout ──
  function layout() {
    var r = stage.getBoundingClientRect(), f = G.frameSize(state);
    var padX = Math.max(18, Math.min(44, r.width * 0.05)), padY = r.height < 300 ? 18 : 40;      // (the hint is above the picture, its size below)
    var k = Math.max(1e-4, Math.min((r.width - 2 * padX) / f.w, (r.height - 2 * padY) / f.h));
    L = { k: k, ox: (r.width - f.w * k) / 2, oy: (r.height - f.h * k) / 2, left: r.left, top: r.top, w: r.width, h: r.height };
  }
  function toStage(x, y) { return { x: L.ox + L.k * x, y: L.oy + L.k * y }; }
  function toFrame(e) { return { x: (e.clientX - L.left - L.ox) / L.k, y: (e.clientY - L.top - L.oy) / L.k }; }

  function render() {
    queued = false;
    if (!state) return;
    if (ui.tab === 'crop') {
      layout();
      var m = G.matrix(state, { x: L.ox, y: L.oy }, L.k);
      img.style.transform = 'matrix(' + [m.a, m.b, m.c, m.d, m.e, m.f].map(function (v) { return v.toFixed(6); }).join(',') + ')';
      showHidden(m);
      var a = toStage(state.crop.x, state.crop.y);
      frameEl.style.left = a.x + 'px'; frameEl.style.top = a.y + 'px';
      frameEl.style.width = state.crop.w * L.k + 'px'; frameEl.style.height = state.crop.h * L.k + 'px';
      var o = G.output(state, 0);
      $('size').textContent = dims(o.width, o.height);
      drawRuler();
      $('reset').hidden = !G.edited(state);
    }
    var ang = Math.round(state.angle * 10) / 10;
    $('angle').textContent = (ang > 0 ? '+' : ang < 0 ? '−' : '') + Math.abs(ang).toString().replace('.', cfg.lang === 'en' ? '.' : ',') + '°';
    $('angle').className = 'angle' + (ang ? ' set' : '');
    $('dial').setAttribute('aria-valuenow', String(ang));
    $('ratio-label').textContent = ratioLabel();
    $('flip').classList.toggle('on', state.m[0] * state.m[3] - state.m[1] * state.m[2] < 0);
    var out = G.output(state, ui.max);
    $('subtitle').textContent = cfg.image.kind + ' · ' + dims(cfg.image.width, cfg.image.height) +
      (G.edited(state) || ui.max ? ' → ' + dims(out.width / (cfg.work.scale || 1), out.height / (cfg.work.scale || 1)) : '');
    $('done').setAttribute('aria-disabled', hasChanges() ? 'false' : 'true');
    $('cancel').textContent = ui.saved.length && !dirty() ? t('close') : t('cancel');          // nothing left to cancel once it is saved
    if (ui.tab === 'faces') renderFaces();
    if (ui.tab === 'convert') renderConvert();
  }
  function later() { if (!queued) { queued = true; requestAnimationFrame(render); } }

  // ── The straighten dial: a ruler under the picture ──
  var PPD = 9;                                                   // pixels per degree
  function drawRuler() {
    var c = $('ruler'), dpr = window.devicePixelRatio || 1, w = c.clientWidth, h = c.clientHeight;
    if (!w || !h) return;
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
    var x = c.getContext('2d');
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
    x.clearRect(0, 0, w, h);
    var mid = w / 2, lo = Math.max(-45, Math.floor(state.angle - mid / PPD)), hi = Math.min(45, Math.ceil(state.angle + mid / PPD));
    x.lineCap = 'round';
    for (var d = lo; d <= hi; d++) {
      var tx = mid + (d - state.angle) * PPD, major = d % 15 === 0, five = d % 5 === 0;
      x.strokeStyle = d === 0 ? 'rgba(255,255,255,.95)' : major ? 'rgba(255,255,255,.8)' : five ? 'rgba(255,255,255,.55)' : 'rgba(255,255,255,.28)';
      x.lineWidth = major || d === 0 ? 2 : 1.4;
      var len = major || d === 0 ? 20 : five ? 14 : 8;
      x.beginPath(); x.moveTo(tx, h / 2 - len / 2); x.lineTo(tx, h / 2 + len / 2); x.stroke();
    }
  }
  function setAngle(v) {
    v = Math.max(-G.MAX_ANGLE, Math.min(G.MAX_ANGLE, v));
    if (Math.abs(v) < 0.3) v = 0;                                // it clicks into place at 0°
    G.setAngle(state, Math.round(v * 10) / 10);
    later();
  }
  var dial = $('dial');
  dial.addEventListener('pointerdown', function (e) {
    if (!state) return;
    quiet(); dial.setPointerCapture(e.pointerId); app.classList.add('grid');
    ui.dial = { x: e.clientX, angle: state.angle };
  });
  dial.addEventListener('pointermove', function (e) { if (ui.dial) setAngle(ui.dial.angle - (e.clientX - ui.dial.x) / PPD); });
  function dialEnd() { ui.dial = null; setTimeout(function () { if (!ui.drag && !ui.dial) app.classList.remove('grid'); }, 500); }
  dial.addEventListener('pointerup', dialEnd);
  dial.addEventListener('pointercancel', dialEnd);
  dial.addEventListener('dblclick', function () { setAngle(0); });
  dial.addEventListener('wheel', function (e) {
    e.preventDefault();
    if (!state) return;
    quiet();
    setAngle(state.angle + (Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY) * 0.04);
  }, { passive: false });
  dial.addEventListener('keydown', function (e) {
    if (!state) return;
    var step = e.shiftKey ? 5 : 0.5;
    if (e.key === 'ArrowRight' || e.key === 'ArrowUp') setAngle(state.angle + step);
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') setAngle(state.angle - step);
    else if (e.key === 'Home' || e.key === '0') setAngle(0);
    else return;
    e.preventDefault(); e.stopPropagation();
  });

  // ── The frame: which part of it is under the pointer ──
  var CURSORS = { n: 'ns-resize', s: 'ns-resize', e: 'ew-resize', w: 'ew-resize', nw: 'nwse-resize', se: 'nwse-resize', ne: 'nesw-resize', sw: 'nesw-resize', move: 'move' };
  function zoneAt(e) {
    var r = stage.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
    var a = toStage(state.crop.x, state.crop.y), b = toStage(state.crop.x + state.crop.w, state.crop.y + state.crop.h);
    var hx = Math.min(22, (b.x - a.x) / 3), hy = Math.min(22, (b.y - a.y) / 3);
    if (x < a.x - hx || x > b.x + hx || y < a.y - hy || y > b.y + hy) return null;
    var top = y <= a.y + hy, bottom = y >= b.y - hy, left = x <= a.x + hx, right = x >= b.x - hx;
    return (top ? 'n' : bottom ? 's' : '') + (left ? 'w' : right ? 'e' : '') || 'move';
  }
  stage.addEventListener('pointermove', function (e) {
    if (!state) return;
    if (!ui.drag) { var z = zoneAt(e); stage.style.cursor = z ? CURSORS[z] : 'default'; return; }
    var p = toFrame(e), d = ui.drag, f = G.frameSize(state), rect;
    if (d.zone === 'move') rect = G.move(state, d.start, p.x - d.sx, p.y - d.sy);
    else rect = G.resize(state, d.start, d.zone, p.x - d.ox, p.y - d.oy, Math.min(44 / L.k, f.w / 2, f.h / 2));
    state.crop = rect; state.want = { x: rect.x, y: rect.y, w: rect.w, h: rect.h };
    later();
  });
  stage.addEventListener('pointerdown', function (e) {
    if (!state || e.button > 0) return;
    var z = zoneAt(e);
    if (!z) return;
    quiet(); closeMenu();
    var p = toFrame(e), c = state.crop;
    ui.drag = {
      zone: z, start: { x: c.x, y: c.y, w: c.w, h: c.h }, sx: p.x, sy: p.y,
      ox: z.indexOf('w') >= 0 ? p.x - c.x : z.indexOf('e') >= 0 ? p.x - (c.x + c.w) : 0,        // where on the edge it was grabbed
      oy: z.indexOf('n') >= 0 ? p.y - c.y : z.indexOf('s') >= 0 ? p.y - (c.y + c.h) : 0
    };
    stage.setPointerCapture(e.pointerId); app.classList.add('grid');
    e.preventDefault();
  });
  function dragEnd() { ui.drag = null; setTimeout(function () { if (!ui.drag && !ui.dial) app.classList.remove('grid'); }, 500); }
  stage.addEventListener('pointerup', dragEnd);
  stage.addEventListener('pointercancel', dragEnd);

  function quiet() { $('hint').classList.add('away'); }                // the hint goes after the first touch

  // ── Turn, mirror, reset ──
  $('turn').addEventListener('click', function () {
    if (!state) return;
    G.turnLeft(state);
    if (state.ratio && ui.ratioKey !== 'original') ui.portrait = !ui.portrait;
    render();
  });
  $('flip').addEventListener('click', function () { if (state) { G.mirror(state); render(); } });
  $('reset').addEventListener('click', function () { if (state) { G.reset(state); ui.ratioKey = 'free'; ui.portrait = false; render(); } });

  // ── The shape of the frame ──
  var RATIOS = [['free'], ['original'], ['square', 1, 1], ['16:9', 16, 9], ['4:3', 4, 3], ['3:2', 3, 2], ['5:4', 5, 4], ['7:5', 7, 5]];
  function ratioLabel() {
    var k = ui.ratioKey;
    if (k === 'free') return t('ratio_free');
    if (k === 'original') return t('ratio_original');
    if (k === 'square') return t('ratio_square');
    return ui.portrait ? k.split(':').reverse().join(':') : k;
  }
  function chooseRatio(key) {
    var f = G.frameSize(state);
    ui.ratioKey = key;
    if (key === 'free') G.setRatio(state, null);
    else if (key === 'original') G.setRatio(state, f.w / f.h);
    else {
      var row = RATIOS.filter(function (r) { return r[0] === key; })[0];
      ui.portrait = f.h > f.w;
      G.setRatio(state, ui.portrait ? row[2] / row[1] : row[1] / row[2]);
    }
    render();
  }
  function closeMenu() { var m = $('menu'); if (!m.hidden) { m.hidden = true; $('ratio').setAttribute('aria-expanded', 'false'); } }
  function openMenu() {
    var m = $('menu'), b = $('ratio').getBoundingClientRect();
    m.textContent = '';
    RATIOS.forEach(function (r) {
      var b2 = el('button', '', r[0] === 'free' ? t('ratio_free') : r[0] === 'original' ? t('ratio_original') : r[0] === 'square' ? t('ratio_square') : r[0]);
      b2.type = 'button'; b2.setAttribute('role', 'menuitemradio'); b2.setAttribute('aria-checked', String(ui.ratioKey === r[0]));
      b2.addEventListener('click', function () { closeMenu(); chooseRatio(r[0]); });
      m.appendChild(b2);
    });
    m.appendChild(document.createElement('hr'));
    [['portrait', true], ['landscape', false]].forEach(function (o) {
      var b3 = el('button', '', t('ratio_' + o[0])), usable = state.ratio && Math.abs(state.ratio - 1) > 1e-6;
      b3.type = 'button'; b3.setAttribute('role', 'menuitemradio'); b3.setAttribute('aria-checked', String(!!usable && (state.ratio < 1) === o[1]));
      b3.disabled = !usable; if (!usable) b3.style.opacity = '.4';
      b3.addEventListener('click', function () {
        closeMenu();
        if ((state.ratio < 1) !== o[1]) { G.setRatio(state, 1 / state.ratio); ui.portrait = !ui.portrait; render(); }
      });
      m.appendChild(b3);
    });
    m.hidden = false;
    m.style.top = (b.bottom + 8) + 'px'; m.style.right = Math.max(8, window.innerWidth - b.right) + 'px'; m.style.left = 'auto';
    $('ratio').setAttribute('aria-expanded', 'true');
  }
  $('ratio').addEventListener('click', function (e) { e.stopPropagation(); if (!state) return; if ($('menu').hidden) openMenu(); else closeMenu(); });
  document.addEventListener('pointerdown', function (e) { if (!$('menu').hidden && !$('menu').contains(e.target) && !$('ratio').contains(e.target)) closeMenu(); });

  // ── Tabs ──
  function showTab(name) {
    if (!state) return;
    ui.tab = name; closeMenu();
    app.setAttribute('data-tab', name);
    $('panel-crop').hidden = name !== 'crop'; $('panel-faces').hidden = name !== 'faces'; $('panel-convert').hidden = name !== 'convert';
    if (name !== 'faces') { fb.drawing = false; fb.ink = null; }
    if (name === 'faces' && fb.status === 'idle') findFaces();
    [].forEach.call(document.querySelectorAll('.tab'), function (b) { b.setAttribute('aria-selected', String(b.getAttribute('data-tab') === name)); });
    render();
  }
  [].forEach.call(document.querySelectorAll('.tab'), function (b) { b.addEventListener('click', function () { showTab(b.getAttribute('data-tab')); }); });

  // ── Face Blur ──

  // What is hidden: the faces that are not left out, and the lines that were drawn
  function shapes() { return fb.faces.filter(function (f) { return f.on; }).map(function (f) { return f.shape; }).concat(fb.strokes); }
  function hiding() { return fb.strokes.length > 0 || fb.faces.some(function (f) { return f.on; }); }
  function blurKey() { return hiding() ? JSON.stringify([shapes(), fb.type, fb.strength]) : ''; }

  // The picture with what is hidden, as a copy of at most VIEW_MAX pixels: what every tab shows. (The picture that is saved
  // is made from the picture itself – drawOutput.) null when nothing is hidden.
  function viewCopy() {
    var key = blurKey();
    if (!key) return null;
    var W = img.naturalWidth, H = img.naturalHeight;
    if (!view.clean) {
      var k = Math.min(1, VIEW_MAX / Math.max(W, H)), w = Math.max(1, Math.round(W * k)), h = Math.max(1, Math.round(H * k));
      view.clean = document.createElement('canvas'); view.clean.width = w; view.clean.height = h;
      var c = view.clean.getContext('2d'); c.imageSmoothingEnabled = true; c.imageSmoothingQuality = 'high'; c.drawImage(img, 0, 0, w, h);
      view.canvas = document.createElement('canvas'); view.canvas.width = w; view.canvas.height = h; view.canvas.className = 'photo-view';
      view.ctx = view.canvas.getContext('2d', { willReadFrequently: true });
    }
    if (view.key !== key) {
      view.key = key;
      view.ctx.drawImage(view.clean, 0, 0);
      var kk = view.canvas.width / W;
      B.clusters(shapes(), fb.type, fb.strength, kk, W, H).forEach(function (c2) {
        var d = view.ctx.getImageData(c2.x, c2.y, c2.w, c2.h);
        B.apply(d.data, c2.w, c2.h, c2.x, c2.y, kk, c2.shapes, fb.type, fb.strength);
        view.ctx.putImageData(d, c2.x, c2.y);
      });
    }
    return view.canvas;
  }

  // The picture that is saved: what is hidden, worked out in pixels of the picture itself and drawn over it the same way
  // (x has the picture's matrix). Each piece is only as big as its faces and lines, and what it does not change is the same
  // as the picture under it – so it leaves no seam, turned or not.
  function hideOver(x) {
    if (!hiding()) return;
    var W = img.naturalWidth, H = img.naturalHeight;
    B.clusters(shapes(), fb.type, fb.strength, 1, W, H).forEach(function (c) {
      var piece = document.createElement('canvas'); piece.width = c.w; piece.height = c.h;
      var px = piece.getContext('2d', { willReadFrequently: true });
      px.drawImage(img, -c.x, -c.y);
      var d = px.getImageData(0, 0, c.w, c.h);
      B.apply(d.data, c.w, c.h, c.x, c.y, 1, c.shapes, fb.type, fb.strength);
      px.putImageData(d, 0, 0);
      x.drawImage(piece, c.x, c.y);
    });
  }

  // Crop: the copy with what is hidden lies over the picture, turned the same way (m: the picture's matrix on the stage)
  function showHidden(m) {
    var v = viewCopy();
    if (!v) { if (view.canvas) view.canvas.hidden = true; img.style.visibility = 'visible'; return; }
    if (v.parentNode !== $('photo')) $('photo').appendChild(v);
    var sx = v.width / img.naturalWidth, sy = v.height / img.naturalHeight;
    v.style.width = v.width + 'px'; v.style.height = v.height + 'px';
    v.style.transform = 'matrix(' + [m.a / sx, m.b / sx, m.c / sy, m.d / sy, m.e, m.f].map(function (n) { return n.toFixed(6); }).join(',') + ')';
    v.hidden = false; img.style.visibility = 'hidden';
  }

  // The faces of the picture, found beside the page (faces-worker.js): in a copy of 640 pixels and its smaller copies – the big
  // faces – and, in a bigger picture, in a copy of 1280 pixels – the small ones. Each face is hidden until it is left out.
  var worker = null, jobId = 0;
  function findFaces() {
    var W = img.naturalWidth, H = img.naturalHeight, copies = [], id = ++jobId;
    function failed(msg) { if (id === jobId) { fb.status = 'failed'; fb.error = msg; later(); } }
    function copyAt(top, levels) {
      var k = Math.min(1, top / Math.max(W, H)), w = Math.max(1, Math.round(W * k)), h = Math.max(1, Math.round(H * k));
      var c = document.createElement('canvas'); c.width = w; c.height = h;
      var x = c.getContext('2d', { willReadFrequently: true }); x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high'; x.drawImage(img, 0, 0, w, h);
      return { data: x.getImageData(0, 0, w, h).data.buffer, w: w, h: h, scale: w / W, levels: levels };
    }
    fb.status = 'looking'; fb.error = '';
    try {
      copies.push(copyAt(640, 0));
      if (Math.max(W, H) > 800) copies.push(copyAt(1280, 1));
      if (!worker) worker = new Worker(base + 'web/faces-worker.js');
    } catch (e) { failed((e && e.message) || String(e)); return; }
    worker.onmessage = function (e) {
      if (e.data.id !== id) return;
      if (e.data.error) { failed(e.data.error); return; }
      fb.faces = e.data.faces.slice().sort(function (a, b) { return a.x - b.x; }).map(function (f) {
        return { box: f, score: f.score, on: true, shape: B.faceEllipse(f.x + f.w / 2, f.y + f.h / 2, f.w, f.h, 0), thumb: null };
      });
      fb.faces.forEach(function (f) { f.thumb = thumb(f); });
      fb.status = 'done';
      later();
    };
    worker.onerror = function (e) { if (e && e.preventDefault) e.preventDefault(); failed((e && e.message) || 'the worker stopped'); };
    worker.postMessage({ id: id, copies: copies }, copies.map(function (c) { return c.data; }));
    later();
  }

  // A round picture of a face for the row under the picture (the face itself, not hidden: it says whose it is)
  function thumb(f) {
    var n = 96, side = 1.7 * Math.max(f.box.w, f.box.h), c = document.createElement('canvas');
    c.width = n; c.height = n;
    var x = c.getContext('2d');
    x.fillStyle = '#2c2c2e'; x.fillRect(0, 0, n, n);
    x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
    x.drawImage(img, f.box.x + f.box.w / 2 - side / 2, f.box.y + f.box.h / 2 - side / 2, side, side, 0, 0, n, n);
    return c;
  }

  function checkIcon() {
    var NS = 'http://www.w3.org/2000/svg', svg = document.createElementNS(NS, 'svg'), path = document.createElementNS(NS, 'path');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
    path.setAttribute('d', 'm5 12.5 4.5 4.5L19 7.5');
    svg.appendChild(path);
    return svg;
  }

  function toggleFace(i) { fb.faces[i].on = !fb.faces[i].on; render(); }

  // A point of the picture → the stage of the Face Blur tab, and back
  function toView(px, py) {
    var m = fbL.m;
    return { x: fbL.ox + fbL.k * (m.a * px + m.c * py + m.e), y: fbL.oy + fbL.k * (m.b * px + m.d * py + m.f) };
  }
  function fromView(sx, sy) {
    var m = fbL.m, ox = (sx - fbL.ox) / fbL.k - m.e, oy = (sy - fbL.oy) / fbL.k - m.f, det = m.a * m.d - m.b * m.c;
    return { x: (m.d * ox - m.c * oy) / det, y: (-m.b * ox + m.a * oy) / det };
  }

  // The tab: the picture as it will be saved (cropped, turned, with what is hidden), a ring on each face, the row of faces
  function renderFaces() {
    var st = $('fb-stage'), r = st.getBoundingClientRect(), out = G.output(state, 0), m = out.matrix;
    if (!r.width || !r.height) return;
    var padX = Math.max(14, Math.min(40, r.width * 0.04)), padY = r.height < 300 ? 16 : 40;
    var k = Math.max(1e-4, Math.min((r.width - 2 * padX) / out.width, (r.height - 2 * padY) / out.height));
    var w = out.width * k, h = out.height * k, ox = (r.width - w) / 2, oy = (r.height - h) / 2;
    fbL = { k: k, ox: ox, oy: oy, w: w, h: h, m: m, s: Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)) };
    var c = $('fb-view'), dpr = window.devicePixelRatio || 1, q = Math.min(dpr, 4096 / Math.max(w, h, 1));
    var cw = Math.max(1, Math.round(w * q)), ch = Math.max(1, Math.round(h * q));
    c.style.left = ox + 'px'; c.style.top = oy + 'px'; c.style.width = w + 'px'; c.style.height = h + 'px';
    if (c.width !== cw || c.height !== ch) { c.width = cw; c.height = ch; }
    var x = c.getContext('2d'), kk = k * q;
    x.setTransform(1, 0, 0, 1, 0, 0); x.clearRect(0, 0, cw, ch);
    x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
    x.setTransform(m.a * kk, m.b * kk, m.c * kk, m.d * kk, m.e * kk, m.f * kk);
    x.drawImage(viewCopy() || img, 0, 0, img.naturalWidth, img.naturalHeight);

    // the rings: one button for each face, where the face is now
    var marks = $('fb-marks'), ang = Math.atan2(m.b, m.a);
    if (marks.childElementCount !== fb.faces.length) {
      marks.textContent = '';
      fb.faces.forEach(function (f, i) {
        var b = el('button', 'fb-mark'); b.type = 'button';
        b.addEventListener('click', function () { toggleFace(i); });
        marks.appendChild(b);
      });
    }
    fb.faces.forEach(function (f, i) {
      var b = marks.children[i], p = toView(f.shape.x, f.shape.y), mw = 2 * f.shape.rx * k * fbL.s, mh = 2 * f.shape.ry * k * fbL.s;
      b.hidden = p.x < ox || p.y < oy || p.x > ox + w || p.y > oy + h;           // (a face that was cropped away)
      b.style.width = mw + 'px'; b.style.height = mh + 'px';
      b.style.transform = 'translate(' + (p.x - mw / 2).toFixed(2) + 'px,' + (p.y - mh / 2).toFixed(2) + 'px) rotate(' + ang.toFixed(4) + 'rad)';
      faceButton(b, f, i);
    });

    // the row of faces
    var row = $('fb-faces');
    row.hidden = !fb.faces.length;
    if (row.childElementCount !== fb.faces.length) {
      row.textContent = '';
      fb.faces.forEach(function (f, i) {
        var b = el('button', 'fb-face'); b.type = 'button';
        b.appendChild(f.thumb);
        var badge = el('b'); badge.appendChild(checkIcon()); b.appendChild(badge);
        b.addEventListener('click', function () { toggleFace(i); });
        row.appendChild(b);
      });
    }
    fb.faces.forEach(function (f, i) { faceButton(row.children[i], f, i); });

    // what is going on, and the tools
    var n = fb.faces.length;
    $('fb-spinner').hidden = fb.status !== 'looking';
    $('fb-status-text').textContent = fb.status === 'looking' ? t('fb_looking') : fb.status === 'failed' ? t('fb_failed', fb.error) :
      fb.status !== 'done' ? '' : n === 0 ? t('fb_none') : n === 1 ? t('fb_one') : t('fb_many', String(n));
    var every = n > 0 && fb.faces.every(function (f) { return f.on; });
    $('fb-all').hidden = !n; $('fb-all').textContent = every ? t('fb_show_all') : t('fb_blur_all');
    var hint = fb.drawing ? t('fb_hint_draw') : n ? t('fb_hint') : fb.status === 'done' || fb.status === 'failed' ? t('fb_hint_none') : '';
    $('fb-hint').textContent = hint; $('fb-hint').hidden = !hint;
    radio($('fb-types'), B.TYPES.map(function (type) { return { value: type, label: t('fb_type_' + type) }; }), fb.type, function (v) { fb.type = v; render(); }, 'segment');
    $('fb-strength-box').hidden = fb.type === 'solid';
    var sl = $('fb-strength');
    if (document.activeElement !== sl) sl.value = String(Math.round(fb.strength * 100));
    $('fb-brushes').hidden = !fb.drawing;
    [].forEach.call(document.querySelectorAll('.fb-brush'), function (b) { b.setAttribute('aria-checked', String(Number(b.getAttribute('data-size')) === fb.brush)); });
    $('fb-draw').setAttribute('aria-pressed', String(fb.drawing)); $('fb-draw').classList.toggle('on', fb.drawing);
    $('fb-undo').disabled = !fb.strokes.length;
    app.classList.toggle('fb-drawing', fb.drawing);
    drawInk();
  }
  function faceButton(b, f, i) {
    var label = f.on ? t('fb_face_on', String(i + 1)) : t('fb_face_off', String(i + 1));
    b.setAttribute('aria-pressed', String(f.on)); b.setAttribute('aria-label', label); b.title = label;
  }

  $('fb-all').addEventListener('click', function () {
    var every = fb.faces.every(function (f) { return f.on; });
    fb.faces.forEach(function (f) { f.on = !every; });
    render();
  });
  $('fb-draw').addEventListener('click', function () { if (!state) return; fb.drawing = !fb.drawing; fb.ink = null; render(); });
  $('fb-undo').addEventListener('click', function () { if (fb.strokes.length) { fb.strokes.pop(); render(); } });
  [].forEach.call(document.querySelectorAll('.fb-brush'), function (b) {
    b.addEventListener('click', function () { fb.brush = Number(b.getAttribute('data-size')); render(); });
  });
  $('fb-strength').addEventListener('input', function () { fb.strength = Number($('fb-strength').value) / 100; later(); });

  // Drawing: a round brush over the picture, as long as the pointer is down; the line is hidden when it is let go
  var BRUSH = [9, 18, 34];                                       // the brush's radius on the screen (CSS pixels)
  var fbStage = $('fb-stage');
  function stagePoint(e) { var r = fbStage.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }
  fbStage.addEventListener('pointerdown', function (e) {
    if (!state || !fb.drawing || !fbL || e.button > 0) return;
    var s2 = stagePoint(e), p = fromView(s2.x, s2.y);
    fb.ink = { points: [p.x, p.y], r: BRUSH[fb.brush] / (fbL.k * fbL.s), screen: [s2.x, s2.y] };
    fbStage.setPointerCapture(e.pointerId);
    drawInk(); e.preventDefault();
  });
  fbStage.addEventListener('pointermove', function (e) {
    if (!fb.ink) return;
    var s2 = stagePoint(e), sc = fb.ink.screen;
    if (Math.abs(s2.x - sc[sc.length - 2]) + Math.abs(s2.y - sc[sc.length - 1]) < 2) return;
    var p = fromView(s2.x, s2.y);
    fb.ink.points.push(p.x, p.y); sc.push(s2.x, s2.y);
    drawInk();
  });
  function inkEnd() {
    if (!fb.ink) return;
    fb.strokes.push({ kind: 'stroke', points: fb.ink.points, r: fb.ink.r });
    fb.ink = null;
    render();
  }
  fbStage.addEventListener('pointerup', inkEnd);
  fbStage.addEventListener('pointercancel', inkEnd);
  function drawInk() {
    var c = $('fb-ink'), dpr = window.devicePixelRatio || 1, w = c.clientWidth, h = c.clientHeight;
    if (!w || !h) return;
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
    var x = c.getContext('2d');
    x.setTransform(dpr, 0, 0, dpr, 0, 0); x.clearRect(0, 0, w, h);
    if (!fb.ink) return;
    var sc = fb.ink.screen;
    x.lineCap = 'round'; x.lineJoin = 'round'; x.lineWidth = 2 * BRUSH[fb.brush]; x.strokeStyle = 'rgba(255, 214, 10, .5)';
    x.beginPath(); x.moveTo(sc[0], sc[1]);
    for (var i = 2; i < sc.length; i += 2) x.lineTo(sc[i], sc[i + 1]);
    if (sc.length === 2) x.lineTo(sc[0] + 0.01, sc[1]);
    x.stroke();
  }

  // ── Convert ──
  var SIZE_NAMES = { 0: 'size_0', 3840: 'size_3840', 2560: 'size_2560', 1920: 'size_1920', 1280: 'size_1280', 640: 'size_640' };
  function radio(parent, items, current, onPick, cls) {
    parent.textContent = '';
    items.forEach(function (it) {
      var b = el('button', cls, it.label); b.type = 'button'; b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', String(it.value === current));
      b.addEventListener('click', function () { onPick(it.value); });
      parent.appendChild(b);
    });
  }
  function renderConvert() {
    radio($('formats'), cfg.formats.map(function (f) { return { value: f.key, label: f.label }; }), ui.format, function (v) { ui.format = v; render(); }, 'chip');
    $('format-about').textContent = t('fmt_' + ui.format);
    $('quality-group').hidden = !lossy();
    radio($('qualities'), cfg.qualities.map(function (q) { return { value: q, label: t('q_' + q) }; }), ui.quality, function (v) { ui.quality = v; render(); }, 'segment');
    $('quality-about').textContent = t('q_' + ui.quality + '_d');
    radio($('sizes'), cfg.sizes.map(function (s) { return { value: s, label: t(SIZE_NAMES[s] || 'size_0') }; }), ui.max, function (v) { ui.max = v; render(); }, 'chip');
    var out = G.output(state, ui.max), scale = cfg.work.scale || 1;
    $('size-about').textContent = ui.max ? t('size_about', px(ui.max)) : t('size_about_0');
    $('out-dims').textContent = dims(out.width / scale, out.height / scale) + ' px';
    drawOutput($('preview'), 220);
    planName();
    var name = ui.plan ? ui.plan.name : '…';
    $('out-name').textContent = name;
    var note = $('save-note');
    note.textContent = '';
    var parts = t('save_note', '\u0001', '\u0002').split(/(\u0001|\u0002)/);
    parts.forEach(function (s) {
      if (s === '\u0001') note.appendChild(el('b', '', name));
      else if (s === '\u0002') note.appendChild(el('b', '', ui.plan ? ui.plan.folder : cfg.folder));
      else note.appendChild(document.createTextNode(s));
    });
  }
  function planName() {
    var key = ui.format + '|' + (isEdited() ? 1 : 0);
    if (ui.planFor === key) return;
    ui.planFor = key;
    fetch(base + 'api/plan?format=' + encodeURIComponent(ui.format) + '&edited=' + (isEdited() ? 1 : 0), { headers: { 'X-Lotus-Edit': '1' } })
      .then(function (r) { return r.json(); })
      .then(function (j) { if (j.ok && ui.planFor === key) { ui.plan = j; if (ui.tab === 'convert') render(); } })
      .catch(function () { /* the next ping says the editor is gone */ });
  }

  // The finished picture drawn into a canvas – the same matrix the page shows it with. A preview (limit: its longer side) is
  // drawn from the copy with what is hidden; the picture that is saved from the picture itself, and what is hidden over it.
  function drawOutput(canvas, limit) {
    var out = G.output(state, limit ? 0 : ui.max), m = out.matrix;
    var k = limit ? Math.min(1, limit / Math.max(out.width, out.height)) : 1;
    canvas.width = Math.max(1, Math.round(out.width * k)); canvas.height = Math.max(1, Math.round(out.height * k));
    var x = canvas.getContext('2d');
    x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
    x.setTransform(m.a * k, m.b * k, m.c * k, m.d * k, m.e * k, m.f * k);
    var v = limit ? viewCopy() : null;
    if (v) x.drawImage(v, 0, 0, img.naturalWidth, img.naturalHeight);
    else { x.drawImage(img, 0, 0); if (!limit) hideOver(x); }
    return out;
  }

  function isEdited() { return G.edited(state) || hiding(); }
  function hasChanges() {
    if (!state) return false;
    var out = G.output(state, 0);
    return isEdited() || ui.format !== cfg.source || (ui.max > 0 && Math.max(out.width, out.height) > ui.max) ||
      (lossy() && ui.quality !== cfg.defaults.quality);
  }

  // What was saved last: Done again without a change shows it instead of writing a copy; Cancel asks only about what is not saved
  function signature() { return JSON.stringify([state.m, state.angle, state.crop, ui.format, ui.quality, ui.max, blurKey()]); }
  function dirty() { return hasChanges() && signature() !== ui.cleanSig; }

  // ── Done ──
  function toast(text, error) {
    var e = $('toast');
    e.textContent = text; e.className = 'toast' + (error ? ' error' : ''); e.hidden = false;
    clearTimeout(toast.t); toast.t = setTimeout(function () { e.hidden = true; }, error ? 7000 : 4500);
  }
  function post(path, body, type) {
    var h = { 'X-Lotus-Edit': '1' };
    if (type) h['Content-Type'] = type;
    return fetch(base + path, { method: 'POST', headers: h, body: body });
  }
  function done() {
    if (ui.busy) return;
    if (!hasChanges()) { toast(t('nothing')); return; }
    if (!dirty() && ui.saved.length) { showSaved(ui.saved[ui.saved.length - 1]); return; }
    ui.busy = true; $('busy').hidden = false;
    var sig = signature(), edited = isEdited(), blob = Promise.resolve(null);      // (what is saved is what was asked for now)
    var q = 'format=' + encodeURIComponent(ui.format) + '&quality=' + ui.quality + '&max=' + ui.max + '&edited=' + (edited ? 1 : 0) +
      '&camera=' + (hiding() ? 0 : 1) + '&pic=' + cfg.pic;      // (a picture with hidden faces does not say where it was taken)
    if (edited) {
      blob = new Promise(function (ok, no) {
        var c = document.createElement('canvas');
        drawOutput(c, 0);
        c.toBlob(function (b) { b ? ok(b) : no(new Error(t('err_canvas'))); }, 'image/png');
      });
    }
    blob.then(function (b) {
      return post('api/save?' + q, b, b ? 'image/png' : undefined);
    }).then(function (r) { return r.json(); }).then(function (j) {
      ui.busy = false; $('busy').hidden = true;
      if (!j.ok) { toast(t('err_save', j.error || ''), true); return; }
      ui.saved.push(j); ui.planFor = ''; ui.cleanSig = sig;
      showSaved(j);
    }).catch(function (e) {
      ui.busy = false; $('busy').hidden = true;
      toast(t('err_save', e && e.message ? e.message : ''), true);
    });
  }
  function showSaved(j) {
    $('sheet-name').textContent = j.name;
    $('sheet-where').textContent = j.folder + ' · ' + dims(j.width, j.height) + ' · ' + humanBytes(j.bytes);
    $('sheet-reveal').textContent = t('show_in', cfg.filesApp);
    $('veil').hidden = false; $('sheet-close').focus();
  }
  function humanBytes(n) { return n < 1048576 ? Math.round(n / 1024) + ' KB' : (n / 1048576).toFixed(1) + ' MB'; }
  $('done').addEventListener('click', done);
  $('sheet-more').addEventListener('click', function () { $('veil').hidden = true; $('done').focus(); render(); });
  $('sheet-reveal').addEventListener('click', function () { post('api/reveal'); });
  $('sheet-open').addEventListener('click', function () { post('api/open'); });
  $('sheet-close').addEventListener('click', function () { leave(); });
  $('sheet-new').hidden = !cfg.drop;
  $('sheet-new').addEventListener('click', function () { another(); });

  // ── Cancel, close, and the editor going away ──
  function gone(title, text) {
    $('gone-title').textContent = title; $('gone-text').textContent = text; $('gone').hidden = false;
    clearInterval(pinger);
  }
  function leave() {
    post('api/quit').catch(function () {}).then(function () { gone(t('closed'), t('closed_text')); try { window.close(); } catch (e) { /* only windows a script opened close */ } });
  }
  // a picture that came from the drop page (/img without a picture): Cancel and "Another picture" go back to it
  var away = false;
  function another() {
    post('api/another').catch(function () {}).then(function () { away = true; location.replace(base); });
  }
  $('cancel').addEventListener('click', function () {
    if (!dirty()) { if (cfg.drop) another(); else leave(); return; }
    $('ask').hidden = false; $('ask-no').focus();
  });
  $('ask-no').addEventListener('click', function () { $('ask').hidden = true; });
  $('ask-yes').addEventListener('click', function () { $('ask').hidden = true; if (cfg.drop) another(); else leave(); });
  var misses = 0;
  function ping() {
    post('api/ping').then(function () { misses = 0; }).catch(function () {
      if (++misses >= 3) gone(t('gone'), t('gone_text'));
    });
  }
  var pinger = setInterval(ping, 2000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) ping(); });
  window.addEventListener('pagehide', function () {
    if (away || !$('gone').hidden) return;                     // (back to the drop page: the same address, no goodbye)
    try { fetch(base + 'api/bye', { method: 'POST', headers: { 'X-Lotus-Edit': '1' }, keepalive: true }); } catch (e) { /* closing anyway */ }
  });
  window.addEventListener('pageshow', ping);
  // a file dropped on the editor: the browser would open it in place of the editor – it does not; from the drop page the next
  // picture comes after Cancel or Another picture
  window.addEventListener('dragover', function (e) { e.preventDefault(); if (e.dataTransfer) e.dataTransfer.dropEffect = 'none'; });
  window.addEventListener('drop', function (e) {
    e.preventDefault();
    if (cfg.drop && e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) toast(t('drop_next'));
  });

  // ── Keys ──
  var tabbed = false;                                           // was the focus moved with Tab since the last click?
  document.addEventListener('keydown', function (e) { if (e.key === 'Tab') tabbed = true; }, true);
  document.addEventListener('pointerdown', function () { tabbed = false; }, true);
  document.addEventListener('keydown', function (e) {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
    var tag = (document.activeElement && document.activeElement.tagName) || '';
    if (!$('veil').hidden) { if (e.key === 'Escape') { $('sheet-more').click(); } return; }
    if (!$('ask').hidden) { if (e.key === 'Escape') $('ask').hidden = true; return; }
    if (e.key === 'Escape') { if (!$('menu').hidden) closeMenu(); else if (fb.drawing) { fb.drawing = false; fb.ink = null; render(); } return; }
    if (!state || tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (e.key === 'Enter' && !(tag === 'BUTTON' && tabbed)) { done(); e.preventDefault(); return; }       // (a button reached with Tab keeps its own Enter)
    if (ui.tab === 'faces' && (e.key === 'd' || e.key === 'D')) { $('fb-draw').click(); return; }
    if (ui.tab !== 'crop') return;
    if (e.key === 'r' || e.key === 'R') { $('turn').click(); return; }
    if (e.key === 'f' || e.key === 'F') { $('flip').click(); return; }
    var step = (e.shiftKey ? 10 : 1), dx = 0, dy = 0;
    if (e.key === 'ArrowLeft') dx = -step; else if (e.key === 'ArrowRight') dx = step; else if (e.key === 'ArrowUp') dy = -step; else if (e.key === 'ArrowDown') dy = step; else return;
    var r = G.move(state, state.crop, dx, dy);
    state.crop = r; state.want = { x: r.x, y: r.y, w: r.w, h: r.h };
    render(); e.preventDefault();
  });

  // ── Start ──
  $('title').textContent = cfg.image.name;
  $('hint').textContent = t('hint');
  $('subtitle').textContent = cfg.image.kind + ' · ' + dims(cfg.image.width, cfg.image.height);
  img.style.visibility = 'hidden';
  $('busy-text').textContent = t('opening'); $('busy').hidden = false;               // a big picture takes a moment
  app.classList.add('loading');
  img.addEventListener('load', function () {
    app.classList.remove('loading'); $('busy').hidden = true; $('busy-text').textContent = t('saving');
    state = G.create(img.naturalWidth, img.naturalHeight);
    img.style.width = img.naturalWidth + 'px'; img.style.height = img.naturalHeight + 'px';
    img.style.visibility = 'visible';
    window.__lotus = { state: state, G: G, ui: ui, fb: fb, layout: function () { return L; }, faceView: function () { return fbL; } };      // (for the tests)
    render();
    if (typeof ResizeObserver === 'function') { var ro = new ResizeObserver(later); ro.observe(stage); ro.observe($('fb-stage')); } else window.addEventListener('resize', later);
  });
  img.addEventListener('error', function () { $('busy').hidden = true; gone(t('err_show'), t('err_show_text')); });
  img.src = base + 'image?pic=' + cfg.pic;                       // (the picture of this page – a dropped one has its own number)
  ping();
})();
