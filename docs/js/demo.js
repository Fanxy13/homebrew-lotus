// Lotus website – animated terminal demo (pure DOM, pauses when off screen).
// The logo is read from logos/lotus.txt and the themes from data/themes.tsv – the same files Lotus uses.
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
  let LOGO = [], THEMES = [];

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
    '  ' + S('c-key2', '    \\   /      ') + '   ' + S('c-bold', 'Zurich') + S('c-dim', ', Switzerland'),
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
    let out = '  ' + S('c-accent c-bold', 'lotus') + S('c-dim', ` / ${L.title} · v2.0.0`) + '\n\n';
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
    const [logo, themes] = await Promise.all([Lotus.text('logos/lotus.txt'), Lotus.loadThemes()]);
    LOGO = logo.replace(/\s+$/, '').split('\n').map((l) => l.replace(/\s+$/, ''));
    THEMES = themes;
    themeIdx = Math.max(0, THEMES.findIndex((t) => t.name === document.documentElement.dataset.theme));
    await sleep(400);
    for (;;) {
      step('live');
      await bloom();
      await sleep(5500);
      step('weather');
      await type('/weather Zurich');
      await output(WEATHER(), '/weather Zurich');
      await sleep(4200);
      await type('clear'); await clear();
      step('app');
      await type('/app spotfy');
      await output(['  Did you mean "Spotify"? ' + S('c-dim', '[Y/n]')], '/app spotfy');
      await sleep(1300);
      outEl.innerHTML = outEl.innerHTML.replace('[Y/n]</span>', '[Y/n]</span> yes') + '  ' + S('c-accent', '›') + ' Opening Spotify\n';
      await sleep(2400);
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
