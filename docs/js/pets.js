// Lotus website – Pets: the cat and the dog from data/pets/*.pet (the files the terminal reads),
// drawn and animated the way Lotus does it, plus the prompt for your own pet.
(() => {
  const $ = (id) => document.getElementById(id);

  // Same rules as lib/cmd/pets.zsh: "key: value" lines, then [frame] drawings (ASCII and block pixels)
  function parse(text) {
    const info = {}, art = {};
    let frame = null;
    for (const raw of text.split('\n')) {
      const line = raw.replace(/\r$/, '').replace(/\t/g, '  ');
      const head = line.match(/^\[([a-z]+)\]$/);
      if (head) { frame = head[1]; art[frame] = []; continue; }
      if (!frame) {
        const kv = line.trim().match(/^([a-z_]+):\s*(.*)$/);
        if (kv) info[kv[1]] = kv[2].trim();
      } else {
        art[frame].push(line.replace(/[^ -~\u2580-\u259F]/g, '').replace(/\s+$/, ''));
      }
    }
    for (const f of Object.keys(art)) while (art[f].length && !art[f][art[f].length - 1]) art[f].pop();
    const h = Math.max(...Object.values(art).map((a) => a.length));
    const w = Math.max(...Object.values(art).flat().map((l) => l.length));
    // feet on the ground: shorter drawings get empty lines on top
    for (const f of Object.keys(art)) while (art[f].length < h) art[f].unshift('');
    return { info, art, w, h };
  }

  const LINES = {
    cat: ['Meow! Type my name and we can talk.', 'Mochi wants fish. /feed mochi?', 'Need a command? Try /help.', 'Purr. The sun is warm today.'],
    dog: ['Woof! You are back!', 'Walk? Ball? Bone? All of it!', 'Remove BG is done – that looks great!', 'I tilt my head at typos. Woof?'],
  };
  const NAMES = { cat: 'Mochi', dog: 'Bruno' };

  function card(kind, pet) {
    const el = document.createElement('div');
    el.className = 'term pet-term reveal';
    el.innerHTML = `<div class="term-bar"><i></i><i></i><i></i><span>${Lotus.esc(NAMES[kind] || pet.info.label || kind)}</span></div>
      <div class="pet-scene"><pre class="pet-art pet-${Lotus.esc(kind)}"></pre><div class="pet-bubble"><span></span></div></div>`;
    const artEl = el.querySelector('.pet-art'), bubble = el.querySelector('.pet-bubble span');
    const lines = LINES[kind] || [`${pet.info.sound || 'Hi'}! I am new here.`];
    let t = 0, line = 0, shown = 0;
    const draw = (f) => { artEl.textContent = (pet.art[f] || pet.art.idle).map((l) => l.padEnd(pet.w)).join('\n'); };
    draw('idle');
    // a little life: blink now and then, wag, and talk while the words appear
    setInterval(() => {
      t++;
      const text = lines[line];
      if (shown < text.length) {
        shown = Math.min(text.length, shown + 2);
        bubble.textContent = text.slice(0, shown);
        draw(t % 4 < 2 ? 'talk' : 'idle');
        return;
      }
      if (t % 38 === 0) { line = (line + 1) % lines.length; shown = 0; }
      draw(t % 23 === 0 ? 'blink' : (t % 17 < 3 ? 'wag' : 'idle'));
    }, 90);
    return el;
  }

  async function stage() {
    const box = $('pet-stage');
    for (const kind of ['cat', 'dog']) {
      try {
        const pet = parse(await Lotus.text(`data/pets/${kind}.pet`));
        if (pet.art.idle) box.appendChild(card(kind, pet));
      } catch (e) { /* the page still works without the drawings */ }
    }
    Lotus.reveal();
  }

  $('copy-pet-prompt').addEventListener('click', (e) => Lotus.copy($('pet-prompt').textContent, e.currentTarget));
  stage();
})();
