// Lotus website – command cheatsheet, built from data/commands.tsv (the same file the terminal uses)
(async () => {
  const rows = (await Lotus.tsv('commands')).filter((r) => r[6] !== '1');
  const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const cats = [...new Set(rows.map((r) => r[0]))];
  const list = document.getElementById('commands');
  const filter = document.getElementById('filter');
  const chips = document.getElementById('cats');
  let active = 'All';

  chips.innerHTML = ['All', ...cats].map((c) => `<button class="chip${c === 'All' ? ' active' : ''}" data-cat="${Lotus.esc(c)}">${Lotus.esc(c)}</button>`).join('');
  chips.addEventListener('click', (e) => {
    const b = e.target.closest('.chip');
    if (!b) return;
    active = b.dataset.cat;
    chips.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === b));
    render();
  });
  filter.addEventListener('input', render);

  function render() {
    const q = filter.value.trim().toLowerCase();
    let html = '', count = 0;
    for (const cat of cats) {
      if (active !== 'All' && cat !== active) continue;
      const items = rows.filter((r) => r[0] === cat && (!q || r.slice(1, 6).join(' ').toLowerCase().includes(q)));
      if (!items.length) continue;
      count += items.length;
      html += `<section class="cmd-group" id="${slug(cat)}"><h2 class="cmd-cat">${Lotus.esc(cat)}</h2>`;
      for (const [, , , usage, desc, example] of items) {
        html += `<div class="cmd-row">
          <code class="cmd-usage">${Lotus.esc(usage)}</code>
          <span class="cmd-desc">${Lotus.esc(desc)}</span>
          <span class="cmd-ex"><code>${Lotus.esc(example)}</code>${Lotus.copyButton(example)}</span>
        </div>`;
      }
      html += '</section>';
    }
    list.innerHTML = html;
    document.querySelector('.empty').hidden = count > 0;
  }
  render();
  if (location.hash) document.querySelector(location.hash)?.scrollIntoView();
})();
