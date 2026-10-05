// Lotus website – the same fuzzy scoring as lib/fuzzy.zsh (exact, prefix, inside, initials, words, typos)
const Fuzzy = (() => {
  function lev(a, b) {
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
      const cur = [i];
      for (let j = 1; j <= b.length; j++) {
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }
  const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
  function score1(q, cand) {
    const c = norm(cand);
    if (!q || !c) return 0;
    if (q === c) return 100;
    if (c.startsWith(q)) return 90 + Math.floor((9 * q.length) / c.length);
    if (c.includes(q)) return 75 + Math.floor((10 * q.length) / c.length);
    const m = Math.max(q.length, c.length);
    let best = Math.floor(((m - lev(q, c)) * 80) / m);
    if (c.length > q.length + 2 && q.length >= 3) {
      best = Math.max(best, Math.floor(((q.length - lev(q, c.slice(0, q.length))) * 72) / q.length));
    }
    return best;
  }
  function score(query, cand) {
    const q = norm(query);
    let best = score1(q, cand);
    if (best >= 90) return best;
    const words = cand.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(Boolean);
    if (words.length > 1) {
      const ini = words.map((w) => w[0]).join('');
      if (ini.length >= 2 && q.startsWith(ini)) best = Math.max(best, 80);
      for (const w of words) if (w.length >= 3) best = Math.max(best, score1(q, w) - 6);
    }
    return best;
  }
  return { score };
})();
