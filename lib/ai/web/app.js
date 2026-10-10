// Lotus AI – the web chat in the browser. It only talks to the Lotus program that served this page
// (lib/ai/Server.swift): the same AI as /ai in the terminal, with the same tools and questions.
'use strict';

const token = document.querySelector('meta[name="lotus-token"]').content;
const $ = (id) => document.getElementById(id);
const ui = {
  side: $('side'), scrim: $('scrim'), menu: $('menu'), chats: $('chats'), sideFoot: $('side-foot'), newChat: $('new'),
  title: $('title'), meta: $('meta'), clear: $('clear'), banner: $('banner'), bannerText: $('banner-text'),
  bannerRetry: $('banner-retry'), log: $('log'), empty: $('empty'), emptyText: $('empty-text'),
  composer: $('composer'), input: $('input'), send: $('send'), stop: $('stop'), mode: $('mode'), suggest: $('suggest'),
  openSettings: $('open-settings'), sheet: $('sheet'), sheetBody: $('sheet-body'), sheetClose: $('sheet-close'),
  sheetSaved: $('sheet-saved'),
};

let state = null;        // /api/state: the AI, the folder, the mode
let chats = [];          // the conversations, newest first
let current = null;      // the open conversation (null: a new one, made with the first message)
let live = null;         // the answer being written in the open conversation
let liveFrom = 0;        // how many of its events arrived
let following = null;    // AbortController of the event stream that is read
let latest = null;       // the newest answer on screen (/copy)

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const validId = (id) => typeof id === 'string' && /^[a-z0-9]{12}$/.test(id);

// ── Talking to Lotus ─────────────────────────────────────────

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function headers(json) {
  const h = { 'X-Lotus-Token': token };
  if (json) h['Content-Type'] = 'application/json';
  return h;
}

async function request(method, path, body, signal) {
  let res;
  try {
    res = await fetch(path, {
      method, cache: 'no-store', credentials: 'same-origin', signal,
      headers: headers(body !== undefined), body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    offline();
    throw new ApiError(0, 'Lotus AI is not reachable');
  }
  online();
  if (res.status === 401 || res.status === 403) signedOut();
  return res;
}

async function api(method, path, body) {
  const res = await request(method, path, body);
  let data = null;
  try { data = await res.json(); } catch { /* no body */ }
  if (!res.ok) throw new ApiError(res.status, (data && data.error) || `Error ${res.status}`);
  return data;
}

// The server answers with text/event-stream: "data: {json}" frames, one event each
async function readEvents(res, onEvent) {
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const frame = buf.slice(0, i);
      buf = buf.slice(i + 2);
      for (const line of frame.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        let ev;
        try { ev = JSON.parse(line.slice(6)); } catch { continue; }
        onEvent(ev);
      }
    }
  }
}

function offline() {
  ui.bannerText.innerHTML = 'Lotus AI is not reachable. Start it in the terminal: <code>lotus ai server start</code>';
  ui.banner.hidden = false;
}
function online() { ui.banner.hidden = true; }

// After a restart of the server the page's token is old: load the page again (it gets a new one,
// or the sign-in page when the access key changed). At most every 10 seconds.
function signedOut() {
  let last = 0;
  try { last = Number(sessionStorage.getItem('lotus-reload') || 0); } catch { /* private mode */ }
  if (Date.now() - last < 10000) {
    ui.bannerText.innerHTML = 'This page is signed out. Open it from the terminal: <code>lotus ai server open</code>';
    ui.banner.hidden = false;
    return;
  }
  try { sessionStorage.setItem('lotus-reload', String(Date.now())); } catch { /* private mode */ }
  location.reload();
}

// ── Markdown ─────────────────────────────────────────────────
// Everything is escaped first; only links to http(s) and mailto become links.

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// HTML that models write into their Markdown – <br> in a table cell, <b>, <sup> … – is shown the way it is
// meant, not as text: line breaks and simple formatting become the real thing, entities (&nbsp;) their
// character, style wrappers (<span style=…>) disappear. Nothing else gets through – no attributes, no
// other tags: `List<T>` stays as written, and code is never touched.
const HTML_INLINE = /&lt;(\/?)(br|b|strong|i|em|u|s|del|strike|ins|sub|sup|mark|small|kbd|code|q|abbr|cite|var|samp|tt)\s*\/?&gt;/gi;
const HTML_WRAPPER = /&lt;\/?(?:span|font)(?:\s(?:(?!&gt;)[^\n])*)?&gt;/gi;
const HTML_ENTITY = /&amp;(#\d{1,7}|#x[0-9a-f]{1,6}|[a-z][a-z0-9]{1,31});/gi;

function html(s) {
  return s
    .replace(HTML_INLINE, (_, close, tag) => {
      const t = tag.toLowerCase();
      if (t === 'br') return '<br>';
      return `<${close}${{ strike: 's', tt: 'code' }[t] || t}>`;
    })
    .replace(HTML_WRAPPER, '')
    .replace(HTML_ENTITY, '&$1;');
}

function inline(src) {
  const kept = [];
  const hold = (html) => { kept.push(html); return `\u0000${kept.length - 1}\u0000`; };
  const link = (url, text) => hold(`<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${text}</a>`);
  let s = src.replace(/`([^`\n]+)`/g, (_, c) => hold(`<code>${esc(c)}</code>`));
  s = s.replace(/\[([^\]\n]+)\]\(((?:https?:\/\/|mailto:)[^\s)]+)\)/g, (_, t, u) => link(u, esc(t)));
  s = s.replace(/(^|[\s(])(https?:\/\/[^\s<>()]*[^\s<>().,;:!?'"])/g, (_, pre, u) => pre + link(u, esc(u)));
  s = esc(s);
  s = s.replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^\w])__(?=\S)([\s\S]*?\S)__(?!\w)/g, '$1<strong>$2</strong>');
  s = s.replace(/(^|[^*\w])\*(?=[^\s*])([^*\n]*?[^\s*])\*(?!\*)/g, '$1<em>$2</em>');
  s = s.replace(/(^|[^\w])_(?=\S)([^_\n]*?\S)_(?!\w)/g, '$1<em>$2</em>');
  s = s.replace(/~~(?=\S)([^~\n]*?\S)~~/g, '<del>$1</del>');
  s = html(s);
  for (let n = 0; n < 3 && s.includes('\u0000'); n++) s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => kept[Number(i)]);
  return s;
}

const indent = (l) => l.match(/^\s*/)[0].replace(/\t/g, '    ').length;
const isFence = (l) => /^\s*(```|~~~)/.test(l);
const isHeading = (l) => /^\s{0,3}#{1,6}\s/.test(l);
const isQuote = (l) => /^\s{0,3}>/.test(l);
const isRule = (l) => /^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(l) || /^\s*<hr\s*\/?>\s*$/i.test(l);
const isList = (l) => /^\s*([-*+•]|\d{1,3}[.)])\s+\S/.test(l);
const isTableSep = (l) => l !== undefined && l.includes('-') && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(l);
const startsTable = (lines, i) => lines[i].includes('|') && isTableSep(lines[i + 1]);

function codeBlock(lang, code) {
  return `<div class="code"><div class="code-head"><span>${esc(lang || 'code')}</span>`
    + `<button type="button" class="copy">Copy</button></div><pre><code>${esc(code)}</code></pre></div>`;
}

function table(lines, i) {
  const cells = (l) => l.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());
  const head = cells(lines[i]);
  const align = cells(lines[i + 1]).map((c) => (c.startsWith(':') && c.endsWith(':') ? ' class="al-c"' : c.endsWith(':') ? ' class="al-r"' : ''));
  let html = '<table><thead><tr>' + head.map((c, k) => `<th${align[k] || ''}>${inline(c)}</th>`).join('') + '</tr></thead><tbody>';
  i += 2;
  while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
    html += '<tr>' + cells(lines[i]).map((c, k) => `<td${align[k] || ''}>${inline(c)}</td>`).join('') + '</tr>';
    i++;
  }
  return { html: html + '</tbody></table>', next: i };
}

function list(lines, start) {
  const base = indent(lines[start]);
  const ordered = /^\s*\d/.test(lines[start]);
  const items = [];
  let i = start;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) {
      const n = lines[i + 1];
      if (n === undefined || !n.trim() || indent(n) < base) break;
      if (indent(n) > base) { if (items.length) items[items.length - 1].sub.push(''); i++; continue; }
      if (isList(n)) { i++; continue; }
      break;
    }
    const ind = indent(l);
    if (ind < base) break;
    if (ind <= base + 1 && isList(l)) {
      if (/^\s*\d/.test(l) !== ordered) break;
      items.push({ body: [l.replace(/^\s*([-*+•]|\d{1,3}[.)])\s+/, '')], sub: [] });
    } else if (!items.length) {
      break;
    } else if (ind > base + 1) {
      items[items.length - 1].sub.push(l);
    } else {
      items[items.length - 1].body.push(l.trim());
    }
    i++;
  }
  const tag = ordered ? 'ol' : 'ul';
  const first = ordered ? parseInt(lines[start].trim(), 10) : 1;
  let html = `<${tag}${ordered && first !== 1 ? ` start="${first}"` : ''}>`;
  for (const it of items) {
    let sub = '';
    if (it.sub.length) {
      const cut = Math.min(...it.sub.filter((x) => x.trim()).map(indent));
      sub = md(it.sub.map((x) => x.replace(/\t/g, '    ').slice(cut)).join('\n'));
    }
    html += `<li>${it.body.map(inline).join('<br>')}${sub}</li>`;
  }
  return { html: html + `</${tag}>`, next: i };
}

function md(src) {
  const lines = String(src).replace(/\r\n?/g, '\n').split('\n');
  let html = '';
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (isFence(line)) {
      const m = line.match(/^\s*(```+|~~~+)\s*([\w+#.-]*)/);
      const code = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(m[1])) code.push(lines[i++]);
      i++;
      html += codeBlock(m[2], code.join('\n'));
    } else if (!line.trim()) {
      i++;
    } else if (isHeading(line)) {
      const m = line.match(/^\s*(#{1,6})\s+(.*?)\s*#*\s*$/);
      const level = Math.min(5, m[1].length + 2);
      html += `<h${level}>${inline(m[2])}</h${level}>`;
      i++;
    } else if (isRule(line)) {
      html += '<hr>';
      i++;
    } else if (isQuote(line)) {
      const q = [];
      while (i < lines.length && isQuote(lines[i])) q.push(lines[i++].replace(/^\s{0,3}>\s?/, ''));
      html += `<blockquote>${md(q.join('\n'))}</blockquote>`;
    } else if (startsTable(lines, i)) {
      const t = table(lines, i);
      html += t.html;
      i = t.next;
    } else if (isList(line)) {
      const l = list(lines, i);
      html += l.html;
      i = l.next;
    } else {
      const p = [];
      while (i < lines.length && lines[i].trim() && !isFence(lines[i]) && !isHeading(lines[i]) && !isQuote(lines[i])
        && !isList(lines[i]) && !isRule(lines[i]) && !startsTable(lines, i)) p.push(lines[i++]);
      html += `<p>${p.map((x) => inline(x.trim())).join('<br>')}</p>`;
    }
  }
  return html;
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try { await navigator.clipboard.writeText(text); return true; } catch { /* below */ }
  }
  const ta = el('textarea', 'offscreen');
  ta.value = text;
  ta.setAttribute('readonly', '');
  document.body.append(ta);
  ta.select();
  let ok = false;
  try { ok = document.execCommand('copy'); } catch { /* not allowed */ }
  ta.remove();
  return ok;
}

// ── Messages ─────────────────────────────────────────────────

let stick = true;    // keep the newest text in view unless the reader scrolled up
ui.log.addEventListener('scroll', () => {
  stick = ui.log.scrollHeight - ui.log.scrollTop - ui.log.clientHeight < 80;
});
function follow(force) {
  if (force || stick) ui.log.scrollTop = ui.log.scrollHeight;
}

function addUser(text) {
  const m = el('div', 'msg user');
  m.append(el('div', 'bubble', text));
  ui.log.append(m);
}

const answerWords = {
  yes: 'Yes', always: "Yes, don't ask again", no: 'No',
  improved: 'Sent the improved prompt', original: 'Sent as you typed it', cancel: 'Not sent',
};

// One answer of the AI, built from its events – live while it is written, or from the history
class Answer {
  constructor(opts = {}) {
    this.root = el('div', 'msg assistant');
    const who = el('div', 'who', 'Lotus AI');
    this.aiName = el('span', '', opts.ai || '');
    who.append(this.aiName);
    this.body = el('div', 'parts');
    this.status = el('div', 'status');
    this.status.hidden = !opts.live;
    this.root.append(who, this.body, this.status);
    ui.log.append(this.root);
    this.live = !!opts.live;
    this.done = false;
    this.text = null;
    this.source = '';
    this.tool = null;
    this.asks = new Map();
    this.label = 'Thinking';
    this.started = Date.now();
    this.drawPending = false;
    this.texts = [];
    latest = this;
    if (this.live) {
      this.timer = setInterval(() => this.showStatus(), 1000);
      this.showStatus();
    }
  }

  endText() {
    if (this.text) this.drawText();
    this.text = null;
  }

  drawText() {
    this.drawPending = false;
    if (this.text) this.text.innerHTML = md(this.source);
  }

  part(node) {
    this.body.append(node);
    return node;
  }

  apply(ev) {
    switch (ev.type) {
      case 'text':
        if (!this.text) { this.text = this.part(el('div', 'md')); this.source = ''; this.texts.push(''); }
        this.source += ev.text;
        this.texts[this.texts.length - 1] += ev.text;
        if (!this.drawPending) { this.drawPending = true; requestAnimationFrame(() => this.drawText()); }
        break;
      case 'end':
        this.endText();
        break;
      case 'thought':
        this.endText();
        this.part(el('div', 'thought', `Thought for ${ev.secs}s`));
        break;
      case 'tool': {
        this.endText();
        const step = this.part(el('div', 'step'));
        const head = el('div', 'step-head');
        head.append(el('b', '', ev.name), el('span', '', ev.detail ? ` ${ev.detail}` : ''));
        step.append(head);
        this.tool = step;
        break;
      }
      case 'lines': {
        this.endText();
        const host = this.tool || this.part(el('div', 'step'));
        // lines after a question get a box of their own, below it
        let box = host.lastElementChild;
        if (!box || !box.classList.contains('step-lines')) box = host.appendChild(el('div', 'step-lines'));
        for (const line of ev.lines) box.append(el('div', ev.color, line || ' '));
        if (ev.more) box.append(el('div', 'dim', `… ${ev.more} more lines`));
        break;
      }
      case 'result': {
        const host = this.tool || this.part(el('div', 'step'));
        host.append(el('div', 'step-result' + (ev.error ? ' error' : ''), ev.text));
        this.tool = null;
        break;
      }
      case 'ask':
        this.endText();
        this.ask(ev);
        break;
      case 'improved':
        this.endText();
        this.improved(ev.text);
        break;
      case 'improve':
        this.endText();
        this.improve(ev);
        break;
      case 'asked': {
        const card = this.asks.get(ev.id);
        if (card) this.answered(card, ev.answer, ev.note);
        break;
      }
      case 'info':
        this.endText();
        this.part(el('div', 'note-line', ev.text));
        break;
      case 'error': {
        this.endText();
        const box = this.part(el('div', 'error'));
        box.append(el('b', '', ev.title));
        if (ev.detail) box.append(el('p', '', ev.detail));
        break;
      }
      case 'status':
        this.label = ev.text;
        this.showStatus();
        break;
      case 'done':
        this.finish();
        break;
      default:
        break;
    }
  }

  ask(ev) {
    // the question belongs to the step it is about: below what the step showed so far
    const card = (this.tool || this.body).appendChild(el('div', 'ask'));
    card.append(el('div', 'ask-q', ev.question));
    const buttons = card.appendChild(el('div', 'ask-buttons'));
    this.asks.set(ev.id, card);
    if (!this.live) return;
    const reply = async (answer, note) => {
      for (const b of card.querySelectorAll('button, input')) b.disabled = true;
      try {
        await api('POST', '/api/answer', { id: ev.id, answer, note: note || '' });
      } catch (e) {
        if (e.status === 404) this.answered(card, null);
        else for (const b of card.querySelectorAll('button, input')) b.disabled = false;
      }
    };
    const button = (label, answer, cls) => {
      const b = el('button', cls || '', label);
      b.type = 'button';
      b.addEventListener('click', () => reply(answer));
      buttons.append(b);
      return b;
    };
    button('Yes', 'yes', 'yes').focus({ preventScroll: true });
    if (ev.always) button("Yes, don't ask again", 'always');
    button('No', 'no');
    // yes – and from now on decide alone, asking only when unsure
    if (state && state.tools && state.mode !== 'auto') {
      const auto = el('button', 'ask-auto', 'Yes, and switch to auto mode');
      auto.type = 'button';
      auto.title = 'Auto mode: it works on its own and asks only when unsure';
      auto.addEventListener('click', async () => {
        if (await setMode(true, true)) reply('yes');
      });
      buttons.append(auto);
    }
    const noteRow = card.appendChild(el('form', 'ask-note'));
    const note = el('input');
    note.placeholder = 'Or say what it should do instead';
    note.maxLength = 2000;
    const go = el('button', '', 'Send');
    go.type = 'submit';
    noteRow.append(note, go);
    noteRow.addEventListener('submit', (e) => {
      e.preventDefault();
      if (note.value.trim()) reply('no', note.value.trim());
    });
    this.showStatus();
    follow();
  }

  // The prompt the AI got instead of the message as typed (/enhance)
  improved(text, asking) {
    const card = this.part(el('div', 'improved'));
    card.append(el('div', 'improved-head', asking ? 'Improved prompt – send it?' : 'Improved prompt'), el('div', 'improved-text', text));
    return card;
  }

  improve(ev) {
    const card = this.improved(ev.text, true);
    card.classList.add('ask');
    this.asks.set(ev.id, card);
    if (!this.live) return;
    const buttons = card.appendChild(el('div', 'ask-buttons'));
    const reply = async (answer) => {
      for (const b of buttons.querySelectorAll('button')) b.disabled = true;
      try {
        await api('POST', '/api/answer', { id: ev.id, answer });
      } catch (e) {
        if (e.status === 404) this.answered(card, null);
        else for (const b of buttons.querySelectorAll('button')) b.disabled = false;
      }
    };
    for (const [label, answer, cls] of [['Send it', 'improved', 'yes'], ['Send mine as typed', 'original'], ['Cancel', 'cancel']]) {
      const b = el('button', cls || '', label);
      b.type = 'button';
      b.addEventListener('click', () => reply(answer));
      buttons.append(b);
    }
    buttons.firstChild.focus({ preventScroll: true });
    this.showStatus();
    follow();
  }

  answered(card, answer, note) {
    if (card.classList.contains('answered')) return;
    card.classList.add('answered');
    for (const n of card.querySelectorAll('.ask-buttons, .ask-note')) n.remove();
    const words = answer ? answerWords[answer] || answer : 'Not answered';
    card.append(el('div', 'ask-done', note ? `${words} – “${note}”` : words));
    this.showStatus();
  }

  showStatus() {
    if (!this.live || this.done) return;
    const waiting = [...this.asks.values()].some((c) => !c.classList.contains('answered'));
    const secs = Math.floor((Date.now() - this.started) / 1000);
    this.status.textContent = waiting ? 'Waiting for your answer' : `${this.label} … ${secs}s`;
  }

  finish() {
    if (this.done) return;
    this.done = true;
    this.endText();
    clearInterval(this.timer);
    this.status.hidden = true;
    for (const card of this.asks.values()) this.answered(card, null);
    if (!this.body.childNodes.length) this.part(el('div', 'note-line', 'No answer.'));
  }
}

// ── Conversations ────────────────────────────────────────────

function ago(t) {
  const s = Date.now() / 1000 - t;
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return new Date(t * 1000).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function drawChats() {
  ui.chats.textContent = '';
  if (!chats.length) {
    ui.chats.append(el('div', 'chats-empty', 'Your conversations appear here.'));
    return;
  }
  for (const c of chats) {
    const row = el('div', 'chat' + (c.id === current ? ' active' : ''));
    const open = el('button', 'open');
    open.type = 'button';
    open.append(el('span', 'chat-title', c.title || 'New chat'), el('span', 'chat-time', ago(c.updated)));
    open.addEventListener('click', () => { closeSide(); openChat(c.id); });
    const del = el('button', 'del', '×');
    del.type = 'button';
    del.title = 'Delete this conversation';
    del.setAttribute('aria-label', `Delete ${c.title || 'this conversation'}`);
    del.addEventListener('click', () => deleteChat(c));
    row.append(open, del);
    ui.chats.append(row);
  }
}

async function loadChats() {
  try {
    chats = (await api('GET', '/api/chats')).chats || [];
  } catch { return; }
  drawChats();
  const c = chats.find((x) => x.id === current);
  if (c) ui.title.textContent = c.title || 'New chat';
}

function showState() {
  if (!state) return;
  const mode = !state.tools ? 'chat only' : state.mode === 'auto' ? 'auto mode' : 'asks before changes';
  const better = state.enhance === 'on' ? ' · improves prompts' : state.enhance === 'ask' ? ' · improves prompts, you choose' : '';
  ui.meta.textContent = '';
  ui.meta.append(el('b', '', state.ai), ` · ${mode}${better} · ${state.folder}`);
  ui.sideFoot.textContent = `Lotus ${state.version} · ${state.lan ? 'open to devices in your network' : 'only on this Mac'}`;
  ui.emptyText.textContent = !state.tools
    ? 'Ask anything. It only talks – working on this Mac is off in /permissions.'
    : state.mode === 'auto'
      ? `Ask anything, or let it work in ${state.folder}. Auto mode: it asks only when unsure.`
      : `Ask anything, or let it work in ${state.folder}. It asks before it changes anything.`;
  ui.mode.hidden = !state.tools;
  ui.mode.textContent = state.mode === 'auto' ? 'Auto' : 'Ask';
  ui.mode.classList.toggle('on', state.mode === 'auto');
  ui.mode.setAttribute('aria-pressed', String(state.mode === 'auto'));
  ui.mode.title = state.mode === 'auto'
    ? 'Auto mode: it asks only when unsure – click for ask first (/auto)'
    : 'Ask first: it asks before it changes anything – click for auto mode (/auto)';
}

async function refreshState() {
  try {
    state = await api('GET', '/api/state');
    showState();
  } catch { /* the banner says it */ }
}

function showEmpty(on) {
  ui.empty.hidden = !on;
  let chips = ui.empty.querySelector('.chips');
  if (on && !chips) {
    chips = ui.empty.appendChild(el('div', 'chips'));
    for (const q of ['What can you do here?', 'What is in this folder?']) {
      const b = el('button', '', q);
      b.type = 'button';
      b.addEventListener('click', () => submit(q));
      chips.append(b);
    }
  }
}

function clearLog() {
  for (const n of [...ui.log.children]) if (n !== ui.empty) n.remove();
}

function stopFollowing() {
  if (following) following.abort();
  following = null;
  if (live) clearInterval(live.timer);
  live = null;
}

function newChat() {
  stopFollowing();
  current = null;
  clearLog();
  showEmpty(true);
  ui.title.textContent = 'New chat';
  ui.clear.hidden = true;
  history.replaceState(null, '', location.pathname);
  drawChats();
  setBusy(false);
  ui.input.focus();
}

async function openChat(id) {
  if (!validId(id)) return newChat();
  stopFollowing();
  let chat;
  try {
    chat = await api('GET', `/api/chats/${id}`);
  } catch (e) {
    if (e.status === 404) return newChat();
    return;
  }
  current = id;
  history.replaceState(null, '', `#${id}`);
  clearLog();
  showEmpty(!chat.messages.length && !chat.running);
  ui.title.textContent = chat.title || 'New chat';
  ui.clear.hidden = false;
  for (const m of chat.messages) {
    if (m.role === 'user') {
      addUser(m.text);
    } else {
      const a = new Answer({ ai: m.ai });
      for (const ev of m.events || []) a.apply(ev);
      a.finish();
    }
  }
  drawChats();
  follow(true);
  if (chat.running) {
    live = new Answer({ live: true, ai: state && state.ai });
    liveFrom = 0;
    setBusy(true);
    attach();
  } else {
    setBusy(false);
  }
}

async function deleteChat(c) {
  if (!confirm(`Delete “${c.title || 'New chat'}”?`)) return;
  try {
    await api('DELETE', `/api/chats/${c.id}`);
  } catch (e) {
    alert(e.message);
    return;
  }
  if (c.id === current) newChat();
  loadChats();
}

async function clearChat() {
  if (!current || !confirm('Clear this conversation? The AI forgets it too.')) return;
  try {
    await api('POST', `/api/chats/${current}/clear`);
  } catch (e) {
    alert(e.message);
    return;
  }
  openChat(current);
  loadChats();
}

// ── Sending ──────────────────────────────────────────────────

function setBusy(on) {
  ui.send.hidden = on;
  ui.stop.hidden = !on;
  ui.send.disabled = on;
}

function onEvent(answer) {
  return (ev) => {
    if (typeof ev.seq === 'number') liveFrom = ev.seq + 1;
    answer.apply(ev);
    if (ev.type === 'start') loadChats();
    follow();
  };
}

async function submit(given) {
  const text = (given ?? ui.input.value).trim();
  if (!text) return;
  if (isCommand(text)) {
    if (given === undefined) { ui.input.value = ''; grow(); }
    hideSuggest();
    return runCommand(text);
  }
  if (live) return;
  if (given === undefined) { ui.input.value = ''; grow(); }
  return startAnswer('send', { text }, text);
}

// A message or /compact: the answer streams in as events
async function startAnswer(action, body, shown) {
  if (live) return;
  if (!current) {
    try {
      current = (await api('POST', '/api/chats')).id;
    } catch (e) {
      if (e.status) alert(e.message);
      return;
    }
    history.replaceState(null, '', `#${current}`);
    ui.clear.hidden = false;
  }
  showEmpty(false);
  addUser(shown);
  live = new Answer({ live: true, ai: state && state.ai });
  liveFrom = 0;
  setBusy(true);
  follow(true);
  const answer = live;
  const ctl = new AbortController();
  following = ctl;
  let res;
  try {
    res = await request('POST', `/api/chats/${current}/${action}`, body, ctl.signal);
  } catch (e) {
    if (e.name !== 'AbortError') answer.apply({ type: 'error', title: 'Lotus AI is not reachable', detail: 'Start it in the terminal: lotus ai server start' });
    return ended(answer);
  }
  if (!res.ok) {
    let data = null;
    try { data = await res.json(); } catch { /* no body */ }
    answer.apply({ type: 'error', title: (data && data.error) || `The message could not be sent (${res.status})` });
    return ended(answer);
  }
  try { await readEvents(res, onEvent(answer)); } catch { /* lost or switched away */ }
  if (answer !== live) return;          // another conversation was opened meanwhile
  if (answer.done) return ended(answer);
  attach();
}

// The answer goes on without this page: attach to it again after a lost connection or a reload
async function attach() {
  const answer = live;
  const id = current;
  for (let tries = 0; tries < 40 && answer === live; tries++) {
    if (tries) await sleep(Math.min(5000, 600 * tries));
    if (answer !== live) return;
    const ctl = new AbortController();
    following = ctl;
    let res;
    try {
      res = await request('GET', `/api/run?chat=${id}&from=${liveFrom}`, undefined, ctl.signal);
    } catch (e) {
      if (e.name === 'AbortError') return;
      continue;
    }
    if (res.status === 404) {          // it is finished: show it as the conversation kept it
      live = null;
      return openChat(id);
    }
    if (!res.ok) continue;
    try { await readEvents(res, onEvent(answer)); } catch { /* try again */ }
    if (answer.done) return ended(answer);
  }
  if (answer === live) {
    answer.apply({ type: 'error', title: 'The connection to Lotus AI was lost', detail: 'Reload the page to see the answer.' });
    ended(answer);
  }
}

function ended(answer) {
  answer.finish();
  if (answer === live) {
    live = null;
    following = null;
    setBusy(false);
  }
  loadChats();
}

async function stopAnswer() {
  ui.stop.disabled = true;
  try { await api('POST', '/api/stop'); } catch { /* the stream says what happened */ }
  ui.stop.disabled = false;
}

// ── Input ────────────────────────────────────────────────────

function grow() {
  ui.input.style.height = 'auto';
  ui.input.style.height = `${Math.min(ui.input.scrollHeight, window.innerHeight * 0.4)}px`;
}

ui.input.addEventListener('input', () => { grow(); updateSuggest(); });
ui.input.addEventListener('blur', () => setTimeout(hideSuggest, 150));
ui.input.addEventListener('keydown', (e) => {
  if (!ui.suggest.hidden) {
    const rows = ui.suggest.children.length;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      suggestAt = (suggestAt + (e.key === 'ArrowDown' ? 1 : rows - 1)) % rows;
      updateSuggest();
      return;
    }
    if (e.key === 'Tab' && !e.shiftKey) {
      e.preventDefault();
      pickSuggest(false);
      return;
    }
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      pickSuggest(true);
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      hideSuggest();
      return;
    }
  }
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.keyCode !== 229) {
    e.preventDefault();
    submit();
  }
});
ui.mode.addEventListener('click', () => setMode(state && state.mode !== 'auto'));
ui.openSettings.addEventListener('click', () => openSettings());
ui.sheetClose.addEventListener('click', closeSettings);
ui.sheet.addEventListener('click', (e) => { if (e.target === ui.sheet) closeSettings(); });
ui.composer.addEventListener('submit', (e) => { e.preventDefault(); submit(); });
ui.stop.addEventListener('click', stopAnswer);
ui.newChat.addEventListener('click', () => { closeSide(); newChat(); });
ui.clear.addEventListener('click', clearChat);
ui.bannerRetry.addEventListener('click', boot);
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (!ui.sheet.hidden) closeSettings();
  else if (ui.side.classList.contains('open')) closeSide();
  else if (live) stopAnswer();
});

ui.log.addEventListener('click', async (e) => {
  const b = e.target.closest('.copy');
  if (!b) return;
  const code = b.closest('.code').querySelector('pre').textContent;
  if (await copyText(code)) {
    b.textContent = 'Copied';
    b.classList.add('done');
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1500);
  }
});

function closeSide() {
  ui.side.classList.remove('open');
  ui.scrim.hidden = true;
}
ui.menu.addEventListener('click', () => {
  ui.side.classList.add('open');
  ui.scrim.hidden = false;
});
ui.scrim.addEventListener('click', closeSide);

// ── Commands ─────────────────────────────────────────────────
// Like in /ai in the terminal: a message that starts with a /word is a command, not a message for the AI.

const COMMANDS = [
  ['/help', 'what you can do here'],
  ['/new', 'start a new conversation'],
  ['/clear', 'empty this conversation – the AI forgets it'],
  ['/model', 'choose who answers'],
  ['/effort', 'how hard it thinks: low, medium, high, max'],
  ['/enhance', 'improve your prompts first: off, on, ask'],
  ['/auto', 'auto mode on or off – it asks only when unsure'],
  ['/permissions', 'what the AI may do on this Mac'],
  ['/settings', 'all settings'],
  ['/memory', 'what it remembers about you – /memory clear forgets it'],
  ['/context', 'how full this conversation is'],
  ['/compact', 'summarize the conversation to free up room'],
  ['/copy', 'copy the last answer'],
];
const EFFORT_WORDS = { low: 'quick', medium: 'balanced', high: 'thorough', max: 'maximum' };

// "/etc/hosts – what is this?" is a message, "/model" a command
function isCommand(text) {
  if (!text.startsWith('/')) return false;
  const word = text.split(/\s/)[0];
  return word.length > 1 && !word.slice(1).includes('/');
}

let suggestAt = 0;
function matches() {
  const v = ui.input.value;
  if (!v.startsWith('/') || /\s/.test(v)) return [];
  return COMMANDS.filter(([name]) => name.startsWith(v.toLowerCase()));
}
function updateSuggest() {
  const list = matches();
  if (!list.length) return hideSuggest();
  suggestAt = Math.min(suggestAt, list.length - 1);
  ui.suggest.textContent = '';
  list.forEach(([name, help], i) => {
    const row = el('div', 'sugg' + (i === suggestAt ? ' on' : ''));
    row.setAttribute('role', 'option');
    row.setAttribute('aria-selected', String(i === suggestAt));
    row.append(el('b', '', name), el('span', '', help));
    row.addEventListener('mousedown', (e) => { e.preventDefault(); suggestAt = i; pickSuggest(true); });
    ui.suggest.append(row);
  });
  ui.suggest.hidden = false;
}
function hideSuggest() {
  ui.suggest.hidden = true;
  suggestAt = 0;
}
function pickSuggest(run) {
  const list = matches();
  const pick = list[Math.min(suggestAt, list.length - 1)];
  hideSuggest();
  if (!pick) return;
  if (run) {
    ui.input.value = '';
    grow();
    runCommand(pick[0]);
  } else {
    ui.input.value = `${pick[0]} `;
    grow();
    ui.input.focus();
  }
}

// A note from Lotus in the conversation – only on this page, the AI does not see it
function note(content) {
  showEmpty(false);
  const box = el('div', 'note-card');
  if (typeof content === 'string') box.textContent = content;
  else box.append(content);
  ui.log.append(box);
  follow(true);
  return box;
}

async function runCommand(text) {
  const [word, ...rest] = text.split(/\s+/);
  const cmd = word.toLowerCase();
  const arg = rest.join(' ').trim().toLowerCase();
  switch (cmd) {
    case '/help': case '/?': return noteHelp();
    case '/new': return newChat();
    case '/clear': case '/reset': return clearChat();
    case '/model': case '/models': return openSettings('model');
    case '/effort': {
      if (!arg) return openSettings('effort');
      const value = { quick: 'low', balanced: 'medium', thorough: 'high', maximum: 'max' }[arg] || arg;
      if (!EFFORT_WORDS[value]) return note('Choose one of: low, medium, high, max.');
      if (await setSetting('LOTUS_AI_EFFORT', value)) note(`The AI now thinks ${EFFORT_WORDS[value]}.`);
      return;
    }
    case '/enhance': case '/improve': {
      if (!arg) return openSettings('effort');
      if (!['off', 'on', 'ask'].includes(arg)) return note('Choose one of: off, on, ask.');
      const said = {
        off: 'Messages go as you type them.',
        on: 'Messages are improved into a clear prompt first – short ones and commands go as typed.',
        ask: 'Messages are improved first, and you choose each time.',
      };
      if (await setSetting('LOTUS_AI_ENHANCE', arg)) note(said[arg]);
      return;
    }
    case '/auto': return setMode(arg === 'on' ? true : arg === 'off' ? false : !(state && state.mode === 'auto'));
    case '/permissions': case '/perms': case '/allow': return openSettings('permissions');
    case '/settings': case '/config': return openSettings();
    case '/memory': return arg === 'clear' ? forgetMemory() : noteMemory();
    case '/context': return noteContext();
    case '/compact':
      if (!current) return note('Nothing to compact yet.');
      return startAnswer('compact', {}, '/compact');
    case '/copy': {
      const text = latest ? latest.texts.join('\n\n').trim() : '';
      if (!text) return note('No answer to copy yet.');
      return note(await copyText(text) ? 'Copied the last answer.' : 'Copying did not work in this browser.');
    }
    default: {
      const close = COMMANDS.find(([name]) => name.startsWith(cmd.slice(0, 3)));
      return note(`Unknown command ${cmd}.${close ? ` Did you mean ${close[0]}?` : ''} /help lists all.`);
    }
  }
}

function noteHelp() {
  const box = el('div');
  box.append(el('b', '', 'Commands'));
  const list = el('dl', 'cmd-list');
  for (const [name, help] of COMMANDS) list.append(el('dt', '', name), el('dd', '', help));
  box.append(list);
  box.append(el('b', '', 'Keys'));
  box.append(el('p', '', 'Enter sends · Shift+Enter new line · ↑↓ and Tab choose a command · Esc stops an answer'));
  box.append(el('b', '', 'What it can do'));
  box.append(el('p', '', 'Read, search, create and change files in the folder and run commands – as far as your settings allow. '
    + 'In auto mode it works on its own and asks only when unsure. Dangerous commands and private files always ask, sudo never runs.'));
  note(box);
}

async function setSetting(key, value) {
  try {
    const now = await api('POST', '/api/settings', { key, value });
    await refreshState();
    return now;
  } catch (e) {
    note(e.message);
    return null;
  }
}

// Auto mode on or off (also the switch next to the message box)
async function setMode(on, quiet) {
  if (!state || !state.tools) {
    note('Working on this Mac is off – turn it on in /permissions first.');
    return false;
  }
  const saved = await setSetting('LOTUS_AI_PERM_MODE', on ? 'auto' : 'ask');
  if (!saved) return false;
  if (!quiet) {
    note(on
      ? 'Auto mode: it works on its own and asks only when unsure – deleting, pushing, installing, other folders, private files.'
      : 'Ask first: it asks before it changes anything.');
  }
  return true;
}

async function noteMemory() {
  let mem;
  try { mem = await api('GET', '/api/memory'); } catch (e) { return note(e.message); }
  const box = el('div');
  box.append(el('b', '', 'What it remembers'));
  if (!mem.facts.length) {
    box.append(el('p', '', 'Nothing yet. Tell it things worth knowing – "remember that I …" – or it keeps them itself.'));
  } else {
    const list = el('ul');
    for (const f of mem.facts) list.append(el('li', '', f));
    box.append(list);
    const forget = el('button', 'note-btn', 'Forget everything');
    forget.type = 'button';
    forget.addEventListener('click', () => forgetMemory());
    box.append(forget);
  }
  if (mem.path) box.append(el('p', 'note-dim', `${mem.path} – a plain text file you can edit`));
  note(box);
}

async function forgetMemory() {
  if (!confirm('Forget everything the AI remembers about you?')) return;
  try {
    await api('POST', '/api/memory/clear');
    note('Forgotten – it starts fresh from the next message.');
  } catch (e) {
    note(e.message);
  }
}

async function noteContext() {
  if (!current) return note('Nothing in this conversation yet.');
  let ctx;
  try { ctx = await api('GET', `/api/chats/${current}/context`); } catch (e) { return note(e.message); }
  const box = el('div');
  box.append(el('b', '', `Memory of this conversation · ${ctx.ai}`));
  const bar = el('div', 'ctx-bar');
  const fill = el('div', 'ctx-fill');
  fill.style.width = `${ctx.percent}%`;
  bar.append(fill);
  box.append(bar);
  box.append(el('p', '', `${ctx.percent}% (about ${ctx.used} of ${ctx.budget} tokens) · ${ctx.messages} ${ctx.messages === 1 ? 'message' : 'messages'}`
    + `${ctx.summary ? ' and a summary of earlier ones' : ''} · it compacts itself at 75% – /compact does it now`));
  note(box);
}

// ── Settings ─────────────────────────────────────────────────
// The same Lotus settings as /settings and /ai in the terminal, saved through Lotus itself.

let settingsData = null;

function closeSettings() {
  ui.sheet.hidden = true;
  ui.input.focus();
}

async function openSettings(focus) {
  ui.sheet.hidden = false;
  ui.sheetSaved.textContent = '';
  ui.sheetBody.textContent = '';
  ui.sheetBody.append(el('p', 'sheet-note', 'Loading …'));
  let models;
  try {
    [settingsData, models] = await Promise.all([api('GET', '/api/settings'), api('GET', '/api/models')]);
  } catch (e) {
    ui.sheetBody.textContent = '';
    ui.sheetBody.append(el('p', 'sheet-note', e.message));
    return;
  }
  drawSettings(models.models);
  const target = focus && ui.sheetBody.querySelector(`[data-section="${focus}"]`);
  if (target) target.scrollIntoView({ block: 'start' });
  ui.sheetClose.focus({ preventScroll: true });
}

function section(name, title, text) {
  const box = el('section', 'set-section');
  box.dataset.section = name;
  box.append(el('h3', '', title));
  if (text) box.append(el('p', 'sheet-note', text));
  ui.sheetBody.append(box);
  return box;
}

function selectRow(parent, label, key, value, options) {
  const row = el('label', 'set-row');
  const select = el('select');
  for (const o of options) {
    const option = el('option', '', o.label);
    option.value = o.value;
    option.selected = o.value === value;
    select.append(option);
  }
  let before = value;
  select.addEventListener('change', async () => {
    const saved = await api('POST', '/api/settings', { key, value: select.value }).catch((e) => {
      ui.sheetSaved.textContent = e.message;
      return null;
    });
    if (!saved) { select.value = before; return; }
    before = select.value;
    ui.sheetSaved.textContent = saved.now ? 'Saved' : 'Saved – counts from the next message';
    refreshState();
  });
  row.append(el('span', 'set-label', label), select);
  parent.append(row);
}

function drawSettings(models) {
  const s = settingsData;
  ui.sheetBody.textContent = '';

  const who = section('model', 'Who answers');
  const list = who.appendChild(el('div', 'set-models'));
  for (const m of models) {
    const row = el('label', 'set-model' + (m.note && !m.current ? ' off' : ''));
    const radio = el('input');
    radio.type = 'radio';
    radio.name = 'model';
    radio.checked = m.current;
    radio.disabled = Boolean(m.note) && !m.current;
    radio.addEventListener('change', () => chooseModel(m, list));
    const text = el('span', '', m.label);
    if (m.note && !m.current) text.append(el('small', '', m.note));
    row.append(radio, text);
    list.append(row);
  }
  if (!models.length) who.append(el('p', 'sheet-note', 'No AI found. Connect one in the terminal: lotus ai login'));

  const how = section('effort', 'How it answers');
  selectRow(how, 'Thinking', s.effort.key, s.effort.value, s.effort.options);
  selectRow(how, 'Improve prompts', s.enhance.key, s.enhance.value, s.enhance.options);

  const may = section('permissions', 'What it may do',
    'Auto mode: it works on its own and asks only when unsure. Dangerous commands and private files (keys, .env) always ask, and sudo never runs.');
  for (const p of s.permissions) selectRow(may, p.label, p.key, p.value, p.options);

  const mem = section('memory', 'What it remembers');
  api('GET', '/api/memory').then((m) => {
    if (!m.facts.length) mem.append(el('p', 'sheet-note', 'Nothing yet.'));
    else {
      const ul = el('ul', 'set-facts');
      for (const f of m.facts) ul.append(el('li', '', f));
      mem.append(ul);
      const forget = el('button', 'note-btn', 'Forget everything');
      forget.type = 'button';
      forget.addEventListener('click', async () => { await forgetMemory(); openSettings('memory'); });
      mem.append(forget);
    }
    if (m.path) mem.append(el('p', 'sheet-note', `${m.path} – a plain text file you can edit`));
  }).catch(() => {});

  const info = section('server', 'This web chat');
  const dl = info.appendChild(el('dl', 'set-info'));
  for (const [k, v] of [['Address', s.server.address], ['Folder', s.server.folder],
    ['Other devices', s.server.lan ? 'allowed, with the link that has your key' : 'off – only this Mac'], ['Lotus', s.server.version]]) {
    dl.append(el('dt', '', k), el('dd', '', v));
  }
  info.append(el('p', 'sheet-note', 'Port, starting with the terminal and other devices: lotus ai server in the terminal.'));
}

async function chooseModel(m, list) {
  ui.sheetSaved.textContent = 'Switching …';
  try {
    const r = await api('POST', '/api/model', { kind: m.kind, model: m.model });
    ui.sheetSaved.textContent = `Now answering: ${r.ai}`;
    await refreshState();
  } catch (e) {
    ui.sheetSaved.textContent = e.message;
    const models = await api('GET', '/api/models').catch(() => null);
    if (models) {
      const radios = list.querySelectorAll('input');
      models.models.forEach((x, i) => { if (radios[i]) radios[i].checked = x.current; });
    }
  }
}

// ── Start ────────────────────────────────────────────────────

async function boot() {
  try {
    state = await api('GET', '/api/state');
  } catch {
    return;
  }
  showState();
  await loadChats();
  const want = state.busy || location.hash.slice(1);
  if (validId(want)) await openChat(want);
  else newChat();
}

setInterval(() => { if (!live) drawChats(); }, 60000);    // "5 min ago" stays right
boot();
