// Lotus website – theme gallery from data/themes.tsv with a small start screen per theme
(async () => {
  const [themes, logo] = await Promise.all([Lotus.loadThemes(), Lotus.text('logos/minimal.txt')]);
  const art = logo.replace(/\s+$/, '').split('\n').map((l) => l.replace(/\s+$/, ''));
  const e = Lotus.esc;
  const info = [
    '<span class="t-b">Hello, </span><span class="t-acc">Alex</span>',
    '',
    '<span class="t-bor">┌──── </span><span class="t-acc">Hardware</span><span class="t-bor"> ────┐</span>',
    '<span class="t-key">├─ CPU </span>   Apple M4',
    '<span class="t-key">├─ RAM </span>   [<span class="t-key">■■■■</span><span class="t-dim">······</span>] 38%',
    '<span class="t-bor">└──────────────────┘</span>',
    '<span class="t-key2">├─ DATE</span>   18:42',
    '',
    '<span class="t-mus">♫ </span>Still Water <span class="t-bor">—</span> Aster',
    '  <span class="t-dim">01:12 / 03:34  ▶ playing</span>',
  ];
  const rows = Math.max(art.length, info.length);
  const top = Math.max(0, Math.floor((info.length - art.length) / 2));
  const screen = () => Array.from({ length: rows }, (_, i) => {
    const l = art[i - top] ?? '';
    return `<span class="t-logo">${e(l.padEnd(34))}</span>  ${info[i] ?? ''}`;
  }).join('\n');

  const grid = document.getElementById('themes');
  document.querySelector('.theme-total').textContent = themes.length;
  grid.innerHTML = themes.map((t) => `
    <article class="card theme-card reveal" data-theme="${t.name}">
      <div class="term"><div class="term-bar"><i></i><i></i><i></i></div><pre>${screen()}</pre></div>
      <div class="theme-meta">
        <div><h3>${e(t.label)}</h3><p class="muted swatches">${['logo', 'key', 'accent', 'key2', 'salute'].map((r) => `<i style="background:${t.colors[r]}"></i>`).join('')}</p></div>
        <button class="btn use">Use on this site</button>
      </div>
    </article>`).join('');
  grid.querySelectorAll('.theme-card').forEach((card) => Lotus.applyColors(card.querySelector('.term'), themes.find((t) => t.name === card.dataset.theme).colors));

  const mark = () => grid.querySelectorAll('.theme-card').forEach((c) => {
    const on = c.dataset.theme === document.documentElement.dataset.theme;
    c.classList.toggle('current', on);
    c.querySelector('.use').textContent = on ? 'Current' : 'Use on this site';
  });
  grid.addEventListener('click', (ev) => {
    const card = ev.target.closest('.use') && ev.target.closest('.theme-card');
    if (card) Lotus.setTheme(card.dataset.theme).then(mark);
  });
  mark();
  Lotus.reveal(grid);
})();
