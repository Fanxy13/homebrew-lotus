// Lotus AI – what view_page asks a page, in JavaScript: what a person would notice, and the elements asked for (a CSS
// selector). The same script runs in WebKit (Page.swift, macOS) and in Chromium (PageChromium.swift, Linux and Windows).

enum PageSurvey {
    static let script = #"""
        function (sel) {
          const text = (el) => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80);
          const name = (el) => {
            let s = el.tagName.toLowerCase();
            if (el.id) s += '#' + el.id;
            if (el.classList && el.classList.length) s += '.' + [...el.classList].slice(0, 2).join('.');
            return s;
          };
          const visible = (el) => {
            const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
          };
          const doc = document.documentElement;
          const view = window.innerWidth;
          // what sticks out sideways: the outermost elements that end right of the screen
          const wide = [];
          if (doc.scrollWidth > view + 1 && document.body) {
            for (const el of document.body.querySelectorAll('*')) {
              const r = el.getBoundingClientRect();
              if (r.width > 0 && r.right > view + 1 && !(el.parentElement && el.parentElement.getBoundingClientRect().right > view + 1 && el.parentElement !== document.body)) {
                wide.push(name(el) + ' (' + Math.round(r.width) + ' px wide, ends at ' + Math.round(r.right) + ' px)');
                if (wide.length >= 5) break;
              }
            }
          }
          const fields = [...document.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=reset]), select, textarea')];
          const unlabeled = fields.filter((f) => !(f.id && document.querySelector('label[for="' + CSS.escape(f.id) + '"]')) && !f.closest('label') && !f.getAttribute('aria-label') && !f.getAttribute('aria-labelledby'));
          let elements = null, selError = '';
          if (sel) {
            try {
              const all = [...document.querySelectorAll(sel)];
              elements = { count: all.length, items: all.slice(0, 8).map((el) => {
                const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
                return { el: name(el), box: [Math.round(r.left + scrollX), Math.round(r.top + scrollY), Math.round(r.width), Math.round(r.height)],
                  visible: visible(el), text: text(el), display: cs.display, position: cs.position, color: cs.color, background: cs.backgroundColor,
                  font: cs.fontSize + ' ' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0].replace(/["']/g, ''), margin: cs.margin, padding: cs.padding };
              }) };
            } catch (e) { selError = String(e.message || e); }
          }
          return JSON.stringify({
            title: document.title, lang: doc.lang || '', viewport: !!document.querySelector('meta[name="viewport"]'),
            view, scrollWidth: doc.scrollWidth, height: Math.max(doc.scrollHeight, document.body ? document.body.scrollHeight : 0), wide,
            landmarks: ['header', 'nav', 'main', 'footer'].filter((t) => document.querySelector(t)),
            headings: [...document.querySelectorAll('h1, h2, h3')].slice(0, 24).map((h) => h.tagName.toLowerCase() + ' "' + text(h) + '"'),
            h1: document.querySelectorAll('h1').length,
            links: document.querySelectorAll('a').length,
            deadLinks: [...document.querySelectorAll('a')].filter((a) => !a.getAttribute('href') || a.getAttribute('href') === '#').length,
            buttons: [...document.querySelectorAll('button, input[type=submit], input[type=button]')].slice(0, 10).map((b) => text(b) || b.value || b.getAttribute('aria-label') || '(no text)'),
            forms: document.forms.length, fields: fields.length, unlabeled: unlabeled.length,
            images: document.images.length,
            noAlt: [...document.images].filter((i) => !i.hasAttribute('alt')).slice(0, 8).map((i) => i.getAttribute('src') || '(inline)'),
            broken: [...document.images].filter((i) => i.complete && i.naturalWidth === 0 && i.getAttribute('src')).slice(0, 8).map((i) => i.getAttribute('src')),
            text: (document.body ? document.body.innerText : '').replace(/\s+/g, ' ').trim().slice(0, 900),
            elements, selError,
          });
        }
        """#
}
