// The macOS helper of /icons (lib/icons/seticon.js) – JavaScript for Automation, which only osascript can run. Here it runs in
// Node against stand-ins for what it uses (ObjC, $, NSWorkspace, NSImage), so every branch is checked on any system: what it asks
// macOS to do, in which order, and what it answers. Plain Node, no packages: node tests/icons/seticon.test.js
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'icons', 'seticon.js'), 'utf8');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('  ✓ ' + name); }
  catch (e) { failed++; console.log('  ✗ ' + name + '\n      ' + String(e.message).split('\n').join('\n      ')); }
}

// A macOS that does what the options say. nil is what $() hands over; null is the other way to write "nothing".
function mac(opts = {}) {
  const calls = [];
  const nil = { isNothing: true };
  const image = { isNil: () => false };
  const gone = { isNil: () => true };
  const $ = function () { return nil; };
  $.NSWorkspace = {
    sharedWorkspace: {
      setIconForFileOptions(icon, folder, options) {
        calls.push({ call: 'setIcon', icon: icon === nil ? 'nil' : icon === null ? 'null' : icon === image ? 'image' : 'other', folder, options });
        if (icon === nil && opts.nilThrows) throw new Error('Error: Can\'t convert types.');
        if (icon === nil && opts.nilFails) return false;
        if (icon === null && opts.nullFails) return false;
        return opts.setIcon === undefined ? true : opts.setIcon;
      },
    },
  };
  $.NSImage = { alloc: { initWithContentsOfFile(file) { calls.push({ call: 'load', file }); return opts.unreadable ? gone : image; } } };
  const context = { ObjC: { import: (name) => calls.push({ call: 'import', name }) }, $ };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { run: (argv) => context.run(argv), calls };
}

// ── set ──
test('set: loads the picture, then gives it to the folder – every size, no options', () => {
  const m = mac();
  assert.strictEqual(m.run(['set', '/Users/me/Desktop/Projects', '/Users/me/Pictures/star.png']), 'ok');
  assert.deepStrictEqual(m.calls, [
    { call: 'import', name: 'AppKit' },
    { call: 'load', file: '/Users/me/Pictures/star.png' },
    { call: 'setIcon', icon: 'image', folder: '/Users/me/Desktop/Projects', options: 0 },
  ]);
});
test('set: a picture macOS cannot read is "unreadable" and the folder is not asked', () => {
  const m = mac({ unreadable: true });
  assert.strictEqual(m.run(['set', '/f', '/p.png']), 'unreadable');
  assert.ok(!m.calls.some((c) => c.call === 'setIcon'), 'setIcon was called');
});
test('set: macOS saying no is "failed"', () => {
  assert.strictEqual(mac({ setIcon: false }).run(['set', '/f', '/p.png']), 'failed');
});
test('set: without a picture it is a usage error and nothing is touched', () => {
  const m = mac();
  assert.strictEqual(m.run(['set', '/f']), 'usage');
  assert.ok(!m.calls.some((c) => c.call === 'setIcon' || c.call === 'load'));
});

// ── reset ──
test('reset: "no picture" – nil – takes the icon away', () => {
  const m = mac();
  assert.strictEqual(m.run(['reset', '/f']), 'ok');
  const set = m.calls.filter((c) => c.call === 'setIcon');
  assert.deepStrictEqual(set, [{ call: 'setIcon', icon: 'nil', folder: '/f', options: 0 }]);
  assert.ok(!m.calls.some((c) => c.call === 'load'), 'no picture is loaded to reset');
});
test('reset: when nil is refused with an error, null is tried', () => {
  const m = mac({ nilThrows: true });
  assert.strictEqual(m.run(['reset', '/f']), 'ok');
  assert.deepStrictEqual(m.calls.filter((c) => c.call === 'setIcon').map((c) => c.icon), ['nil', 'null']);
});
test('reset: when nil does not work, null is tried', () => {
  const m = mac({ nilFails: true });
  assert.strictEqual(m.run(['reset', '/f']), 'ok');
  assert.deepStrictEqual(m.calls.filter((c) => c.call === 'setIcon').map((c) => c.icon), ['nil', 'null']);
});
test('reset: when neither works it is "failed"', () => {
  assert.strictEqual(mac({ setIcon: false }).run(['reset', '/f']), 'failed');
});

// ── anything else ──
test('no folder, or an action it does not know, is a usage error', () => {
  const m = mac();
  assert.strictEqual(m.run([]), 'usage');
  assert.strictEqual(m.run(['set']), 'usage');
  assert.strictEqual(m.run(['delete', '/f']), 'usage');
  assert.ok(!m.calls.some((c) => c.call === 'setIcon'));
});
test('a folder with spaces and non-ASCII letters is passed on as it is', () => {
  const m = mac();
  assert.strictEqual(m.run(['set', '/Users/jörg/Desktop/Meine Spiele', '/Users/jörg/Bilder/Stern 1.png']), 'ok');
  assert.strictEqual(m.calls.find((c) => c.call === 'setIcon').folder, '/Users/jörg/Desktop/Meine Spiele');
  assert.strictEqual(m.calls.find((c) => c.call === 'load').file, '/Users/jörg/Bilder/Stern 1.png');
});

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
