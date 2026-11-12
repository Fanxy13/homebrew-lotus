// How the image editor hides faces and what was drawn (lib/edit/web/blur.js): the shapes, the rectangles it works on, a blur,
// big pixels and black – and that nothing outside a shape changes, that the small copy the page shows looks like the picture
// it saves, and that see-through pixels stay as they were. Plain Node, no packages: node tests/edit/blur.test.js
'use strict';
const assert = require('assert');
const path = require('path');
const B = require(path.join(__dirname, '..', '..', 'lib', 'edit', 'web', 'blur.js'));
const P = require(path.join(__dirname, 'pixels.js'));

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e.stack || e.message).split('\n').slice(0, 4).join('\n      ')); }
}
const near = (a, b, eps, what) => assert.ok(Math.abs(a - b) <= eps, (what || 'value') + ': ' + a + ' is not ' + b + ' (±' + eps + ')');

// pictures
function noise(w, h, seed) {
  let a = seed >>> 0;
  const next = () => { a = (Math.imul(a, 1664525) + 1013904223) >>> 0; return a >>> 24; };
  return P.blank(w, h, () => [next(), next(), next()]);
}
const copy = (img) => ({ data: new Uint8ClampedArray(img.data), w: img.w, h: img.h });
function region(img, fn) {            // the pixels for which fn(x, y) holds → [[r, g, b, a], …]
  const out = [];
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) if (fn(x, y)) { const i = (y * img.w + x) * 4; out.push([img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]]); }
  return out;
}
function spread(px) {                 // how much the colors vary: the standard deviation of red, green and blue
  let sum = 0, sq = 0, n = 0;
  px.forEach((p) => { for (let c = 0; c < 3; c++) { sum += p[c]; sq += p[c] * p[c]; n++; } });
  return Math.sqrt(Math.max(0, sq / n - (sum / n) * (sum / n)));
}
// every pixel the shapes do not touch (their mask is 0 there) is the same in both pictures
function untouchedSame(before, after, shapes) {
  let changed = 0, outside = 0;
  const m = shapes.map((s) => B.mask(s, 0, 0, before.w, before.h, 1, 0));
  for (let i = 0; i < before.w * before.h; i++) {
    if (m.some((mm) => mm[i] > 0)) continue;
    outside++;
    for (let c = 0; c < 4; c++) if (before.data[4 * i + c] !== after.data[4 * i + c]) { changed++; break; }
  }
  assert.ok(outside > 0, 'there are pixels outside');
  assert.strictEqual(changed, 0, changed + ' of ' + outside + ' pixels outside the shapes changed');
}
// hide the shapes the way the page does: rectangle by rectangle
function hide(img, shapes, type, strength, scale) {
  B.clusters(shapes, type, strength, scale || 1, img.w / (scale || 1), img.h / (scale || 1)).forEach((c) => {
    const part = new Uint8ClampedArray(c.w * c.h * 4);
    for (let y = 0; y < c.h; y++) part.set(img.data.subarray(((c.y + y) * img.w + c.x) * 4, ((c.y + y) * img.w + c.x + c.w) * 4), y * c.w * 4);
    B.apply(part, c.w, c.h, c.x, c.y, scale || 1, c.shapes, type, strength);
    for (let y = 0; y < c.h; y++) img.data.set(part.subarray(y * c.w * 4, (y + 1) * c.w * 4), ((c.y + y) * img.w + c.x) * 4);
  });
  return img;
}

const face = { kind: 'ellipse', x: 100, y: 80, rx: 40, ry: 50, rot: 0 };

// ── Shapes ──
test('the ellipse of a face is wider and higher than the box the detector found, and a little higher up', () => {
  const e = B.faceEllipse(100, 80, 60, 70, 0);
  assert.deepStrictEqual([e.kind, e.x, e.rot], ['ellipse', 100, 0]);
  near(e.y, 80 - 0.04 * 70, 1e-9, 'its middle');
  assert.ok(e.rx > 30 && e.ry > 35, 'bigger than the box');
  const turned = B.faceEllipse(100, 80, 60, 70, Math.PI / 2);                     // the picture lies on its side: up is to the right
  near(turned.x, 100 + 0.04 * 70, 1e-9); near(turned.y, 80, 1e-9);
});

test('an ellipse covers what is inside it: its area is π·a·b, its middle is 1, beyond its edge is 0', () => {
  const m = B.mask(face, 0, 0, 200, 160, 1, 0);
  let area = 0; for (const v of m) area += v;
  near(area, Math.PI * 40 * 50, 0.01 * Math.PI * 40 * 50, 'area');
  assert.strictEqual(m[80 * 200 + 100], 1);
  assert.strictEqual(m[80 * 200 + 145], 0, 'right of it');
  assert.strictEqual(m[25 * 200 + 100], 0, 'above it');
  assert.strictEqual(m[34 * 200 + 100], 1, 'just inside its top');
});

test('a soft edge: 0 at the edge, 1 a little inside, growing in between', () => {
  const m = B.mask(face, 0, 0, 200, 160, 1, 8), row = (x) => m[80 * 200 + x];
  assert.ok(row(139) < 0.05 && row(136) > 0 && row(136) < row(134) && row(134) < row(132) && row(131) === 1, [row(139), row(136), row(134), row(132), row(131)].join(' '));
});

test('a turned ellipse lies along its direction', () => {
  const e = { kind: 'ellipse', x: 100, y: 100, rx: 60, ry: 15, rot: Math.PI / 4 };
  const m = B.mask(e, 0, 0, 200, 200, 1, 0);
  assert.strictEqual(m[(100 + 35) * 200 + 100 + 35], 1, 'along the turned long side');
  assert.strictEqual(m[100 * 200 + 100 + 50], 0, 'not along x');
});

test('a line drawn with a round brush covers everything within its radius of the line', () => {
  const s = { kind: 'stroke', points: [20, 20, 120, 20, 120, 90], r: 6 };
  const m = B.mask(s, 0, 0, 160, 120, 1, 0);
  assert.strictEqual(m[20 * 160 + 70], 1); assert.strictEqual(m[25 * 160 + 70], 1); assert.strictEqual(m[27 * 160 + 70], 0);
  assert.strictEqual(m[60 * 160 + 120], 1, 'the second piece');
  assert.strictEqual(m[24 * 160 + 124], 1, 'the corner is round, not cut');
  assert.strictEqual(m[60 * 160 + 70], 0, 'not between the pieces');
  const dot = B.mask({ kind: 'stroke', points: [50, 50], r: 10 }, 0, 0, 100, 100, 1, 0);
  let area = 0; for (const v of dot) area += v;
  near(area, Math.PI * 100, 0.03 * Math.PI * 100, 'one point is a round dot');
});

// ── The rectangles that are worked on ──
test('the rectangle of a shape: the shape and what a blur mixes in, inside the picture – none outside it', () => {
  const b = B.bounds(face, 'blur', 0.6, 1, 200, 160), p = B.params(face, 'blur', 0.6);
  assert.ok(b.x <= 60 - 2 * p.sigma || b.x === 0); assert.ok(b.x + b.w <= 200 && b.y + b.h <= 160 && b.x >= 0 && b.y >= 0);
  assert.strictEqual(B.bounds({ kind: 'ellipse', x: -500, y: 80, rx: 20, ry: 20, rot: 0 }, 'blur', 0.6, 1, 200, 160), null);
  const s = B.bounds(face, 'solid', 0.6, 1, 1000, 1000);
  assert.deepStrictEqual(s, { x: 59, y: 29, w: 82, h: 102 }, 'black needs only the shape');
});

test('the blocks of big pixels are counted from the corner of the picture: a rectangle starts and ends on whole blocks', () => {
  const b = B.bounds(face, 'pixel', 0.6, 1, 1000, 1000), bs = B.params(face, 'pixel', 0.6).block;
  near(b.x / bs, Math.round(b.x / bs), 1 / bs + 1e-9); near((b.x + b.w) / bs, Math.round((b.x + b.w) / bs), 1 / bs + 1e-9);
});

test('a stronger setting hides more: a wider blur, bigger pixels', () => {
  assert.ok(B.params(face, 'blur', 1).sigma > 2 * B.params(face, 'blur', 0).sigma);
  assert.ok(B.params(face, 'pixel', 1).block > 2 * B.params(face, 'pixel', 0).block);
  assert.ok(B.params({ kind: 'ellipse', x: 0, y: 0, rx: 80, ry: 100 }, 'blur', 0.6).sigma > B.params(face, 'blur', 0.6).sigma, 'a bigger face, a wider blur');
});

test('shapes whose rectangles touch are worked on together, the others alone, in their order', () => {
  const a = { kind: 'ellipse', x: 50, y: 50, rx: 20, ry: 20 }, b = { kind: 'ellipse', x: 80, y: 50, rx: 20, ry: 20 }, c = { kind: 'ellipse', x: 400, y: 300, rx: 20, ry: 20 };
  const cl = B.clusters([c, a, b], 'blur', 0.6, 1, 600, 400);
  assert.strictEqual(cl.length, 2);
  const both = cl.find((k) => k.shapes.length === 2);
  assert.deepStrictEqual(both.shapes, [a, b]);
});

// ── Hiding ──
const pic = noise(200, 160, 7);

test('black: inside the shape every pixel is black, outside every pixel is as it was', () => {
  const after = hide(copy(pic), [face], 'solid', 0.6);
  const inside = region(after, (x, y) => ((x + 0.5 - 100) / 40) ** 2 + ((y + 0.5 - 80) / 50) ** 2 < 0.9);
  assert.ok(inside.every((p) => p[0] === 0 && p[1] === 0 && p[2] === 0 && p[3] === 255));
  untouchedSame(pic, after, [face]);
});

test('a blur: inside the shape the noise is gone, outside every pixel is as it was', () => {
  const after = hide(copy(pic), [face], 'blur', 0.6);
  const core = (img) => region(img, (x, y) => ((x + 0.5 - 100) / 40) ** 2 + ((y + 0.5 - 80) / 50) ** 2 < 0.5);
  assert.ok(spread(core(after)) < 0.12 * spread(core(pic)), spread(core(after)).toFixed(1) + ' of ' + spread(core(pic)).toFixed(1));
  untouchedSame(pic, after, [face]);
});

test('a stronger blur leaves less', () => {
  const core = (img) => region(img, (x, y) => ((x + 0.5 - 100) / 40) ** 2 + ((y + 0.5 - 80) / 50) ** 2 < 0.5);
  const lo = spread(core(hide(copy(pic), [face], 'blur', 0))), hi = spread(core(hide(copy(pic), [face], 'blur', 1)));
  assert.ok(hi < lo, hi + ' < ' + lo);
});

test('big pixels: inside the shape each block has one color, outside every pixel is as it was', () => {
  const after = hide(copy(pic), [face], 'pixel', 0.6), bs = B.params(face, 'pixel', 0.6).block, colors = new Map();
  let blocks = 0;
  for (let y = 0; y < 160; y++) for (let x = 0; x < 200; x++) {
    if (((x + 0.5 - 100) / 40) ** 2 + ((y + 0.5 - 80) / 50) ** 2 > 0.85) continue;
    const key = Math.floor((x + 0.5) / bs) + ',' + Math.floor((y + 0.5) / bs), i = (y * 200 + x) * 4, c = after.data.slice(i, i + 3).join();
    if (!colors.has(key)) { colors.set(key, c); blocks++; } else assert.strictEqual(colors.get(key), c, 'block ' + key);
  }
  assert.ok(blocks >= 9 && blocks <= 120, blocks + ' blocks across the face');
  untouchedSame(pic, after, [face]);
});

test('a drawn line hides what is under it, too', () => {
  const line = { kind: 'stroke', points: [10, 140, 190, 140], r: 7 };
  const after = hide(copy(pic), [line], 'solid', 0.6);
  assert.ok(region(after, (x, y) => y >= 136 && y <= 143 && x >= 12 && x <= 188).every((p) => p[0] + p[1] + p[2] === 0));
  untouchedSame(pic, after, [line]);
});

test('rectangle by rectangle (as the page does it) is the same as all of the picture at once', () => {
  const shapes = [face, { kind: 'ellipse', x: 160, y: 120, rx: 20, ry: 25, rot: 0.3 }, { kind: 'stroke', points: [10, 10, 40, 30], r: 5 }];
  for (const type of B.TYPES) {
    const parts = hide(copy(pic), shapes, type, 0.6), whole = copy(pic);
    B.apply(whole.data, whole.w, whole.h, 0, 0, 1, shapes, type, 0.6);
    assert.deepStrictEqual(Array.from(parts.data), Array.from(whole.data), type);
  }
});

test('the small copy the page shows looks like the picture it saves (scale ½, ¼)', () => {
  const photo = P.resize(P.portrait(), 360, 384), e = B.faceEllipse(2 * 89, 2 * 99, 2 * 90, 2 * 106, 0);
  for (const type of B.TYPES) for (const times of [1, 2]) {
    const k = 1 / (1 << times);
    const full = P.half(hide(copy(photo), [e], type, 0.6, 1), times);           // saved, then made small
    const small = hide(P.half(photo, times), [e], type, 0.6, k);                 // made small, then hidden in the small copy
    let diff = 0;
    for (let i = 0; i < full.data.length; i += 4) for (let c = 0; c < 3; c++) diff += Math.abs(full.data[i + c] - small.data[i + c]);
    const mean = diff / (full.w * full.h * 3);
    assert.ok(mean < (type === 'pixel' ? 4 : 2.5), type + ' at ' + k + ': ' + mean.toFixed(2));
  }
});

test('see-through pixels stay see-through, and no dark edge creeps in from them', () => {
  const img = P.blank(120, 80, (x) => x < 60 ? [250, 250, 250, 255] : [0, 0, 0, 0]);
  const e = { kind: 'ellipse', x: 60, y: 40, rx: 30, ry: 30, rot: 0 };
  for (const type of ['blur', 'pixel']) {
    const after = hide(copy(img), [e], type, 0.6);
    const seen = region(after, () => true).filter((p) => p[3] > 8);
    assert.ok(seen.every((p) => p[0] > 238 && p[1] > 238 && p[2] > 238), type + ': a pixel that can be seen is still white');
    assert.ok(region(after, (x) => x >= 90).every((p) => p[3] === 0), type + ': far from the shape nothing changed');
  }
  const black = hide(copy(img), [e], 'solid', 0.6);
  assert.deepStrictEqual(Array.from(black.data.slice((40 * 120 + 70) * 4, (40 * 120 + 70) * 4 + 4)), [0, 0, 0, 255], 'black covers what was see-through');
});

test('the same input gives the same pixels', () => {
  const a = hide(copy(pic), [face], 'blur', 0.4), b = hide(copy(pic), [face], 'blur', 0.4);
  assert.deepStrictEqual(Array.from(a.data), Array.from(b.data));
});

test('a face that is partly outside the picture is hidden where it is in the picture', () => {
  const edge = { kind: 'ellipse', x: 5, y: 80, rx: 30, ry: 40, rot: 0 };
  const after = hide(copy(pic), [edge], 'solid', 0.6);
  assert.ok(region(after, (x, y) => x < 20 && Math.abs(y - 80) < 20).every((p) => p[0] + p[1] + p[2] === 0));
  untouchedSame(pic, after, [edge]);
});

console.log('\n' + passed + ' passed, ' + failed + ' failed');
process.exit(failed ? 1 : 0);
