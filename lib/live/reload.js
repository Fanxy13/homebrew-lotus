// Lotus Live Server – in every page it serves: reloads the page when a file of the folder changes, and only
// swaps the style sheets when nothing but CSS changed. When the server stops, it waits for it to come back.
// It tells the server when this page is in front ("open /about.html") – /html takes the page that is open.
// A .vue file that cannot be compiled shows what is wrong over the page (window.__lotusError, called by the module the server
// sends in its place); the page reloads when the file is saved again, and Esc or a click puts the message away.
(() => {
  if (window.__lotusLive) return;
  window.__lotusLive = true;

  window.__lotusError = info => {
    let box = document.getElementById("__lotus-error");
    if (!box) {
      box = document.createElement("div");
      box.id = "__lotus-error";
      box.style.cssText = "position:fixed;inset:0;z-index:2147483647;overflow:auto;padding:28px 32px;background:rgba(14,10,12,.96);" +
        "color:#ffd9d9;font:13px/1.55 ui-monospace,'SF Mono',Menlo,monospace;white-space:pre-wrap;cursor:pointer";
      box.addEventListener("click", () => box.remove());
      document.addEventListener("keydown", e => { if (e.key === "Escape") box.remove(); });
      (document.body || document.documentElement).appendChild(box);
    }
    const title = document.createElement("div");
    title.style.cssText = "font:600 15px/1.4 -apple-system,system-ui,sans-serif;color:#ff8a8a;margin:0 0 14px";
    title.textContent = "Vue – " + info.file;
    box.appendChild(title);
    for (const e of info.errors || []) {
      const line = document.createElement("div");
      line.style.cssText = "margin:0 0 12px";
      line.textContent = (e.line ? "line " + e.line + (e.column ? ":" + e.column : "") + "  " : "") + e.message;
      box.appendChild(line);
    }
    const hint = document.createElement("div");
    hint.style.cssText = "margin-top:18px;color:#a08a8a";
    hint.textContent = "Save the file again to reload · click or Esc to hide this";
    box.appendChild(hint);
  };
  const url = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/__lotus/ws";
  let lost = false, wait = 500, socket = null;
  const mark = on => { document.documentElement.dataset.lotusLive = on ? "on" : "off"; };

  const swapStyles = () => {
    const links = [...document.querySelectorAll('link[rel~="stylesheet"][href]')]
      .filter(link => new URL(link.href, location.href).origin === location.origin);
    if (!links.length) return location.reload();
    for (const old of links) {
      const next = old.cloneNode();
      const href = new URL(old.href, location.href);
      href.searchParams.set("lotus", Date.now());
      next.href = href.href;
      next.onload = next.onerror = () => old.remove();   // the new one first, so nothing flashes
      old.after(next);
    }
  };

  const tell = () => {
    if (socket && socket.readyState === 1 && document.visibilityState !== "hidden") socket.send("open " + location.pathname);
  };
  document.addEventListener("visibilitychange", tell);
  window.addEventListener("focus", tell);

  const connect = () => {
    const ws = socket = new WebSocket(url);
    ws.onopen = () => {
      if (lost) return location.reload();               // the server is back: maybe with new files
      wait = 500;
      mark(true);
      tell();
    };
    ws.onmessage = e => (e.data === "css" ? swapStyles() : location.reload());
    ws.onclose = () => {
      lost = true;
      mark(false);
      setTimeout(connect, wait);
      wait = Math.min(wait * 2, 5000);
    };
  };
  connect();
})();
