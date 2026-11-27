// A Vue 3 app through the Live Server, in a real browser (Chromium through Playwright): a project like the one `npm create vue` makes
// (JavaScript), in small – an index.html, main.js that imports a stylesheet, components with <script setup>, scoped styles, v-bind() in
// CSS, a module imported without its extension, an image with a relative URL – served by lib/live/liveserver.py with the compiler
// that carries Vue's (LOTUS_VUE_HOST: tests/live/vue-host.js, Node). The page runs, reacts, is styled; a change reloads it; what is
// wrong in a file is shown over the page and goes away when the file is right; a router's /about is the index.html.
//   node tests/live/vue_ui.test.js      (needs the Node package "playwright" and a browser it can start)
'use strict';
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const D = fs.mkdtempSync(path.join(os.tmpdir(), 'lotus-vue-ui.'));
const SITE = path.join(D, 'my-vue-app');
let passed = 0, failed = 0;
async function test(name, fn) {
  try { await fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e && e.stack || e).split('\n').slice(0, 6).join('\n      ')); }
}
function ok(cond, what) { if (!cond) throw new Error(what || 'not true'); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function write(rel, text) { const f = path.join(SITE, rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, text); }
function freePort() { return new Promise((res) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); }); }

write('index.html', '<!doctype html>\n<html lang="en"><head><meta charset="UTF-8"><title>Vue app</title></head>\n<body><div id="app"></div>\n<script type="module" src="/src/main.js"></script></body></html>\n');
write('src/main.js', "import './assets/main.css'\nimport { createApp } from 'vue'\nimport App from './App.vue'\n\ncreateApp(App).mount('#app')\n");
write('src/assets/main.css', 'body { margin: 0; background: rgb(1, 2, 3); font-family: sans-serif }\n');
write('src/assets/logo.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>\n');
write('src/util.js', "export const greeting = 'Grüezi Vue 3'\n");
write('src/App.vue', `<script setup>
import { ref } from 'vue'
import Counter from './components/Counter.vue'
import { greeting } from './util'
const total = ref(0)
const names = ['Ada', 'Grace', 'Linus']
</script>

<template>
  <main>
    <h1 id="title">{{ greeting }}</h1>
    <ul><li v-for="name in names" :key="name" class="name">{{ name }}</li></ul>
    <Counter label="Clicks" :start="2" @bump="total = $event" />
    <p id="total">total: {{ total }}</p>
    <img id="logo" src="./assets/logo.svg" alt="logo">
  </main>
</template>

<style scoped>
h1 { color: rgb(0, 128, 0) }
</style>
`);
const COUNTER = (label) => `<script setup>
import { ref, computed } from 'vue'
const props = defineProps({ label: String, start: { type: Number, default: 0 } })
const emit = defineEmits(['bump'])
const n = ref(props.start)
const color = ref('rgb(200, 0, 0)')
const text = computed(() => props.label + ': ' + n.value${label})
function bump() { n.value++; emit('bump', n.value) }
</script>

<template>
  <button id="counter" class="counter" @click="bump">{{ text }}</button>
</template>

<style scoped>
.counter { color: v-bind(color); border: 2px solid rgb(0, 0, 200) }
</style>
`;
write('src/components/Counter.vue', COUNTER(''));

(async () => {
  const port = await freePort();
  const B = 'http://127.0.0.1:' + port;
  const host = 'node ' + path.join(ROOT, 'tests', 'live', 'vue-host.js');
  const server = spawn('python3', ['-B', path.join(ROOT, 'lib', 'live', 'liveserver.py'), '--no-open', '--local', '--port', String(port)], {
    env: Object.assign({}, process.env, { LOTUS_PWD: SITE, LOTUS_LIVE_DATA: path.join(D, 'state'), LOTUS_VUE_HOST: host }), cwd: SITE
  });
  let log = '';
  server.stdout.on('data', (d) => { log += d; });
  server.stderr.on('data', (d) => { log += d; });
  const plain = () => log.replace(/\x1b\[[0-9;]*m/g, '');
  for (let i = 0; i < 100 && !/Live – the page reloads/.test(plain()); i++) await sleep(100);
  ok(/Live – the page reloads/.test(plain()), 'the server did not start: ' + plain());

  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1000, height: 700 } });
  const page = await ctx.newPage();
  const problems = [];
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') problems.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));
  const text = (sel) => page.textContent(sel);
  const css = (sel, prop) => page.$eval(sel, (el, p) => getComputedStyle(el)[p], prop);

  await test('the app runs: the greeting from a module without its extension, the list, the child component with its props', async () => {
    await page.goto(B + '/');
    await page.waitForSelector('#counter', { timeout: 60000 });
    ok((await text('#title')) === 'Grüezi Vue 3', await text('#title'));
    ok((await page.$$eval('li.name', (els) => els.map((e) => e.textContent))).join() === 'Ada,Grace,Linus');
    ok((await text('#counter')) === 'Clicks: 2', await text('#counter'));
    ok((await text('#total')) === 'total: 0');
    ok(problems.length === 0, problems.join('\n'));
  });

  await test('it reacts: a click counts, the child tells the parent', async () => {
    await page.click('#counter');
    ok((await text('#counter')) === 'Clicks: 3', await text('#counter'));
    ok((await text('#total')) === 'total: 3', await text('#total'));
  });

  await test('it is styled: the stylesheet main.js imports, a scoped style, v-bind() in CSS – and the scope is on the elements', async () => {
    ok((await css('body', 'backgroundColor')) === 'rgb(1, 2, 3)', await css('body', 'backgroundColor'));
    ok((await css('#title', 'color')) === 'rgb(0, 128, 0)', await css('#title', 'color'));
    ok((await css('#counter', 'color')) === 'rgb(200, 0, 0)', 'v-bind(color): ' + await css('#counter', 'color'));
    ok((await css('#counter', 'borderTopColor')) === 'rgb(0, 0, 200)');
    const attrs = await page.$eval('#title', (el) => el.getAttributeNames().filter((n) => n.startsWith('data-v-')));
    ok(attrs.length === 1, 'the scope of App.vue: ' + attrs);
    const link = await page.$$eval('link[data-lotus-css]', (els) => els.map((e) => e.getAttribute('href')));
    ok(link.join() === '/src/assets/main.css', 'the stylesheet is a link: ' + link);
  });

  await test('an image with a relative URL in a template is found (the URL is the file\'s, not the page\'s)', async () => {
    await page.waitForFunction(() => { const i = document.getElementById('logo'); return i && i.complete && i.naturalWidth > 0; });
    ok((await page.$eval('#logo', (i) => i.naturalWidth)) === 10);
    ok((await page.$eval('#logo', (i) => i.getAttribute('src'))) === '/src/assets/logo.svg');
  });

  await test('a change in a component reloads the page, with the new text', async () => {
    write('src/components/Counter.vue', COUNTER(" + '!'"));
    await page.waitForFunction(() => document.getElementById('counter') && document.getElementById('counter').textContent === 'Clicks: 2!', null, { timeout: 30000 });
    ok(problems.length === 0, problems.join('\n'));
  });

  await test('a change in CSS only is swapped in – the page is not reloaded: what the visitor did is still there', async () => {
    await page.click('#counter');
    ok((await text('#counter')) === 'Clicks: 3!');
    write('src/assets/main.css', 'body { margin: 0; background: rgb(9, 8, 7); font-family: sans-serif }\n');
    await page.waitForFunction(() => getComputedStyle(document.body).backgroundColor === 'rgb(9, 8, 7)', null, { timeout: 30000 });
    ok((await text('#counter')) === 'Clicks: 3!', 'the count is still there: no reload');
  });

  await test('a file that cannot be compiled is shown over the page and in the terminal – and goes when the file is right', async () => {
    write('src/components/Counter.vue', '<template>\n  <div>\n</template>\n');
    await page.waitForSelector('#__lotus-error', { timeout: 30000 });
    const shown = await text('#__lotus-error');
    ok(/Vue – src\/components\/Counter\.vue/.test(shown) && /\S/.test(shown.split('\n').slice(1).join('')), shown);
    ok(/✗ src\/components\/Counter\.vue/.test(plain()), 'the terminal: ' + plain().slice(-400));
    write('src/components/Counter.vue', COUNTER(''));
    await page.waitForFunction(() => !document.getElementById('__lotus-error') && document.getElementById('counter'), null, { timeout: 30000 });
    ok((await text('#counter')) === 'Clicks: 2');
  });

  await test('what is not there yet says so over the page: TypeScript in a .vue file', async () => {
    write('src/components/Counter.vue', '<script setup lang="ts">\nconst a: number = 1\n</script>\n<template><button id="counter">ts</button></template>\n');
    await page.waitForSelector('#__lotus-error', { timeout: 30000 });
    ok(/lang="ts"/.test(await text('#__lotus-error')) && /not supported yet/.test(await text('#__lotus-error')), await text('#__lotus-error'));
    write('src/components/Counter.vue', COUNTER(''));
    await page.waitForFunction(() => !document.getElementById('__lotus-error') && document.getElementById('counter'), null, { timeout: 30000 });
  });

  await test('a page of the router (/about/team) is the index.html – the app is there', async () => {
    await page.goto(B + '/about/team');
    await page.waitForSelector('#counter', { timeout: 60000 });
    ok((await text('#title')) === 'Grüezi Vue 3');
  });

  await test('Vue as a page without any .vue file: a template string and the import map – import { createApp } from \'vue\'', async () => {
    write('plain.html', `<!doctype html><div id="app">{{ message }}</div>
<script type="module">
import { createApp, ref } from 'vue'
createApp({ setup() { return { message: ref('hello from a page') } } }).mount('#app')
</script>`);
    await page.goto(B + '/plain.html');
    await page.waitForFunction(() => document.getElementById('app').textContent === 'hello from a page', null, { timeout: 30000 });
  });

  await test('the terminal never complained about a thing that works', async () => {
    const bad = plain().split('\n').filter((l) => /✗|Traceback|Error/.test(l) && !/Counter\.vue/.test(l));
    ok(bad.length === 0, bad.join('\n'));
  });

  await browser.close();
  server.kill('SIGTERM');
  await new Promise((r) => { server.on('exit', r); setTimeout(r, 5000); });
  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('✗ the test stopped: ' + (e && e.stack || e)); process.exit(1); });
