// The compile host of the Live Server's Vue support, for Node – what lotus-vue (lib/live/Vue.swift) is on a Mac: the scripts it is told
// to load (lib/live/vue/compiler-sfc.js, then sfc.js) run in a context that has nothing but JavaScript itself – like JavaScriptCore
// without a browser –, and one request per line on stdin is answered by one line on stdout.
//   node tests/live/vue-host.js <compiler-sfc.js> <sfc.js>
// The tests use it where there is no Mac (LOTUS_VUE_HOST names it), the Live Server never starts it by itself.
'use strict';
const vm = require('vm');
const fs = require('fs');
const readline = require('readline');

const context = vm.createContext({});
for (const file of process.argv.slice(2)) {
  try { vm.runInContext(fs.readFileSync(file, 'utf8'), context, { filename: file }); }
  catch (e) { process.stdout.write(JSON.stringify({ fatal: file + ': ' + (e && e.message || e) }) + '\n'); process.exit(1); }
}
const request = vm.runInContext('typeof lotusRequest === "function" ? lotusRequest : null', context);
if (!request) { process.stdout.write(JSON.stringify({ fatal: 'the scripts do not define lotusRequest' }) + '\n'); process.exit(1); }

const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on('line', (line) => {
  let answer;
  try { answer = request(line); } catch (e) { answer = JSON.stringify({ id: null, errors: [{ message: String(e && e.message || e) }] }); }
  process.stdout.write(answer + '\n');
});
