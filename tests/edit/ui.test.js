// The image editor's page in a real browser (Chromium through Playwright): the mouse on the frame, the shape menu, turn and mirror,
// the dial, the Convert tab, saving, Cancel, the Face Blur tab (faces found, left out, drawn over, how they are hidden, and the
// saved picture – in which the face detector itself finds none of the hidden faces) – and that a phone-sized window does not
// scroll sideways.
//   node tests/edit/ui.test.js      (needs the Node package "playwright" and a browser it can start; tests/test-editserver.zsh
//                                    runs it where both are there and says so where they are not)
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..', '..');
const P = require(path.join(__dirname, 'pixels.js'));
const F = require(path.join(ROOT, 'lib', 'edit', 'web', 'faces.js'));
const D = fs.mkdtempSync(path.join(os.tmpdir(), 'lotus-edit-ui.'));
let passed = 0, failed = 0;
async function test(name, fn) {
  try { await fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e && e.stack || e).split('\n').slice(0, 6).join('\n      ')); }
}
function ok(cond, what) { if (!cond) throw new Error(what || 'not true'); }
function near(a, b, eps, what) { ok(Math.abs(a - b) <= (eps === undefined ? 1.5 : eps), (what || 'value') + ': ' + a + ' is not ' + b); }

// a PNG without any program
const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t.push(c >>> 0); } return t; })();
const crc32 = (b) => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function png(file, w, h, fn) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const [r, g, b] = fn(x, y), i = y * (w * 3 + 1) + 1 + x * 3; raw[i] = r; raw[i + 1] = g; raw[i + 2] = b; }
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
const pngSize = (file) => { const b = fs.readFileSync(file); return [b.readUInt32BE(16), b.readUInt32BE(20)]; };

// an editor process
function start(image, lang) {
  const proc = spawn('python3', ['-B', path.join(ROOT, 'lib', 'edit', 'editor.py'), image, '--no-open'], {
    env: Object.assign({}, process.env, { LOTUS_EDIT_DATA: path.join(D, 'data'), LOTUS_EDIT_NO_SHOW: '1', LOTUS_LANG: lang || 'en', LOTUS_IMG_LAST: path.join(D, 'last'), LOTUS_EDIT_IDLE: '30' })
  });
  let out = '';
  proc.stdout.on('data', (d) => { out += d; });
  proc.stderr.on('data', (d) => { out += d; });
  const exited = new Promise((res) => proc.on('exit', (code) => res(code)));
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      const m = out.replace(/\x1b\[[0-9;]*m/g, '').match(/http:\/\/127\.0\.0\.1:\d+\/[\w-]+\//);
      if (m) { clearInterval(iv); resolve({ url: m[0], proc, exited, out: () => out }); }
      else if (Date.now() - t0 > 20000) { clearInterval(iv); proc.kill(); reject(new Error('the editor did not start: ' + out)); }
    }, 50);
  });
}

(async () => {
  fs.mkdirSync(path.join(D, 'pics'));
  const image = path.join(D, 'pics', 'shot.png');
  png(image, 800, 600, (x, y) => [x % 256, y % 256, 90]);
  const browser = await chromium.launch();
  const ed = await start(image);
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const problems = [];
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') problems.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));
  await page.goto(ed.url);
  await page.waitForFunction(() => window.__lotus && window.__lotus.state);
  const S = () => page.evaluate(() => JSON.parse(JSON.stringify(window.__lotus.state)));
  const K = () => page.evaluate(() => { const L = window.__lotus.layout(); return { k: L.k, ox: L.ox, oy: L.oy }; });
  const box = (sel) => page.locator(sel).boundingBox();
  // (the page draws on the next frame: wait for it before asking what it shows)
  const frame = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  const reset = async () => { await frame(); if (await page.locator('#reset').isVisible()) await page.locator('#reset').click(); await frame(); };
  const drag = async (from, to, steps) => { await page.mouse.move(from[0], from[1]); await page.mouse.down(); await page.mouse.move(to[0], to[1], { steps: steps || 8 }); await page.mouse.up(); };

  await test('the page opens without an error: the picture, its name and size, nothing to save yet', async () => {
    ok(problems.length === 0, problems.join('\n'));
    const s = await S();
    ok(s.W === 800 && s.H === 600, 'size ' + s.W + 'x' + s.H);
    ok(await page.textContent('#title') === 'shot.png');
    ok((await page.textContent('#subtitle')).includes('PNG · 800 × 600'), await page.textContent('#subtitle'));
    ok(await page.getAttribute('#done', 'aria-disabled') === 'true', 'Done waits for a change');
    ok(await page.locator('#reset').isHidden(), 'no Reset yet');
    ok((await page.textContent('#size')) === '800 × 600');
  });

  await test('the frame shows what the pointer would do: corners resize, inside moves, outside nothing', async () => {
    const f = await box('#frame');
    const cursor = async (x, y) => { await page.mouse.move(x, y); return page.evaluate(() => document.getElementById('stage').style.cursor); };
    ok(await cursor(f.x + f.width - 2, f.y + f.height - 2) === 'nwse-resize');
    ok(await cursor(f.x + 2, f.y + f.height - 2) === 'nesw-resize');
    ok(await cursor(f.x + f.width / 2, f.y + 2) === 'ns-resize');
    ok(await cursor(f.x + 2, f.y + f.height / 2) === 'ew-resize');
    ok(await cursor(f.x + f.width / 2, f.y + f.height / 2) === 'move');
  });

  await test('dragging a corner crops by as much as the pointer moved', async () => {
    const { k } = await K(), f = await box('#frame');
    await drag([f.x + f.width - 2, f.y + f.height - 2], [f.x + f.width - 2 - 100, f.y + f.height - 2 - 60]);
    const c = (await S()).crop;
    near(c.w, 800 - 100 / k, 3, 'width'); near(c.h, 600 - 60 / k, 3, 'height'); near(c.x, 0, 0.01); near(c.y, 0, 0.01);
    ok(await page.getAttribute('#done', 'aria-disabled') === 'false', 'Done is ready');
    ok(await page.locator('#reset').isVisible(), 'Reset shows');
    ok((await page.textContent('#size')) === `${Math.round(c.w)} × ${Math.round(c.h)}`, await page.textContent('#size'));
  });

  await test('dragging inside moves the frame, and it stops at the edge of the picture', async () => {
    const { k } = await K(), before = (await S()).crop, f = await box('#frame');
    await drag([f.x + f.width / 2, f.y + f.height / 2], [f.x + f.width / 2 + 30, f.y + f.height / 2 + 20]);
    const c = (await S()).crop;
    near(c.x, before.x + 30 / k, 3); near(c.y, before.y + 20 / k, 3); near(c.w, before.w, 0.01);
    await drag([f.x + f.width / 2 + 30, f.y + f.height / 2 + 20], [f.x + 900, f.y + 900]);
    const e = (await S()).crop;
    near(e.x + e.w, 800, 0.01, 'right edge'); near(e.y + e.h, 600, 0.01, 'bottom edge');
  });

  await test('Reset gives the whole picture back', async () => {
    await reset();
    const s = await S();
    ok(s.crop.w === 800 && s.crop.h === 600 && s.crop.x === 0 && s.crop.y === 0);
    ok(await page.getAttribute('#done', 'aria-disabled') === 'true');
  });

  await test('the shape menu: a square, 16:9, portrait and landscape', async () => {
    await page.click('#ratio');
    ok(await page.locator('#menu').isVisible());
    ok((await page.locator('#menu button[aria-checked="true"]').first().textContent()) === 'Freeform');
    await page.click('#menu button:has-text("Square")');
    ok(await page.locator('#menu').isHidden());
    let c = (await S()).crop;
    near(c.w, c.h, 1.01, 'square'); near(c.w, 600, 0.01, 'as big as it can be');
    ok((await page.textContent('#ratio-label')) === 'Square');
    await page.click('#ratio'); await page.click('#menu button:has-text("16:9")');
    c = (await S()).crop;
    near(c.w / c.h, 16 / 9, 0.01, '16:9');
    await page.click('#ratio'); await page.click('#menu button:has-text("Portrait")');
    c = (await S()).crop;
    near(c.w / c.h, 9 / 16, 0.01, '9:16'); ok((await page.textContent('#ratio-label')) === '9:16');
    await page.click('#ratio'); await page.click('#menu button:has-text("Freeform")');
    ok((await S()).ratio === null);
  });

  await test('a handle keeps the shape while it is dragged', async () => {
    await reset();
    await page.click('#ratio'); await page.click('#menu button:has-text("4:3")');
    const f = await box('#frame');
    await drag([f.x + f.width - 2, f.y + f.height - 2], [f.x + f.width - 120, f.y + f.height - 40]);
    const c = (await S()).crop;
    near(c.w / c.h, 4 / 3, 0.01, '4:3 after the drag'); ok(c.w < 790, 'smaller');
  });

  await test('turn left and mirror: the frame turns with the picture; R and F do the same', async () => {
    await reset();
    await page.click('#turn');
    let s = await S();
    ok(s.crop.w === 600 && s.crop.h === 800 && s.m.join() === '0,1,-1,0', JSON.stringify(s.m));
    await page.click('#turn'); await page.click('#turn'); await page.click('#turn');
    ok((await S()).m.join() === '1,0,0,1');
    await page.click('#flip');
    ok((await S()).m[0] === -1 && await page.locator('#flip.on').count() === 1, 'mirrored and lit');
    await page.keyboard.press('f');
    ok((await S()).m[0] === 1, 'F mirrors back');
    await page.keyboard.press('r');
    ok((await S()).crop.w === 600, 'R turns');
    await reset();
  });

  await test('the dial: drag to straighten (left is clockwise), the crop stays inside, a double click resets', async () => {
    const d = await box('#dial'), y = d.y + d.height / 2;
    await drag([d.x + d.width / 2, y], [d.x + d.width / 2 - 90, y]);
    let s = await S();
    near(s.angle, 10, 0.3, 'angle');
    ok((await page.textContent('#angle')) === '+10°', await page.textContent('#angle'));
    ok(await page.evaluate(() => window.__lotus.G.inside(window.__lotus.state, window.__lotus.state.crop)), 'inside the picture');
    ok(s.crop.w < 800, 'the frame had to shrink');
    await page.locator('#dial').dblclick();
    s = await S();
    ok(s.angle === 0 && s.crop.w === 800, 'back at 0°, the frame as before');
    await page.locator('#dial').focus();
    await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight');
    near((await S()).angle, 1, 0.01, 'two arrow keys: 1°');
    await reset();
    ok((await S()).angle === 0);
  });

  await test('Convert: formats, quality only where it matters, the name and size of what will be saved', async () => {
    await reset();
    const f = await box('#frame'), { k } = await K();
    await drag([f.x + f.width - 2, f.y + f.height - 2], [f.x + f.width - 2 - 60, f.y + f.height - 2 - 45]);
    await page.click('#tab-convert');
    ok(await page.locator('#panel-crop').isHidden() && await page.locator('#panel-convert').isVisible());
    ok((await page.locator('#formats button[aria-checked="true"]').textContent()) === 'PNG', 'the format of the picture');
    ok(await page.locator('#quality-group').isHidden(), 'PNG has no quality');
    await page.click('#formats button:has-text("JPEG")');
    ok(await page.locator('#quality-group').isVisible(), 'JPEG has');
    await page.waitForFunction(() => document.getElementById('out-name').textContent === 'shot edited.jpg');
    await page.click('#sizes button:has-text("640 px")');
    const dims = await page.textContent('#out-dims');
    ok(/^640 × \d+ px$/.test(dims) || /^\d+ × 640 px$/.test(dims), dims);
    await page.click('#sizes button:has-text("Keep the size")');
    await page.click('#formats button:has-text("PNG")');
    await page.waitForFunction(() => document.getElementById('out-name').textContent === 'shot edited.png');
  });

  await test('Done saves the cropped picture next to the original; the sheet says where; Keep editing goes on', async () => {
    const c = (await S()).crop, want = [Math.round(c.x + c.w) - Math.round(c.x), Math.round(c.y + c.h) - Math.round(c.y)];
    await page.click('#done');
    await page.waitForSelector('#veil:not([hidden])', { timeout: 20000 });
    ok((await page.textContent('#sheet-name')) === 'shot edited.png', await page.textContent('#sheet-name'));
    const file = path.join(D, 'pics', 'shot edited.png');
    ok(fs.existsSync(file), 'the file is there');
    const [w, h] = pngSize(file);
    near(w, want[0], 1); near(h, want[1], 1);
    ok(fs.existsSync(image) && pngSize(image).join() === '800,600', 'the original is as it was');
    await page.click('#sheet-more');
    ok(await page.locator('#veil').isHidden());
    await page.click('#done');                                           // nothing changed since: it shows what was saved, no copy
    await page.waitForSelector('#veil:not([hidden])', { timeout: 20000 });
    ok((await page.textContent('#sheet-name')) === 'shot edited.png' && !fs.existsSync(path.join(D, 'pics', 'shot edited (2).png')), 'no copy of the same picture');
    await page.click('#sheet-more');
    await page.click('#tab-crop'); await page.click('#flip');            // a change: a new picture, never over a file
    await page.click('#done');
    await page.waitForSelector('#veil:not([hidden])', { timeout: 20000 });
    ok((await page.textContent('#sheet-name')) === 'shot edited (2).png', 'never over a file: ' + await page.textContent('#sheet-name'));
    await page.click('#sheet-more');
  });

  await test('without a change Done says so and saves nothing', async () => {
    await page.click('#tab-crop'); await reset();
    await page.click('#tab-convert');
    const before = fs.readdirSync(path.join(D, 'pics')).length;
    await page.click('#done', { force: true });
    ok((await page.textContent('#toast')).startsWith('Nothing to save yet'), await page.textContent('#toast'));
    ok(fs.readdirSync(path.join(D, 'pics')).length === before);
    await page.click('#tab-crop');
  });

  await test('Esc closes a menu; Enter is Done', async () => {
    await page.click('#ratio'); await page.keyboard.press('Escape');
    ok(await page.locator('#menu').isHidden());
    await page.click('#turn');
    await page.keyboard.press('Enter');
    await page.waitForSelector('#veil:not([hidden])', { timeout: 20000 });
    await page.keyboard.press('Escape');
    ok(await page.locator('#veil').isHidden(), 'Esc is Keep editing');
  });

  await test('Cancel with unsaved changes asks; Discard closes the editor and the program ends', async () => {
    await reset(); await page.click('#flip');
    await page.click('#cancel');
    ok(await page.locator('#ask').isVisible());
    await page.click('#ask-no');
    ok(await page.locator('#ask').isHidden() && ed.proc.exitCode === null);
    await page.click('#cancel'); await page.click('#ask-yes');
    await page.waitForSelector('#gone:not([hidden])');
    const code = await Promise.race([ed.exited, new Promise((r) => setTimeout(() => r('still running'), 8000))]);
    ok(code === 0, 'exit ' + code);
    ok(/3 pictures saved\./.test(ed.out()) || /pictures? saved\./.test(ed.out()), ed.out());
  });
  await ctx.close();

  await test('in German; and a phone-sized window does not scroll sideways', async () => {
    const de = await start(image, 'de');
    const c2 = await browser.newContext({ viewport: { width: 390, height: 780 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
    const p2 = await c2.newPage();
    await p2.goto(de.url);
    await p2.waitForFunction(() => window.__lotus && window.__lotus.state);
    ok((await p2.textContent('#cancel')) === 'Abbrechen' && (await p2.textContent('#done')) === 'Fertig');
    ok((await p2.textContent('.tab[data-tab="convert"] span')) === 'Umwandeln' && (await p2.textContent('.tab[data-tab="faces"] span')) === 'Face Blur');
    for (const tab of ['crop', 'faces', 'convert']) {
      await p2.click('#tab-' + tab);
      const wide = await p2.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      ok(wide <= 0, tab + ' is ' + wide + 'px too wide');
    }
    await p2.click('#tab-crop');
    const f = await p2.locator('#frame').boundingBox(), s = await p2.locator('#stage').boundingBox();
    ok(f.x >= s.x && f.x + f.width <= s.x + s.width + 1 && f.y >= s.y - 1 && f.y + f.height <= s.y + s.height + 1, 'the picture is inside its stage');
    await c2.close();
    await fetchQuit(de.url);
    await de.exited;
  });

  // ── Face Blur ──
  const model = F.load(fs.readFileSync(path.join(ROOT, 'lib', 'edit', 'web', 'faces.bin')));
  const scene = P.scene(), sceneFile = path.join(D, 'pics', 'people.png');
  P.writePng(sceneFile, scene.picture);
  const fbEd = await start(sceneFile);
  const c3 = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  const p3 = await c3.newPage();
  const problems3 = [];
  p3.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') problems3.push(m.type() + ': ' + m.text()); });
  p3.on('pageerror', (e) => problems3.push('pageerror: ' + e.message));
  await p3.goto(fbEd.url);
  await p3.waitForFunction(() => window.__lotus && window.__lotus.state);
  const FB = () => p3.evaluate(() => { const f = window.__lotus.fb; return { status: f.status, error: f.error, on: f.faces.map((x) => x.on), boxes: f.faces.map((x) => x.box), strokes: f.strokes.length, type: f.type, strength: f.strength, drawing: f.drawing }; });
  const frame3 = () => p3.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  let saved = 0;
  async function save() {                                    // Done → the saved picture, read back
    await p3.click('#done');
    await p3.waitForSelector('#veil:not([hidden])', { timeout: 30000 });
    const name = await p3.textContent('#sheet-name');
    await p3.click('#sheet-more');
    saved++;
    return P.readPng(path.join(D, 'pics', name));
  }
  // the faces the detector finds in a picture → [{ cx, cy, w }]
  const facesIn = (pic) => F.detect(model, pic.data, pic.w, pic.h).map((f) => ({ cx: f.x + f.w / 2, cy: f.y + f.h / 2, w: f.w }));
  const near2 = (a, b, d) => Math.hypot(a.cx - b.cx, a.cy - b.cy) < d;
  async function every(on) {                                 // every face hidden (or every one left out)
    for (let i = 0; i < 2 && (await FB()).on.some((o) => o !== on); i++) await p3.click('#fb-all');
    ok((await FB()).on.every((o) => o === on), 'every face ' + (on ? 'hidden' : 'left out'));
  }
  async function upright() {                                 // the picture as it was opened
    await p3.click('#tab-crop'); await frame3();
    if (await p3.locator('#reset').isVisible()) await p3.click('#reset');
    await frame3();
  }

  await test('Face Blur: the tab looks for faces on this computer and finds the three of the picture – each hidden, with a ring', async () => {
    await p3.click('#tab-faces');
    await p3.waitForFunction(() => window.__lotus.fb.status === 'done' || window.__lotus.fb.status === 'failed', null, { timeout: 60000 });
    const f = await FB();
    ok(f.status === 'done', f.status + ' ' + f.error);
    ok(f.boxes.length === 3, f.boxes.length + ' faces');
    scene.faces.forEach((want) => ok(f.boxes.some((b) => near2({ cx: b.x + b.w / 2, cy: b.y + b.h / 2 }, want, 0.2 * want.w)), 'the face at ' + want.cx + ', ' + want.cy));
    ok(f.on.every(Boolean), 'all of them hidden');
    ok((await p3.textContent('#fb-status-text')) === '3 faces found', await p3.textContent('#fb-status-text'));
    ok(await p3.locator('.fb-mark').count() === 3 && await p3.locator('.fb-face').count() === 3, 'three rings, three faces in the row');
    ok(await p3.locator('.fb-mark[aria-pressed="true"]').count() === 3);
    ok((await p3.textContent('#fb-all')) === 'Show all');
    ok(problems3.length === 0, problems3.join('\n'));
  });

  await test('Face Blur: tapping a ring or a face of the row leaves it out, again hides it; Show all and Blur all', async () => {
    await p3.locator('.fb-mark').nth(0).click();
    ok((await FB()).on.join() === 'false,true,true');
    ok((await p3.getAttribute('.fb-face >> nth=0', 'aria-pressed')) === 'false', 'the row says so too');
    ok((await p3.textContent('#fb-all')) === 'Blur all');
    await p3.locator('.fb-face').nth(0).click();
    ok((await FB()).on.join() === 'true,true,true');
    await p3.click('#fb-all');
    ok((await FB()).on.join() === 'false,false,false' && (await p3.textContent('#fb-all')) === 'Blur all');
    await p3.click('#fb-all');
    ok((await FB()).on.join() === 'true,true,true');
  });

  await test('Face Blur: the kinds of hiding and the strength; black needs no strength', async () => {
    await p3.click('#fb-types >> text=Pixelate');
    ok((await FB()).type === 'pixel' && await p3.locator('#fb-strength-box').isVisible());
    await p3.click('#fb-types >> text=Black');
    ok((await FB()).type === 'solid' && await p3.locator('#fb-strength-box').isHidden());
    await p3.click('#fb-types >> text=Blur');
    await p3.locator('#fb-strength').fill('90');
    near((await FB()).strength, 0.9, 1e-9, 'strength');
    await p3.locator('#fb-strength').fill('80');
  });

  await test('Face Blur: the pencil draws over the picture, Undo takes the line back, Esc puts the pencil away', async () => {
    await p3.click('#fb-draw');
    ok((await FB()).drawing && await p3.locator('#fb-brushes').isVisible(), 'drawing, with the brushes');
    ok((await p3.textContent('#fb-hint')) === 'Draw over what should be hidden');
    const v = await p3.locator('#fb-view').boundingBox();
    await p3.mouse.move(v.x + v.width * 0.05, v.y + v.height * 0.1); await p3.mouse.down();
    await p3.mouse.move(v.x + v.width * 0.3, v.y + v.height * 0.12, { steps: 6 }); await p3.mouse.up();
    ok((await FB()).strokes === 1 && await p3.locator('#fb-undo').isEnabled());
    await p3.click('#fb-undo');
    ok((await FB()).strokes === 0 && await p3.locator('#fb-undo').isDisabled());
    await p3.keyboard.press('Escape');
    ok(!(await FB()).drawing && await p3.locator('#fb-brushes').isHidden());
    await p3.keyboard.press('d');
    ok((await FB()).drawing, 'D takes the pencil');
    await p3.keyboard.press('d');
    ok(!(await FB()).drawing);
  });

  await test('Face Blur: the saved picture – no hidden face can be found in it, the face that was left out is as it was, the rest of the picture too', async () => {
    await p3.click('#fb-types >> text=Black');
    await p3.locator('.fb-mark').nth(0).click();                                     // the leftmost face stays as it is
    const kept = (await FB()).boxes[0], kc = { cx: kept.x + kept.w / 2, cy: kept.y + kept.h / 2, w: kept.w };
    await p3.click('#tab-convert');
    await p3.click('#formats >> text=PNG');
    const out = await save();
    ok(out.w === 640 && out.h === 400, out.w + ' × ' + out.h);
    const found = facesIn(out);
    ok(found.length === 1 && near2(found[0], kc, 0.2 * kc.w), 'only the face that was left out: ' + JSON.stringify(found) + ' – the page: ' + JSON.stringify(await FB()));
    // far from the faces nothing changed (a PNG keeps every pixel)
    const shapes = await p3.evaluate(() => window.__lotus.fb.faces.filter((f) => f.on).map((f) => f.shape));
    let same = 0, all = 0;
    for (let y = 0; y < 400; y += 3) for (let x = 0; x < 640; x += 3) {
      if (shapes.some((e) => ((x - e.x) / (e.rx + 3)) ** 2 + ((y - e.y) / (e.ry + 3)) ** 2 < 1)) continue;
      all++; const i = (y * 640 + x) * 4;
      if (out.data[i] === scene.picture.data[i] && out.data[i + 1] === scene.picture.data[i + 1] && out.data[i + 2] === scene.picture.data[i + 2]) same++;
    }
    ok(same === all, (all - same) + ' of ' + all + ' pixels outside the faces changed');
    const e = shapes[0], i0 = (Math.round(e.y) * 640 + Math.round(e.x)) * 4;
    ok(out.data[i0] + out.data[i0 + 1] + out.data[i0 + 2] === 0, 'black where a face was');
  });

  await test('Face Blur: mirrored and straightened – nothing of the faces is left in what is saved, and the rings are where the faces are now', async () => {
    await upright();
    await p3.click('#tab-faces'); await every(true);
    await p3.click('#fb-types >> text=Black');
    await p3.click('#tab-crop');
    ok(await p3.locator('#photo .photo-view').isVisible() && (await p3.evaluate(() => document.getElementById('img').style.visibility)) === 'hidden', 'Crop shows the picture with the hidden faces');
    await p3.click('#flip');
    await p3.locator('#dial').focus();
    for (let i = 0; i < 12; i++) await p3.keyboard.press('ArrowRight');           // 6°
    await frame3();
    await p3.click('#tab-faces'); await frame3();
    const where = await p3.evaluate(() => {          // the middle of each ring, in pixels of what is saved
      const L = window.__lotus.faceView(), st = document.getElementById('fb-stage').getBoundingClientRect();
      return [].map.call(document.querySelectorAll('.fb-mark'), (b) => { const r = b.getBoundingClientRect(); return { x: (r.left + r.width / 2 - st.left - L.ox) / L.k, y: (r.top + r.height / 2 - st.top - L.oy) / L.k, hidden: b.hidden }; });
    });
    await p3.click('#tab-convert');
    const out = await save(), found = facesIn(out);
    ok(found.length === 0, 'no face can be found: ' + JSON.stringify(found));
    where.filter((w) => !w.hidden).forEach((w) => {
      const i = (Math.round(w.y) * out.w + Math.round(w.x)) * 4;
      ok(out.data[i] + out.data[i + 1] + out.data[i + 2] === 0, 'black under the ring at ' + Math.round(w.x) + ', ' + Math.round(w.y));
    });
    await p3.click('#tab-faces'); await every(false);                                // the same picture, nothing hidden
    await p3.click('#tab-convert');
    const plain = await save(), seen = facesIn(plain);
    ok(seen.length === 3, seen.length + ' faces in the picture that hides none');
    where.filter((w) => !w.hidden).forEach((w) => ok(seen.some((f) => Math.hypot(f.cx - w.x, f.cy - w.y) < 0.25 * f.w), 'the ring at ' + Math.round(w.x) + ', ' + Math.round(w.y) + ' is on a face'));
    ok(problems3.length === 0, problems3.join('\n'));
  });

  await test('Face Blur: turned a quarter – what is saved is black where the faces are now (the geometry worked out here in Node)', async () => {
    await upright();
    await p3.click('#tab-faces'); await every(true);
    await p3.click('#fb-types >> text=Black');
    await p3.click('#tab-crop'); await p3.click('#turn'); await frame3();
    const st = await p3.evaluate(() => JSON.parse(JSON.stringify(window.__lotus.state)));
    const shapes = await p3.evaluate(() => window.__lotus.fb.faces.map((f) => f.shape));
    await p3.click('#tab-convert');
    const out = await save(), G = require(path.join(ROOT, 'lib', 'edit', 'web', 'geometry.js')), o = G.output(st, 0), m = o.matrix;
    ok(out.w === o.width && out.h === o.height, 'the size the geometry says: ' + out.w + ' × ' + out.h);
    shapes.forEach((e) => {
      const x = Math.round(m.a * e.x + m.c * e.y + m.e), y = Math.round(m.b * e.x + m.d * e.y + m.f), i = (y * out.w + x) * 4;
      ok(x >= 0 && y >= 0 && x < out.w && y < out.h && out.data[i] + out.data[i + 1] + out.data[i + 2] === 0, 'black at ' + x + ', ' + y);
    });
  });

  await test('Face Blur: blurred at the strength it starts with – the detector finds none of the faces in what is saved', async () => {
    await upright();
    await p3.click('#tab-faces'); await every(true);
    await p3.click('#fb-types >> text=Blur');
    near((await FB()).strength, 0.8, 1e-9, 'the strength it starts with');
    await p3.click('#tab-convert');
    const out = await save(), found = facesIn(out);
    ok(found.length === 0, JSON.stringify(found));
  });

  await test('Face Blur: a picture with hidden faces says so in its name and is saved without the camera data', async () => {
    await upright();
    await p3.click('#tab-faces'); await every(true);
    await p3.click('#fb-types >> text=Pixelate');                                    // (something new: Done saves again)
    const requests = [];
    p3.on('request', (r) => { if (r.url().includes('/api/save')) requests.push(r.url()); });
    await p3.click('#tab-convert');
    ok(/^people edited/.test(await p3.textContent('#out-name')), await p3.textContent('#out-name'));
    await save();
    ok(requests.length === 1 && /[?&]edited=1/.test(requests[0]) && /[?&]camera=0/.test(requests[0]), requests.join(' '));
  });

  await c3.close();
  await fetchQuit(fbEd.url);
  await fbEd.exited;

  await test('Face Blur: a crowd – every face is found, the row of faces scrolls by itself and the page stays as wide as the window (a phone too)', async () => {
    const crowd = P.crowd(12, 3), file = path.join(D, 'pics', 'crowd.png');
    P.writePng(file, crowd.picture);
    const cr = await start(file);
    for (const vp of [{ width: 1280, height: 800 }, { width: 390, height: 780 }]) {
      const c4 = await browser.newContext({ viewport: vp, deviceScaleFactor: 1 }), p4 = await c4.newPage();
      await p4.goto(cr.url);
      await p4.waitForFunction(() => window.__lotus && window.__lotus.state);
      await p4.click('#tab-faces');
      await p4.waitForFunction(() => window.__lotus.fb.status === 'done', null, { timeout: 60000 });
      const n = await p4.evaluate(() => window.__lotus.fb.faces.length);
      ok(n === crowd.count, n + ' of ' + crowd.count + ' faces');
      const wide = await p4.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      ok(wide <= 0, vp.width + ': the page is ' + wide + 'px too wide');
      const row = await p4.evaluate(() => { const r = document.getElementById('fb-faces'); return [r.scrollWidth, r.clientWidth]; });
      ok(row[0] > row[1] && row[1] <= vp.width, vp.width + ': the row scrolls inside the window: ' + row.join(' / '));
      const done = await p4.locator('#done').boundingBox();
      ok(done.x + done.width <= vp.width, vp.width + ': Done is in the window');
      await c4.close();
    }
    await fetchQuit(cr.url);
    await cr.exited;
  });

  await browser.close();
  ed.proc.kill();
  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('✗ the test stopped: ' + (e && e.stack || e)); process.exit(1); });

function fetchQuit(url) {
  return new Promise((resolve) => {
    const u = new URL(url + 'api/quit');
    require('http').request({ hostname: u.hostname, port: u.port, path: u.pathname, method: 'POST', headers: { 'X-Lotus-Edit': '1', 'Content-Length': 0 } }, (r) => { r.resume(); r.on('end', resolve); }).on('error', resolve).end();
  });
}
