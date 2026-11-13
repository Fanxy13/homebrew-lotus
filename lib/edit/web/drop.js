/* Lotus image editor – the drop page: /img without a picture opens it. A picture dropped on it (anywhere in the window), chosen
 * or pasted is sent to the editor's own server on this computer – nowhere else –, which makes it ready; then the same address
 * is the editor with that picture. No framework, no network except the editor's server.
 */
(function () {
  'use strict';

  var cfg = JSON.parse(document.getElementById('config').textContent);
  var T = cfg.strings;
  var base = location.pathname.replace(/[^/]*$/, '');            // '/<secret>/'
  var $ = function (id) { return document.getElementById(id); };
  var app = $('app'), zone = $('zone'), input = $('file');

  // ── Texts ──
  function t(key) {
    var s = T[key] === undefined ? key : T[key], i = 1, a = arguments;
    return s.replace(/%s/g, function () { return i < a.length ? a[i++] : ''; });
  }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; }
  [].forEach.call(document.querySelectorAll('[data-t]'), function (e) { e.textContent = t(e.getAttribute('data-t')); });
  document.documentElement.lang = cfg.lang;
  var mac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || '');
  $('zone-paste').textContent = t('drop_paste', mac ? '⌘V' : 'Ctrl+V');
  var note = $('drop-note'), parts = t('drop_note', '\u0001').split('\u0001');       // the folder in bold
  note.appendChild(document.createTextNode(parts[0]));
  note.appendChild(el('b', '', cfg.folder));
  note.appendChild(document.createTextNode(parts[1] || ''));
  input.accept = 'image/*,' + cfg.pictures.map(function (x) { return '.' + x; }).join(',');

  // ── Which file is a picture ──
  function extOf(name) { var m = /\.([^./]+)$/.exec(name || ''); return m ? m[1].toLowerCase() : ''; }
  function isPicture(f) { return /^image\//.test(f.type || '') || cfg.pictures.indexOf(extOf(f.name)) >= 0; }
  // what the browser calls a picture pasted from the clipboard ("image.png") gets the name /img gives it in the terminal
  function clipName(f) {
    var d = new Date(), p = function (n) { return (n < 10 ? '0' : '') + n; };
    var ext = extOf(f.name) || { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/tiff': 'tiff', 'image/gif': 'gif', 'image/webp': 'webp',
      'image/heic': 'heic', 'image/bmp': 'bmp' }[f.type] || 'png';
    return 'Clipboard ' + d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + '.' +
      p(d.getMinutes()) + '.' + p(d.getSeconds()) + '.' + ext;
  }

  // ── Sending it ──
  var busy = false, leaving = false;
  function error(text) { var e = $('zone-error'); e.textContent = text; e.hidden = false; }
  function take(list, pasted, folders) {                         // the first picture of what was dropped, chosen or pasted
    var files = [].slice.call(list || []).filter(function (f) { return folders.indexOf(f.name) < 0; });
    var pictures = files.filter(isPicture);
    if (!pictures.length) {
      if (folders.length) error(t('drop_folder'));
      else if (files.length) error(t('drop_not_picture', files[0].name || '?'));
      else if (pasted) error(t('drop_no_paste'));
      return;
    }
    var f = pictures[0], name = f.name;
    if (pasted && (!name || /^image\.[a-z0-9]+$/i.test(name))) name = clipName(f);
    send(f, name, pictures.length);
  }
  function send(f, name, count) {
    if (busy) return;
    if (!f.size) { error(t('drop_not_picture', name)); return; }
    if (f.size > cfg.max) { error(t('drop_too_big', name)); return; }
    busy = true; $('zone-error').hidden = true;
    $('busy-text').textContent = t('opening'); $('busy').hidden = false;
    fetch(base + 'api/drop?name=' + encodeURIComponent(name) + '&count=' + count, {
      method: 'POST', headers: { 'X-Lotus-Edit': '1', 'Content-Type': 'application/octet-stream' }, body: f
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j.ok || j.error === 'open') { leaving = true; location.replace(base); return; }   // the editor, with the picture
      busy = false; $('busy').hidden = true;
      error(t('drop_cannot', name, j.error || ''));
    }).catch(function (e) {
      busy = false; $('busy').hidden = true;
      error(t('drop_cannot', name, (e && e.message) || ''));
    });
  }

  // ── Drop (anywhere in the window), choose, paste ──
  var depth = 0;
  function files(e) { return !!e.dataTransfer && [].indexOf.call(e.dataTransfer.types || [], 'Files') >= 0; }
  function dragging(on) { app.classList.toggle('dragging', on); $('zone-title').textContent = t(on ? 'drop_release' : 'drop_here'); }
  window.addEventListener('dragenter', function (e) { e.preventDefault(); if (files(e) && !busy) { depth++; dragging(true); } });
  window.addEventListener('dragover', function (e) {               // (without this the browser would open the file itself)
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = files(e) && !busy ? 'copy' : 'none';
  });
  window.addEventListener('dragleave', function () { if (depth && --depth === 0) dragging(false); });
  window.addEventListener('drop', function (e) {
    e.preventDefault();
    depth = 0; dragging(false);
    if (busy || !e.dataTransfer) return;
    var folders = [];
    [].forEach.call(e.dataTransfer.items || [], function (it) {
      var entry = it.kind === 'file' && it.webkitGetAsEntry ? it.webkitGetAsEntry() : null;
      if (entry && entry.isDirectory) folders.push(entry.name);
    });
    take(e.dataTransfer.files, false, folders);
  });
  function choose() { if (!busy) input.click(); }
  zone.addEventListener('click', choose);                         // (the button is in the zone: one click, one chooser)
  zone.addEventListener('keydown', function (e) {
    if (e.target === zone && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); choose(); }
  });
  input.addEventListener('change', function () {
    if (input.files && input.files.length) take(input.files, false, []);
    input.value = '';                                              // (the same file again is a change too)
  });
  document.addEventListener('paste', function (e) {
    var cd = e.clipboardData;
    if (!cd || busy) return;
    var list = [].slice.call(cd.files || []);
    if (!list.length) [].forEach.call(cd.items || [], function (it) { var f = it.kind === 'file' && it.getAsFile(); if (f) list.push(f); });
    e.preventDefault();
    take(list, true, []);
  });

  // ── Close, and the editor going away ──
  function post(path) { return fetch(base + path, { method: 'POST', headers: { 'X-Lotus-Edit': '1' } }); }
  function gone(title, text) {
    $('gone-title').textContent = title; $('gone-text').textContent = text; $('gone').hidden = false;
    clearInterval(pinger);
  }
  $('close').addEventListener('click', function () {
    post('api/quit').catch(function () {}).then(function () { gone(t('closed'), t('closed_text')); try { window.close(); } catch (e) { /* only windows a script opened close */ } });
  });
  var misses = 0;
  function ping() {
    post('api/ping').then(function () { misses = 0; }).catch(function () { if (++misses >= 3) gone(t('gone'), t('gone_text')); });
  }
  var pinger = setInterval(ping, 2000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) ping(); });
  window.addEventListener('pagehide', function () {
    if (leaving || !$('gone').hidden) return;                      // (on to the editor: the same address, no goodbye)
    try { fetch(base + 'api/bye', { method: 'POST', headers: { 'X-Lotus-Edit': '1' }, keepalive: true }); } catch (e) { /* closing anyway */ }
  });
  window.addEventListener('pageshow', ping);
  window.__lotusDrop = { busy: function () { return busy; } };    // (for the tests)
  ping();
})();
