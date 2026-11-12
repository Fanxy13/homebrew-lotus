/* Lotus image editor – hiding parts of a picture: a blur, big pixels or black over the faces and over what was drawn.
 * Pure functions on pixels: no DOM, no network.
 *
 * It is shared by every system (macOS, Linux, Windows): the page uses it for what it shows and for what it saves, and
 * tests/edit/blur.test.js checks it with Node.
 *
 * A shape, in pixels of the picture:
 *   { kind: 'ellipse', x, y, rx, ry, rot }       a face: its middle, half its width and height, and the direction of its
 *                                                 width (radians; 0 when the picture is upright)
 *   { kind: 'stroke', points: [x, y, …], r }      a line drawn with a round brush of radius r
 * How it is hidden: type 'blur' | 'pixel' | 'solid' and a strength from 0 (light) to 1 (strong). The blur and the size of the
 * pixels follow the size of the shape: a small face and a big one are hidden equally well.
 *
 * The page shows a smaller copy of a big picture and saves the picture itself: `scale` is how many pixels of the copy one
 * pixel of the picture is (1 when it is saved). Pixels are red, green, blue, alpha – row after row, as a canvas has them.
 *
 *   LotusBlur.clusters(shapes, type, strength, scale, W, H)  → [{ x, y, w, h, shapes }]   the rectangles to work on
 *   LotusBlur.apply(pixels, w, h, x, y, scale, shapes, type, strength)                   hides the shapes in that rectangle
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LotusBlur = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var TYPES = ['blur', 'pixel', 'solid'];
  var STRENGTH = 0.8;                 // what the page starts with: at it the face detector itself finds no face it blurred

  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
  function smooth(t) { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); }

  // The ellipse that hides a face the detector found (a box around eyes, nose and mouth): a little wider and higher than
  // the box, and a little higher up – the forehead is part of a face. `rot`: the direction of the box's width in the picture.
  function faceEllipse(cx, cy, w, h, rot) {
    var up = 0.04 * h, r = rot || 0;
    return { kind: 'ellipse', x: cx + up * Math.sin(r), y: cy - up * Math.cos(r), rx: 0.62 * w, ry: 0.68 * h, rot: r };
  }

  // ── How big, how strong ────────────────────────────────────────────────────────────────────

  // What a shape is measured by: the narrow side of a face, twice the width of a brush
  function size(shape) { return shape.kind === 'ellipse' ? 2 * Math.min(shape.rx, shape.ry) : 4 * shape.r; }

  // In pixels of the picture: how far the blur spreads (sigma), how big a pixel block is, how wide the soft edge is
  function params(shape, type, strength) {
    var s = size(shape), k = clamp(strength === undefined ? STRENGTH : strength, 0, 1);
    var edge = shape.kind === 'ellipse' ? 0.2 * Math.min(shape.rx, shape.ry) : 0.35 * shape.r;
    return {
      sigma: type === 'blur' ? s * (0.08 + 0.22 * k) : 0,
      block: type === 'pixel' ? s / (12 - 8 * k) : 0,
      feather: type === 'blur' ? edge : 0                                    // (pixels and black have a crisp edge)
    };
  }

  // The box around a shape, in pixels of the picture: [x0, y0, x1, y1]
  function extent(shape) {
    if (shape.kind === 'ellipse') {
      var c = Math.cos(shape.rot || 0), s = Math.sin(shape.rot || 0);
      var ex = Math.sqrt(shape.rx * shape.rx * c * c + shape.ry * shape.ry * s * s), ey = Math.sqrt(shape.rx * shape.rx * s * s + shape.ry * shape.ry * c * c);
      return [shape.x - ex, shape.y - ey, shape.x + ex, shape.y + ey];
    }
    var p = shape.points, x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (var i = 0; i + 1 < p.length; i += 2) { x0 = Math.min(x0, p[i]); x1 = Math.max(x1, p[i]); y0 = Math.min(y0, p[i + 1]); y1 = Math.max(y1, p[i + 1]); }
    return [x0 - shape.r, y0 - shape.r, x1 + shape.r, y1 + shape.r];
  }

  // The rectangle of the copy that hiding a shape reads and writes – the shape, and around it what a blur mixes in or what
  // a block of pixels covers. Whole pixels, inside the picture; null when the shape is outside of it.
  function bounds(shape, type, strength, scale, W, H) {
    var e = extent(shape), p = params(shape, type, strength), k = scale || 1;
    var pad = type === 'blur' ? 2 * p.sigma * k + 2 : 1, bs = p.block * k;
    var x0 = e[0] * k - pad, y0 = e[1] * k - pad, x1 = e[2] * k + pad, y1 = e[3] * k + pad;
    if (type === 'pixel' && bs > 1) { x0 = Math.floor(x0 / bs) * bs; y0 = Math.floor(y0 / bs) * bs; x1 = Math.ceil(x1 / bs) * bs; y1 = Math.ceil(y1 / bs) * bs; }
    var maxX = Math.ceil(W * k), maxY = Math.ceil(H * k);
    x0 = clamp(Math.floor(x0), 0, maxX); y0 = clamp(Math.floor(y0), 0, maxY); x1 = clamp(Math.ceil(x1), 0, maxX); y1 = clamp(Math.ceil(y1), 0, maxY);
    return x1 > x0 && y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : null;
  }

  // Shapes whose rectangles touch are worked on together, in the order they were given: one rectangle for each group
  function clusters(shapes, type, strength, scale, W, H) {
    var list = [];
    shapes.forEach(function (shape) {
      var b = bounds(shape, type, strength, scale, W, H);
      if (b) list.push({ x: b.x, y: b.y, w: b.w, h: b.h, shapes: [shape] });
    });
    for (var merged = true; merged;) {
      merged = false;
      for (var i = 0; i < list.length && !merged; i++) for (var j = i + 1; j < list.length && !merged; j++) {
        var a = list[i], b2 = list[j];
        if (a.x < b2.x + b2.w && b2.x < a.x + a.w && a.y < b2.y + b2.h && b2.y < a.y + a.h) {
          var x0 = Math.min(a.x, b2.x), y0 = Math.min(a.y, b2.y), x1 = Math.max(a.x + a.w, b2.x + b2.w), y1 = Math.max(a.y + a.h, b2.y + b2.h);
          list[i] = { x: x0, y: y0, w: x1 - x0, h: y1 - y0, shapes: a.shapes.concat(b2.shapes) };
          list.splice(j, 1);
          merged = true;
        }
      }
    }
    list.forEach(function (c) { c.shapes.sort(function (p, q) { return shapes.indexOf(p) - shapes.indexOf(q); }); });
    return list;
  }

  // ── Where a shape is: 0 (outside) … 1 (inside) for every pixel of a rectangle of the copy ─────

  // `feather`: how wide the soft edge inside the shape is, in pixels of the picture (0: a crisp edge, smoothed over one pixel)
  function mask(shape, x, y, w, h, scale, feather) {
    var out = new Float32Array(w * h), k = scale || 1, soft = feather * k, px, py, i;
    // d: how far inside the shape a pixel's middle is (pixels of the copy)
    function alpha(d) { return soft > 1 ? smooth(d / soft) : clamp(d + 0.5, 0, 1); }
    if (shape.kind === 'ellipse') {
      var c = Math.cos(shape.rot || 0), s = Math.sin(shape.rot || 0), rx = shape.rx * k, ry = shape.ry * k, cx = shape.x * k, cy = shape.y * k;
      var small = Math.min(rx, ry);
      for (py = 0; py < h; py++) for (px = 0; px < w; px++) {
        var dx = x + px + 0.5 - cx, dy = y + py + 0.5 - cy, u = (c * dx + s * dy) / rx, v = (-s * dx + c * dy) / ry;
        var d = (1 - Math.sqrt(u * u + v * v)) * small;
        if (d > -0.5) out[py * w + px] = alpha(d);
      }
      return out;
    }
    var p = shape.points, r = shape.r * k, n = p.length >> 1;
    for (i = 0; i < Math.max(1, n - 1); i++) {
      var ax = p[2 * i] * k, ay = p[2 * i + 1] * k, bx = n > 1 ? p[2 * i + 2] * k : ax, by = n > 1 ? p[2 * i + 3] * k : ay;
      var vx = bx - ax, vy = by - ay, len2 = vx * vx + vy * vy;
      var x0 = clamp(Math.floor(Math.min(ax, bx) - r) - 1 - x, 0, w), x1 = clamp(Math.ceil(Math.max(ax, bx) + r) + 1 - x, 0, w);
      var y0 = clamp(Math.floor(Math.min(ay, by) - r) - 1 - y, 0, h), y1 = clamp(Math.ceil(Math.max(ay, by) + r) + 1 - y, 0, h);
      for (py = y0; py < y1; py++) for (px = x0; px < x1; px++) {
        var qx = x + px + 0.5 - ax, qy = y + py + 0.5 - ay, t = len2 > 0 ? clamp((qx * vx + qy * vy) / len2, 0, 1) : 0;
        var ex = qx - t * vx, ey = qy - t * vy, d2 = r - Math.sqrt(ex * ex + ey * ey);
        if (d2 > -0.5) { var a = alpha(d2); if (a > out[py * w + px]) out[py * w + px] = a; }
      }
    }
    return out;
  }

  // ── A blur ─────────────────────────────────────────────────────────────────────────────────

  // Three box blurs in a row are close to a Gaussian blur: the three half-widths for a spread of sigma
  function boxes(sigma) {
    var ideal = Math.sqrt(12 * sigma * sigma / 3 + 1), lo = Math.floor(ideal);
    if (lo % 2 === 0) lo--;
    var m = Math.round((12 * sigma * sigma - 3 * lo * lo - 12 * lo - 9) / (-4 * lo - 4)), out = [];
    for (var i = 0; i < 3; i++) out.push(Math.max(0, ((i < m ? lo : lo + 2) - 1) / 2));
    return out;
  }

  // One box blur along a line of `n` values, `step` apart; beyond the ends the first and last value go on
  function line(src, dst, start, step, n, r) {
    var acc = 0, div = 2 * r + 1, i;
    for (i = -r - 1; i < r; i++) acc += src[start + clamp(i, 0, n - 1) * step];
    for (i = 0; i < n; i++) {
      acc += src[start + (i + r < n ? i + r : n - 1) * step] - src[start + (i - r - 1 > 0 ? i - r - 1 : 0) * step];
      dst[start + i * step] = acc / div;
    }
  }

  function gauss(px, w, h, sigma) {
    if (!(sigma > 0.3)) return px;
    var rs = boxes(sigma), tmp = new Float32Array(px.length), a = px, b = tmp, t, c, i;
    for (var pass = 0; pass < 3; pass++) {
      if (!rs[pass]) continue;
      for (i = 0; i < h; i++) for (c = 0; c < 4; c++) line(a, b, i * w * 4 + c, 4, w, rs[pass]);
      t = a; a = b; b = t;
      for (i = 0; i < w; i++) for (c = 0; c < 4; c++) line(a, b, i * 4 + c, w * 4, h, rs[pass]);
      t = a; a = b; b = t;
    }
    return a;
  }

  // The rectangle (rx, ry, rw, rh) of the pixels, blurred. A wide blur is made on a smaller copy (every f × f pixels
  // their mean) – it looks the same and takes a fraction of the time. → { px, w, h, f }: colors times alpha when `pre`.
  // (Numbers with a fraction, not bytes: a color times a small alpha would lose its color when it is rounded.)
  function blurred(buf, bw, rx, ry, rw, rh, sigma, pre) {
    var f = Math.max(1, Math.floor(sigma / 6)), sw = Math.ceil(rw / f), sh = Math.ceil(rh / f), small = new Float32Array(sw * sh * 4);
    for (var sy = 0; sy < sh; sy++) for (var sx = 0; sx < sw; sx++) {
      var r = 0, g = 0, b = 0, a = 0, n = 0, yEnd = Math.min(rh, (sy + 1) * f), xEnd = Math.min(rw, (sx + 1) * f);
      for (var y = sy * f; y < yEnd; y++) {
        var i = ((ry + y) * bw + rx + sx * f) * 4;
        for (var x = sx * f; x < xEnd; x++, i += 4, n++) {
          if (pre) { var al = buf[i + 3]; r += buf[i] * al; g += buf[i + 1] * al; b += buf[i + 2] * al; a += al; }
          else { r += buf[i]; g += buf[i + 1]; b += buf[i + 2]; a += buf[i + 3]; }
        }
      }
      var o = (sy * sw + sx) * 4, div = pre ? n * 255 : n;
      small[o] = r / div; small[o + 1] = g / div; small[o + 2] = b / div; small[o + 3] = a / n;
    }
    return { px: gauss(small, sw, sh, sigma / f), w: sw, h: sh, f: f };
  }

  // ── Hiding ─────────────────────────────────────────────────────────────────────────────────

  // Hides the shapes, one after the other, in the pixels of the rectangle (x, y, w, h) of the copy – in place.
  function apply(buf, w, h, x, y, scale, shapes, type, strength) {
    var k = scale || 1, W = (x + w) / k, H = (y + h) / k;
    shapes.forEach(function (shape) {
      var p = params(shape, type, strength), e = extent(shape), i, px, py, m, o, t;
      // where the shape is, inside these pixels
      var mx0 = clamp(Math.floor(e[0] * k) - 1 - x, 0, w), my0 = clamp(Math.floor(e[1] * k) - 1 - y, 0, h);
      var mx1 = clamp(Math.ceil(e[2] * k) + 1 - x, 0, w), my1 = clamp(Math.ceil(e[3] * k) + 1 - y, 0, h), mw = mx1 - mx0, mh = my1 - my0;
      if (mw <= 0 || mh <= 0) return;
      var cover = mask(shape, x + mx0, y + my0, mw, mh, k, p.feather);

      if (type === 'solid') {
        for (py = 0; py < mh; py++) for (px = 0; px < mw; px++) {
          m = cover[py * mw + px];
          if (!m) continue;
          o = ((my0 + py) * w + mx0 + px) * 4;
          var al = buf[o + 3] / 255, na = al * (1 - m) + m;                       // black, fully there, over what was
          buf[o] = buf[o] * al * (1 - m) / na; buf[o + 1] = buf[o + 1] * al * (1 - m) / na; buf[o + 2] = buf[o + 2] * al * (1 - m) / na;
          buf[o + 3] = na * 255;
        }
        return;
      }

      // what the shape reads: itself and what is around it (see bounds)
      var b = bounds(shape, type, strength, k, W, H);
      if (!b) return;
      var rx = clamp(b.x - x, 0, w), ry = clamp(b.y - y, 0, h), rw = clamp(b.x + b.w - x, 0, w) - rx, rh = clamp(b.y + b.h - y, 0, h) - ry;
      if (rw <= 0 || rh <= 0) return;
      var pre = false;                                                          // is any of it see-through?
      for (py = 0; py < rh && !pre; py++) for (i = ((ry + py) * w + rx) * 4 + 3, t = i + rw * 4; i < t; i += 4) if (buf[i] !== 255) { pre = true; break; }

      var src = null, sums = null, bs = 0, cols = 0, bx0 = 0, by0 = 0;
      if (type === 'blur') src = blurred(buf, w, rx, ry, rw, rh, p.sigma * k, pre);
      else {
        // the mean color of every block (the blocks are counted from the picture's corner, so they do not move)
        bs = Math.max(1, p.block * k); bx0 = Math.floor((x + rx) / bs); by0 = Math.floor((y + ry) / bs);
        cols = Math.floor((x + rx + rw - 0.5) / bs) - bx0 + 1;
        var rows = Math.floor((y + ry + rh - 0.5) / bs) - by0 + 1;
        sums = new Float64Array(cols * rows * 5);
        for (py = 0; py < rh; py++) {
          var row = (Math.floor((y + ry + py + 0.5) / bs) - by0) * cols;
          for (px = 0, o = ((ry + py) * w + rx) * 4; px < rw; px++, o += 4) {
            i = (row + Math.floor((x + rx + px + 0.5) / bs) - bx0) * 5;
            var a2 = pre ? buf[o + 3] / 255 : 1;
            sums[i] += buf[o] * a2; sums[i + 1] += buf[o + 1] * a2; sums[i + 2] += buf[o + 2] * a2; sums[i + 3] += buf[o + 3]; sums[i + 4] += 1;
          }
        }
      }

      for (py = 0; py < mh; py++) for (px = 0; px < mw; px++) {
        m = cover[py * mw + px];
        if (!m) continue;
        var gx = mx0 + px, gy = my0 + py, r2, g2, b2, a3;                       // (g…: in these pixels)
        o = (gy * w + gx) * 4;
        if (src) {
          // the blurred copy, read between its pixels
          var fx = clamp((gx - rx + 0.5) / src.f - 0.5, 0, src.w - 1), fy = clamp((gy - ry + 0.5) / src.f - 0.5, 0, src.h - 1);
          var x0 = Math.floor(fx), y0 = Math.floor(fy), x1 = Math.min(src.w - 1, x0 + 1), y1 = Math.min(src.h - 1, y0 + 1), tx = fx - x0, ty = fy - y0;
          var i00 = (y0 * src.w + x0) * 4, i10 = (y0 * src.w + x1) * 4, i01 = (y1 * src.w + x0) * 4, i11 = (y1 * src.w + x1) * 4, s = src.px;
          var w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
          r2 = s[i00] * w00 + s[i10] * w10 + s[i01] * w01 + s[i11] * w11;
          g2 = s[i00 + 1] * w00 + s[i10 + 1] * w10 + s[i01 + 1] * w01 + s[i11 + 1] * w11;
          b2 = s[i00 + 2] * w00 + s[i10 + 2] * w10 + s[i01 + 2] * w01 + s[i11 + 2] * w11;
          a3 = s[i00 + 3] * w00 + s[i10 + 3] * w10 + s[i01 + 3] * w01 + s[i11 + 3] * w11;
        } else {
          i = ((Math.floor((y + gy + 0.5) / bs) - by0) * cols + Math.floor((x + gx + 0.5) / bs) - bx0) * 5;
          var cnt = sums[i + 4] || 1;
          r2 = sums[i] / cnt; g2 = sums[i + 1] / cnt; b2 = sums[i + 2] / cnt; a3 = sums[i + 3] / cnt;
        }
        if (!pre) {
          buf[o] += (r2 - buf[o]) * m; buf[o + 1] += (g2 - buf[o + 1]) * m; buf[o + 2] += (b2 - buf[o + 2]) * m;
        } else {
          // colors times alpha are mixed, then divided again: what is see-through does not darken the rest
          var oa = buf[o + 3] / 255, na2 = oa + (a3 / 255 - oa) * m;
          if (na2 > 0) {
            buf[o] = (buf[o] * oa + (r2 - buf[o] * oa) * m) / na2; buf[o + 1] = (buf[o + 1] * oa + (g2 - buf[o + 1] * oa) * m) / na2;
            buf[o + 2] = (buf[o + 2] * oa + (b2 - buf[o + 2] * oa) * m) / na2;
          }
          buf[o + 3] = na2 * 255;
        }
      }
    });
    return buf;
  }

  return {
    TYPES: TYPES, STRENGTH: STRENGTH, faceEllipse: faceEllipse, size: size, params: params, extent: extent, bounds: bounds,
    clusters: clusters, mask: mask, boxes: boxes, apply: apply
  };
});
