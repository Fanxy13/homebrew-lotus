// Lotus website – animated terminal demo (pure DOM, pauses when off screen).
// The logo is read from logos/lotus.txt, the themes from data/themes.tsv and the blooming lotus of
// /bg remove from data/bloom.txt – the same files Lotus uses.
(() => {
  const term = document.getElementById('terminal');
  if (!term) return;
  const screen = term.querySelector('.screen');
  const logoEl = term.querySelector('.logo');
  const infoEl = term.querySelector('.info');
  const outEl = term.querySelector('.output');
  const settingsEl = term.querySelector('.settings');
  const promptEl = term.querySelector('.promptline');
  const steps = document.querySelectorAll('.demo-caption .step');

  const HELLOS = ['Bonjour', 'こんにちは', 'Hello', 'Grüezi', '你好', 'Hola', 'Ciao', '안녕하세요', 'Olá', 'Hej', 'नमस्ते', 'Aloha', 'Γειά σου', 'Xin chào', 'Allillanchu'];
  const TRACKS = [['Midnight Bloom', 'Koi Pond', 214], ['Neon Petals', 'Lumen', 187], ['Still Water', 'Aster', 241], ['Paper Lanterns', 'Mori', 199]];
  const NAME = 'Alex';
  let LOGO = [], THEMES = [], BLOOM = [], VERSION = '2';

  const esc = Lotus.esc;
  const S = (cls, txt) => `<span class="${cls}">${esc(txt)}</span>`;
  const pad = (s, n) => s + ' '.repeat(Math.max(0, n - [...s].length));
  const line = (n) => '─'.repeat(n);
  const box = (title, cls) => {
    const t = ` ${title} `, l = Math.floor((42 - t.length) / 2);
    return S('c-border', '┌' + line(l)) + S(cls, t) + S('c-border', line(42 - t.length - l) + '┐');
  };
  const bottom = S('c-border', '└' + line(42) + '┘');
  const bar = (pct) => { const n = Math.round(pct / 10); return '[' + S('c-key', '■'.repeat(n)) + S('c-dim', '·'.repeat(10 - n)) + ']'; };
  const key = (k, cls = 'c-key') => S(cls, pad('├─ ' + k, 14));
  const mmss = (s) => String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0');

  let hello = 0, track = 0, pos = 62, themeIdx = 0, lang = 'en', sel = 1, inSettings = false, shown = false;
  const login = new Date(Date.now() - 3 * 3600e3);
  const stamp = (d) => d.toISOString().slice(0, 10) + ' ' + d.toTimeString().slice(0, 8);

  const npLine1 = () => S('c-music', '♫ ') + S('c-white', TRACKS[track][0]) + S('c-border', ' — ') + S('c-white', TRACKS[track][1]);
  const npLine2 = () => '  ' + bar((pos / TRACKS[track][2]) * 100) + ' ' + S('c-dim', `${mmss(pos)} / ${mmss(TRACKS[track][2])}  ▶ playing`);
  const infoLines = () => [
    `<span class="hello-t">${S('c-bold', HELLOS[hello] + ', ')}</span>${S('c-accent', NAME)}`, '',
    box('Hardware', 'c-accent'),
    key('CPU') + 'Apple M4 Pro (14C / 14T) @ 4.51 GHz',
    key('GPU') + 'Apple M4 Pro [Integrated] // 20 Cores',
    key('RAM') + '18.21 GiB / 48.00 GiB ' + bar(38) + ' 38%',
    key('SWAP') + '0 B / 0 B ' + bar(0) + ' 0%',
    key('DRIVE') + '/ 412.80 GiB / 994.66 GiB ' + bar(41) + ' 41%',
    bottom, '',
    box('Session', 'c-accent'),
    key('LOGIN') + 'alex // ' + stamp(login),
    bottom, '',
    box('Uptime / Date', 'c-key2'),
    key('UPTIME', 'c-key2') + '2 days, 4 hours, 9 mins',
    key('DATE', 'c-key2') + `<span class="clock">${stamp(new Date())}</span>`,
    bottom, '',
    `<span class="np1">${npLine1()}</span>`,
    `<span class="np2">${npLine2()}</span>`,
  ];

  const wrap = (html) => `<span class="ln">${html || ' '}</span>`;

  async function bloom() {
    screen.classList.remove('clearing', 'cleared', 'out');
    outEl.innerHTML = '';
    logoEl.innerHTML = LOGO.map((l) => wrap(S('c-logo', l))).join('');
    infoEl.innerHTML = infoLines().map(wrap).join('');
    promptEl.innerHTML = '';
    const ll = [...logoEl.children], il = [...infoEl.children];
    shown = true;
    for (let i = 0; i < Math.max(ll.length, il.length); i++) {
      ll[ll.length - 1 - i]?.classList.add('on');
      il[i]?.classList.add('on');
      await sleep(26);
    }
    await sleep(250);
    prompt();
  }

  function prompt(text = '') {
    promptEl.innerHTML = '\n' + S('c-accent', 'alex@MacBook ~ % ') + esc(text) + '<span class="cursor"></span>';
  }

  async function type(text) {
    for (let i = 1; i <= text.length; i++) { prompt(text.slice(0, i)); await sleep(60 + Math.random() * 70); }
    await sleep(380);
  }

  async function clear() {
    screen.classList.add('clearing');
    await sleep(260);
    shown = false;
    logoEl.innerHTML = infoEl.innerHTML = outEl.innerHTML = '';
    screen.classList.add('cleared');
    prompt();
  }

  // Output of a command, shown line by line above the prompt
  async function output(lines, typed) {
    screen.classList.add('cleared', 'out');
    outEl.innerHTML = S('c-accent', 'alex@MacBook ~ % ') + esc(typed) + '\n';
    promptEl.innerHTML = '';
    for (const l of lines) { outEl.innerHTML += l + '\n'; await sleep(70); }
    prompt();
  }

  const WEATHER = () => [
    '',
    '  ' + S('c-bold c-accent', 'lotus') + S('c-dim', ' / ') + S('c-bold', 'Weather'),
    '',
    '  ' + S('c-key2', '    \\   /      ') + '   ' + S('c-bold', 'Tokyo') + S('c-dim', ', Japan'),
    '  ' + S('c-key2', '     .-.       ') + '   ' + S('c-bold', '21°C') + '  Clear sky',
    '  ' + S('c-key2', '  - (   ) -    ') + '   ' + S('c-key', 'Feels like') + '  19°C',
    '  ' + S('c-key2', "     `-'       ") + '   ' + S('c-key', 'Humidity  ') + '  49%',
    '  ' + S('c-key2', '    /   \\      ') + '   ' + S('c-key', 'Wind      ') + '  9 km/h',
    '',
    '  ' + S('c-bold c-accent', 'FORECAST'),
    '    ' + S('c-key', 'Mon ') + ' Rain           ' + S('c-bold', '22°C') + S('c-dim', ' / 14°C  90% rain'),
    '    ' + S('c-key', 'Tue ') + ' Overcast       ' + S('c-bold', '22°C') + S('c-dim', ' / 12°C  0% rain'),
    '    ' + S('c-key', 'Wed ') + ' Partly cloudy  ' + S('c-bold', '24°C') + S('c-dim', ' / 13°C  10% rain'),
  ];

  // ── Settings screen (English / Deutsch) ─────────────────────
  const T = {
    en: { title: 'Settings', heads: ['GENERAL', 'GREETING', 'SECTIONS'],
      rows: [['Name', NAME, 'text'], ['Language', 'English'], ['Auto-start on terminal launch', 'on', 'bool'], ['Logo', 'Lotus Classic'], ['Preview logos, paste your own', '', 'action'],
        ['Theme', 'theme'], ['Colored prompt', 'on', 'bool'], ['Top', '15 languages in order'], ['Bottom, by time of day', 'Off'],
        ['Hardware', 'on', 'bool'], ['Session', 'on', 'bool'], ['Uptime & date', 'on', 'bool'], ['Now playing', 'on', 'bool']],
      on: 'on', off: 'off', edit: '⏎ edit', footer: '↑↓ select   ←→ ⏎ change   v preview   r reset   q done', saved: '✓ saved' },
    de: { title: 'Einstellungen', heads: ['ALLGEMEIN', 'BEGRÜSSUNG', 'BEREICHE'],
      rows: [['Name', NAME, 'text'], ['Sprache', 'Deutsch'], ['Automatisch beim Öffnen starten', 'on', 'bool'], ['Logo', 'Lotus Classic'], ['Logos ansehen, eigenes einfügen', '', 'action'],
        ['Farbschema', 'theme'], ['Farbiger Prompt', 'on', 'bool'], ['Oben', '15 Sprachen der Reihe nach'], ['Unten, je nach Tageszeit', 'Aus'],
        ['Hardware', 'on', 'bool'], ['Session', 'on', 'bool'], ['Uptime & Datum', 'on', 'bool'], ['Läuft gerade', 'on', 'bool']],
      on: 'an', off: 'aus', edit: '⏎ ändern', footer: '↑↓ auswählen   ←→ ⏎ ändern   v Vorschau   r Standard   q fertig', saved: '✓ gespeichert' },
  };
  const HEAD_AT = { 0: 0, 7: 1, 9: 2 };

  function renderSettings(msg = '') {
    const L = T[lang];
    let out = '  ' + S('c-accent c-bold', 'lotus') + S('c-dim', ` / ${L.title} · v${VERSION}`) + '\n\n';
    L.rows.forEach(([label, val, type], i) => {
      if (i in HEAD_AT) out += (i ? '\n' : '') + '  ' + S('c-dim', L.heads[HEAD_AT[i]]) + '\n';
      let v = val === 'theme' ? (THEMES[themeIdx]?.label || 'Matcha') : val;
      if (type === 'bool') v = val === 'on' ? S('c-key', '● ' + L.on) : S('c-dim', '○ ' + L.off);
      else if (type === 'action') v = '';
      else if (i === sel && type === 'text') v = esc(v) + S('c-dim', '  ' + L.edit);
      else v = esc(i === sel ? `‹ ${v} ›` : v);
      const lab = esc(pad(label, 32));
      out += i === sel ? '  ' + S('c-accent', '›') + ' ' + `<span class="c-bold">${lab}</span>` + v + '\n' : '    ' + lab + v + '\n';
    });
    out += '\n  ' + S('c-dim', L.footer) + '\n  ' + msg;
    settingsEl.innerHTML = out;
  }

  function applyTheme(i) {
    themeIdx = (i + THEMES.length) % THEMES.length;
    if (THEMES[themeIdx]) Lotus.applyColors(term, THEMES[themeIdx].colors);
  }

  async function settingsDemo() {
    inSettings = true; sel = 1;
    screen.classList.add('alt');
    renderSettings();
    await sleep(900);
    const move = async (to) => { while (sel !== to) { sel += Math.sign(to - sel); renderSettings(); await sleep(220); } await sleep(320); };
    const saved = () => S('c-key', T[lang].saved);
    await move(5);
    for (let k = 0; k < 3; k++) { applyTheme(themeIdx + 1); renderSettings(saved()); await sleep(850); }
    await move(1);
    lang = 'de'; renderSettings(saved()); await sleep(1700);
    lang = 'en'; renderSettings(saved()); await sleep(800);
    screen.classList.remove('alt');
    inSettings = false;
  }

  // ── /bg remove: the drop zone, then the lotus that blooms, then the result ──
  const cols = () => (term.classList.contains('narrow') ? 66 : 112);
  const center = (plain, html = esc(plain)) => ' '.repeat(Math.max(0, Math.floor((cols() - [...plain].length) / 2))) + html;
  const hero = (title, right = '') => {
    const left = '    ' + S('c-accent', '◇') + ' ' + S('c-bold', 'lotus') + S('c-dim', ' / ') + S('c-bold', title);
    const gap = cols() - 4 - 2 - 7 - [...title].length - [...right].length - 4;
    return left + (right ? ' '.repeat(Math.max(2, gap)) + S('c-dim', right) : '');
  };

  // Heavy line glyphs may come from a fallback font with another width: one cell each, exactly 1ch
  const cell = (ch) => `<span class="c-key cell">${ch}</span>`;
  function dropZone() {
    const w = cols() > 70 ? 58 : 46, inner = w - 2;
    const row = (plain, html = esc(plain)) => {
      const l = Math.floor((inner - [...plain].length) / 2);
      return '    ' + S('c-border', '┆') + ' '.repeat(l) + html + ' '.repeat(inner - l - [...plain].length) + S('c-border', '┆');
    };
    return ['', hero('Remove BG'), '', '    ' + S('c-dim', 'Remove image backgrounds locally. Nothing leaves your Mac.'), '',
      '    ' + S('c-border', '╭' + '╌'.repeat(inner) + '╮'), row(''),
      row('  ┃  ', '  ' + cell('┃') + '  '), row('━━╋━━', [...'━━╋━━'].map(cell).join('')), row('  ┃  ', '  ' + cell('┃') + '  '),
      row(''), row('Drop images here', S('c-bold', 'Drop images here')), row('PNG · JPG · WebP · HEIC · whole folders', S('c-dim', 'PNG · JPG · WebP · HEIC · whole folders')),
      row(''), '    ' + S('c-border', '╰' + '╌'.repeat(inner) + '╯'),
      '    ' + S('c-dim', 'drag from the Finder or type a path · ⏎ start · empty line cancels'), ''];
  }

  // Theme color → shade (0 … 1): the same ramp as lib/bg/progress.zsh
  const rgbOf = (css) => (css.match(/\d+/g) || [200, 200, 200]).slice(0, 3).map(Number);
  function ramp(rgb, k) {
    const m = (rgb[0] + rgb[1] + rgb[2]) / 3;
    const deep = rgb.map((c) => Math.max(0, Math.min(255, c * 0.58 - (m - c) * 0.7)));
    const tip = rgb.map((c) => c + (255 - c) * 0.62);
    const [a, b, f] = k < 0.6 ? [deep, rgb, k / 0.6] : [rgb, tip, (k - 0.6) / 0.4];
    return `rgb(${a.map((v, i) => Math.round(v + (b[i] - v) * f)).join(',')})`;
  }
  function palette() {
    const c = (THEMES[themeIdx] || THEMES[0]).colors;
    const p = {}, logo = rgbOf(c.logo), key = rgbOf(c.key), key2 = rgbOf(c.key2);
    for (let n = 0; n <= 9; n++) p[n] = ramp(logo, n / 9);
    Object.assign(p, { y: ramp(key2, 0.45), Y: ramp(key2, 0.8), g: ramp(key, 0.25), G: ramp(key, 0.55), pollen: ramp(key2, 0.7) });
    return p;
  }
  // One frame on a canvas: one pixel is half a terminal cell, like the half blocks in the terminal
  function drawBloom(canvas, f, pollen) {
    const ctx = canvas.getContext('2d'), pal = palette(), px = BLOOM[f] || [];
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    px.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== '.') { ctx.fillStyle = pal[ch]; ctx.fillRect(x, y, 1, 1); } }));
    ctx.fillStyle = pal.pollen;
    for (const p of pollen) if ((px[Math.floor(p.y)] || '')[Math.floor(p.x)] === '.') ctx.fillRect(Math.floor(p.x), Math.floor(p.y), 1, 1);
  }

  const BG_STEPS = [['load_model', 'Loading BiRefNet', 'Model', 1300], ['load_image', 'Reading the image', 'Image', 300],
    ['segment', 'Finding the subject', 'Subject', 2300], ['refine', 'Refining edges', 'Edges', 800], ['write', 'Writing the PNG', 'PNG', 800]];

  async function bgDemo() {
    // the drop zone, then a dragged file and Enter
    screen.classList.add('cleared', 'out');
    outEl.innerHTML = S('c-accent', 'alex@MacBook ~ % ') + '/bg remove\n' + dropZone().join('\n') + '\n    ' + S('c-accent', '›') + ' <span class="drop-in"></span><span class="cursor"></span>';
    promptEl.innerHTML = '';
    await sleep(1600);
    outEl.querySelector('.drop-in').textContent = '~/Pictures/portrait.jpg';
    await sleep(1100);

    // the progress screen
    screen.classList.add('alt');
    const W = cols(), aw = BLOOM[0] ? BLOOM[0][0].length : 41, ah = BLOOM[0] ? BLOOM[0].length / 2 : 10;
    let bloom = 0, frame = 0, stage = 0, stageStart = Date.now();
    const start = Date.now(), pollen = [];
    const render = (done) => {
      frame++;
      const spin = ['◇', '◈', '◆', '◈'][Math.floor(frame / 3) % 4];
      const [, label] = BG_STEPS[Math.min(stage, BG_STEPS.length - 1)];
      let water = '';
      const t = Date.now() / 1000, reach = Math.floor(6 + 13 * bloom);
      for (let c = 0; c < aw; c++) {
        const v = Math.sin(c * 0.55 - t * 2.6) + 0.6 * Math.sin(c * 0.21 + t * 1.3);
        water += Math.abs(c - aw / 2) > reach + 2 ? ' ' : v > 1.05 ? S('c-accent', '~') : v > 0.55 ? S('c-dim', '~') : ' ';
      }
      const bw = 36, pos = (() => { const span = bw - 6, p = frame % (2 * span); return p > span ? 2 * span - p : p; })();
      let bar = '';
      for (let i = 0; i < bw; i++) bar += done ? S('c-key', '━') : i >= pos && i < pos + 6 ? S('c-key', '━') : i === pos - 1 || i === pos + 6 ? S('c-accent', '━') : S('c-dim', '━');
      const strip = BG_STEPS.map(([, , short], i) => (done || i < stage ? S('c-key', '✓') + ' ' + esc(short) : i === stage ? S('c-accent', '◆') + ' ' + S('c-bold', short) : S('c-dim', '· ' + short))).join('   ');
      const stripPlain = BG_STEPS.map(([, , short]) => 'x ' + short).join('   ');
      const secs = ((Date.now() - start) / 1000).toFixed(1) + 's';
      const info = 'BiRefNet · MPS' + (stage >= 2 || done ? ' · 1916 × 2608' : '') + ' · ' + secs;
      const head = done ? S('c-key', '✓') + ' ' + S('c-bold', 'Done') : S('c-accent', spin) + ' ' + S('c-bold', label);
      const headPlain = done ? '✓ Done' : spin + ' ' + label;
      settingsEl.innerHTML = '\n' + hero('Remove BG', 'portrait.jpg') + '\n\n' +
        `<canvas class="bloom" width="${aw}" height="${ah * 2}" style="margin-left:${Math.floor((W - aw) / 2)}ch;width:${aw}ch;height:calc(var(--fs) * 1.4 * ${ah})"></canvas>\n` +
        ' '.repeat(Math.floor((W - aw) / 2)) + water + '\n\n' +
        center(headPlain, head) + '\n' + center('x'.repeat(bw), bar) + '\n\n\n' +
        center(stripPlain, strip) + '\n\n' + center(info, S('c-dim', info)) + '\n\n' + center('ctrl-c cancels', S('c-dim', 'ctrl-c cancels'));
      if (bloom > 0.4 && Math.random() < 0.3) pollen.push({ x: aw / 2 + (Math.random() - 0.5) * 18 * bloom, y: ah * 2 * (0.55 - 0.3 * bloom), v: (Math.random() - 0.5) * 0.35, l: 0 });
      if (done && frame % 5 === 0) for (let i = 0; i < 5; i++) pollen.push({ x: aw / 2 + (Math.random() - 0.5) * 18, y: ah * 0.6, v: (Math.random() - 0.5) * 0.5, l: 0 });
      for (const p of pollen) { p.x += p.v; p.y -= 0.3; p.l++; }
      while (pollen.length && (pollen[0].l > 26 || pollen[0].y < 0)) pollen.shift();
      drawBloom(settingsEl.querySelector('canvas'), Math.round(bloom * (BLOOM.length - 1)), pollen);
    };
    while (stage < BG_STEPS.length) {
      const within = Math.min(0.5, (Date.now() - stageStart) / BG_STEPS[stage][3] * 0.5);
      const target = (stage + within) / BG_STEPS.length;
      bloom += Math.max(0, target - bloom) * 0.12;
      render(false);
      await sleep(80);
      if (Date.now() - stageStart > BG_STEPS[stage][3]) { stage++; stageStart = Date.now(); }
    }
    for (let i = 0; i < 18; i++) { bloom += (1 - bloom) * 0.3; render(true); await sleep(80); }

    // the result screen, then back to the shell
    const res = (k, v) => '    ' + S('c-dim', k.padEnd(12)) + esc(v);
    settingsEl.innerHTML = ['', hero('Background removed'), '', res('Input', '~/Pictures/portrait.jpg'), res('Output', '~/Pictures/Lotus/Background Removed/portrait_no_bg.png'), '',
      res('Model', 'BiRefNet'), res('Backend', 'MPS'), res('Resolution', '1916 × 2608'), res('Time', '2.16s'), '',
      '  ' + S('c-key', '✓') + ' Transparent PNG created', '',
      '    ' + ['o open', 'f show in Finder', 'r refine by hand', 'd discard', 'q done'].map((k) => S('c-key', k[0]) + k.slice(1)).join('   ')].join('\n');
    await sleep(2600);
    screen.classList.remove('alt');
    outEl.innerHTML = S('c-accent', 'alex@MacBook ~ % ') + '/bg remove\n  ' + S('c-key', '✓') + ' Transparent PNG created  ' + S('c-dim', 'BiRefNet · MPS · 2.16s') +
      '\n    ' + S('c-dim', '~/Pictures/Lotus/Background Removed/portrait_no_bg.png') + '\n';
    prompt();
  }

  // ── /lotus log ──────────────────────────────────────────────
  const LOG = [['09:31:02', 'INFO', 'bg', 'Remove BG requested for 1 image(s)'], ['09:31:03', 'INFO', 'bg', 'BiRefNet ready on MPS in 1.3s'],
    ['09:31:05', 'INFO', 'bg', 'Done in 2.16s: ~/Pictures/Lotus/Background Removed/portrait_no_bg.png'], ['09:32:40', 'INFO', 'ai', 'AI tui with claude (thinking: high)'],
    ['09:32:51', 'INFO', 'ai', 'Tool write_file index.html'], ['09:33:10', 'WARN', 'convert', 'yt-dlp 2026.03.17 is 204 days old'],
    ['09:33:24', 'INFO', 'convert', 'yt-dlp updated: 2026.03.17 → 2026.08.19'], ['09:34:02', 'INFO', 'settings', 'Changed: THEME']];
  function renderLog(sel, filter) {
    const rows = LOG.filter((e) => !filter || e[1] === 'WARN');
    const room = cols() - 34;
    const lvl = (l) => (l === 'WARN' ? S('c-key2', l.padEnd(6)) : S('c-accent', l.padEnd(6)));
    const lines = ['', hero('Log'), '', '    ' + S('c-dim', `Today · 09:31 – 09:34 · ${LOG.length} entries · Log level: Normal`),
      '    ' + S('c-dim', 'Showing: ') + (filter ? 'WARN+' : 'everything'), '', '    ' + S('c-dim', '── Today ──')];
    rows.forEach((e, i) => {
      const msg = e[3].length > room ? e[3].slice(0, room - 1) + '…' : e[3];
      const pre = i === sel ? '  ' + S('c-accent', '›') + ' ' : '    ';
      lines.push(pre + S('c-dim', e[0]) + '  ' + lvl(e[1]) + ' ' + S('c-dim', e[2].padEnd(10)) + esc(msg));
    });
    lines.push('', '    ' + S('c-dim', '↑↓ scroll   ⏎ details   f filter   / search   l live   y copy   c clear   q quit'));
    settingsEl.innerHTML = lines.join('\n');
  }
  async function logDemo() {
    screen.classList.add('alt');
    let sel = LOG.length - 1;
    renderLog(sel, false);
    await sleep(1200);
    for (let i = 0; i < 4; i++) { renderLog(--sel, false); await sleep(330); }
    await sleep(700);
    renderLog(0, true);
    await sleep(1800);
    renderLog(LOG.length - 1, false);
    await sleep(900);
    screen.classList.remove('alt');
  }

  // ── Live bits: clock, song progress, greeting scramble ──────
  const GLYPHS = 'アイウエオカキ안녕你好#*+=-:.ΓλΩж';
  async function scrambleHello() {
    const el = infoEl.querySelector('.hello-t');
    if (!el) return;
    hello = (hello + 1) % HELLOS.length;
    const target = HELLOS[hello] + ', ';
    for (let f = 0; f < 8; f++) {
      const n = [...target].length;
      el.innerHTML = S('c-bold', [...target].map((c, i) => (i < (f / 8) * n || c === ' ' ? c : GLYPHS[(Math.random() * GLYPHS.length) | 0])).join(''));
      await sleep(45);
    }
    el.innerHTML = S('c-bold', target);
  }
  setInterval(() => {
    if (!visible) return;
    pos++;
    if (pos >= TRACKS[track][2]) { pos = 0; track = (track + 1) % TRACKS.length; const n1 = infoEl.querySelector('.np1'); if (n1) n1.innerHTML = npLine1(); }
    const c = infoEl.querySelector('.clock'); if (c) c.textContent = stamp(new Date());
    const n2 = infoEl.querySelector('.np2'); if (n2) n2.innerHTML = npLine2();
  }, 1000);
  setInterval(() => { if (visible && shown && !inSettings) scrambleHello(); }, 2600);

  // ── Only animate while visible ──────────────────────────────
  let visible = false, wake = [];
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible) { wake.forEach((r) => r()); wake = []; }
  }, { threshold: 0.15 }).observe(term);
  async function sleep(ms) {
    while (!visible) await new Promise((r) => wake.push(r));
    await new Promise((r) => setTimeout(r, ms));
  }
  const step = (name) => steps.forEach((s) => s.classList.toggle('active', s.dataset.step === name));

  function fit() {
    const w = term.clientWidth - 44, cols = w < 640 ? 66 : 112;
    term.classList.toggle('narrow', cols === 66);
    term.style.setProperty('--fs', Math.min(13, w / (cols * 0.6)) + 'px');
  }
  addEventListener('resize', fit);
  fit();

  // the theme picker on the page recolors the demo as well
  addEventListener('lotus-theme', (e) => applyTheme(Math.max(0, THEMES.findIndex((t) => t.name === e.detail))));

  // ── The script ──────────────────────────────────────────────
  (async function main() {
    const [logo, themes, bloomText, changelog] = await Promise.all([Lotus.text('logos/lotus.txt'), Lotus.loadThemes(),
      Lotus.text('data/bloom.txt').catch(() => ''), Lotus.text('CHANGELOG.md').catch(() => '')]);
    LOGO = logo.replace(/\s+$/, '').split('\n').map((l) => l.replace(/\s+$/, ''));
    THEMES = themes;
    BLOOM = bloomText.split('\n%').map((f) => f.split('\n').filter((l) => l && !l.startsWith('#') && l !== '%')).filter((f) => f.length);
    VERSION = (changelog.match(/^## (\d+\.\d+\.\d+)/m) || [, '2'])[1];
    themeIdx = Math.max(0, THEMES.findIndex((t) => t.name === document.documentElement.dataset.theme));
    await sleep(400);
    for (;;) {
      step('live');
      await bloom();
      await sleep(5500);
      step('weather');
      await type('/weather Tokyo');
      await output(WEATHER(), '/weather Tokyo');
      await sleep(4200);
      await type('clear'); await clear();
      step('app');
      await type('/app spotfy');
      await output(['  Did you mean "Spotify"? ' + S('c-dim', '[Y/n]')], '/app spotfy');
      await sleep(1300);
      outEl.innerHTML = outEl.innerHTML.replace('[Y/n]</span>', '[Y/n]</span> yes') + '  ' + S('c-accent', '›') + ' Opening Spotify\n';
      await sleep(2400);
      if (BLOOM.length) {
        await type('clear'); await clear();
        step('bg');
        await type('/bg remove');
        await bgDemo();
        await sleep(2200);
      }
      step('log');
      await type('/lotus log');
      await logDemo();
      prompt();
      await sleep(500);
      step('settings');
      await type('/settings');
      await settingsDemo();
      step('live');
      await bloom();
      await sleep(5000);
      await type('clear'); await clear();
      await sleep(600);
    }
  })();
})();
