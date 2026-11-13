/* Lotus Live Server – a .vue file (a Vue 3 single-file component) made into an ES module, the way @vitejs/plugin-vue does it: the
 * <script> or <script setup>, the <template> compiled to a render function, the <style> blocks (scoped too) put into the page.
 *
 * It runs after compiler-sfc.js (which sets globalThis.VueCompilerSFC) in any JavaScript engine – JavaScriptCore on a Mac (the
 * program lotus-vue, lib/live/Vue.swift), Node in the tests – and knows none: plain, synchronous JavaScript, no DOM, no timers.
 *
 *   lotusRequest(line)   one request as a line of JSON   {"id": 1, "file": "src/App.vue", "source": "<template>…"}
 *                        → one answer as a line of JSON  {"id": 1, "code": "…"}
 *                                                    or  {"id": 1, "errors": [{"message": "…", "line": 3, "column": 5}]}
 *                        {"id": 1, "op": "version"} → {"id": 1, "vue": "3.5.45"}
 *
 * What is not there yet is said instead of being left out quietly: TypeScript, a style or template language other than CSS and
 * HTML (SCSS, Less, Pug …), CSS modules (<style module>) and blocks that point to another file (<script src="…">).
 */
(function (root) {
  'use strict';

  if (typeof root.console === 'undefined') {       // (JavaScriptCore without a browser has none; the compiler may warn through it)
    var quiet = function () {};
    root.console = { log: quiet, info: quiet, warn: quiet, error: quiet, debug: quiet, trace: quiet };
  }
  var C = root.VueCompilerSFC;

  // FNV-1a, eight hex digits: the id of a file – its scope (data-v-xxxxxxxx) – stays the same from run to run and machine to machine
  function hash(text) {
    var h = 0x811c9dc5;
    for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
    return ('00000000' + h.toString(16)).slice(-8);
  }

  // where a file lives as a URL, with the slash after it: 'src/components/Foo.vue' → '/src/components/'
  function folderUrl(file) {
    var i = file.lastIndexOf('/');
    return '/' + (i > 0 ? file.slice(0, i + 1) : '');
  }

  // what went wrong, in a few words, and where – `line` counted in the file (`block` is the block the error is in, when it is)
  function describe(e, block) {
    var text = String((e && e.message) || e);
    var at = e && (e.loc && (e.loc.start || e.loc)) || null;
    var line = at && typeof at.line === 'number' ? at.line : 0, column = at && typeof at.column === 'number' ? at.column : 0;
    if (line && block && block.loc) line += block.loc.start.line - 1;         // (positions inside a block start at its first line)
    return { message: text, line: line || undefined, column: column || undefined };
  }

  function unsupported(d) {
    var out = [], lang = function (b) { return b && b.lang ? String(b.lang) : ''; };
    var no = function (message, block) { out.push({ message: message, line: block && block.loc ? block.loc.start.line : undefined }); };
    [d.script, d.scriptSetup].forEach(function (b) {
      if (!b) return;
      if (b.src) no('<script src="…"> is not supported yet – put the script into the .vue file', b);
      if (/^(ts|tsx|jsx)$/.test(lang(b))) no('<script lang="' + lang(b) + '"> is not supported yet – the Live Server compiles JavaScript, not TypeScript or JSX: write the script without lang', b);
      else if (lang(b) && lang(b) !== 'js') no('<script lang="' + lang(b) + '"> is not supported', b);
    });
    if (d.template) {
      if (d.template.src) no('<template src="…"> is not supported yet – put the template into the .vue file', d.template);
      if (lang(d.template) && lang(d.template) !== 'html') no('<template lang="' + lang(d.template) + '"> is not supported – only HTML templates', d.template);
    }
    d.styles.forEach(function (s) {
      if (s.src) no('<style src="…"> is not supported yet – put the style into the .vue file', s);
      if (lang(s) && lang(s) !== 'css') no('<style lang="' + lang(s) + '"> is not supported yet – the Live Server compiles plain CSS (scoped works), not SCSS, Sass, Less or Stylus', s);
      if (s.module) no('<style module> (CSS modules) is not supported yet – use <style scoped>', s);
    });
    return out;
  }

  function compile(file, source) {
    var parsed = C.parse(source, { filename: file });
    var d = parsed.descriptor;
    if (parsed.errors.length) return { errors: parsed.errors.map(function (e) { return describe(e, null); }) };
    var bad = unsupported(d);
    if (bad.length) return { errors: bad };

    var id = hash(file), scopeId = 'data-v-' + id;
    var scoped = d.styles.some(function (s) { return s.scoped; });
    var out = [], script = null, i;

    // the script: `const _sfc_main = { … }` (a <script setup> becomes its setup() – the template reads what it returns)
    if (d.script || d.scriptSetup) {
      script = C.compileScript(d, { id: id, inlineTemplate: false, genDefaultAs: '_sfc_main', sourceMap: false, isProd: false });
      out.push(script.content);
    } else {
      out.push('const _sfc_main = {};');
    }

    // the template: a render function; relative URLs in it (<img src="./logo.png">) become the URLs the server has the files at
    if (d.template) {
      var t = C.compileTemplate({
        source: d.template.content, filename: file, id: id, scoped: scoped, slotted: d.slotted, isProd: false,
        transformAssetUrls: { base: folderUrl(file), includeAbsolute: false },
        compilerOptions: { bindingMetadata: script ? script.bindings : undefined, scopeId: scoped ? scopeId : undefined, sourceMap: false }
      });
      if (t.errors && t.errors.length) return { errors: t.errors.map(function (e) { return describe(e, d.template); }) };
      out.push(t.code);
      out.push('_sfc_main.render = render;');
    }
    out.push('_sfc_main.__file = ' + JSON.stringify(file) + ';');
    if (scoped) out.push('_sfc_main.__scopeId = ' + JSON.stringify(scopeId) + ';');

    // the styles: one <style> element in the head, there when the module is loaded
    var css = [];
    for (i = 0; i < d.styles.length; i++) {
      var s = d.styles[i];
      var r = C.compileStyle({ source: s.content, filename: file, id: scopeId, scoped: !!s.scoped, isProd: false });
      if (r.errors && r.errors.length) return { errors: r.errors.map(function (e) { return describe(e, s); }) };
      css.push(r.code);
    }
    if (css.length) {
      out.push('(function () { if (typeof document === "undefined") return; var el = document.createElement("style"); ' +
        'el.setAttribute("data-lotus-vue", ' + JSON.stringify(file) + '); el.textContent = ' + JSON.stringify(css.join('\n')) + '; ' +
        'document.head.appendChild(el); })();');
    }
    out.push('export default _sfc_main;');
    return { code: out.join('\n') + '\n' };
  }

  root.lotusRequest = function (line) {
    var id = null;
    try {
      var req = JSON.parse(line);
      id = req.id === undefined ? null : req.id;
      if (req.op === 'version') return JSON.stringify({ id: id, vue: C.version });
      var res = compile(String(req.file), String(req.source));
      res.id = id;
      return JSON.stringify(res);
    } catch (e) {
      return JSON.stringify({ id: id, errors: [describe(e, null)] });
    }
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
