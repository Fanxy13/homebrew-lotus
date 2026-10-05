// Lotus website – ASCII art: AI prompt builder, preview, import and export.
// No AI runs on this page and no keys are needed: the prompt goes to the AI the user picks.
(() => {
  const $ = (id) => document.getElementById(id);
  const MAX_W = 80, MAX_H = 40;   // same limits as "lotus logo import"
  const EXAMPLES = [['lotus', 'Lotus Classic'], ['minimal', 'Lotus Minimal'], ['large', 'Lotus Large'], ['terminal', 'Lotus Terminal']];

  // ── Prompt builder ──────────────────────────────────────────
  function buildPrompt() {
    const desc = $('desc').value.trim() || $('desc').placeholder;
    const chars = $('chars').value;
    const charRule = chars
      ? `Use only these characters (and spaces): ${JSON.stringify(chars.trim())}.`
      : 'Use only printable ASCII characters.';
    return [
      `Create ASCII art of: ${desc}.`,
      `Size: at most ${$('w').value} characters wide and ${$('h').value} lines tall.`,
      charRule,
      `Style: ${$('style').value}, designed for a monospace terminal with a dark background.`,
      'Center the subject, keep the edges clean, no text or signature.',
      'Reply with only the art inside one code block – no explanation.',
    ].join('\n');
  }
  function updatePrompt() {
    const p = buildPrompt();
    $('prompt').textContent = p;
    $('open-chatgpt').href = 'https://chatgpt.com/?q=' + encodeURIComponent(p);
    $('open-claude').href = 'https://claude.ai/new?q=' + encodeURIComponent(p);
  }
  ['desc', 'w', 'h', 'chars', 'style'].forEach((id) => $(id).addEventListener('input', updatePrompt));
  $('copy-prompt').addEventListener('click', (e) => Lotus.copy(buildPrompt(), e.currentTarget));
  updatePrompt();

  // ── Clean, check and preview ────────────────────────────────
  function clean(text) {
    let lines = text
      .replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '')          // color codes
      .replace(/```[a-z]*\n?|```/g, '')                // code fences from AI answers
      .replace(/\t/g, '    ')
      .split(/\r?\n/)
      .map((l) => l.replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '').replace(/\s+$/, ''));
    while (lines.length && !lines[0].trim()) lines.shift();
    while (lines.length && !lines.at(-1).trim()) lines.pop();
    return lines;
  }
  function show(text) {
    const lines = clean(text);
    const w = Math.max(0, ...lines.map((l) => [...l].length)), h = lines.length;
    $('preview').innerHTML = `<span class="t-logo">${Lotus.esc(lines.join('\n') || ' ')}</span>`;
    $('size').textContent = `${w} × ${h}`;
    const check = $('check');
    if (!h) { check.textContent = 'Paste or pick a logo to see it here.'; check.className = 'check'; }
    else if (w > MAX_W || h > MAX_H) { check.textContent = `Too big for Lotus: at most ${MAX_W} × ${MAX_H}.`; check.className = 'check bad'; }
    else { check.textContent = `Fits: ${w} × ${h}. Lotus switches to a smaller logo in narrow windows.`; check.className = 'check ok'; }
    return lines;
  }
  $('art').addEventListener('input', () => show($('art').value));
  $('file').addEventListener('change', async (e) => {
    const f = e.target.files[0];
    if (!f) return;
    if (f.size > 64 * 1024) { $('check').textContent = 'That file is too large for a logo.'; return; }
    $('art').value = await f.text();
    show($('art').value);
  });
  $('copy-art').addEventListener('click', (e) => Lotus.copy(clean($('art').value).join('\n'), e.currentTarget));
  $('download').addEventListener('click', () => {
    const blob = new Blob([clean($('art').value).join('\n') + '\n'], { type: 'text/plain' });
    const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: 'logo.txt' });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  });

  // ── Examples: the built-in logos ────────────────────────────
  const ex = $('examples');
  ex.innerHTML = EXAMPLES.map(([f, l], i) => `<button class="chip${i ? '' : ' active'}" data-file="${f}">${l}</button>`).join('');
  async function load(file) {
    const text = await Lotus.text(`logos/${file}.txt`);
    $('art').value = text;
    show(text);
  }
  ex.addEventListener('click', (e) => {
    const b = e.target.closest('.chip');
    if (!b) return;
    ex.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === b));
    load(b.dataset.file);
  });
  load('lotus');
})();
