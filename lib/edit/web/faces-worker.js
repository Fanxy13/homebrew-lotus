/* Lotus image editor – finds the faces of a picture beside the page (a worker), so that the page stays quick while it looks:
 * that takes a second or two. The network and its file are faces.js and faces.bin; nothing leaves the computer.
 *
 *   → { id, copies: [{ data: ArrayBuffer (red, green, blue, alpha), w, h, scale, levels }] }
 *        each copy of the picture, `scale` copy pixels to a pixel of the picture; levels: how many sizes are looked at
 *        (0: down to the smallest – the big faces; 1: this size only – the small faces of a bigger copy)
 *   ← { id, faces: [{ x, y, w, h, score, points }] }   in pixels of the picture, the surest first – or { id, error }
 */
'use strict';
importScripts('faces.js');

var model = null;
function getModel() {
  if (model) return Promise.resolve(model);
  return fetch('faces.bin').then(function (r) {
    if (!r.ok) throw new Error('the face model is missing (' + r.status + ')');
    return r.arrayBuffer();
  }).then(function (b) { model = LotusFaces.load(b); return model; });
}

self.onmessage = function (e) {
  var job = e.data;
  getModel().then(function (m) {
    var all = [];
    job.copies.forEach(function (c) {
      LotusFaces.detect(m, new Uint8ClampedArray(c.data), c.w, c.h, { levels: c.levels || 0 }).forEach(function (f) {
        all.push({ x: f.x / c.scale, y: f.y / c.scale, w: f.w / c.scale, h: f.h / c.scale, score: f.score,
                   points: f.points.map(function (v) { return v / c.scale; }) });
      });
    });
    self.postMessage({ id: job.id, faces: LotusFaces.nms(all, LotusFaces.IOU) });
  }).catch(function (err) {
    self.postMessage({ id: job.id, error: String((err && err.message) || err) });
  });
};
