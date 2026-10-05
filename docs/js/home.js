// Lotus website – home page interactions
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ── Install commands (from data/project.tsv) ────────────────
  let CMDS = {};
  Lotus.installCommands().then((c) => {
    CMDS = c;
    $$('.install-pill').forEach((p) => { $('.cmd-text', p).textContent = CMDS[p.dataset.cmd]; });
  });
  $$('.install-copy').forEach((b) => b.addEventListener('click', () => Lotus.copy(CMDS[b.closest('.install-pill').dataset.cmd], b)));

  const tabs = $$('.tab'), glider = $('.tab-glider');
  function selectTab(tab) {
    tabs.forEach((t) => t.classList.toggle('active', t === tab));
    glider.style.width = tab.offsetWidth + 'px';
    glider.style.transform = `translateX(${tab.offsetLeft - 4}px)`;
    const pill = $('.install .install-pill');
    pill.dataset.cmd = tab.dataset.cmd;
    const text = $('.cmd-text', pill);
    text.animate([{ opacity: 0, transform: 'translateY(6px)', filter: 'blur(4px)' }, { opacity: 1, transform: 'none', filter: 'none' }], { duration: 400, easing: 'cubic-bezier(.22,1,.36,1)' });
    text.textContent = CMDS[tab.dataset.cmd] || text.textContent;
  }
  tabs.forEach((t) => t.addEventListener('click', () => selectTab(t)));
  addEventListener('load', () => selectTab($('.tab.active')));

  // ── Themes tile: one orb per theme in data/themes.tsv ───────
  Lotus.loadThemes().then((themes) => {
    const grid = $('.theme-grid');
    $('.theme-count').textContent = themes.length;
    grid.innerHTML = themes.map((t) => `<button class="orb" data-theme="${t.name}" aria-label="${Lotus.esc(t.label)}" style="--c1:${t.colors.logo};--c2:${t.colors.key}"><span>${Lotus.esc(t.label)}</span></button>`).join('');
    const mark = () => {
      const now = document.documentElement.dataset.theme;
      $$('.orb', grid).forEach((o) => o.classList.toggle('active', o.dataset.theme === now));
      $('.theme-name').textContent = themes.find((t) => t.name === now)?.label || 'tap one';
    };
    grid.addEventListener('click', (e) => {
      const orb = e.target.closest('.orb');
      if (orb) Lotus.setTheme(orb.dataset.theme).then(mark);
    });
    mark();
  });

  // ── Hello in 15 languages ───────────────────────────────────
  const HELLOS = [['Bonjour', 'French'], ['こんにちは', 'Japanese'], ['Hello', 'English'], ['Grüezi', 'Swiss German'], ['你好', 'Chinese'],
    ['Hola', 'Spanish'], ['Ciao', 'Italian'], ['안녕하세요', 'Korean'], ['Olá', 'Portuguese'], ['Hej', 'Swedish'], ['नमस्ते', 'Hindi'],
    ['Aloha', 'Hawaiian'], ['Γειά σου', 'Greek'], ['Xin chào', 'Vietnamese'], ['Allillanchu', 'Quechua']];
  const word = $('.hello-word'), langEl = $('.hello-lang');
  const GLYPHS = 'アイウエオ안녕你好ΓλΩжæøß';
  let h = 0;
  setInterval(() => {
    h = (h + 1) % HELLOS.length;
    const [target, lang] = HELLOS[h];
    langEl.textContent = lang;
    if (reduce) { word.textContent = target; return; }
    const chars = [...target];
    let f = 0;
    const id = setInterval(() => {
      f++;
      word.textContent = chars.map((c, i) => (i < (f / 10) * chars.length ? c : GLYPHS[(Math.random() * GLYPHS.length) | 0])).join('');
      if (f >= 10) { clearInterval(id); word.textContent = target; }
    }, 40);
  }, 2200);

  // ── Now playing ─────────────────────────────────────────────
  const TRACKS = [['Midnight Bloom', 'Koi Pond'], ['Neon Petals', 'Lumen'], ['Still Water', 'Aster'], ['Paper Lanterns', 'Mori']];
  let tr = 0, prog = 15;
  const npBar = $('.np-bar span'), npTitle = $('.np-title'), npArtist = $('.np-artist');
  setInterval(() => {
    prog += 4;
    if (prog > 100) {
      prog = 0; tr = (tr + 1) % TRACKS.length;
      [npTitle.textContent, npArtist.textContent] = TRACKS[tr];
      [npTitle, npArtist].forEach((el) => el.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }], { duration: 500 }));
    }
    npBar.style.width = prog + '%';
  }, 1000);

  // ── /settings keys + interface languages ────────────────────
  const keys = $$('.keys kbd'), langs = $$('.langs span');
  let ks = 0, li = 0;
  langs[0].classList.add('on');
  setInterval(() => {
    const k = [0, 1, 1, 2][ks++ % 4];
    keys[k].classList.add('press');
    setTimeout(() => keys[k].classList.remove('press'), 160);
    if (k === 2) { langs[li].classList.remove('on'); li = (li + 1) % langs.length; langs[li].classList.add('on'); }
  }, 700);

  // ── Small typed terminal scenes (/ai, /app) ─────────────────
  async function typeScene(el, lines, pause = 2600) {
    const visible = () => el.getBoundingClientRect().top < innerHeight && el.getBoundingClientRect().bottom > 0;
    for (;;) {
      if (!visible() && !reduce) { await sleep(800); continue; }
      el.innerHTML = '';
      for (const [cls, text, speed] of lines) {
        const span = document.createElement('span');
        span.className = cls;
        el.appendChild(span);
        for (const ch of text) {
          span.textContent += ch;
          if (speed && !reduce) await sleep(speed);
        }
        el.appendChild(document.createTextNode('\n'));
        if (!speed && !reduce) await sleep(350);
      }
      const caret = document.createElement('span');
      caret.className = 'caret';
      el.appendChild(caret);
      await sleep(pause * 2);
    }
  }
  typeScene($('.ai-term'), [
    ['p', '% /ai what is a symlink?', 45],
    ['a', 'A symlink is a file that points to another', 12],
    ['a', 'file or folder, like a shortcut.', 12],
  ]);
  typeScene($('.app-term'), [
    ['p', '% /app spotfy', 70],
    ['a', '  Did you mean "Spotify"? [Y/n] yes', 0],
    ['a', '  › Opening Spotify', 0],
  ]);

  // ── Tiles tilt, light follows the pointer ───────────────────
  if (!reduce && matchMedia('(hover: hover)').matches) {
    $$('.tile').forEach((tile) => {
      tile.addEventListener('pointermove', (e) => {
        const r = tile.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
        tile.style.setProperty('--mx', x * 100 + '%');
        tile.style.setProperty('--my', y * 100 + '%');
        tile.style.setProperty('--ry', (x - 0.5) * 10 + 'deg');
        tile.style.setProperty('--rx', (0.5 - y) * 10 + 'deg');
      });
      tile.addEventListener('pointerleave', () => { tile.style.setProperty('--rx', '0deg'); tile.style.setProperty('--ry', '0deg'); });
    });
    const win = $('#terminal');
    win.addEventListener('pointermove', (e) => {
      const r = win.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
      win.style.transform = `perspective(1600px) rotateX(${-y * 3}deg) rotateY(${x * 4}deg)`;
    });
    win.addEventListener('pointerleave', () => { win.style.transform = ''; });
  }
})();
