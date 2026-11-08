#!/usr/bin/env node
// The Lotus for Windows video: a take of record.py (an asciicast) replayed in xterm.js in Chromium, frame by frame,
// cut as the cut file says – captions, a cross dissolve between parts, a note where time is left out, the title and
// end cards – and encoded with ffmpeg. Every frame of a scene is the terminal as it was at that moment of the take.
//
//   node render.mjs <take.cast[.gz]> <cut.json> <out.mp4>
//   node render.mjs <take.cast[.gz]> <cut.json> --stills <dir> <second> [<second> …]   still frames, to look at
//   node render.mjs <take.cast[.gz]> <cut.json> --plan                                the parts and their times
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));

function loadCast(file) {
  let buf = readFileSync(file);
  if (file.endsWith('.gz')) buf = gunzipSync(buf);
  const lines = buf.toString('utf8').split('\n').filter(Boolean);
  const head = JSON.parse(lines[0]);
  const events = lines.slice(1).map((l) => JSON.parse(l));
  const marks = new Map();
  for (const [t, type, data] of events) {
    if (type !== 'm') continue;
    if (!marks.has(data)) marks.set(data, []);
    marks.get(data).push(t);
  }
  return { head, events, marks };
}

// A moment of the take: seconds, a marker ("scene:img+1.5", "end:img-2", "scene:pet#2"), or the first moment after one
// that the window shows a text: { "after": "scene:app", "shows": "Did you mean", "plus": 0.5 } (a regular expression)
const shownKey = (expr) => JSON.stringify([expr.after, expr.shows]);
function at(expr, marks, shown) {
  if (typeof expr === 'number') return expr;
  if (typeof expr === 'object') {
    const t = shown?.get(shownKey(expr));
    if (t == null) throw new Error(`"${expr.shows}" does not show after ${JSON.stringify(expr.after)}`);
    return t + (expr.plus || 0);
  }
  const m = /^(.+?)(?:#(\d+))?([+-]\d+(?:\.\d+)?)?$/.exec(expr);
  const times = marks.get(m[1]);
  if (!times) throw new Error(`no marker "${m[1]}" in the take`);
  return times[(m[2] ? +m[2] : 1) - 1] + (m[3] ? +m[3] : 0);
}

// The texts the cut waits for, found in one replay of the take in the page
async function findShown(page, cut, cast) {
  const wants = new Map();
  for (const scene of cut.scenes) for (const part of scene.parts) for (const e of part) {
    if (typeof e === 'object') wants.set(shownKey(e), { after: at(e.after, cast.marks), shows: e.shows });
  }
  const list = [...wants.values()];
  const times = await page.evaluate(([ev, w, c, r]) => window.stage.find(ev, w, c, r), [cast.events, list, cast.head.width, cast.head.height]);
  return new Map([...wants.keys()].map((k, i) => [k, times[i]]));
}

// What a note says where time is left out: the seconds, or minutes from one and a half on
function later(seconds) {
  if (seconds < 90) return `${Math.round(seconds)} seconds later`;
  const min = Math.round(seconds / 30) / 2;
  return `${min} minutes later`;
}

const ease = (x) => 0.5 - Math.cos(Math.PI * Math.min(1, Math.max(0, x))) / 2;

// The video, part by part: cards and stretches of the take
function plan(cut, marks, shown) {
  const parts = [{ kind: 'card', card: cut.title.html, seconds: cut.title.seconds, first: true }];
  for (const scene of cut.scenes) {
    let prev = null;
    for (const [a, b] of scene.parts) {
      const from = at(a, marks, shown), to = at(b, marks, shown);
      if (!(to > from)) throw new Error(`${scene.name}: ${a} … ${b} is empty`);
      const gap = prev === null ? 0 : from - prev;
      parts.push({ kind: 'take', scene, from, to, note: gap > 3 ? later(gap) : '' });
      prev = to;
    }
  }
  parts.push({ kind: 'card', card: cut.end.html, seconds: cut.end.seconds, last: true });
  return parts;
}

class Player {
  constructor(page, events) { Object.assign(this, { page, events, i: 0 }); }
  async to(t) {                                  // the terminal as it was at second t of the take
    let chunk = '';
    const flush = async () => { if (chunk) await this.page.evaluate((d) => window.stage.write(d), chunk); chunk = ''; };
    while (this.i < this.events.length && this.events[this.i][0] <= t) {
      const [, type, data] = this.events[this.i++];
      if (type === 'o') chunk += data;
      else if (type === 'm' && data === 'window') { await flush(); await this.page.evaluate(() => window.stage.reset()); }
    }
    await flush();
  }
}

async function main() {
  const [castFile, cutFile, out, ...rest] = process.argv.slice(2);
  if (!out) { console.error('node render.mjs <take.cast[.gz]> <cut.json> <out.mp4 | --stills dir s… | --plan>'); process.exit(2); }
  const cast = loadCast(castFile);
  const cut = JSON.parse(readFileSync(cutFile, 'utf8'));
  const fps = cut.fps || 30;
  const stills = out === '--stills' ? { dir: rest[0], at: rest.slice(1).map(Number) } : null;

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(path.join(here, 'stage.html')).href);
  const box = await page.evaluate((o) => window.stage.init(o), { cols: cast.head.width, rows: cast.head.height, fontSize: cut.fontSize || 18 });
  console.log(`window ${Math.round(box.width)}×${Math.round(box.height)} px at ${Math.round(box.top)}`);
  const parts = plan(cut, cast.marks, await findShown(page, cut, cast));
  if (out === '--plan') {                         // the parts with their times in the take, to check a cut
    for (const p of parts) console.log(p.kind === 'card' ? `card ${p.seconds} s` : `${p.scene.name.padEnd(12)} ${p.from.toFixed(2).padStart(7)} … ${p.to.toFixed(2).padStart(7)}  ${(p.to - p.from).toFixed(1).padStart(5)} s  ${p.note}`);
    console.log(`${(parts.reduce((s, p) => s + (p.kind === 'card' ? p.seconds : p.to - p.from), 0)).toFixed(1)} s in all`);
    await browser.close();
    return;
  }
  const set = (s) => page.evaluate((x) => window.stage.set(x), s);
  const player = new Player(page, cast.events);

  let ffmpeg = null;
  if (!stills) {
    ffmpeg = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  } else mkdirSync(stills.dir, { recursive: true });

  const total = parts.reduce((s, p) => s + Math.round((p.kind === 'card' ? p.seconds : p.to - p.from) * fps), 0);
  console.log(`${parts.length} parts, ${(total / fps).toFixed(1)} s`);
  let frame = 0, last = null;
  const wanted = stills ? new Set(stills.at.map((s) => Math.round(s * fps))) : null;
  for (const p of parts) {
    const n = Math.round((p.kind === 'card' ? p.seconds : p.to - p.from) * fps);
    if (p.kind === 'card') await set({ card: p.card, cardOpacity: 1, windowOpacity: 0, captionOpacity: 0, noteOpacity: 0 });
    else {
      await set({ card: '', cardOpacity: 0, windowOpacity: 1, captionOpacity: 1, title: p.scene.title, sub: p.scene.sub || '', note: p.note, noteOpacity: 0 });
      await player.to(p.from);
    }
    const dissolve = last ? Math.round((cut.dissolve ?? 0.4) * fps) : 0;
    if (dissolve) await set({ fade: `data:image/jpeg;base64,${last.toString('base64')}`, fadeOpacity: 1 });
    for (let f = 0; f < n; f++, frame++) {
      const keep = !wanted || wanted.has(frame);
      if (p.kind === 'take') await player.to(p.from + f / fps);
      if (!keep && !(f === n - 1 && wanted)) continue;
      const s = {};
      s.fadeOpacity = f < dissolve ? 1 - ease((f + 1) / dissolve) : 0;
      if (p.note) { const t = f / fps; s.noteOpacity = t < 0.3 ? ease(t / 0.3) : t < 2.4 ? 1 : 1 - ease((t - 2.4) / 0.5); }
      if (p.first) s.cardOpacity = ease(f / (0.8 * fps));
      if (p.last) s.cardOpacity = 1 - ease((f - (n - 1.2 * fps)) / (1.2 * fps));
      await set(s);
      await page.evaluate(() => window.stage.settle());
      const shot = await page.screenshot({ type: stills ? 'png' : 'jpeg', quality: stills ? undefined : 93 });
      if (stills) {
        if (keep) writeFileSync(path.join(stills.dir, `frame-${(frame / fps).toFixed(1).padStart(6, '0')}.png`), shot);
        last = shot;
        continue;
      }
      if (!ffmpeg.stdin.write(shot)) await once(ffmpeg.stdin, 'drain');
      last = shot;
      if (frame % (fps * 10) === 0) console.log(`  ${(frame / fps).toFixed(0)} s / ${(total / fps).toFixed(0)} s`);
    }
    if (stills) last = null;                      // (stills: no dissolve from a frame that was not taken)
  }
  if (ffmpeg) { ffmpeg.stdin.end(); await once(ffmpeg, 'close'); console.log(`→ ${out}`); }
  await browser.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
