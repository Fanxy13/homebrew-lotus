// lotus – animated terminal demo (pure DOM, pauses when off screen)
(() => {
  const term = document.getElementById('terminal');
  if (!term) return;
  const screen = term.querySelector('.screen');
  const logoEl = term.querySelector('.logo');
  const infoEl = term.querySelector('.info');
  const settingsEl = term.querySelector('.settings');
  const promptEl = term.querySelector('.promptline');
  const steps = document.querySelectorAll('.demo-caption .step');

  const LOGO = `                         :
                        +#-           :-
           -.         +**##*.        =##-
         .*##       +#####*#*+     +####+
         *###**-   *##*-  =**#* .*#*+***#:
         **#*=*#*--##*.:**- =** -.=:=####:
         =###*:... **.:***#+ -..+*- +###*:
   :      *###+:+**:  *+. :--.+###*.+###*.     -
   **:     **#+  =+  .        ..*::.+#*+. .=*##-
  .###***=: +#=.+.       -*    .=:= -.+#######*
   ####***+*+..=##+    +##*+    .**.=*++#####*:
   =#####*+-.. +*### -*#####*: *##*  -+**###*.
    =*#######*:.*### *########==**-:===**#*:
      =######*=. =** +########+.*+:*****=
          ..+#**+=. :.+*******:+.    .=*#*#-
         -*##*::+##*: .=+- .+=. +######*##*#*-
        **###****#* =###*#+ -##* :*#####*###*#+
      .*########*** *#####*-.*##:
      *#*##*###*#*- -######+=***
                      =*####**+
                        .+#*+
                           :`.split('\n');

  const HELLOS = ['Bonjour', 'こんにちは', 'Hello', 'Grüezi', '你好', 'Hola', 'Ciao', '안녕하세요', 'Olá', 'Hej', 'नमस्ते', 'Aloha', 'Γειά σου', 'Xin chào', 'Allillanchu'];
  const TRACKS = [['Midnight Bloom', 'Koi Pond', 214], ['Neon Petals', 'Lumen', 187], ['Still Water', 'Aster', 241], ['Paper Lanterns', 'Mori', 199]];
  const THEMES = ['matcha', 'sakura', 'ocean', 'sunset', 'mono'];
  const NAME = 'Alex';

  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
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

  // ── State ───────────────────────────────────────────────────
  let hello = 0, track = 0, pos = 62, themeIdx = 0;
  let lang = 'en', sel = 1, inSettings = false, shown = false;
  const login = new Date(Date.now() - 3 * 3600e3);
  const stamp = (d) => d.toISOString().slice(0, 10) + ' ' + d.toTimeString().slice(0, 8);

  function salute() {
    const h = new Date().getHours();
    return (h < 5 ? 'Bonne nuit!' : h < 18 ? 'Bonjour!' : 'Bonsoir!') + ' ' + NAME + '.';
  }

  const infoLines = () => [
    `<span class="hello-t">${S('c-bold', HELLOS[hello] + ', ')}</span>${S('c-accent', NAME)}`,
    '',
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
    S('c-salute', salute()), '',
    `<span class="np1">${npLine1()}</span>`,
    `<span class="np2">${npLine2()}</span>`,
  ];
  const npLine1 = () => S('c-music', '♫ ') + S('c-white', TRACKS[track][0]) + S('c-border', ' — ') + S('c-white', TRACKS[track][1]);
  const npLine2 = () => {
    const [, , len] = TRACKS[track];
    return '  ' + bar((pos / len) * 100) + ' ' + S('c-dim', `${mmss(pos)} / ${mmss(len)}  ▶ playing`);
  };

  // ── Rendering ───────────────────────────────────────────────
  const wrap = (html) => `<span class="ln">${html || ' '}</span>`;

  async function bloom() {
    screen.classList.remove('clearing', 'cleared');
    logoEl.innerHTML = LOGO.map((l) => wrap(S('c-logo', l))).join('');
    infoEl.innerHTML = infoLines().map(wrap).join('');
    promptEl.innerHTML = '';
    const logoLines = [...logoEl.children], infoLns = [...infoEl.children];
    shown = true;
    for (let i = 0; i < Math.max(logoLines.length, infoLns.length); i++) {
      logoLines[logoLines.length - 1 - i]?.classList.add('on');   // logo grows from the bottom
      infoLns[i]?.classList.add('on');
      await sleep(28);
    }
    await sleep(250);
    prompt();
  }

  function prompt(text = '') {
    promptEl.innerHTML = '\n' + S('c-accent', 'alex@MacBook ~ % ') + esc(text) + '<span class="cursor"></span>';
  }

  async function type(text) {
    for (let i = 1; i <= text.length; i++) {
      prompt(text.slice(0, i));
      await sleep(70 + Math.random() * 70);
    }
    await sleep(380);
  }

  async function clear() {
    screen.classList.add('clearing');
    await sleep(260);
    shown = false;
    logoEl.innerHTML = infoEl.innerHTML = '';
    screen.classList.add('cleared');
    prompt();
  }

  // ── Settings screen (English / Deutsch) ─────────────────────
  const T = {
    en: { title: 'Settings', general: 'GENERAL', greeting: 'GREETING', sections: 'SECTIONS', np: 'NOW PLAYING',
      rows: [['Name', NAME, 'text'], ['Language', 'English'], ['Show on launch', 'on', 'bool'], ['Logo', 'Lotus'], ['Theme', 'theme'],
        ['Colored prompt', 'on', 'bool'], ['Hide “Last login” line', 'off', 'bool'],
        ['Top', '15 languages in order'], ['Bottom, by time of day', 'French'],
        ['Hardware', 'on', 'bool'], ['Session', 'on', 'bool'], ['Uptime & date', 'on', 'bool'], ['Now playing', 'on', 'bool'],
        ['Live updates', 'on', 'bool'], ['Update every', '2 seconds'], ['Color mode', 'Automatic'], ['Uninstall lotus', '', 'action']],
      on: 'on', off: 'off', edit: '⏎ edit', run: '⏎ run', footer: '↑↓ select   ←→ ⏎ change   v preview   r reset   q done', saved: '✓ saved' },
    de: { title: 'Einstellungen', general: 'ALLGEMEIN', greeting: 'BEGRÜSSUNG', sections: 'BEREICHE', np: 'LÄUFT GERADE',
      rows: [['Name', NAME, 'text'], ['Sprache', 'Deutsch'], ['Beim Öffnen anzeigen', 'on', 'bool'], ['Logo', 'Lotus'], ['Farbschema', 'theme'],
        ['Farbiger Prompt', 'on', 'bool'], ['„Last login“-Zeile ausblenden', 'off', 'bool'],
        ['Oben', '15 Sprachen der Reihe nach'], ['Unten, je nach Tageszeit', 'Französisch'],
        ['Hardware', 'on', 'bool'], ['Session', 'on', 'bool'], ['Uptime & Datum', 'on', 'bool'], ['Läuft gerade', 'on', 'bool'],
        ['Live aktualisieren', 'on', 'bool'], ['Aktualisieren alle', '2 Sekunden'], ['Farbmodus', 'Automatisch'], ['lotus deinstallieren', '', 'action']],
      on: 'an', off: 'aus', edit: '⏎ ändern', run: '⏎ ausführen', footer: '↑↓ auswählen   ←→ ⏎ ändern   v Vorschau   r Standard   q fertig', saved: '✓ gespeichert' },
  };
  const HEADS = { 0: 'general', 7: 'greeting', 9: 'sections', 13: 'np', 16: 'LOTUS' };
  const themeName = (t) => ({ ocean: lang === 'de' ? 'Ozean' : 'Ocean' })[t] || t[0].toUpperCase() + t.slice(1);

  function renderSettings(msg = '') {
    const L = T[lang];
    let out = '  ' + S('c-accent c-bold', '🪷 lotus') + S('c-dim', `  ${L.title} · v1.1.0`) + '\n\n';
    L.rows.forEach(([label, val, type], i) => {
      if (i in HEADS) out += (i ? '\n' : '') + '  ' + S('c-dim', L[HEADS[i]] || HEADS[i]) + '\n';
      let v = val === 'theme' ? themeName(THEMES[themeIdx]) : val;
      if (type === 'bool') v = val === 'on' ? S('c-key', '● ' + L.on) : S('c-dim', '○ ' + L.off);
      else if (type === 'action') v = i === sel ? S('c-dim', L.run) : '';
      else if (i === sel && type === 'text') v = esc(v) + S('c-dim', '  ' + L.edit);
      else v = esc(i === sel ? `‹ ${v} ›` : v);
      const lab = type === 'action' ? S('c-red', pad(label, 32)) : esc(pad(label, 32));
      out += i === sel ? '  ' + S('c-accent', '›') + ' ' + `<span class="c-bold">${lab}</span>` + v + '\n'
                       : '    ' + lab + v + '\n';
    });
    out += '\n  ' + S('c-dim', L.footer) + '\n  ' + msg;
    settingsEl.innerHTML = out;
  }

  async function settingsDemo() {
    inSettings = true; sel = 1;
    screen.classList.add('alt');
    renderSettings();
    await sleep(900);
    const move = async (to) => { while (sel !== to) { sel += Math.sign(to - sel); renderSettings(); await sleep(230); } await sleep(350); };
    const saved = () => S('c-key', T[lang].saved);

    await move(4);                                    // Theme
    for (let k = 0; k < 2; k++) {
      themeIdx = (themeIdx + 1) % THEMES.length;
      term.dataset.theme = THEMES[themeIdx];
      renderSettings(saved());
      await sleep(900);
    }
    await move(1);                                    // Language → Deutsch
    lang = 'de'; renderSettings(saved());
    await sleep(1700);
    lang = 'en'; renderSettings(saved());
    await sleep(900);
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
    el.parentElement.classList.remove('flash'); void el.offsetWidth; el.parentElement.classList.add('flash');
  }

  setInterval(() => {
    if (!visible) return;
    pos++;
    if (pos >= TRACKS[track][2]) { pos = 0; track = (track + 1) % TRACKS.length; const n1 = infoEl.querySelector('.np1'); if (n1) n1.innerHTML = npLine1(); }
    const c = infoEl.querySelector('.clock'); if (c) c.textContent = stamp(new Date());
    const n2 = infoEl.querySelector('.np2'); if (n2) n2.innerHTML = npLine2();
  }, 1000);
  setInterval(() => { if (visible && shown && !inSettings) scrambleHello(); }, 2600);

  // ── Visibility: only animate while the demo is on screen ────
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

  // Fit 112 columns into the window width
  function fit() {
    const w = term.clientWidth - 44;
    const cols = w < 640 ? 66 : 112;
    term.classList.toggle('narrow', cols === 66);
    term.style.setProperty('--fs', Math.min(13, w / (cols * 0.6)) + 'px');
  }
  addEventListener('resize', fit);
  fit();

  // The site-wide theme picker also recolors the demo
  addEventListener('lotus-theme', (e) => {
    themeIdx = Math.max(0, THEMES.indexOf(e.detail));
    term.dataset.theme = THEMES[themeIdx];
  });

  // ── The script ──────────────────────────────────────────────
  (async function main() {
    await sleep(400);
    for (;;) {
      step('live');
      await bloom();
      await sleep(6500);
      await type('clear'); await clear();
      await sleep(900);
      step('lotus');
      await type('lotus'); prompt(); await clear(); await bloom();
      await sleep(3800);
      step('settings');
      await type('/settings');
      await settingsDemo();
      step('live');
      await bloom();
      await sleep(6000);
      await type('clear'); await clear();
      await sleep(700);
    }
  })();
})();
