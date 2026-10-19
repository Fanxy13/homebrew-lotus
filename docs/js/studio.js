// Lotus website – Theme Studio: make your own theme and watch a start screen change with it.
// The built-in themes come from data/themes.tsv and the logos from logos/*.txt – the files Lotus
// uses. The result is the line Lotus takes: lotus themes add <name> <8 colors>.
(async () => {
  const $ = (id) => document.getElementById(id);
  const e = Lotus.esc;
  // role, name, what it colors in Lotus (same order as data/themes.tsv)
  const ROLES = [
    ['logo', 'Logo', 'the lotus – the middle of the gradient'],
    ['key', 'Keys', 'CPU, RAM, the bars – the end of the gradient'],
    ['accent', 'Accent', 'your name, box titles, the selected row'],
    ['key2', 'Second keys', 'uptime and date – the start of the gradient'],
    ['salute', 'Greeting', 'the greeting at the bottom'],
    ['border', 'Borders', 'the lines of the boxes'],
    ['dim', 'Dim text', 'hints, times, what is off'],
    ['music', 'Music', 'the ♫ of now playing'],
  ];
  const LOGOS = [['lotus', 'Lotus Classic'], ['minimal', 'Lotus Minimal'], ['terminal', 'Lotus Terminal'], ['apple', 'Apple'], ['earth', 'Flag of Earth']];
  const TERM_BG = '#0e1311';
  // block characters by their lit quarters (top left 1, top right 2, bottom left 4, bottom right 8), shades
  const QUAD = { '▘': 1, '▝': 2, '▀': 3, '▖': 4, '▌': 5, '▞': 6, '▛': 7, '▗': 8, '▚': 9, '▐': 10, '▜': 11, '▄': 12, '▙': 13, '▟': 14, '█': 15 };
  const SHADE = { '░': 0.25, '▒': 0.5, '▓': 0.75 };

  // ── Colors ──────────────────────────────────────────────────
  const hexOf = (rgb) => '#' + rgb.match(/\d+/g).slice(0, 3).map((n) => (+n).toString(16).padStart(2, '0')).join('');
  const rgbOf = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const validHex = (s) => /^#?[0-9a-f]{6}$/i.test(s.trim());
  const normHex = (s) => '#' + s.trim().replace(/^#/, '').toLowerCase();
  const lum = (hex) => {
    const [r, g, b] = rgbOf(hex).map((v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  // OKLab, like Lotus (lib/art.zsh): the gradient of the logo is mixed there
  const toLin = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  function oklab(hex) {
    const [r, g, b] = rgbOf(hex).map(toLin);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
  }
  function fromOklab([L, A, B]) {
    const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3, m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
    const s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3;
    return 'rgb(' + [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s].map((v) => {
      v = Math.min(1, Math.max(0, v));
      return Math.round((v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055) * 255);
    }).join(', ') + ')';
  }
  // One color per half line of the logo: second key color → logo color → key color, or the logo color
  function halfColors(rows) {
    const c = state.colors;
    if (!state.fade) return Array(2 * rows).fill(c.logo);
    const stops = [c.key2, c.logo, c.key].map(oklab), n = stops.length - 1;
    return Array.from({ length: 2 * rows }, (_, k) => {
      let t = rows > 0 ? k / (2 * rows - 1) * n : 0, s = Math.min(Math.floor(t), n - 1);
      const u = t - s;
      return fromOklab(stops[s].map((v, i) => v + (stops[s + 1][i] - v) * u));
    });
  }

  // OKLCH → hex, with less chroma until the color fits into sRGB
  function oklch(L, C, h) {
    for (let c = C; c >= 0; c -= 0.004) {
      const a = c * Math.cos(h * Math.PI / 180), b = c * Math.sin(h * Math.PI / 180);
      const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
      const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
      const s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3;
      const rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
      if (rgb.every((v) => v >= -0.001 && v <= 1.001)) {
        return '#' + rgb.map((v) => {
          v = Math.min(1, Math.max(0, v));
          v = v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055;
          return Math.round(v * 255).toString(16).padStart(2, '0');
        }).join('');
      }
    }
    return '#808080';
  }
  // A theme that holds together: two hues for the gradient, quiet borders, light text colors
  function shuffle() {
    const h = Math.random() * 360, turn = [120, 150, 180, 210][Math.floor(Math.random() * 4)];
    return {
      logo: oklch(0.82, 0.13, h), key: oklch(0.8, 0.15, h + turn), accent: oklch(0.86, 0.1, h + turn - 20),
      key2: oklch(0.9, 0.12, h - turn / 2), salute: oklch(0.88, 0.08, h + 25), border: oklch(0.68, 0.025, h),
      dim: oklch(0.6, 0.02, h), music: '#1ed760',
    };
  }

  // ── Data ────────────────────────────────────────────────────
  const themes = await Lotus.loadThemes();
  const builtIn = themes.map((t) => ({ name: t.name, label: t.label, colors: Object.fromEntries(ROLES.map(([r]) => [r, hexOf(t.colors[r])])) }));
  const logoText = {};
  async function logo(name) {
    if (!logoText[name]) logoText[name] = Lotus.text(`logos/${name}.txt`).then((t) => t.replace(/\s+$/, '').split('\n').map((l) => l.replace(/\s+$/, '')));
    return logoText[name];
  }

  // ── State: from a shared link, from the last visit, or Matcha ─
  const state = { base: 'matcha', name: '', colors: { ...builtIn[0].colors }, logo: 'lotus', fade: true };
  function fromHash() {
    const m = location.hash.match(/^#t=(.+)$/);
    if (!m) return false;
    const p = decodeURIComponent(m[1]).split('|');
    if (p.length < 9 || !p.slice(1, 9).every(validHex)) return false;
    state.name = p[0].slice(0, 24);
    ROLES.forEach(([r], i) => { state.colors[r] = normHex(p[i + 1]); });
    if (LOGOS.some(([n]) => n === p[9])) state.logo = p[9];
    state.fade = p[10] !== '0';
    state.base = '';
    return true;
  }
  function fromStorage() {
    try {
      const s = JSON.parse(localStorage.getItem('lotus-studio') || 'null');
      if (s && ROLES.every(([r]) => validHex(s.colors?.[r] || ''))) Object.assign(state, s);
    } catch { /* private mode or old data */ }
  }
  const save = () => { try { localStorage.setItem('lotus-studio', JSON.stringify(state)); } catch { /* private mode */ } };
  if (!fromHash()) fromStorage();

  // ── Controls ────────────────────────────────────────────────
  $('base').innerHTML = (state.base ? '' : '<option value="">Your colors</option>') +
    builtIn.map((t) => `<option value="${t.name}">${e(t.label)}</option>`).join('');
  $('base').value = state.base;
  $('logo').innerHTML = LOGOS.map(([n, l]) => `<option value="${n}">${l}</option>`).join('');
  $('logo').value = state.logo;
  $('fade').checked = state.fade;
  $('name').value = state.name;
  $('roles').innerHTML = ROLES.map(([r, label, what]) => `
    <div class="role" data-role="${r}">
      <label class="swatch" style="--c:${state.colors[r]}"><input type="color" value="${state.colors[r]}" aria-label="${label}"></label>
      <div class="role-text"><b>${label}</b><small>${what}</small></div>
      <input class="hex" value="${state.colors[r]}" maxlength="7" spellcheck="false" aria-label="${label} as hex">
      <span class="hard" hidden title="Hard to read on a dark terminal">dark</span>
    </div>`).join('');

  function setColor(role, hex, from) {
    state.colors[role] = hex;
    const row = $('roles').querySelector(`[data-role="${role}"]`);
    row.querySelector('.swatch').style.setProperty('--c', hex);
    if (from !== 'picker') row.querySelector('input[type=color]').value = hex;
    if (from !== 'hex') { row.querySelector('.hex').value = hex; row.querySelector('.hex').classList.remove('bad'); }
    // borders and dim text may be quiet; the rest has to be readable on a dark terminal
    row.querySelector('.hard').hidden = contrast(hex, TERM_BG) >= (role === 'border' || role === 'dim' ? 2 : 3);
  }
  function custom() {
    if ($('base').value) {
      $('base').insertAdjacentHTML('afterbegin', '<option value="">Your colors</option>');
      $('base').value = '';
      state.base = '';
    }
  }
  $('roles').addEventListener('input', (ev) => {
    const row = ev.target.closest('.role');
    if (!row) return;
    if (ev.target.type === 'color') setColor(row.dataset.role, ev.target.value, 'picker');
    else if (ev.target.classList.contains('hex')) {
      const ok = validHex(ev.target.value);
      ev.target.classList.toggle('bad', !ok);
      if (!ok) return;
      setColor(row.dataset.role, normHex(ev.target.value), 'hex');
    }
    custom();
    update();
  });
  $('base').addEventListener('change', () => {
    const t = builtIn.find((x) => x.name === $('base').value);
    if (!t) return;
    $('base').querySelector('option[value=""]')?.remove();
    state.base = t.name;
    ROLES.forEach(([r]) => setColor(r, t.colors[r]));
    update();
  });
  $('shuffle').addEventListener('click', () => {
    const c = shuffle();
    ROLES.forEach(([r]) => setColor(r, c[r]));
    custom();
    update();
  });
  $('reset').addEventListener('click', () => {
    const t = builtIn.find((x) => x.name === (state.base || 'matcha')) || builtIn[0];
    ROLES.forEach(([r]) => setColor(r, t.colors[r]));
    update();
  });
  $('name').addEventListener('input', () => { state.name = $('name').value; update(); });
  $('logo').addEventListener('change', () => { state.logo = $('logo').value; update(); });
  $('fade').addEventListener('change', () => { state.fade = $('fade').checked; update(); });

  // ── The preview: the start screen as Lotus draws it ─────────
  const bar = (n) => `[<span class="t-key">${'■'.repeat(n)}</span><span class="t-dim">${'·'.repeat(10 - n)}</span>]`;
  const box = (title, cls) => {
    const t = ` ${title} `, left = Math.floor((42 - t.length) / 2);
    return `<span class="t-bor">┌${'─'.repeat(left)}</span><span class="${cls}">${t}</span><span class="t-bor">${'─'.repeat(42 - t.length - left)}┐</span>`;
  };
  const end = '<span class="t-bor">└' + '─'.repeat(42) + '┘</span>';
  const row = (key, value, cls = 't-key') => `<span class="${cls}">${(`├─ ${key}`).padEnd(14)}</span>${value}`;
  const INFO = [
    '<span class="t-b">Grüezi, </span><span class="t-acc">Alex</span>',
    '',
    box('Hardware', 't-acc'),
    row('CPU', 'Apple M4 (10C / 10T) @ 4.46 GHz'),
    row('GPU', 'Apple M4 [Integrated] // 10 Cores'),
    row('RAM', `12.40 GiB / 24.00 GiB ${bar(5)} 52%`),
    row('SWAP', `0.90 GiB / 2.00 GiB ${bar(4)} 45%`),
    row('DRIVE', `/ 163.35 GiB / 926.30 GiB ${bar(2)} 18%`),
    end,
    '',
    box('Session', 't-acc'),
    row('LOGIN', 'alex // 2026-10-19 09:41:00'),
    end,
    '',
    box('Uptime / Date', 't-key2'),
    row('UPTIME', '2 days, 4 hours', 't-key2'),
    row('DATE', '2026-10-19 09:41:12', 't-key2'),
    end,
    '',
    '<span class="t-mus">♫ </span>Still Water <span class="t-bor">—</span> Aster',
    `  ${bar(3)} <span class="t-dim">01:12 / 03:34  ▶ playing</span>`,
  ];
  function menu(name) {
    const label = (s) => s.padEnd(32);
    return [
      '',
      '  <span class="t-acc"><b>lotus</b></span><span class="t-dim"> / Settings · v2.18.2</span>',
      '',
      '  <span class="t-dim">GENERAL</span>',
      `    ${label('Logo')}${e(LOGOS.find(([n]) => n === state.logo)[1])}`,
      `    ${label('Logo in theme colors')}<span class="t-key">● on</span>`,
      `    ${label('Logo gradient')}${state.fade ? '<span class="t-key">● on</span>' : '<span class="t-dim">○ off</span>'}`,
      `  <span class="t-acc">›</span> <span class="t-b">${label('Theme')}</span>‹ ${e(name)} ›`,
      `    ${label('Colored prompt')}<span class="t-dim">○ off</span>`,
      '',
      '  <span class="t-dim">↑↓ select   ←→ ⏎ change   v preview   r reset   q done</span>',
    ].join('\n');
  }
  const quote = (s) => (/^[A-Za-z0-9._-]+$/.test(s) ? s : `'${s.replace(/'/g, "'\\''")}'`);

  // The logo on a canvas, cell by cell like a terminal: block characters touch, a cell can hold
  // two colors (Lotus draws half lines), the font gives the size of a cell
  let artLines = [];
  function drawArt(lines = artLines) {
    artLines = lines;
    const cv = $('art'), info = getComputedStyle($('info'));
    const fs = parseFloat(info.fontSize), ch = parseFloat(info.lineHeight) || fs * 1.2;
    const g = cv.getContext('2d');
    g.font = `600 ${fs}px "JetBrains Mono", ui-monospace, monospace`;
    const cw = g.measureText('M').width;
    // the logo sits next to the info like in Lotus: two rows down, or centered when it is smaller
    const top = lines.length >= INFO.length - 2 ? 2 : Math.floor((INFO.length - lines.length) / 2);
    const cols = Math.max(...lines.map((l) => [...l].length)), rows = top + lines.length, dpr = devicePixelRatio || 1;
    cv.width = Math.ceil(cols * cw * dpr); cv.height = Math.ceil(rows * ch * dpr);
    cv.style.width = `${cols * cw}px`; cv.style.height = `${rows * ch}px`;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.font = `600 ${fs}px "JetBrains Mono", ui-monospace, monospace`;
    g.textBaseline = 'middle';
    const colors = halfColors(lines.length);
    lines.forEach((line, i) => {
      const y0 = (top + i) * ch, ym = y0 + ch / 2, y1 = y0 + ch, top2 = colors[2 * i], bot = colors[2 * i + 1];
      [...line].forEach((c, j) => {
        const x0 = j * cw, xm = x0 + cw / 2, x1 = x0 + cw;
        const q = QUAD[c];
        if (q) {
          for (const [bit, a, b, yy0, yy1, col] of [[1, x0, xm, y0, ym, top2], [2, xm, x1, y0, ym, top2], [4, x0, xm, ym, y1, bot], [8, xm, x1, ym, y1, bot]]) {
            if (q & bit) { g.fillStyle = col; g.fillRect(a, yy0, b - a + 0.4, yy1 - yy0 + 0.4); }
          }
        } else if (SHADE[c]) {
          g.globalAlpha = SHADE[c]; g.fillStyle = bot; g.fillRect(x0, y0, cw + 0.4, ch + 0.4); g.globalAlpha = 1;
        } else if (c !== ' ') {
          g.fillStyle = bot; g.fillText(c, x0, ym);
        }
      });
    });
  }
  new ResizeObserver(() => artLines.length && drawArt()).observe(document.querySelector('.studio-term'));
  document.fonts?.ready.then(() => artLines.length && drawArt());

  let drawn = 0;
  async function update() {
    const id = ++drawn;
    const lines = await logo(state.logo);
    if (id !== drawn) return;
    const name = state.name.trim() || 'My theme';
    const pv = $('preview');
    Lotus.applyColors(pv, Object.fromEntries(ROLES.map(([r]) => [r, state.colors[r]])));
    $('info').innerHTML = INFO.join('\n');
    drawArt(lines);
    $('below').innerHTML = `<span class="t-sal">Good morning, Alex.</span>\n\n<span class="t-acc">alex@MacBook ~ %</span> <span class="cursor"></span>`;
    $('menu').innerHTML = menu(name);
    $('cmd').textContent = `lotus themes add ${quote(name)} ${ROLES.map(([r]) => state.colors[r].slice(1)).join(' ')}`;
    const link = `#t=${encodeURIComponent([name, ...ROLES.map(([r]) => state.colors[r].slice(1)), state.logo, state.fade ? 1 : 0].join('|'))}`;
    history.replaceState(null, '', link);
    save();
  }

  $('copy-cmd').addEventListener('click', (ev) => { ev.stopPropagation(); Lotus.copy($('cmd').textContent, ev.currentTarget); });
  $('share').addEventListener('click', (ev) => Lotus.copy(location.href, ev.currentTarget));
  addEventListener('hashchange', () => {
    if (!fromHash()) return;
    ROLES.forEach(([r]) => setColor(r, state.colors[r]));
    $('name').value = state.name; $('logo').value = state.logo; $('fade').checked = state.fade;
    custom();
    update();
  });

  ROLES.forEach(([r]) => setColor(r, state.colors[r]));
  update();
})();
