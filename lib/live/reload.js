// Lotus Live Server – in every page it serves: reloads the page when a file of the folder changes, and only
// swaps the style sheets when nothing but CSS changed. When the server stops, it waits for it to come back.
// It tells the server when this page is in front ("open /about.html") – /html takes the page that is open.
(() => {
  if (window.__lotusLive) return;
  window.__lotusLive = true;
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
