// The face detector of the image editor's Face Blur tab (lib/edit/web/faces.js and the model lib/edit/web/faces.bin): the model
// file, the network's steps, boxes from its results, and the faces of a real portrait – as it is, bigger, smaller, mirrored.
// Plain Node, no packages: node tests/edit/faces.test.js
'use strict';
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', '..');
const F = require(path.join(ROOT, 'lib', 'edit', 'web', 'faces.js'));
const P = require(path.join(__dirname, 'pixels.js'));
const B = require(path.join(ROOT, 'lib', 'edit', 'web', 'blur.js'));

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e.message).split('\n').join('\n      ')); }
}
const near = (a, b, eps, what) => assert.ok(Math.abs(a - b) <= eps, (what || 'value') + ': ' + a + ' is not ' + b + ' (±' + eps + ')');
// is each expected face found – its middle and its width about right – and nothing else?
function sameFaces(found, expected, what) {
  assert.strictEqual(found.length, expected.length, (what || 'faces') + ': ' + found.length + ' found, ' + JSON.stringify(found.map((f) => [Math.round(f.x + f.w / 2), Math.round(f.y + f.h / 2), Math.round(f.w), f.score.toFixed(2)])));
  const left = found.slice();
  expected.forEach((e) => {
    const i = left.findIndex((f) => Math.hypot(f.x + f.w / 2 - e.cx, f.y + f.h / 2 - e.cy) <= 0.15 * e.w);
    assert.ok(i >= 0, (what || 'faces') + ': no face around ' + e.cx + ', ' + e.cy);
    near(left[i].w, e.w, 0.3 * e.w, 'the width of the face at ' + e.cx + ', ' + e.cy);
    assert.ok(left[i].score >= 0.8, 'a clear face is a sure one: ' + left[i].score);
    left.splice(i, 1);
  });
}

const file = path.join(ROOT, 'lib', 'edit', 'web', 'faces.bin');
const bytes = fs.readFileSync(file);
const model = F.load(bytes);

// ── The model file ──
test('the model file is read: its steps, where its numbers are, what it is and where it comes from', () => {
  assert.strictEqual(model.head.format, 'lotus-faces-1');
  assert.strictEqual(model.w.length, model.head.numbers);
  assert.deepStrictEqual(model.head.strides, [8, 16, 32]);
  assert.ok(/YuNet/.test(model.head.model) && /MIT/.test(model.head.license) && /opencv_zoo/.test(model.head.source));
  assert.ok(model.head.steps.length > 50 && model.head.steps.every((s) => ['c3s2', 'pw', 'dw', 'relu', 'sig', 'pool', 'up', 'add', 'free'].includes(s[0])));
  assert.ok(Array.from(model.w).every(Number.isFinite), 'every number is a number');
});

test('it is small – a "lightweight" model: under 250 KB, about 53,000 numbers', () => {
  assert.ok(bytes.length < 250 * 1024, bytes.length + ' bytes');
  near(model.w.length, 53104, 0, 'numbers');
});

test('THIRD_PARTY.md names the model with the checksums of the file it was made from and of the file itself', () => {
  const text = fs.readFileSync(path.join(ROOT, 'THIRD_PARTY.md'), 'utf8');
  assert.ok(text.includes(model.head.sha256), 'the SHA256 of the ONNX file');
  assert.ok(text.includes(crypto.createHash('sha256').update(bytes).digest('hex')), 'the SHA256 of lib/edit/web/faces.bin');
  assert.ok(/YuNet/.test(text) && /Shiqi Yu/.test(text));
});

test('a file that is not the model, or a damaged one, is refused', () => {
  assert.throws(() => F.load(Buffer.from('not a model at all')), /not a face model/);
  assert.throws(() => F.load(bytes.subarray(0, bytes.length - 8)), /damaged/);
});

test('the same file is read from an ArrayBuffer (a browser) and from a Buffer at an odd place (Node)', () => {
  const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
  const odd = Buffer.concat([Buffer.from([1]), bytes]).subarray(1);
  const a = F.load(ab), b = F.load(odd);
  assert.strictEqual(a.w.length, model.w.length);
  for (let i = 0; i < a.w.length; i += 997) { assert.strictEqual(a.w[i], model.w[i]); assert.strictEqual(b.w[i], model.w[i]); }
});

// ── The network ──
test('the network gives a picture of results for each stride: 1/8, 1/16 and 1/32 of the size', () => {
  const out = F.forward(model, new Float32Array(3 * 96 * 64), 96, 64);
  [8, 16, 32].forEach((stride, i) => {
    assert.deepStrictEqual([out.cls[i].w, out.cls[i].h, out.cls[i].c], [96 / stride, 64 / stride, 1]);
    assert.deepStrictEqual([out.bbox[i].c, out.kps[i].c, out.obj[i].c], [4, 10, 1]);
    assert.ok(Array.from(out.cls[i].data).every((v) => v >= 0 && v <= 1), 'a likelihood is between 0 and 1');
  });
  assert.throws(() => F.forward(model, new Float32Array(3 * 100 * 64), 100, 64), /wrong size/);
});

// ── Pixels ──
test('the pixels of a canvas become blue, green, red planes, filled up to a multiple of 32; what is see-through is white', () => {
  const rgba = new Uint8ClampedArray([10, 20, 30, 255, 200, 100, 50, 0]);          // one opaque pixel, one fully see-through
  const p = F.planes(rgba, 2, 1), n = p.w * p.h;
  assert.deepStrictEqual([p.w, p.h], [32, 32]);
  assert.deepStrictEqual([p.data[0], p.data[n], p.data[2 * n]], [30, 20, 10]);
  assert.deepStrictEqual([p.data[1], p.data[n + 1], p.data[2 * n + 1]], [255, 255, 255]);
  assert.strictEqual(p.data[2], 0);
});

test('half the size: every pixel is the mean of four', () => {
  const h = F.halve(new Uint8ClampedArray([0, 0, 0, 255, 100, 40, 8, 255, 20, 0, 0, 255, 40, 0, 0, 255]), 2, 2);
  assert.deepStrictEqual([h.w, h.h, Array.from(h.data)], [1, 1, [40, 10, 2, 255]]);
});

// ── Boxes ──
test('boxes on the same face become one – the surest; a "face" inside a bigger face goes', () => {
  const a = { x: 0, y: 0, w: 100, h: 100, score: 0.9 }, b = { x: 10, y: 5, w: 100, h: 100, score: 0.8 }, c = { x: 300, y: 0, w: 50, h: 50, score: 0.7 };
  const eye = { x: 20, y: 30, w: 20, h: 20, score: 0.65 }, sure = { x: 20, y: 30, w: 20, h: 20, score: 0.95 };
  assert.deepStrictEqual(F.nms([b, c, a], 0.3), [a, c]);
  assert.deepStrictEqual(F.nms([a, eye], 0.3), [a]);
  assert.deepStrictEqual(F.nms([a, sure], 0.3), [sure, a], 'a surer small face stays, and the big one too');
  near(F.iou(a, b), (90 * 95) / (20000 - 90 * 95), 1e-9, 'intersection over union');
});

// ── Real faces ──
const scene = P.scene();
let found;
test('a picture with three faces – big, middle, small and mirrored: all three are found, where they are', () => {
  const t0 = Date.now();
  found = F.detect(model, scene.picture.data, scene.picture.w, scene.picture.h);
  console.log('      (' + (Date.now() - t0) + ' ms for 640 × 400 and its smaller copies)');
  sameFaces(found, scene.faces);
  assert.ok(found[0].score >= found[1].score && found[1].score >= found[2].score, 'the surest first');
  found.forEach((f) => {
    assert.strictEqual(f.points.length, 10);
    assert.ok(f.points[0] < f.points[2], 'the eye on the left of the picture comes first');
    for (let p = 0; p < 10; p += 2) assert.ok(f.points[p] > f.x - 0.2 * f.w && f.points[p] < f.x + 1.2 * f.w && f.points[p + 1] > f.y - 0.2 * f.h && f.points[p + 1] < f.y + 1.2 * f.h, 'eyes, nose and mouth are in the face');
  });
});

test('the same picture again gives the same boxes', () => {
  assert.deepStrictEqual(F.detect(model, scene.picture.data, scene.picture.w, scene.picture.h), found);
});

test('a picture without a face has none: a soft gradient, a chessboard, noise', () => {
  const noise = (() => { let a = 12345; return () => { a = (Math.imul(a, 1664525) + 1013904223) >>> 0; return a >>> 24; }; })();
  [P.blank(320, 224, (x, y) => [x >> 1, y, 128]), P.blank(256, 256, (x, y) => ((x >> 5) + (y >> 5)) & 1 ? [235, 235, 235] : [20, 20, 20]),
    P.blank(160, 160, () => [noise(), noise(), noise()])].forEach((pic, i) => {
    assert.strictEqual(F.detect(model, pic.data, pic.w, pic.h).length, 0, 'picture ' + (i + 1));
  });
});

test('a face that fills the picture is found in the smaller copies (the network knows faces up to about 300 pixels)', () => {
  const p = P.portrait(), big = P.resize(p, p.w * 5, p.h * 5);                      // the face is 450 pixels wide
  const faces = F.detect(model, big.data, big.w, big.h);
  sameFaces(faces, [{ cx: 5 * P.FACE.cx, cy: 5 * P.FACE.cy, w: 5 * P.FACE.fw }], 'the big portrait');
});

test('one size only (for the small faces of a bigger copy): the small faces, as with all sizes', () => {
  const one = F.detect(model, scene.picture.data, scene.picture.w, scene.picture.h, { levels: 1 });
  const small = scene.faces[2];
  assert.ok(one.some((f) => Math.hypot(f.x + f.w / 2 - small.cx, f.y + f.h / 2 - small.cy) < 8), 'the small face');
});

test('a stricter or looser score changes what counts as a face, never the boxes', () => {
  const loose = F.detect(model, scene.picture.data, scene.picture.w, scene.picture.h, { score: 0.3 });
  const strict = F.detect(model, scene.picture.data, scene.picture.w, scene.picture.h, { score: 0.99 });
  assert.ok(loose.length >= found.length && strict.length <= found.length);
  found.forEach((f) => assert.ok(loose.some((g) => g.x === f.x && g.y === f.y && g.score === f.score)));
});

test('a tiny picture and one that is not a multiple of 32 are no problem', () => {
  assert.deepStrictEqual(F.detect(model, new Uint8ClampedArray(4 * 5 * 7), 5, 7), []);
  const odd = P.resize(P.portrait(), 173, 185);
  sameFaces(F.detect(model, odd.data, odd.w, odd.h), [{ cx: P.FACE.cx * 173 / 180, cy: P.FACE.cy * 185 / 192, w: P.FACE.fw * 173 / 180 }], 'the odd size');
});

test('what Face Blur hides at the strength it starts with, this detector cannot find again – nor what is black', () => {
  const shapes = found.map((f) => B.faceEllipse(f.x + f.w / 2, f.y + f.h / 2, f.w, f.h, 0));
  for (const type of ['blur', 'solid']) {
    const pic = { data: new Uint8ClampedArray(scene.picture.data), w: scene.picture.w, h: scene.picture.h };
    B.apply(pic.data, pic.w, pic.h, 0, 0, 1, shapes, type, B.STRENGTH);
    const again = F.detect(model, pic.data, pic.w, pic.h);
    assert.strictEqual(again.length, 0, type + ': ' + JSON.stringify(again.map((f) => [Math.round(f.w), f.score.toFixed(2)])));
  }
});

console.log('\n' + passed + ' passed, ' + failed + ' failed');
process.exit(failed ? 1 : 0);
