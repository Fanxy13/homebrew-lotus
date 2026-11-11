/* Lotus image editor – the geometry of a crop: pure functions, no DOM, no network.
 *
 * It is shared by every system (macOS, Linux, Windows): the page draws with it, and tests/edit/geometry.test.js checks it
 * with Node. Nothing in here knows an operating system, a browser or an image engine.
 *
 * The picture goes through three steps, always in this order:
 *
 *   1. orientation  – turned in steps of 90° and/or mirrored. A 2×2 matrix m = [a, b, c, d] with entries -1, 0 or 1.
 *                     The result is the "frame": the picture as it is seen, `frameSize(s)` pixels wide and high.
 *   2. straighten   – turned about the middle of the frame by `angle` degrees (clockwise is positive, -45 … 45).
 *   3. crop         – a rectangle in the frame, always inside the straightened picture. What is outside is gone.
 *
 * All coordinates are pixels of the picture itself (not of the screen). The frame's origin is its top left corner and y
 * points down, like on screen and in a canvas.
 *
 * A state is plain data (it can go through JSON):
 *   { W, H, m, angle, crop: {x, y, w, h}, want: {x, y, w, h}, ratio }
 *   W, H   size of the picture that was opened (upright, as it is seen)
 *   crop   the rectangle that is kept – always valid
 *   want   the rectangle the person asked for. When the straighten angle makes it stick out of the picture, `crop` is
 *          the biggest part of it that fits; turning back to 0° brings `crop` back to `want` (nothing is lost on the way)
 *   ratio  null (free) or the width / height the rectangle keeps while it is dragged
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LotusGeometry = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var MAX_ANGLE = 45;
  var SLACK = 1e-9;                              // rounding noise when a corner lies exactly on the edge

  function rad(deg) { return deg * Math.PI / 180; }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function copyRect(r) { return { x: r.x, y: r.y, w: r.w, h: r.h }; }

  // ── Orientation (2×2 matrices [a, b, c, d] = [[a, b], [c, d]]) ─────────────────────────────

  function mul(p, q) {
    return [p[0] * q[0] + p[1] * q[2], p[0] * q[1] + p[1] * q[3], p[2] * q[0] + p[3] * q[2], p[2] * q[1] + p[3] * q[3]];
  }
  var TURN_LEFT = [0, 1, -1, 0];                 // 90° counterclockwise on screen (y points down)
  var TURN_RIGHT = [0, -1, 1, 0];
  var MIRROR = [-1, 0, 0, 1];                    // left ↔ right
  function isIdentity(m) { return m[0] === 1 && m[1] === 0 && m[2] === 0 && m[3] === 1; }

  // The size of the frame: the picture turned by m
  function frameSize(s) {
    return { w: Math.abs(s.m[0]) * s.W + Math.abs(s.m[1]) * s.H, h: Math.abs(s.m[2]) * s.W + Math.abs(s.m[3]) * s.H };
  }

  // ── A new state ────────────────────────────────────────────────────────────────────────────

  function create(W, H) {
    var s = { W: W, H: H, m: [1, 0, 0, 1], angle: 0, ratio: null, crop: null, want: null };
    s.crop = { x: 0, y: 0, w: W, h: H };
    s.want = copyRect(s.crop);
    return s;
  }

  function clone(s) {
    return { W: s.W, H: s.H, m: s.m.slice(), angle: s.angle, ratio: s.ratio, crop: copyRect(s.crop), want: copyRect(s.want) };
  }

  // ── Is a rectangle inside the (straightened) picture? ─────────────────────────────────────

  // Straightened, the picture is the frame turned by `angle` about its middle. A rectangle of the frame lies inside it when
  // its four corners, turned back by -angle, lie in the frame. At an angle the edges of the picture are soft (every pixel
  // there is a mix with "nothing"), so a rectangle keeps one pixel away from them.
  function margin(s) { return Math.abs(s.angle) > 1e-6 ? 1 : 0; }

  function inside(s, r) {
    var f = frameSize(s), th = rad(s.angle), c = Math.cos(th), sn = Math.sin(th), mg = margin(s);
    var hw = f.w / 2 - mg + SLACK, hh = f.h / 2 - mg + SLACK, ox = f.w / 2, oy = f.h / 2;
    var xs = [r.x, r.x + r.w], ys = [r.y, r.y + r.h];
    for (var i = 0; i < 2; i++) for (var j = 0; j < 2; j++) {
      var dx = xs[i] - ox, dy = ys[j] - oy;
      var lx = c * dx + sn * dy, ly = -sn * dx + c * dy;      // R(-angle) · d
      if (Math.abs(lx) > hw || Math.abs(ly) > hh) return false;
    }
    return true;
  }

  // The largest t in [0, 1] for which ok(t) holds (ok(0) holds; ok is true up to some t and false after it)
  function largest(ok) {
    if (ok(1)) return 1;
    var lo = 0, hi = 1;
    for (var i = 0; i < 40; i++) { var mid = (lo + hi) / 2; if (ok(mid)) lo = mid; else hi = mid; }
    return lo;
  }

  function around(cx, cy, w, h) { return { x: cx - w / 2, y: cy - h / 2, w: w, h: h }; }

  // The rectangle `want` as far as it fits: the same shape, shrunk about its middle (the middle moves toward the frame's
  // middle when it is outside)
  function fit(s, want) {
    if (inside(s, want)) return copyRect(want);
    var f = frameSize(s), ox = f.w / 2, oy = f.h / 2;
    var cx = want.x + want.w / 2, cy = want.y + want.h / 2;
    if (!inside(s, around(cx, cy, 1, 1))) {
      var t = largest(function (u) { return inside(s, around(ox + u * (cx - ox), oy + u * (cy - oy), 1, 1)); });
      cx = ox + t * (cx - ox); cy = oy + t * (cy - oy);
    }
    var k = largest(function (u) { return inside(s, around(cx, cy, want.w * u, want.h * u)); });
    return around(cx, cy, want.w * k, want.h * k);
  }

  // The biggest rectangle of the shape w / h = ratio inside the picture, around (cx, cy) – or as near as it can be
  function biggest(s, ratio, cx, cy) {
    var f = frameSize(s), ox = f.w / 2, oy = f.h / 2;
    if (!inside(s, around(cx, cy, 1, 1))) {
      var t = largest(function (u) { return inside(s, around(ox + u * (cx - ox), oy + u * (cy - oy), 1, 1)); });
      cx = ox + t * (cx - ox); cy = oy + t * (cy - oy);
    }
    var top = Math.max(f.h, f.w / ratio) * 1.5;
    var k = largest(function (u) { return inside(s, around(cx, cy, ratio * u * top, u * top)); });
    return around(cx, cy, ratio * k * top, k * top);
  }

  // After a change of the picture (angle, orientation …): `crop` is what fits of `want`
  function refit(s) { s.crop = fit(s, s.want); return s; }

  // ── Changing the picture ───────────────────────────────────────────────────────────────────

  function mapRect(r, how, f) {   // the rectangle after the frame f (its size before) was turned or mirrored
    if (how === 'left') return { x: r.y, y: f.w - (r.x + r.w), w: r.h, h: r.w };
    if (how === 'right') return { x: f.h - (r.y + r.h), y: r.x, w: r.h, h: r.w };
    return { x: f.w - (r.x + r.w), y: r.y, w: r.w, h: r.h };       // mirror
  }

  function apply(s, how) {
    var f = frameSize(s);
    s.m = mul(how === 'left' ? TURN_LEFT : how === 'right' ? TURN_RIGHT : MIRROR, s.m);
    s.crop = mapRect(s.crop, how, f);
    s.want = mapRect(s.want, how, f);
    if (how === 'mirror') s.angle = -s.angle;                       // a mirror turns the other way round
    else if (s.ratio) s.ratio = 1 / s.ratio;                        // portrait ↔ landscape
    return s;
  }
  function turnLeft(s) { return apply(s, 'left'); }
  function turnRight(s) { return apply(s, 'right'); }
  function mirror(s) { return apply(s, 'mirror'); }

  function setAngle(s, deg) {
    s.angle = clamp(deg, -MAX_ANGLE, MAX_ANGLE);
    return refit(s);
  }

  // A shape for the rectangle: null = free, a number = width / height. The rectangle becomes the biggest one of that shape.
  function setRatio(s, ratio) {
    s.ratio = ratio || null;
    if (!s.ratio) return s;
    var r = biggest(s, s.ratio, s.crop.x + s.crop.w / 2, s.crop.y + s.crop.h / 2);
    s.want = r; s.crop = copyRect(r);
    return s;
  }

  // The rectangle that keeps all of the picture: the frame, or – at an angle – the biggest rectangle of the frame's shape
  function full(s) {
    var f = frameSize(s);
    if (Math.abs(s.angle) < 1e-6) return { x: 0, y: 0, w: f.w, h: f.h };
    return biggest(s, f.w / f.h, f.w / 2, f.h / 2);
  }

  function reset(s) {
    s.m = [1, 0, 0, 1]; s.angle = 0; s.ratio = null;
    s.crop = { x: 0, y: 0, w: s.W, h: s.H };
    s.want = copyRect(s.crop);
    return s;
  }

  // Has anything been changed?
  function edited(s) {
    if (!isIdentity(s.m) || Math.abs(s.angle) > 1e-6) return true;
    var f = frameSize(s), c = s.crop;
    return Math.abs(c.x) > 0.5 || Math.abs(c.y) > 0.5 || Math.abs(c.w - f.w) > 0.5 || Math.abs(c.h - f.h) > 0.5;
  }

  // ── Dragging ───────────────────────────────────────────────────────────────────────────────

  // The rectangle `start` moved by (dx, dy), as far as the picture allows. Straightened, the picture's edges slant: the
  // movement is clamped in the turned-back frame, where they are straight, so the rectangle slides along them.
  function move(s, start, dx, dy) {
    var f = frameSize(s);
    if (Math.abs(s.angle) < 1e-6) {
      return { x: clamp(start.x + dx, 0, f.w - start.w), y: clamp(start.y + dy, 0, f.h - start.h), w: start.w, h: start.h };
    }
    var th = rad(s.angle), c = Math.cos(th), sn = Math.sin(th), mg = margin(s);
    var hw = f.w / 2 - mg, hh = f.h / 2 - mg, ox = f.w / 2, oy = f.h / 2;
    var loX = -Infinity, hiX = Infinity, loY = -Infinity, hiY = Infinity;
    var xs = [start.x, start.x + start.w], ys = [start.y, start.y + start.h];
    for (var i = 0; i < 2; i++) for (var j = 0; j < 2; j++) {
      var ddx = xs[i] - ox, ddy = ys[j] - oy;
      var lx = c * ddx + sn * ddy, ly = -sn * ddx + c * ddy;
      loX = Math.max(loX, -hw - lx); hiX = Math.min(hiX, hw - lx);
      loY = Math.max(loY, -hh - ly); hiY = Math.min(hiY, hh - ly);
    }
    var ux = c * dx + sn * dy, uy = -sn * dx + c * dy;               // the movement in the turned-back frame
    ux = clamp(ux, Math.min(loX, hiX), Math.max(loX, hiX)); uy = clamp(uy, Math.min(loY, hiY), Math.max(loY, hiY));
    return { x: start.x + c * ux - sn * uy, y: start.y + sn * ux + c * uy, w: start.w, h: start.h };
  }

  // A handle drags some of the edges: 'nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'
  function edgesOf(handle) { return { l: handle.indexOf('w') >= 0, r: handle.indexOf('e') >= 0, t: handle.indexOf('n') >= 0, b: handle.indexOf('s') >= 0 }; }

  // The rectangle `start`, dragged at `handle` to the point (px, py), never smaller than `min` and never outside the picture.
  // With a ratio it keeps its shape: a corner follows the pointer's longer side; an edge grows evenly to both sides.
  function resize(s, start, handle, px, py, min) {
    var e = edgesOf(handle), ratio = s.ratio, f = frameSize(s);
    var x0 = start.x, y0 = start.y, x1 = start.x + start.w, y1 = start.y + start.h;
    min = Math.max(1, min || 1);

    if (!ratio) {
      var tx0 = e.l ? Math.min(px, x1 - min) : x0, tx1 = e.r ? Math.max(px, x0 + min) : x1;
      var ty0 = e.t ? Math.min(py, y1 - min) : y0, ty1 = e.b ? Math.max(py, y0 + min) : y1;
      if (Math.abs(s.angle) < 1e-6) {
        return rectOf(clamp(tx0, 0, x1 - min), clamp(ty0, 0, y1 - min), clamp(tx1, x0 + min, f.w), clamp(ty1, y0 + min, f.h));
      }
      // slanted edges: each edge moves toward its target as far as the picture reaches – along x, then y, then x again
      var cur = { x0: x0, y0: y0, x1: x1, y1: y1 }, target = { x0: tx0, y0: ty0, x1: tx1, y1: ty1 };
      var slide = function (keys) {
        var base = { x0: cur.x0, y0: cur.y0, x1: cur.x1, y1: cur.y1 };
        var t = largest(function (u) {
          var r = { x0: base.x0, y0: base.y0, x1: base.x1, y1: base.y1 };
          keys.forEach(function (k) { r[k] = base[k] + u * (target[k] - base[k]); });
          return inside(s, rectOf(r.x0, r.y0, r.x1, r.y1));
        });
        keys.forEach(function (k) { cur[k] = base[k] + t * (target[k] - base[k]); });
      };
      slide(['x0', 'x1']); slide(['y0', 'y1']); slide(['x0', 'x1']);
      return rectOf(cur.x0, cur.y0, cur.x1, cur.y1);
    }

    // A fixed shape: the rectangle grows from an anchor – the opposite corner, or the middle of the opposite edge
    var w, h, ax, ay, sx, sy;                       // sx, sy: which way it grows from the anchor (-1, 0, 1)
    if ((e.l || e.r) && (e.t || e.b)) {
      ax = e.l ? x1 : x0; ay = e.t ? y1 : y0; sx = e.l ? -1 : 1; sy = e.t ? -1 : 1;
      var dw = Math.max(0, sx * (px - ax)), dh = Math.max(0, sy * (py - ay));
      w = Math.max(dw, dh * ratio, min); h = w / ratio;
    } else if (e.l || e.r) {
      ax = e.l ? x1 : x0; ay = (y0 + y1) / 2; sx = e.l ? -1 : 1; sy = 0;
      w = Math.max(sx * (px - ax), min); h = w / ratio;
    } else {
      ax = (x0 + x1) / 2; ay = e.t ? y1 : y0; sx = 0; sy = e.t ? -1 : 1;
      h = Math.max(sy * (py - ay), min / ratio); w = h * ratio;
    }
    var build = function (k) {
      var ww = w * k, hh2 = h * k;
      var rx = sx === 0 ? ax - ww / 2 : (sx > 0 ? ax : ax - ww);
      var ry = sy === 0 ? ay - hh2 / 2 : (sy > 0 ? ay : ay - hh2);
      return { x: rx, y: ry, w: ww, h: hh2 };
    };
    var k = largest(function (u) { return inside(s, build(u)); });
    return build(k);
  }

  function rectOf(x0, y0, x1, y1) { return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }; }

  // ── Getting the pixels ─────────────────────────────────────────────────────────────────────

  // Where the pixels of the picture go: x' = a·x + c·y + e, y' = b·x + d·y + f – the form of a canvas' setTransform and of
  // CSS' matrix(). `origin` is where the frame's top left corner lands (the crop's, to draw the kept part at 0, 0), `scale`
  // the size of a picture pixel afterwards.
  function matrix(s, origin, scale) {
    var f = frameSize(s), th = rad(s.angle), c = Math.cos(th), sn = Math.sin(th), m = s.m;
    var A0 = c * m[0] - sn * m[2], A1 = c * m[1] - sn * m[3], A2 = sn * m[0] + c * m[2], A3 = sn * m[1] + c * m[3];   // R · m
    var tx = f.w / 2 - (A0 * s.W / 2 + A1 * s.H / 2), ty = f.h / 2 - (A2 * s.W / 2 + A3 * s.H / 2);
    var k = scale || 1, o = origin || { x: 0, y: 0 };
    return { a: k * A0, b: k * A2, c: k * A1, d: k * A3, e: o.x + k * tx, f: o.y + k * ty };
  }

  // A ratio as small whole numbers, 16:9 → [16, 9] (null when it has none: an odd picture's own shape)
  function fraction(r) {
    for (var q = 1; q <= 1000; q++) {
      var p = Math.round(r * q);
      if (p > 0 && Math.abs(p / q - r) < 1e-9 * Math.max(1, r)) return [p, q];
    }
    return null;
  }

  // The crop on whole pixels (so that a plain crop does not blur): grown outward when upright, shrunk inward at an angle.
  // A shape stays exact – a square comes out square, 16:9 as p × 16 by p × 9 – at most a few pixels smaller.
  function snapped(s) {
    var c = s.crop, f = frameSize(s), upright = Math.abs(s.angle) < 1e-6, fr = s.ratio ? fraction(s.ratio) : null;
    if (fr) {
      for (var n = Math.floor(Math.min(c.w / fr[0], c.h / fr[1]) + 1e-9); n >= 1; n--) {
        var w = fr[0] * n, h = fr[1] * n, cx = c.x + c.w / 2 - w / 2, cy = c.y + c.h / 2 - h / 2;
        var tries = [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]];
        for (var i = 0; i < tries.length; i++) {
          var x0 = Math.round(cx) + tries[i][0], y0 = Math.round(cy) + tries[i][1];
          if (upright) { x0 = clamp(x0, 0, f.w - w); y0 = clamp(y0, 0, f.h - h); }
          if (x0 >= 0 && y0 >= 0 && inside(s, { x: x0, y: y0, w: w, h: h })) return { x: x0, y: y0, w: w, h: h };
        }
      }
    }
    if (upright) {
      var a0 = clamp(Math.round(c.x), 0, f.w - 1), b0 = clamp(Math.round(c.y), 0, f.h - 1);
      var a1 = clamp(Math.round(c.x + c.w), a0 + 1, f.w), b1 = clamp(Math.round(c.y + c.h), b0 + 1, f.h);
      return rectOf(a0, b0, a1, b1);
    }
    var d0 = Math.ceil(c.x), e0 = Math.ceil(c.y), d1 = Math.floor(c.x + c.w), e1 = Math.floor(c.y + c.h);
    return rectOf(d0, e0, Math.max(d1, d0 + 1), Math.max(e1, e0 + 1));
  }

  // The finished picture: its size (at most `maxPx` on the longer side – 0 or less: all of it) and the matrix that draws the
  // picture into a canvas of that size
  function output(s, maxPx) {
    var r = snapped(s), longer = Math.max(r.w, r.h);
    var k = maxPx > 0 && longer > maxPx ? maxPx / longer : 1;
    var w = Math.max(1, Math.round(r.w * k)), h = Math.max(1, Math.round(r.h * k));
    // the scale of each axis follows the rounded size, so that the last row and column are filled
    var kx = w / r.w, ky = h / r.h, m = matrix(s, { x: -r.x, y: -r.y }, 1);
    return { width: w, height: h, rect: r, scale: k,
             matrix: { a: m.a * kx, b: m.b * ky, c: m.c * kx, d: m.d * ky, e: m.e * kx, f: m.f * ky } };
  }

  // The corners of the crop on the picture that was opened (before any turning): for tests and for engines that crop
  // the original themselves – [x, y] four times, clockwise from the crop's top left
  function footprint(s) {
    var m = matrix(s, { x: 0, y: 0 }, 1), det = m.a * m.d - m.b * m.c, c = s.crop;
    var corners = [[c.x, c.y], [c.x + c.w, c.y], [c.x + c.w, c.y + c.h], [c.x, c.y + c.h]];
    return corners.map(function (p) {
      var x = p[0] - m.e, y = p[1] - m.f;
      return [(m.d * x - m.c * y) / det, (-m.b * x + m.a * y) / det];
    });
  }

  return {
    MAX_ANGLE: MAX_ANGLE, create: create, clone: clone, frameSize: frameSize, inside: inside, fit: fit, biggest: biggest,
    refit: refit, turnLeft: turnLeft, turnRight: turnRight, mirror: mirror, setAngle: setAngle, setRatio: setRatio,
    full: full, reset: reset, edited: edited, move: move, resize: resize, matrix: matrix, snapped: snapped,
    output: output, footprint: footprint, isIdentity: isIdentity
  };
});
