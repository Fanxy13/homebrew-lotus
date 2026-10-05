// Lotus website – the /install catalog from data/apps.tsv, with the same fuzzy search as the terminal
(async () => {
  const rows = (await Lotus.tsv('apps')).map(([name, cask, cats, app, desc]) => ({ name, cask, cats: cats.split(','), desc }));
  const order = ['Browsers', 'Communication', 'Microsoft', 'Development', 'Media', 'Utilities', 'Games', 'Productivity', 'Free alternatives', 'Open-source software'];
  const list = document.getElementById('apps'), filter = document.getElementById('filter'), chips = document.getElementById('cats');
  let active = 'All';
  document.querySelector('.app-total').textContent = rows.length;

  chips.innerHTML = ['All', ...order].map((c) => `<button class="chip${c === 'All' ? ' active' : ''}" data-cat="${Lotus.esc(c)}">${Lotus.esc(c)}</button>`).join('');
  chips.addEventListener('click', (e) => {
    const b = e.target.closest('.chip');
    if (!b) return;
    active = b.dataset.cat;
    chips.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === b));
    render();
  });
  filter.addEventListener('input', render);

  function render() {
    const q = filter.value.trim();
    let items = rows.filter((r) => active === 'All' || r.cats.includes(active));
    if (q) {
      items = items.map((r) => ({ r, s: Math.max(Fuzzy.score(q, r.name), Fuzzy.score(q, r.cask) - 2) }))
        .filter((x) => x.s >= 55).sort((a, b) => b.s - a.s).map((x) => x.r);
    }
    list.innerHTML = items.map((a) => `
      <article class="card app-card">
        <div class="app-head"><span class="app-icon">${Lotus.esc(a.name[0])}</span><div><h3>${Lotus.esc(a.name)}</h3><p class="muted small">Homebrew Cask · ${Lotus.esc(a.cask)}</p></div></div>
        <p class="app-desc">${Lotus.esc(a.desc)}</p>
        <p>${a.cats.map((c) => `<span class="tag">${Lotus.esc(c)}</span>`).join('')}</p>
        <div class="codeblock small"><code><span class="dollar">$</span> /install ${Lotus.esc(a.name)}</code>${Lotus.copyButton('/install ' + a.name)}</div>
      </article>`).join('');
    document.querySelector('.empty').hidden = items.length > 0;
  }
  render();
})();
