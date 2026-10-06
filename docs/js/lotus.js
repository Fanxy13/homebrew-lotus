// Lotus website – shared building blocks: navigation, footer, data, themes, copy buttons, reveal.
// The data comes from the same files the terminal uses (data/*.tsv, logos/*.txt).
const Lotus = (() => {
  const PAGES = [
    ['index.html', 'Home'],
    ['commands.html', 'Commands'],
    ['themes.html', 'Themes'],
    ['ascii.html', 'ASCII Art'],
    ['apps.html', 'Apps'],
    ['ios.html', 'iOS Tools'],
    ['minecraft.html', 'Minecraft'],
    ['shortcuts.html', 'Shortcuts'],
    ['docs.html', 'Docs'],
  ];
  const PRIMARY = 5; // the rest goes into "More"

  // The Lotus mark: a lotus flower drawn as SVG (no emoji)
  const MARK = `<svg class="mark" viewBox="0 0 32 32" aria-hidden="true">
    <path d="M16 4c3.6 4.4 4 12 0 19.5C12 16 12.4 8.4 16 4z"/>
    <path d="M16 23.5c-5.6-1.2-8.8-6.6-8.4-12.8 4.2 1.8 7.4 6.6 8.4 12.8z"/>
    <path d="M16 23.5c5.6-1.2 8.8-6.6 8.4-12.8-4.2 1.8-7.4 6.6-8.4 12.8z"/>
    <path d="M16 25c-6.4.6-11.4-2.6-13.6-7.6 5.4-.4 10.4 2.6 13.6 7.6z"/>
    <path d="M16 25c6.4.6 11.4-2.6 13.6-7.6-5.4-.4-10.4 2.6-13.6 7.6z"/>
  </svg>`;

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

  // ── Data ────────────────────────────────────────────────────
  const cache = {};
  async function tsv(name) {
    if (!cache[name]) {
      cache[name] = fetch(`data/${name}.tsv`, { cache: 'no-cache' }).then((r) => r.text()).then((t) =>
        t.split('\n').filter((l) => l.trim() && !l.startsWith('#')).map((l) => l.split('\t')));
    }
    return cache[name];
  }
  async function text(path) { return (await fetch(path)).text(); }
  async function project() {
    const rows = await tsv('project');
    return Object.fromEntries(rows.map(([k, v]) => [k, (v || '').trim()]));
  }
  async function installCommands() {
    const p = await project();
    const owner = p.repo.split('/')[0];
    return {
      curl: `curl -fsSL https://raw.githubusercontent.com/${p.repo}/main/install.sh | zsh`,
      brew: `brew install ${owner}/lotus/lotus`,
    };
  }

  // ── Themes (data/themes.tsv) ────────────────────────────────
  const ROLES = ['logo', 'key', 'accent', 'key2', 'salute', 'border', 'dim', 'music'];
  let themes = null;
  async function loadThemes() {
    if (!themes) {
      themes = (await tsv('themes')).map(([name, label, ...rgb]) => ({
        name, label, colors: Object.fromEntries(ROLES.map((r, i) => [r, `rgb(${rgb[i].replace(/;/g, ', ')})`])),
      }));
    }
    return themes;
  }
  function applyColors(el, colors) {
    for (const [role, value] of Object.entries(colors)) el.style.setProperty(`--${role}`, value);
  }
  async function setTheme(name, { save = true } = {}) {
    const list = await loadThemes();
    const theme = list.find((t) => t.name === name) || list[0];
    applyColors(document.documentElement, theme.colors);
    document.documentElement.dataset.theme = theme.name;
    if (save) { try { localStorage.setItem('lotus-theme', theme.name); } catch { /* private mode */ } }
    dispatchEvent(new CustomEvent('lotus-theme', { detail: theme.name }));
    return theme;
  }
  function savedTheme() { try { return localStorage.getItem('lotus-theme'); } catch { return null; } }

  // ── Copy with a small burst of petals ───────────────────────
  async function copy(textToCopy, button) {
    try { await navigator.clipboard.writeText(textToCopy); } catch { /* clipboard blocked */ }
    if (!button) return;
    button.classList.add('done');
    const label = button.querySelector('.copy-label');
    const before = label?.textContent;
    if (label) label.textContent = 'Copied';
    setTimeout(() => { button.classList.remove('done'); if (label) label.textContent = before; }, 1400);
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const r = button.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    for (let i = 0; i < 14; i++) {
      const p = document.createElement('i');
      p.className = 'burst';
      document.body.appendChild(p);
      const a = Math.random() * Math.PI * 2, d = 50 + Math.random() * 80;
      p.animate([
        { transform: `translate(${cx}px, ${cy}px) rotate(0) scale(.6)`, opacity: 1 },
        { transform: `translate(${cx + Math.cos(a) * d}px, ${cy + Math.sin(a) * d + 30}px) rotate(${Math.random() * 540}deg)`, opacity: 0 },
      ], { duration: 900 + Math.random() * 400, easing: 'cubic-bezier(.22,1,.36,1)' }).onfinish = () => p.remove();
    }
  }
  const COPY_ICON = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="3"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>';
  function copyButton(value, label = '') {
    return `<button class="copy" data-copy="${esc(value)}" aria-label="Copy">${COPY_ICON}${label ? `<span class="copy-label">${esc(label)}</span>` : ''}</button>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-copy]');
    if (b) copy(b.dataset.copy, b);
  });

  // ── Reveal on scroll ────────────────────────────────────────
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }, { threshold: 0.12 });
  function reveal(root = document) { root.querySelectorAll('.reveal:not(.in)').forEach((el) => io.observe(el)); }

  // ── Components ──────────────────────────────────────────────
  const here = location.pathname.split('/').pop() || 'index.html';
  const GH = '<svg viewBox="0 0 16 16" width="18" height="18" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>';

  class LotusNav extends HTMLElement {
    connectedCallback() {
      const link = ([href, label]) => `<a href="${href}"${href === here ? ' aria-current="page"' : ''}>${label}</a>`;
      const moreActive = PAGES.slice(PRIMARY).some(([h]) => h === here);
      this.innerHTML = `
        <nav class="nav">
          <a class="brand" href="index.html">${MARK}<span>lotus</span></a>
          <button class="menu-toggle" aria-label="Menu" aria-expanded="false"><span></span><span></span></button>
          <div class="nav-links">
            ${PAGES.slice(1, PRIMARY).map(link).join('')}
            <div class="more${moreActive ? ' active' : ''}">
              <button class="more-btn" aria-haspopup="true">More<svg viewBox="0 0 12 12" width="10" height="10"><path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6"/></svg></button>
              <div class="more-menu">${PAGES.slice(PRIMARY).map(link).join('')}</div>
            </div>
            <a href="docs.html#install" class="pill">Install</a>
            <a href="https://github.com/Fanxy13/homebrew-lotus" class="gh" aria-label="Lotus on GitHub">${GH}</a>
          </div>
        </nav>`;
      const nav = this.querySelector('.nav');
      const toggle = this.querySelector('.menu-toggle');
      toggle.addEventListener('click', () => {
        const open = nav.classList.toggle('open');
        toggle.setAttribute('aria-expanded', open);
      });
      this.querySelector('.more-btn').addEventListener('click', (e) => {
        e.stopPropagation();
        this.querySelector('.more').classList.toggle('open');
      });
      document.addEventListener('click', () => this.querySelector('.more')?.classList.remove('open'));
      const solid = () => nav.classList.toggle('solid', scrollY > 30 || !document.querySelector('.hero'));
      addEventListener('scroll', solid, { passive: true });
      solid();
    }
  }

  class LotusFooter extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `
        <footer class="footer">
          <div class="footer-brand">${MARK}<span>lotus</span><small>Your terminal, in bloom.</small></div>
          <div class="footer-links">${PAGES.map(([h, l]) => `<a href="${h}">${l}</a>`).join('')}</div>
          <div class="footer-meta"><a href="https://github.com/Fanxy13/homebrew-lotus">GitHub</a><span>MIT license</span><a href="docs.html#changelog">Changelog</a></div>
        </footer>`;
    }
  }
  customElements.define('lotus-nav', LotusNav);
  customElements.define('lotus-footer', LotusFooter);

  // Install commands and project links come from data/project.tsv (one place for all URLs)
  async function fillProject() {
    const [p, cmds] = await Promise.all([project(), installCommands()]);
    document.querySelectorAll('[data-install]').forEach((el) => {
      const cmd = cmds[el.dataset.install];
      if (el.matches('.copy')) el.dataset.copy = cmd; else el.textContent = cmd;
    });
    document.querySelectorAll('[data-link]').forEach((a) => {
      const key = a.dataset.link;
      a.href = key === 'repo' ? `https://github.com/${p.repo}` : (p[key] || a.href);
      // Links that only exist once set in project.tsv (e.g. shortcut_url) start hidden
      const box = a.closest('[data-link-box]') || a;
      if (box.hidden && p[key]) box.hidden = false;
    });
  }

  // Favicon: the Lotus mark
  if (!document.querySelector('link[rel="icon"]')) {
    const svg = MARK.replace('<svg class="mark"', `<svg xmlns="http://www.w3.org/2000/svg" fill="#f8b8d055" stroke="#f8b8d0" stroke-width="1.6"`);
    const link = Object.assign(document.createElement('link'), { rel: 'icon', href: 'data:image/svg+xml,' + encodeURIComponent(svg) });
    document.head.appendChild(link);
  }

  // Theme, links and reveal for every page
  setTheme(savedTheme() || 'matcha', { save: false });
  addEventListener('DOMContentLoaded', () => { reveal(); fillProject(); });

  return { tsv, text, project, installCommands, loadThemes, setTheme, applyColors, copy, copyButton, esc, reveal, MARK };
})();
