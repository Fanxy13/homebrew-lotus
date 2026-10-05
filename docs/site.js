// lotus – page interactions
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ── Reveal on scroll ────────────────────────────────────────
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }, { threshold: 0.18 });
  $$('.reveal:not(.hero .reveal)').forEach((el) => io.observe(el));

  // ── Nav gets a glass background once you scroll ─────────────
  const nav = $('.nav');
  addEventListener('scroll', () => nav.classList.toggle('solid', scrollY > 40), { passive: true });

  // ── Install commands ────────────────────────────────────────
  const CMDS = {
    curl: 'curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh',
    brew: 'brew install Fanxy13/lotus/lotus && lotus setup',
  };
  const tabs = $$('.tab'), glider = $('.tab-glider');
  function selectTab(tab) {
    tabs.forEach((t) => t.classList.toggle('active', t === tab));
    glider.style.width = tab.offsetWidth + 'px';
    glider.style.transform = `translateX(${tab.offsetLeft - 4}px)`;
    const pill = $('.install .install-pill');
    pill.dataset.cmd = tab.dataset.cmd;
    const text = $('.cmd-text', pill);
    text.animate([{ opacity: 0, transform: 'translateY(6px)', filter: 'blur(4px)' }, { opacity: 1, transform: 'none', filter: 'none' }], { duration: 400, easing: 'cubic-bezier(.22,1,.36,1)' });
    text.textContent = CMDS[tab.dataset.cmd];
  }
  tabs.forEach((t) => t.addEventListener('click', () => selectTab(t)));
  addEventListener('load', () => selectTab($('.tab.active')));

  // Copy + a little burst of petals
  $$('.copy').forEach((btn) => btn.addEventListener('click', async () => {
    const cmd = CMDS[btn.closest('.install-pill').dataset.cmd];
    try { await navigator.clipboard.writeText(cmd); } catch { /* clipboard blocked: still celebrate */ }
    btn.classList.add('done');
    setTimeout(() => btn.classList.remove('done'), 1400);
    if (!reduce) burst(btn);
  }));

  function burst(el) {
    const r = el.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    for (let i = 0; i < 18; i++) {
      const p = document.createElement('i');
      p.className = 'burst';
      document.body.appendChild(p);
      const a = Math.random() * Math.PI * 2, d = 60 + Math.random() * 90;
      p.animate([
        { transform: `translate(${cx}px, ${cy}px) rotate(0) scale(.6)`, opacity: 1 },
        { transform: `translate(${cx + Math.cos(a) * d}px, ${cy + Math.sin(a) * d + 40}px) rotate(${Math.random() * 540}deg) scale(1)`, opacity: 0 },
      ], { duration: 900 + Math.random() * 500, easing: 'cubic-bezier(.22,1,.36,1)' }).onfinish = () => p.remove();
    }
  }

  // ── Themes: recolor the whole page, the 3D lotus and the demo ─
  const orbs = $$('.orb');
  function setTheme(name) {
    document.documentElement.dataset.theme = name;
    orbs.forEach((o) => o.classList.toggle('active', o.dataset.theme === name));
    dispatchEvent(new CustomEvent('lotus-theme', { detail: name }));
    try { localStorage.setItem('lotus-theme', name); } catch { /* private mode */ }
  }
  orbs.forEach((o) => o.addEventListener('click', () => setTheme(o.dataset.theme)));
  let saved = null;
  try { saved = localStorage.getItem('lotus-theme'); } catch { /* ignore */ }
  setTheme(saved || 'matcha');

  // ── Tile: hello in 15 languages ─────────────────────────────
  const HELLOS = [['Bonjour', 'French'], ['こんにちは', 'Japanese'], ['Hello', 'English'], ['Grüezi', 'Swiss German'], ['你好', 'Chinese'],
    ['Hola', 'Spanish'], ['Ciao', 'Italian'], ['안녕하세요', 'Korean'], ['Olá', 'Portuguese'], ['Hej', 'Swedish'], ['नमस्ते', 'Hindi'],
    ['Aloha', 'Hawaiian'], ['Γειά σου', 'Greek'], ['Xin chào', 'Vietnamese'], ['Allillanchu', 'Quechua']];
  const word = $('.hello-word'), langEl = $('.hello-lang');
  let h = 0;
  const GLYPHS = 'アイウエオ안녕你好ΓλΩжæøß';
  setInterval(() => {
    h = (h + 1) % HELLOS.length;
    const [target, lang] = HELLOS[h];
    langEl.textContent = lang;
    if (reduce) { word.textContent = target; return; }
    let f = 0;
    const chars = [...target];
    const id = setInterval(() => {
      f++;
      word.textContent = chars.map((c, i) => (i < (f / 10) * chars.length ? c : GLYPHS[(Math.random() * GLYPHS.length) | 0])).join('');
      if (f >= 10) { clearInterval(id); word.textContent = target; }
    }, 40);
  }, 2200);

  // ── Tile: now playing ───────────────────────────────────────
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

  // ── Tile: /settings keys + interface languages ──────────────
  const keys = $$('.keys kbd'), langs = $$('.langs span');
  let ks = 0, li = 0;
  langs[0].classList.add('on');
  setInterval(() => {
    const k = [0, 1, 1, 2][ks++ % 4];
    keys[k].classList.add('press');
    setTimeout(() => keys[k].classList.remove('press'), 160);
    if (k === 2) {
      langs[li].classList.remove('on');
      li = (li + 1) % langs.length;
      langs[li].classList.add('on');
    }
  }, 700);

  // ── Tile: startup speed counts up when visible ──────────────
  const speedTile = $('.tile-speed'), num = $('.speed-num');
  new IntersectionObserver(([e], obs) => {
    if (!e.isIntersecting) return;
    obs.disconnect();
    speedTile.classList.add('in');
    const t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / 1400);
      num.textContent = Math.round(35 * (1 - Math.pow(1 - k, 3)));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }, { threshold: 0.5 }).observe(speedTile);

  // ── Tiles: 3D tilt + light that follows the pointer ─────────
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

    // The terminal window tilts a little, too
    const win = $('#terminal');
    win.addEventListener('pointermove', (e) => {
      const r = win.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
      win.style.transform = `perspective(1600px) rotateX(${-y * 3}deg) rotateY(${x * 4}deg)`;
    });
    win.addEventListener('pointerleave', () => { win.style.transform = ''; });
  }
})();
