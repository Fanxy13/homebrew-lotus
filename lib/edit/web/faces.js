/* Lotus image editor – finding faces: a small neural network, run in plain JavaScript. Pure functions: no DOM, no network.
 *
 * It is shared by every system (macOS, Linux, Windows): the page runs it (in a worker, faces-worker.js), and
 * tests/edit/faces.test.js checks it with Node. Nothing is installed and nothing leaves the computer.
 *
 * The network is YuNet (Shiqi Yu and others, MIT license – THIRD_PARTY.md), 53,000 numbers in web/faces.bin, made from
 * its ONNX file by scripts/make-face-model.py (which describes the file). It finds faces of about 10 to 300 pixels, so a
 * picture is looked at several times, each time half as big: the big faces are found in the small copies.
 *
 *   var model = LotusFaces.load(arrayBuffer);                       // web/faces.bin
 *   var faces = LotusFaces.detect(model, rgba, width, height);      // rgba: the pixels as a canvas gives them
 *   → [{ x, y, w, h, score, points: [x, y, …] }]                    // boxes in pixels of that picture, the best first;
 *                                                                   // points: right eye, left eye, nose, the mouth's corners
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LotusFaces = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var MAGIC = 'LFACE1\n\0';
  var SCORE = 0.6;              // a face counts from here (the square root of "a face" × "an object", 0 … 1)
  var IOU = 0.3;                // two boxes that share more than this are one face
  var SMALLEST = 200;           // the picture is halved until its longer side is at most this

  // ── The model file ─────────────────────────────────────────────────────────────────────────

  function load(data) {
    var bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    for (var i = 0; i < MAGIC.length; i++) if (bytes[i] !== MAGIC.charCodeAt(i)) throw new Error('This is not a face model.');
    var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), n = view.getUint32(8, true), text = '';
    for (i = 0; i < n; i++) text += String.fromCharCode(bytes[12 + i]);            // (the header is ASCII)
    var head = JSON.parse(text), at = (12 + n + 3) & ~3;
    if (head.format !== 'lotus-faces-1' || bytes.length - at !== head.numbers * 4) throw new Error('The face model is damaged.');
    var w = new Float32Array(head.numbers);
    for (i = 0; i < head.numbers; i++) w[i] = view.getFloat32(at + 4 * i, true);  // little endian, whatever this computer is
    return { head: head, w: w };
  }

  // ── The steps of the network (pictures of numbers: channel after channel, row after row) ──────

  // 3×3, every second pixel, a border of one
  function conv3s2(src, cin, W, H, w, wo, bo, cout) {
    var OW = W >> 1, OH = H >> 1, n = OW * OH, plane = W * H, out = new Float32Array(cout * n);
    for (var o = 0; o < cout; o++) {
      var ob = o * n, bias = w[bo + o], i;
      for (i = 0; i < n; i++) out[ob + i] = bias;
      for (var c = 0; c < cin; c++) {
        for (var ky = 0; ky < 3; ky++) {
          var k = wo + ((o * cin + c) * 3 + ky) * 3, k0 = w[k], k1 = w[k + 1], k2 = w[k + 2];
          for (var oy = ky === 0 ? 1 : 0; oy < OH; oy++) {
            var si = c * plane + (2 * oy - 1 + ky) * W, di = ob + oy * OW;
            out[di] += k1 * src[si] + k2 * src[si + 1];                            // (left of the first pixel is the border)
            si += 1; di += 1;
            for (var ox = 1; ox < OW; ox++, si += 2, di++) out[di] += k0 * src[si] + k1 * src[si + 1] + k2 * src[si + 2];
          }
        }
      }
    }
    return out;
  }

  // 1×1: every pixel's channels mixed into new channels
  function pointwise(src, cin, n, w, wo, bo, cout) {
    var out = new Float32Array(cout * n);
    for (var o = 0; o < cout; o++) {
      var ob = o * n, row = wo + o * cin, bias = w[bo + o], c = 0, i, end = ob + n, a, b, d, e, k0, k1, k2, k3;
      for (i = ob; i < end; i++) out[i] = bias;
      for (; c + 4 <= cin; c += 4) {
        k0 = w[row + c]; k1 = w[row + c + 1]; k2 = w[row + c + 2]; k3 = w[row + c + 3];
        a = c * n; b = a + n; d = b + n; e = d + n;
        for (i = ob; i < end; i++, a++, b++, d++, e++) out[i] += k0 * src[a] + k1 * src[b] + k2 * src[d] + k3 * src[e];
      }
      for (; c < cin; c++) {
        k0 = w[row + c]; a = c * n;
        for (i = ob; i < end; i++, a++) out[i] += k0 * src[a];
      }
    }
    return out;
  }

  // 3×3 of each channel by itself, a border of one
  function depthwise(src, ch, W, H, w, wo, bo) {
    var n = W * H, PW = W + 2, out = new Float32Array(ch * n), pad = new Float32Array(PW * (H + 2));
    for (var c = 0; c < ch; c++) {
      var base = c * n, k = wo + c * 9, bias = w[bo + c], y, x;
      var k0 = w[k], k1 = w[k + 1], k2 = w[k + 2], k3 = w[k + 3], k4 = w[k + 4], k5 = w[k + 5], k6 = w[k + 6], k7 = w[k + 7], k8 = w[k + 8];
      for (y = 0; y < H; y++) pad.set(src.subarray(base + y * W, base + y * W + W), (y + 1) * PW + 1);
      for (y = 0; y < H; y++) {
        var p0 = y * PW, p1 = p0 + PW, p2 = p1 + PW, d = base + y * W;
        for (x = 0; x < W; x++, d++, p0++, p1++, p2++) {
          out[d] = bias + k0 * pad[p0] + k1 * pad[p0 + 1] + k2 * pad[p0 + 2] + k3 * pad[p1] + k4 * pad[p1 + 1] + k5 * pad[p1 + 2] +
            k6 * pad[p2] + k7 * pad[p2 + 1] + k8 * pad[p2 + 2];
        }
      }
    }
    return out;
  }

  function relu(a) { for (var i = 0; i < a.length; i++) if (a[i] < 0) a[i] = 0; }
  function sigmoid(a) { for (var i = 0; i < a.length; i++) a[i] = 1 / (1 + Math.exp(-a[i])); }

  function pool(src, ch, W, H) {
    var OW = W >> 1, OH = H >> 1, out = new Float32Array(ch * OW * OH), d = 0;
    for (var c = 0; c < ch; c++) for (var y = 0; y < OH; y++) {
      var s = c * W * H + 2 * y * W;
      for (var x = 0; x < OW; x++, s += 2, d++) {
        var m = src[s], v = src[s + 1];
        if (v > m) m = v;
        v = src[s + W]; if (v > m) m = v;
        v = src[s + W + 1]; if (v > m) m = v;
        out[d] = m;
      }
    }
    return out;
  }

  function upsample(src, ch, W, H) {
    var OW = W * 2, out = new Float32Array(ch * OW * H * 2), s = 0;
    for (var c = 0; c < ch; c++) for (var y = 0; y < H; y++) {
      var d = c * OW * H * 2 + 2 * y * OW;
      for (var x = 0; x < W; x++, s++, d += 2) { var v = src[s]; out[d] = v; out[d + 1] = v; out[d + OW] = v; out[d + OW + 1] = v; }
    }
    return out;
  }

  function add(a, b) {
    var out = new Float32Array(a.length);
    for (var i = 0; i < a.length; i++) out[i] = a[i] + b[i];
    return out;
  }

  // The network on one picture: `input` is blue, green, red (0 … 255), W and H are multiples of 32.
  // → { cls, obj, bbox, kps }: for each stride (8, 16, 32) a picture { data, c, w, h }
  function forward(model, input, W, H) {
    if (W % 32 || H % 32 || input.length !== 3 * W * H) throw new Error('The picture for the face model has the wrong size.');
    var steps = model.head.steps, w = model.w, data = [], dim = [];        // dim[slot] = [channels, width, height]
    data[0] = input; dim[0] = [3, W, H];
    for (var i = 0; i < steps.length; i++) {
      var s = steps[i], d, j;
      switch (s[0]) {
        case 'c3s2': d = dim[s[2]]; data[s[1]] = conv3s2(data[s[2]], s[3], d[1], d[2], w, s[5], s[6], s[4]); dim[s[1]] = [s[4], d[1] >> 1, d[2] >> 1]; break;
        case 'pw': d = dim[s[2]]; data[s[1]] = pointwise(data[s[2]], s[3], d[1] * d[2], w, s[5], s[6], s[4]); dim[s[1]] = [s[4], d[1], d[2]]; break;
        case 'dw': d = dim[s[2]]; data[s[1]] = depthwise(data[s[2]], s[3], d[1], d[2], w, s[4], s[5]); dim[s[1]] = d; break;
        case 'relu': relu(data[s[1]]); break;
        case 'sig': sigmoid(data[s[1]]); break;
        case 'pool': d = dim[s[2]]; data[s[1]] = pool(data[s[2]], d[0], d[1], d[2]); dim[s[1]] = [d[0], d[1] >> 1, d[2] >> 1]; break;
        case 'up': d = dim[s[2]]; data[s[1]] = upsample(data[s[2]], d[0], d[1], d[2]); dim[s[1]] = [d[0], d[1] * 2, d[2] * 2]; break;
        case 'add': data[s[1]] = add(data[s[2]], data[s[3]]); dim[s[1]] = dim[s[2]]; break;
        case 'free': for (j = 1; j < s.length; j++) data[s[j]] = null; break;
        default: throw new Error('The face model has a step this page does not know: ' + s[0]);
      }
    }
    var out = {}, names = ['cls', 'obj', 'bbox', 'kps'];
    names.forEach(function (name) {
      out[name] = model.head.outputs[name].map(function (slot) { return { data: data[slot], c: dim[slot][0], w: dim[slot][1], h: dim[slot][2] }; });
    });
    return out;
  }

  // ── From the network's pictures to boxes ────────────────────────────────────────────────────

  // Every cell of a result picture says: how sure, and where the face around it is (in pixels of the network's input)
  function decode(model, out, minScore) {
    var faces = [], strides = model.head.strides;
    for (var s = 0; s < strides.length; s++) {
      var stride = strides[s], cls = out.cls[s], obj = out.obj[s].data, box = out.bbox[s].data, kps = out.kps[s].data;
      var cols = cls.w, rows = cls.h, n = cols * rows;
      for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) {
        var i = r * cols + c, score = Math.sqrt(Math.min(1, Math.max(0, cls.data[i])) * Math.min(1, Math.max(0, obj[i])));
        if (!(score >= minScore)) continue;
        var cx = (c + box[i]) * stride, cy = (r + box[n + i]) * stride;
        var w = Math.exp(box[2 * n + i]) * stride, h = Math.exp(box[3 * n + i]) * stride, points = [];
        for (var p = 0; p < 5; p++) points.push((kps[2 * p * n + i] + c) * stride, (kps[(2 * p + 1) * n + i] + r) * stride);
        faces.push({ x: cx - w / 2, y: cy - h / 2, w: w, h: h, score: score, points: points });
      }
    }
    return faces;
  }

  function iou(a, b) {
    var x0 = Math.max(a.x, b.x), y0 = Math.max(a.y, b.y), x1 = Math.min(a.x + a.w, b.x + b.w), y1 = Math.min(a.y + a.h, b.y + b.h);
    var inter = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
    return inter > 0 ? inter / (a.w * a.h + b.w * b.h - inter) : 0;
  }

  // Is most of the small box `b` inside the much bigger box `a`? (an eye or a mouth of a big face, taken for a small face)
  function within(a, b) {
    if (b.w * b.h > 0.5 * a.w * a.h) return false;
    var x0 = Math.max(a.x, b.x), y0 = Math.max(a.y, b.y), x1 = Math.min(a.x + a.w, b.x + b.w), y1 = Math.min(a.y + a.h, b.y + b.h);
    return Math.max(0, x1 - x0) * Math.max(0, y1 - y0) > 0.7 * b.w * b.h;
  }

  // The surest box of each face: the others that cover the same face go, and so does a less sure "face" inside a bigger one
  function nms(faces, limit) {
    var sorted = faces.slice().sort(function (a, b) { return b.score - a.score; }), kept = [];
    for (var i = 0; i < sorted.length; i++) {
      var ok = true;
      for (var j = 0; j < kept.length && ok; j++) if (iou(sorted[i], kept[j]) > limit || within(kept[j], sorted[i])) ok = false;
      if (ok) kept.push(sorted[i]);
    }
    return kept;
  }

  // ── Pixels ─────────────────────────────────────────────────────────────────────────────────

  // The pixels of a canvas (red, green, blue, alpha – row after row) as the network wants them; what is see-through is white,
  // and the picture is filled up with black to a multiple of 32
  function planes(rgba, w, h) {
    var W = Math.ceil(w / 32) * 32, H = Math.ceil(h / 32) * 32, n = W * H, out = new Float32Array(3 * n);
    for (var y = 0; y < h; y++) {
      var s = y * w * 4, d = y * W;
      for (var x = 0; x < w; x++, s += 4, d++) {
        var a = rgba[s + 3];
        if (a === 255) { out[d] = rgba[s + 2]; out[n + d] = rgba[s + 1]; out[2 * n + d] = rgba[s]; }
        else { var t = 255 - a; out[d] = (rgba[s + 2] * a + 255 * t) / 255; out[n + d] = (rgba[s + 1] * a + 255 * t) / 255; out[2 * n + d] = (rgba[s] * a + 255 * t) / 255; }
      }
    }
    return { data: out, w: W, h: H };
  }

  // Half as wide and high: each pixel is the mean of four
  function halve(rgba, w, h) {
    var W = w >> 1, H = h >> 1, out = new Uint8ClampedArray(W * H * 4);
    for (var y = 0; y < H; y++) {
      var a = 2 * y * w * 4, b = a + w * 4, d = y * W * 4;
      for (var x = 0; x < W; x++, a += 8, b += 8, d += 4) {
        out[d] = (rgba[a] + rgba[a + 4] + rgba[b] + rgba[b + 4] + 2) >> 2;
        out[d + 1] = (rgba[a + 1] + rgba[a + 5] + rgba[b + 1] + rgba[b + 5] + 2) >> 2;
        out[d + 2] = (rgba[a + 2] + rgba[a + 6] + rgba[b + 2] + rgba[b + 6] + 2) >> 2;
        out[d + 3] = (rgba[a + 3] + rgba[a + 7] + rgba[b + 3] + rgba[b + 7] + 2) >> 2;
      }
    }
    return { data: out, w: W, h: H };
  }

  // ── All of it ──────────────────────────────────────────────────────────────────────────────

  // The faces of a picture. `options`: score (0 … 1, a face counts from here), levels (how many sizes are looked at – all of
  // them when it is not given; 1 is the picture as it is, for the small faces of a bigger copy)
  function detect(model, rgba, w, h, options) {
    var o = options || {}, minScore = o.score || SCORE, found = [], scale = 1, level = 0;
    var cur = { data: rgba, w: w, h: h };
    while (cur.w >= 16 && cur.h >= 16) {
      var p = planes(cur.data, cur.w, cur.h), faces = decode(model, forward(model, p.data, p.w, p.h), minScore);
      for (var i = 0; i < faces.length; i++) {
        var f = faces[i];
        found.push({ x: f.x * scale, y: f.y * scale, w: f.w * scale, h: f.h * scale, score: f.score,
                     points: f.points.map(function (v) { return v * scale; }) });
      }
      level++;
      if ((o.levels && level >= o.levels) || Math.max(cur.w, cur.h) <= SMALLEST) break;
      cur = halve(cur.data, cur.w, cur.h); scale *= 2;
    }
    return nms(found, o.iou || IOU).filter(function (f) {            // (a box whose middle is in the black filling is no face)
      var cx = f.x + f.w / 2, cy = f.y + f.h / 2;
      return cx >= 0 && cy >= 0 && cx <= w && cy <= h;
    });
  }

  return { SCORE: SCORE, IOU: IOU, load: load, forward: forward, decode: decode, nms: nms, iou: iou, planes: planes, halve: halve, detect: detect };
});
