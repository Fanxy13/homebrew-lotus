// Pictures for the image editor's tests, without any program: a PNG read and written with Node's zlib, a picture made bigger,
// smaller and mirrored, and a scene with three faces made from tests/edit/face.png (a portrait by NASA, public domain – see
// THIRD_PARTY.md). A picture is { data: Uint8ClampedArray (red, green, blue, alpha – row after row), w, h }.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t.push(c >>> 0); } return t; })();
const crc32 = (b) => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };

// A PNG of 8 bits per channel – colors, colors with alpha, or a palette – not interlaced (what the tests write, what face.png is,
// what ImageMagick writes)
function readPng(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32BE(0) !== 0x89504e47) throw new Error(file + ' is not a PNG');
  let at = 8, w = 0, h = 0, type = 0, palette = null, trns = null;
  const parts = [];
  while (at < b.length) {
    const len = b.readUInt32BE(at), name = b.toString('latin1', at + 4, at + 8), body = b.subarray(at + 8, at + 8 + len);
    if (name === 'IHDR') {
      w = body.readUInt32BE(0); h = body.readUInt32BE(4); type = body[9];
      if (body[8] !== 8 || ![2, 3, 6].includes(type) || body[12] !== 0) throw new Error(file + ': a kind of PNG this reader does not know');
    } else if (name === 'PLTE') palette = body;
    else if (name === 'tRNS') trns = body;
    else if (name === 'IDAT') parts.push(body);
    at += 12 + len;
  }
  const bpp = type === 6 ? 4 : type === 2 ? 3 : 1, row = w * bpp, raw = zlib.inflateSync(Buffer.concat(parts)), px = Buffer.alloc(row * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (row + 1)], src = y * (row + 1) + 1, dst = y * row;
    for (let i = 0; i < row; i++) {
      const a = i >= bpp ? px[dst + i - bpp] : 0, up = y ? px[dst + i - row] : 0, c = y && i >= bpp ? px[dst + i - row - bpp] : 0;
      let v = raw[src + i];
      if (f === 1) v += a;
      else if (f === 2) v += up;
      else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) { const p = a + up - c, pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
      px[dst + i] = v & 255;
    }
  }
  const data = new Uint8ClampedArray(w * h * 4);
  for (let i = 0, j = 0; i < w * h; i++, j += bpp) {
    if (type === 3) { const c = px[j]; data[4 * i] = palette[3 * c]; data[4 * i + 1] = palette[3 * c + 1]; data[4 * i + 2] = palette[3 * c + 2]; data[4 * i + 3] = trns && c < trns.length ? trns[c] : 255; continue; }
    data[4 * i] = px[j]; data[4 * i + 1] = px[j + 1]; data[4 * i + 2] = px[j + 2]; data[4 * i + 3] = bpp === 4 ? px[j + 3] : 255;
  }
  return { data, w, h };
}

// A picture as a PNG (red, green, blue; with alpha when `alpha` is set)
function writePng(file, img, alpha) {
  const bpp = alpha ? 4 : 3, raw = Buffer.alloc((img.w * bpp + 1) * img.h);
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
    const s = (y * img.w + x) * 4, d = y * (img.w * bpp + 1) + 1 + x * bpp;
    raw[d] = img.data[s]; raw[d + 1] = img.data[s + 1]; raw[d + 2] = img.data[s + 2];
    if (alpha) raw[d + 3] = img.data[s + 3];
  }
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(img.w, 0); ihdr.writeUInt32BE(img.h, 4); ihdr[8] = 8; ihdr[9] = alpha ? 6 : 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}

function blank(w, h, fn) {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const c = fn(x, y), i = (y * w + x) * 4; data[i] = c[0]; data[i + 1] = c[1]; data[i + 2] = c[2]; data[i + 3] = c.length > 3 ? c[3] : 255; }
  return { data, w, h };
}

// Another size (each new pixel is a mix of the four around its place in the old picture)
function resize(img, w, h) {
  const out = new Uint8ClampedArray(w * h * 4), kx = img.w / w, ky = img.h / h;
  for (let y = 0; y < h; y++) {
    const fy = Math.min(img.h - 1, Math.max(0, (y + 0.5) * ky - 0.5)), y0 = Math.floor(fy), y1 = Math.min(img.h - 1, y0 + 1), ty = fy - y0;
    for (let x = 0; x < w; x++) {
      const fx = Math.min(img.w - 1, Math.max(0, (x + 0.5) * kx - 0.5)), x0 = Math.floor(fx), x1 = Math.min(img.w - 1, x0 + 1), tx = fx - x0;
      for (let c = 0; c < 4; c++) {
        const a = img.data[(y0 * img.w + x0) * 4 + c], b = img.data[(y0 * img.w + x1) * 4 + c], d = img.data[(y1 * img.w + x0) * 4 + c], e = img.data[(y1 * img.w + x1) * 4 + c];
        out[(y * w + x) * 4 + c] = Math.round((a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty);
      }
    }
  }
  return { data: out, w, h };
}

// Half the size (each pixel the mean of four), as often as asked
function half(img, times) {
  let cur = img;
  for (let t = 0; t < (times || 1); t++) {
    const w = cur.w >> 1, h = cur.h >> 1, out = new Uint8ClampedArray(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) for (let c = 0; c < 4; c++) {
      const i = (2 * y * cur.w + 2 * x) * 4 + c;
      out[(y * w + x) * 4 + c] = (cur.data[i] + cur.data[i + 4] + cur.data[i + cur.w * 4] + cur.data[i + cur.w * 4 + 4] + 2) >> 2;
    }
    cur = { data: out, w, h };
  }
  return cur;
}

function mirror(img) {
  const out = new Uint8ClampedArray(img.data.length);
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) for (let c = 0; c < 4; c++) out[(y * img.w + x) * 4 + c] = img.data[(y * img.w + img.w - 1 - x) * 4 + c];
  return { data: out, w: img.w, h: img.h };
}

function paste(dst, src, x0, y0) {
  for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
    if (x0 + x < 0 || y0 + y < 0 || x0 + x >= dst.w || y0 + y >= dst.h) continue;
    for (let c = 0; c < 4; c++) dst.data[((y0 + y) * dst.w + x0 + x) * 4 + c] = src.data[(y * src.w + x) * 4 + c];
  }
  return dst;
}

// The portrait of the tests, and where its face is (what the detector says of the picture alone, rounded)
const FACE = { file: path.join(__dirname, 'face.png'), w: 180, h: 192, cx: 89, cy: 99, fw: 90, fh: 106 };
function portrait() { return readPng(FACE.file); }

// A picture with three faces: the portrait as it is, twice as big, and half as big and mirrored – on a quiet background.
// → { picture, faces: [{ cx, cy, w }] } (where the middle of each face is and how wide it is), the biggest face first
function scene() {
  const p = portrait(), pic = blank(640, 400, (x, y) => [70 + (x >> 3), 92 + (y >> 3), 120]);
  paste(pic, p, 40, 60);
  paste(pic, resize(p, p.w * 2, p.h * 2), 250, 8);
  paste(pic, mirror(half(p)), 60, 280);
  return {
    picture: pic,
    faces: [
      { cx: 250 + 2 * FACE.cx, cy: 8 + 2 * FACE.cy, w: 2 * FACE.fw },
      { cx: 40 + FACE.cx, cy: 60 + FACE.cy, w: FACE.fw },
      { cx: 60 + (FACE.w - FACE.cx) / 2, cy: 280 + FACE.cy / 2, w: FACE.fw / 2 }
    ]
  };
}

// A crowd: the portrait, half as big, `cols` × `rows` times side by side → { picture, count }
function crowd(cols, rows) {
  const small = half(portrait()), pic = blank(cols * small.w, rows * small.h, () => [40, 40, 44]);
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) paste(pic, (r + c) % 2 ? mirror(small) : small, c * small.w, r * small.h);
  return { picture: pic, count: cols * rows };
}

module.exports = { readPng, writePng, blank, resize, half, mirror, paste, portrait, scene, crowd, FACE };
