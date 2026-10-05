// Lotus website – iOS tools from data/ios-tools.tsv with the same compatibility rules as lib/cmd/ios.zsh
(async () => {
  const tools = (await Lotus.tsv('ios-tools')).map(([id, name, kind, desc, source, repo, app, asset, min, max, warning]) =>
    ({ id, name, kind, desc, source, min, max, warning: warning === '-' ? '' : warning }));
  const DEVICES = [
    ['iPhone 8 / X (A11)', 'A11'], ['iPhone XS / XR (A12)', 'A12'], ['iPhone 11 (A13)', 'A13'], ['iPhone 12 (A14)', 'A14'],
    ['iPhone 13 / 14 (A15)', 'A15'], ['iPhone 14 Pro / 15 (A16)', 'A16'], ['iPhone 15 Pro (A17)', 'A17'], ['iPhone 16 (A18)', 'A18'],
    ['iPhone 17 (A19)', 'A19'], ['iPad or other', ''],
  ];
  const le = (a, b) => {
    const x = a.split('.').map(Number), y = b.split('.').map(Number);
    for (let i = 0; i < 3; i++) { if ((x[i] || 0) < (y[i] || 0)) return true; if ((x[i] || 0) > (y[i] || 0)) return false; }
    return true;
  };
  function compat(t, ver, chip) {
    if (!/^\d+(\.\d+){0,2}$/.test(ver)) return ['unknown', 'Enter a version like 18.6'];
    if (!le(t.min, ver)) return ['no', `needs iOS ${t.min} or newer`];
    if (t.max !== '-' && !le(ver, t.max)) return ['no', `supports up to iOS ${t.max.replace('26.99', '26.x')}`];
    if (t.id === 'dopamine') {
      if (!chip) return ['unknown', 'depends on the chip – check the Dopamine page'];
      let limit = '17.3.1';
      if (['A8', 'A9', 'A10', 'A11'].includes(chip)) limit = '18.7.1';
      if (['A12', 'A13'].includes(chip)) {
        if (!le(ver, '18.7.1') && !ver.startsWith('26.0')) return ['no', `${chip}: iOS 15.0–18.7.1 or 26.0–26.0.1`];
        limit = '26.0.1';
      }
      if (!le(ver, limit)) return ['no', `${chip} supports up to iOS ${limit}`];
    }
    return ['ok', 'compatible'];
  }

  const sel = document.getElementById('device'), ver = document.getElementById('version'), list = document.getElementById('tools');
  sel.innerHTML = DEVICES.map(([l, c], i) => `<option value="${c}"${i === 1 ? ' selected' : ''}>${Lotus.esc(l)}</option>`).join('');
  const e = Lotus.esc;
  function render() {
    list.innerHTML = tools.map((t) => {
      const [state, why] = compat(t, ver.value.trim(), sel.value);
      return `<article class="card tool-card">
        <div class="tool-head"><h3>${e(t.name)}</h3><span class="state ${state}">${state === 'ok' ? 'Compatible' : state === 'no' ? 'Not compatible' : 'Unknown'}</span></div>
        <p>${e(t.desc)}</p>
        <table class="mini">
          <tr><td>Type</td><td>${t.kind === 'ipa' ? 'iOS app (IPA), installed with Sideloadly or TrollStore' : 'Mac app'}</td></tr>
          <tr><td>Supports</td><td>iOS ${e(t.min)}${t.max === '-' ? ' and newer' : ' – ' + e(t.max.replace('26.99', '26.x'))}</td></tr>
          <tr><td>Your device</td><td>${e(why)}</td></tr>
          <tr><td>Source</td><td><a href="${e(t.source)}" target="_blank" rel="noopener">${e(t.source.replace('https://', ''))}</a></td></tr>
        </table>
        ${t.warning ? `<div class="callout warn"><p>${e(t.warning)}</p></div>` : ''}
        <div class="codeblock small"><code><span class="dollar">$</span> /ios ${e(t.name)}</code>${Lotus.copyButton('/ios ' + t.name)}</div>
      </article>`;
    }).join('');
  }
  sel.addEventListener('change', render);
  ver.addEventListener('input', render);
  render();
})();
