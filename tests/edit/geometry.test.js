// The geometry of the image editor (lib/edit/web/geometry.js): turning, mirroring, straightening, the crop rectangle and
// its handles, and the matrix that draws the finished picture. Plain Node, no packages: node tests/edit/geometry.test.js
'use strict';
const assert = require('assert');
const path = require('path');
const G = require(path.join(__dirname, '..', '..', 'lib', 'edit', 'web', 'geometry.js'));

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e.message).split('\n').join('\n      ')); }
}
const near = (a, b, eps, what) => assert.ok(Math.abs(a - b) <= (eps || 1e-6), (what || 'value') + ': ' + a + ' is not ' + b);
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const apply = (m, x, y) => [m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f];
const sameSet = (p, q, what) => {
  const key = (l) => l.map(([x, y]) => Math.round(x * 1000) + ',' + Math.round(y * 1000)).sort().join(' ');
  assert.strictEqual(key(p), key(q), what || 'the same four corners');
};

// ── A new state ──
test('a new state keeps all of the picture and has nothing to save', () => {
  const s = G.create(400, 300);
  assert.deepStrictEqual(G.frameSize(s), { w: 400, h: 300 });
  assert.deepStrictEqual(s.crop, { x: 0, y: 0, w: 400, h: 300 });
  assert.strictEqual(G.edited(s), false);
  assert.strictEqual(G.inside(s, s.crop), true);
});

// ── Turning and mirroring ──
test('turning swaps width and height; four turns are no turn', () => {
  const s = G.create(400, 300);
  G.turnLeft(s);
  assert.deepStrictEqual(G.frameSize(s), { w: 300, h: 400 });
  assert.deepStrictEqual(s.crop, { x: 0, y: 0, w: 300, h: 400 });
  assert.strictEqual(G.edited(s), true);
  G.turnLeft(s); G.turnLeft(s); G.turnLeft(s);
  assert.deepStrictEqual(G.frameSize(s), { w: 400, h: 300 });
  assert.strictEqual(G.isIdentity(s.m), true);
  assert.strictEqual(G.edited(s), false);
});
test('left and right undo each other; mirroring twice is no mirroring', () => {
  const s = G.create(400, 300);
  s.crop = { x: 50, y: 20, w: 100, h: 80 }; s.want = { ...s.crop };
  G.turnLeft(s); G.turnRight(s);
  assert.deepStrictEqual(s.crop, { x: 50, y: 20, w: 100, h: 80 });
  G.mirror(s);
  assert.deepStrictEqual(s.crop, { x: 250, y: 20, w: 100, h: 80 });
  G.mirror(s);
  assert.deepStrictEqual(s.crop, { x: 50, y: 20, w: 100, h: 80 });
  assert.strictEqual(G.isIdentity(s.m), true);
});
test('the crop stays on the same part of the picture whatever is done to the orientation', () => {
  const r = rng(7);
  for (let n = 0; n < 200; n++) {
    const s = G.create(300 + Math.floor(r() * 500), 200 + Math.floor(r() * 400));
    const f = G.frameSize(s);
    const w = 20 + r() * (f.w - 40), h = 20 + r() * (f.h - 40);
    s.crop = { x: r() * (f.w - w), y: r() * (f.h - h), w, h }; s.want = { ...s.crop };
    if (n % 2) G.setAngle(s, (r() - 0.5) * 40);
    const before = G.footprint(s);
    for (let i = 0; i < 6; i++) {
      const k = Math.floor(r() * 3);
      (k === 0 ? G.turnLeft : k === 1 ? G.turnRight : G.mirror)(s);
      sameSet(G.footprint(s), before, 'step ' + i + ' of run ' + n);
      assert.ok(G.inside(s, s.crop), 'inside after step ' + i + ' of run ' + n);
    }
  }
});
test('a turn to the right puts the top left of the picture at the top right', () => {
  const s = G.create(4, 2);
  G.turnRight(s);
  const m = G.output(s, 0).matrix;
  assert.deepStrictEqual(G.frameSize(s), { w: 2, h: 4 });
  const [x, y] = apply(m, 0, 0);
  near(x, 2); near(y, 0);
  const [x2, y2] = apply(m, 4, 2);
  near(x2, 0); near(y2, 4);
});
test('a turn to the left puts the top left of the picture at the bottom left', () => {
  const s = G.create(4, 2);
  G.turnLeft(s);
  const m = G.output(s, 0).matrix;
  const [x, y] = apply(m, 0, 0);
  near(x, 0); near(y, 4);
});
test('mirroring puts the left of the picture at the right', () => {
  const s = G.create(400, 300);
  G.mirror(s);
  const m = G.output(s, 0).matrix;
  const [x, y] = apply(m, 0, 10);
  near(x, 400); near(y, 10);
});
test('a fixed shape turns with the picture (landscape becomes portrait)', () => {
  const s = G.create(400, 300);
  G.setRatio(s, 16 / 9);
  const r = s.crop;
  near(r.w / r.h, 16 / 9);
  G.turnRight(s);
  near(s.ratio, 9 / 16);
  near(s.crop.w / s.crop.h, 9 / 16);
});

// ── Straightening ──
test('a positive angle turns the picture clockwise on screen', () => {
  const s = G.create(400, 300);
  G.setAngle(s, 10);
  const m = G.matrix(s, null, 1);
  const [, y] = apply(m, 400, 150);              // the middle of the right edge goes down
  assert.ok(y > 150 + 20, 'right edge goes down: ' + y);
  const [, y2] = apply(m, 0, 150);
  assert.ok(y2 < 150 - 20, 'left edge goes up: ' + y2);
});
test('straightening keeps the crop inside the picture and brings it back at 0°', () => {
  const s = G.create(400, 300);
  s.crop = { x: 20, y: 20, w: 360, h: 260 }; s.want = { ...s.crop };
  G.setAngle(s, 8);
  assert.ok(G.inside(s, s.crop), 'inside at 8°');
  assert.ok(s.crop.w < 360 && s.crop.h < 260, 'it had to shrink');
  assert.deepStrictEqual(s.want, { x: 20, y: 20, w: 360, h: 260 });
  G.setAngle(s, 0);
  near(s.crop.x, 20); near(s.crop.y, 20); near(s.crop.w, 360); near(s.crop.h, 260);
});
test('the whole picture at an angle: the biggest rectangle of its shape', () => {
  const s = G.create(400, 300);
  G.setAngle(s, 10);
  const r = G.full(s);
  assert.ok(G.inside(s, r));
  near(r.w / r.h, 400 / 300, 1e-6);
  near(r.x + r.w / 2, 200, 1e-6); near(r.y + r.h / 2, 150, 1e-6);
  // a little bigger no longer fits
  const bigger = { x: r.x - 2, y: r.y - 1.5, w: r.w + 4, h: r.h + 3 };
  assert.strictEqual(G.inside(s, bigger), false);
});
test('the angle is limited to 45°', () => {
  const s = G.create(400, 300);
  G.setAngle(s, 90);
  assert.strictEqual(s.angle, 45);
  G.setAngle(s, -90);
  assert.strictEqual(s.angle, -45);
});
test('a mirror turns the angle the other way round and keeps the crop', () => {
  const s = G.create(400, 300);
  G.setAngle(s, 12);
  const before = G.footprint(s);
  G.mirror(s);
  assert.strictEqual(s.angle, -12);
  sameSet(G.footprint(s), before);
});
test('whatever the angle: the crop stays inside, the shape stays, the picture is filled', () => {
  const r = rng(11);
  for (let n = 0; n < 300; n++) {
    const s = G.create(200 + Math.floor(r() * 800), 200 + Math.floor(r() * 600));
    if (r() < 0.5) G.setRatio(s, [1, 4 / 3, 16 / 9, 3 / 4, 9 / 16][Math.floor(r() * 5)]);
    G.setAngle(s, (r() - 0.5) * 90);
    assert.ok(G.inside(s, s.crop), 'inside, run ' + n);
    assert.ok(s.crop.w > 1 && s.crop.h > 1, 'not empty, run ' + n);
    if (s.ratio) near(s.crop.w / s.crop.h, s.ratio, 1e-6, 'shape, run ' + n);
    // every corner of the output lands inside the source picture
    const o = G.output(s, 0), m = o.matrix, det = m.a * m.d - m.b * m.c;
    for (const [px, py] of [[0, 0], [o.width, 0], [o.width, o.height], [0, o.height]]) {
      const x = px - m.e, y = py - m.f;
      const sx = (m.d * x - m.c * y) / det, sy = (-m.b * x + m.a * y) / det;
      assert.ok(sx >= -1e-6 && sx <= s.W + 1e-6 && sy >= -1e-6 && sy <= s.H + 1e-6, 'corner (' + px + ',' + py + ') is on the picture, run ' + n + ': ' + sx + ',' + sy);
    }
  }
});

// ── A shape ──
test('a square in a landscape picture is the biggest centered square', () => {
  const s = G.create(400, 300);
  G.setRatio(s, 1);
  near(s.crop.x, 50, 1e-6); near(s.crop.y, 0, 1e-6); near(s.crop.w, 300, 1e-6); near(s.crop.h, 300, 1e-6);
  assert.deepStrictEqual(G.output(s, 0).rect, { x: 50, y: 0, w: 300, h: 300 });
});
test('a shape is made around the middle of the current crop', () => {
  const s = G.create(400, 300);
  s.crop = { x: 0, y: 0, w: 100, h: 100 }; s.want = { ...s.crop };
  G.setRatio(s, 1);
  near(s.crop.x + s.crop.w / 2, 50, 1e-4); near(s.crop.y + s.crop.h / 2, 50, 1e-4);
  near(s.crop.w, 100, 1e-3);                      // a corner of the picture: the square can only be as big as its middle allows
});
test('no shape: free again, the rectangle stays', () => {
  const s = G.create(400, 300);
  G.setRatio(s, 1);
  const r = { ...s.crop };
  G.setRatio(s, null);
  assert.strictEqual(s.ratio, null);
  assert.deepStrictEqual(s.crop, r);
});

// ── Dragging ──
test('moving stops at the edges of the picture', () => {
  const s = G.create(400, 300);
  const start = { x: 100, y: 100, w: 100, h: 50 };
  assert.deepStrictEqual(G.move(s, start, 30, -20), { x: 130, y: 80, w: 100, h: 50 });
  assert.deepStrictEqual(G.move(s, start, 1000, 1000), { x: 300, y: 250, w: 100, h: 50 });
  assert.deepStrictEqual(G.move(s, start, -1000, -1000), { x: 0, y: 0, w: 100, h: 50 });
});
test('at an angle moving slides along the slanted edge and never leaves the picture', () => {
  const s = G.create(400, 300);
  G.setAngle(s, 15);
  const start = G.fit(s, { x: 150, y: 110, w: 100, h: 80 });
  const r = rng(3);
  for (let n = 0; n < 200; n++) {
    const dx = (r() - 0.5) * 900, dy = (r() - 0.5) * 900;
    const m = G.move(s, start, dx, dy);
    assert.ok(G.inside(s, m), 'inside, run ' + n);
    near(m.w, 100, 1e-9); near(m.h, 80, 1e-9);
  }
  // a pointer that pushes against the right slanted edge, then moves down along it: the rectangle follows
  const a = G.move(s, start, 500, 0), b = G.move(s, start, 500, 40);
  assert.ok(b.y > a.y + 1, 'it slid down: ' + a.y + ' → ' + b.y);
});
test('a free handle follows the pointer, not past the other side, not outside', () => {
  const s = G.create(400, 300);
  const start = { x: 100, y: 100, w: 100, h: 100 };
  assert.deepStrictEqual(G.resize(s, start, 'e', 250, 999, 20), { x: 100, y: 100, w: 150, h: 100 });
  assert.deepStrictEqual(G.resize(s, start, 'w', 40, 0, 20), { x: 40, y: 100, w: 160, h: 100 });
  assert.deepStrictEqual(G.resize(s, start, 'se', 260, 190, 20), { x: 100, y: 100, w: 160, h: 90 });
  assert.deepStrictEqual(G.resize(s, start, 'nw', 70, 60, 20), { x: 70, y: 60, w: 130, h: 140 });
  assert.deepStrictEqual(G.resize(s, start, 'e', 105, 0, 20), { x: 100, y: 100, w: 20, h: 100 }, 'not smaller than the minimum');
  assert.deepStrictEqual(G.resize(s, start, 'w', 900, 0, 20), { x: 180, y: 100, w: 20, h: 100 }, 'not over the other side');
  assert.deepStrictEqual(G.resize(s, start, 'se', 900, 900, 20), { x: 100, y: 100, w: 300, h: 200 }, 'not outside the picture');
  assert.deepStrictEqual(G.resize(s, start, 'nw', -50, -50, 20), { x: 0, y: 0, w: 200, h: 200 });
});
test('a handle with a shape keeps it: corners follow the longer side, edges grow to both sides', () => {
  const s = G.create(400, 300);
  G.setRatio(s, 2);                                   // 2 : 1
  s.crop = { x: 100, y: 100, w: 100, h: 50 }; s.want = { ...s.crop };
  const start = { ...s.crop };
  const a = G.resize(s, start, 'se', 260, 170, 20);   // 160 wide, 70 high → 160 × 80
  near(a.w / a.h, 2); near(a.x, 100); near(a.y, 100); near(a.w, 160);
  const b = G.resize(s, start, 'se', 140, 300, 20);   // the height pulls: 40 wide, 200 high → 400 × 200, then limited by the picture
  near(b.w / b.h, 2);
  assert.ok(G.inside(s, b));
  const c = G.resize(s, start, 'e', 300, 0, 20);      // 200 wide → 100 high, around the middle line y = 125
  near(c.w, 200); near(c.h, 100); near(c.y, 75); near(c.x, 100);
  const d = G.resize(s, start, 'n', 0, 50, 20);       // 100 high → 200 wide, around x = 150
  near(d.h, 100); near(d.w, 200); near(d.x, 50); near(d.y, 50);
  const e = G.resize(s, start, 'nw', -500, -500, 20); // as big as the picture allows from the corner (200, 150)
  near(e.w / e.h, 2); assert.ok(G.inside(s, e)); near(e.x + e.w, 200); near(e.y + e.h, 150);
});
test('dragging at an angle: always inside, always the shape', () => {
  const r = rng(5);
  for (let n = 0; n < 400; n++) {
    const s = G.create(300 + Math.floor(r() * 500), 300 + Math.floor(r() * 300));
    if (r() < 0.5) G.setRatio(s, [1, 4 / 3, 3 / 2, 16 / 9, 3 / 4][Math.floor(r() * 5)]);
    G.setAngle(s, (r() - 0.5) * 60);
    const start = G.clone(s).crop;
    const handle = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'][Math.floor(r() * 8)];
    const f = G.frameSize(s);
    const out = G.resize(s, start, handle, (r() * 1.6 - 0.3) * f.w, (r() * 1.6 - 0.3) * f.h, 24);
    assert.ok(G.inside(s, out), 'inside: run ' + n + ' ' + handle + ' ' + JSON.stringify(out));
    assert.ok(out.w > 0 && out.h > 0, 'not empty');
    if (s.ratio) near(out.w / out.h, s.ratio, 1e-6, 'shape: run ' + n);
  }
});

// ── The finished picture ──
test('without changes the output is the picture itself', () => {
  const s = G.create(400, 300);
  const o = G.output(s, 0);
  assert.strictEqual(o.width, 400); assert.strictEqual(o.height, 300);
  assert.deepStrictEqual(o.matrix, { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 });
});
test('a crop draws the kept part at 0, 0', () => {
  const s = G.create(400, 300);
  s.crop = { x: 100, y: 50, w: 200, h: 150 }; s.want = { ...s.crop };
  const o = G.output(s, 0);
  assert.strictEqual(o.width, 200); assert.strictEqual(o.height, 150);
  const [x, y] = apply(o.matrix, 100, 50);
  near(x, 0); near(y, 0);
  const [x2, y2] = apply(o.matrix, 300, 200);
  near(x2, 200); near(y2, 150);
});
test('a size limit shrinks the longer side to it and never makes the picture larger', () => {
  const s = G.create(400, 300);
  const o = G.output(s, 200);
  assert.strictEqual(o.width, 200); assert.strictEqual(o.height, 150);
  const [x, y] = apply(o.matrix, 400, 300);
  near(x, 200); near(y, 150);
  const big = G.output(s, 4000);
  assert.strictEqual(big.width, 400);
});
test('the crop falls on whole pixels', () => {
  const s = G.create(400, 300);
  s.crop = { x: 10.4, y: 20.6, w: 100.3, h: 50.2 }; s.want = { ...s.crop };
  const o = G.output(s, 0);
  assert.deepStrictEqual(o.rect, { x: 10, y: 21, w: 101, h: 50 });   // 10.4 → 10, 110.7 → 111, 20.6 → 21, 70.8 → 71
});
test('a square comes out square, whatever the angle; 16:9 comes out exactly 16:9', () => {
  const r = rng(21);
  for (let n = 0; n < 200; n++) {
    const s = G.create(300 + Math.floor(r() * 900), 300 + Math.floor(r() * 700));
    const ratio = n % 2 ? 1 : 16 / 9;
    G.setRatio(s, ratio);
    G.setAngle(s, (r() - 0.5) * 60);
    const o = G.output(s, 0);
    if (ratio === 1) assert.strictEqual(o.width, o.height, 'square, run ' + n + ': ' + o.width + ' × ' + o.height);
    else assert.strictEqual(o.width * 9, o.height * 16, '16:9, run ' + n + ': ' + o.width + ' × ' + o.height);
    assert.ok(G.inside(s, o.rect), 'inside, run ' + n);
    assert.ok(o.width >= s.crop.w - 17 && o.width <= s.crop.w + 1e-6, 'not much smaller, run ' + n);
  }
});
test('a state goes through JSON', () => {
  const s = G.create(400, 300);
  G.turnLeft(s); G.setAngle(s, 5); G.setRatio(s, 1);
  const t = JSON.parse(JSON.stringify(s));
  assert.deepStrictEqual(G.output(t, 0), G.output(s, 0));
});
test('reset brings everything back', () => {
  const s = G.create(400, 300);
  G.turnLeft(s); G.mirror(s); G.setAngle(s, 5); G.setRatio(s, 1);
  G.reset(s);
  assert.strictEqual(G.edited(s), false);
  assert.deepStrictEqual(s.crop, { x: 0, y: 0, w: 400, h: 300 });
});

console.log('\n' + passed + ' passed, ' + failed + ' failed');
process.exit(failed ? 1 : 0);
