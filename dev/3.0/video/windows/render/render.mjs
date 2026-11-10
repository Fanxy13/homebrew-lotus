#!/usr/bin/env node
// The Lotus for Windows video: a take of record.py (an asciicast) replayed in xterm.js in Chromium, frame by frame,
// cut as the cut file says – a camera that comes close to what is happening, captions, a dissolve between parts, a
// note where time is left out, the title and end cards – encoded with ffmpeg, with a sound track from audio.py (music
// made for the video, the keys of the take, a swish between scenes). Every frame of a scene is the terminal as it was
// at that moment of the take.
//
//   node render.mjs <take.cast[.gz]> <cut.json> <out.mp4>
//   node render.mjs <take.cast[.gz]> <cut.json> --stills <dir> <second> [<second> …]   still frames, to look at
//   node render.mjs <take.cast[.gz]> <cut.json> --plan                                the parts and their times
import { readFileSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.join(here, '../../../../..');

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
  return `${Math.round(seconds / 30) / 2} minutes later`;
}

const ease = (x) => { x = Math.min(1, Math.max(0, x)); return x * x * (3 - 2 * x); };
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// The lotus of the start screen (logos/lotus.txt), from gold at the top to pink at the bottom, as Lotus paints it
function lotusArt() {
  const rows = readFileSync(path.join(repo, 'logos/lotus.txt'), 'utf8').replace(/\s+$/, '').split('\n');
  const mix = (a, b, k) => a.map((x, i) => Math.round(x + (b[i] - x) * k));
  const gold = [233, 196, 106], pink = [242, 167, 195];
  return `<pre class="art">${rows.map((r, i) => `<span style="color:rgb(${mix(gold, pink, i / (rows.length - 1)).join(',')})">${esc(r) || ' '}</span>`).join('')}</pre>`;
}

function cardHtml(c, kind) {
  const art = lotusArt();
  if (kind === 'title') return `${art}<div class="big">${c.title}</div><div class="tag">${c.tag}</div><div class="small">${esc(c.small)}</div>`;
  return `${art.replace('class="art"', 'class="art" style="font-size:9px;margin-bottom:22px"')}<div class="big" style="font-size:104px">${c.title}</div>`
    + `<div class="tag">${c.tag}</div><div class="cmd" data-text="${esc(c.cmd)}"></div><div class="small">${esc(c.small)}</div>`;
}

// The video, part by part: cards and stretches of the take
function plan(cut, marks, shown) {
  const parts = [{ kind: 'card', card: 'title', seconds: cut.title.seconds }];
  cut.scenes.forEach((scene, i) => {
    let prev = null;
    scene.parts.forEach(([a, b], k) => {
      const from = at(a, marks, shown), to = at(b, marks, shown);
      if (!(to > from)) throw new Error(`${scene.name}: ${JSON.stringify(a)} … ${JSON.stringify(b)} is empty`);
      const gap = prev === null ? 0 : from - prev;
      parts.push({ kind: 'take', scene, index: i, first: k === 0, from, to, note: gap > 3 ? later(gap) : '' });
      prev = to;
    });
  });
  parts.push({ kind: 'card', card: 'end', seconds: cut.end.seconds });
  let v = 0;
  for (const p of parts) { p.start = v; v += p.kind === 'card' ? p.seconds : p.to - p.from; }
  return { parts, total: v };
}

// The sound track's cues, in seconds of the video: the keys typed in the take, a swish where a scene begins, a chime
// where a ✓ comes, and the cards
function cues(parts, events) {
  const list = [];
  for (const p of parts) {
    if (p.kind === 'card') { list.push({ t: p.start, k: p.card }); continue; }
    if (p.first) list.push({ t: p.start, k: 'swish' });
    for (const [t, type, data] of events) {
      if (t <= p.from || t > p.to) continue;
      if (type === 'i') list.push({ t: p.start + t - p.from, k: 'key', d: data });
      else if (type === 'o' && data.includes('✓')) list.push({ t: p.start + t - p.from, k: 'chime' });
    }
  }
  list.sort((a, b) => a.t - b.t);
  const out = []; let lastChime = -9;
  for (const c of list) {
    if (c.k === 'chime') { if (c.t - lastChime < 1.2) continue; lastChime = c.t; }
    out.push(c);
  }
  return out;
}

// The keys worth showing as keycaps: what moves in a list, answers it or stops something – typed words are on the
// screen already
const KEYCAPS = { '\r': 'Enter', '\x1b': 'Esc', '\x1b[A': '↑', '\x1b[B': '↓', '\x1b[C': '→', '\x1b[D': '←', '\x7f': '⌫',
  '\x03': 'Ctrl C', '\x0c': 'Ctrl L' };
function keycap(data) {
  if (KEYCAPS[data]) return KEYCAPS[data];
  if (data.length > 3 && !data.startsWith('\x1b')) return 'Ctrl V';
  return null;
}

class Player {                                   // the terminal as it was at second t of the take
  constructor(events) { Object.assign(this, { events, i: 0 }); }
  to(t) {
    const ops = []; let chunk = '';
    while (this.i < this.events.length && this.events[this.i][0] <= t) {
      const [, type, data] = this.events[this.i++];
      if (type === 'o') chunk += data;
      else if (type === 'm' && data === 'window') { if (chunk) ops.push(['w', chunk]); chunk = ''; ops.push(['r']); }
    }
    if (chunk) ops.push(['w', chunk]);
    return ops;
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
  const L = await page.evaluate((o) => window.stage.init(o), { cols: cast.head.width, rows: cast.head.height, fontSize: cut.fontSize || 30 });
  console.log(`window ${L.ww}×${L.wh} px, terminal shown at ${(L.s * 100).toFixed(0)} % – the camera up to ${(L.s * L.zmax * 100).toFixed(0)} %`);
  const { parts, total } = plan(cut, cast.marks, await findShown(page, cut, cast));
  if (out === '--plan') {
    for (const p of parts) console.log(p.kind === 'card' ? `${p.start.toFixed(1).padStart(6)}  card ${p.card} ${p.seconds} s`
      : `${p.start.toFixed(1).padStart(6)}  ${p.scene.name.padEnd(12)} ${p.from.toFixed(2).padStart(7)} … ${p.to.toFixed(2).padStart(7)}  ${(p.to - p.from).toFixed(1).padStart(5)} s  ${p.note}`);
    console.log(`${total.toFixed(1)} s in all`);
    await browser.close();
    return;
  }

  const base = stills ? null : out.replace(/\.mp4$/, '');
  let ffmpeg = null;
  if (!stills) {
    ffmpeg = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', `${base}.video.mp4`], { stdio: ['pipe', 'inherit', 'inherit'] });
  } else mkdirSync(stills.dir, { recursive: true });

  const main = new Player(cast.events), scout = new Player(cast.events);
  const inputs = cast.events.filter((e) => e[1] === 'i');
  const n = (p) => Math.round((p.kind === 'card' ? p.seconds : p.to - p.from) * fps);
  const frames = parts.reduce((s, p) => s + n(p), 0);
  const wanted = stills ? new Set(stills.at.map((s) => Math.round(s * fps))) : null;
  const html = { title: cardHtml(cut.title, 'title'), end: cardHtml(cut.end, 'end') };
  const nScenes = cut.scenes.length;
  console.log(`${parts.length} parts, ${(frames / fps).toFixed(1)} s`);
  let frame = 0, last = null, sceneStart = 0, noteStart = 0, prev = null;
  for (const p of parts) {
    const count = n(p);
    const takeAfterTake = p.kind === 'take' && prev?.kind === 'take';
    const dissolve = takeAfterTake ? Math.round((p.first ? 0.45 : 0.3) * fps) : 0;
    let fadeSrc = dissolve && last ? `data:image/jpeg;base64,${last.toString('base64')}` : undefined;
    if (p.kind === 'take') {
      if (p.first) sceneStart = p.start;
      noteStart = p.start;
    }
    for (let f = 0; f < count; f++, frame++) {
      const T = p.start + f / fps;
      const keep = !wanted || wanted.has(frame);
      const o = { T };
      if (p.kind === 'card') {
        const t = f / fps;
        o.card = { kind: p.card, t, html: html[p.card],
          opacity: p.card === 'title' ? 1 : ease(t / 0.6),
          curtain: p.card === 'title' ? 1 - ease(t / 0.5) : ease((t - (p.seconds - 0.7)) / 0.7) };
      } else {
        const tt = p.from + f / fps;
        o.ops = main.to(tt);
        o.ahead = scout.to(Math.min(p.to, tt + 0.45));
        o.cam = { dt: 1 / fps, snap: f === 0 };
        o.cap = { key: p.scene.name, title: p.scene.title, sub: p.scene.sub || '', t: T - sceneStart };
        o.prog = { i: p.index, n: nScenes, t: T - sceneStart, visible: true };
        o.note = { text: p.note, t: T - noteStart };
        o.keys = [];
        for (const [t, , data] of inputs) {                   // (the keys of the last 1.4 s of this part)
          if (t > tt || t < Math.max(p.from, tt - 1.4)) continue;
          const label = keycap(data);
          if (label) o.keys.push([label, tt - t]);
        }
        o.keys = o.keys.slice(-6);
        if (f === 0) o.fade = { src: fadeSrc, o: fadeSrc ? 1 : 0 };
        else if (f < dissolve) o.fade = { o: 1 - ease(f / dissolve) };
        else if (f === dissolve) o.fade = { o: 0 };
        if (prev?.kind === 'card') o.card = { kind: prev.card, t: prev.seconds + T - p.start, html: html[prev.card], opacity: 1 - ease((T - p.start) / 0.6), curtain: 0 };
      }
      if (!keep && wanted) {                       // (stills: everything keeps up, nothing is drawn)
        await page.evaluate((x) => window.stage.frame(x), { ...o, quick: true });
        continue;
      }
      await page.evaluate((x) => window.stage.frame(x), o);
      const shot = await page.screenshot({ type: stills ? 'png' : 'jpeg', quality: stills ? undefined : 94 });
      if (stills) writeFileSync(path.join(stills.dir, `frame-${(frame / fps).toFixed(1).padStart(6, '0')}.png`), shot);
      else if (!ffmpeg.stdin.write(shot)) await once(ffmpeg.stdin, 'drain');
      last = shot;
      if (!stills && frame % (fps * 10) === 0) console.log(`  ${(frame / fps).toFixed(0)} s / ${(frames / fps).toFixed(0)} s`);
    }
    if (stills) last = null;
    prev = p;
  }
  await browser.close();
  if (!ffmpeg) return;
  ffmpeg.stdin.end(); await once(ffmpeg, 'close');

  // the narrator (voice.py: Kokoro, offline) – a line where a card or a scene begins
  const lines = [];
  for (const p of parts) {
    if (p.kind === 'card' && cut[p.card].say) lines.push({ id: p.card, text: cut[p.card].say, t: p.start + (p.card === 'title' ? 0.45 : 0.55) });
    else if (p.kind === 'take' && p.first && p.scene.say) lines.push({ id: p.scene.name, text: p.scene.say, t: p.start + 0.35 });
  }
  let voice = [];
  if (lines.length && process.env.LOTUS_VIDEO_VOICE !== 'off') {
    writeFileSync(`${base}.lines.json`, JSON.stringify(lines));
    const v = spawnSync(process.env.VOICE_PYTHON || 'python3', [path.join(here, 'voice.py'), `${base}.lines.json`, `${base}.voice`], { stdio: 'inherit' });
    if (v.status !== 0) throw new Error('voice.py failed (LOTUS_VIDEO_VOICE=off renders without the narrator)');
    voice = JSON.parse(readFileSync(path.join(`${base}.voice`, 'lines.json'), 'utf8'));
    voice.forEach((l, i) => {
      const next = voice[i + 1];
      if (next && l.t + l.seconds > next.t - 0.2) console.log(`  the line of ${l.id} (${l.seconds.toFixed(1)} s) runs into ${next.id}`);
    });
  }

  // the sound track, then both together
  const all = [...cues(parts, cast.events), ...voice.map((l) => ({ t: l.t, k: 'voice', file: l.file, seconds: l.seconds }))].sort((x, y) => x.t - y.t);
  writeFileSync(`${base}.cues.json`, JSON.stringify({ duration: frames / fps, cues: all }));
  const a = spawnSync('python3', [path.join(here, 'audio.py'), `${base}.cues.json`, `${base}.wav`], { stdio: 'inherit' });
  if (a.status !== 0) throw new Error('audio.py failed');
  const m = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', `${base}.video.mp4`, '-i', `${base}.wav`, '-map', '0:v', '-map', '1:a',
    '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11', '-ar', '48000',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out], { stdio: 'inherit' });
  if (m.status !== 0) throw new Error('ffmpeg could not put the sound in');
  for (const f of [`${base}.video.mp4`, `${base}.wav`]) rmSync(f, { force: true });
  console.log(`→ ${out}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
