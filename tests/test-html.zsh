# /html (plugins/liveserver: html.zsh, convert.py, lotusdoc/): web pages, style sheets and scripts as Word, PDF,
# Text, Markdown, OpenDocument and RTF – as code (colors, a number for each line of the file) or as the page a
# visitor reads. One file, the page open in Live Server, or all of a folder into a folder of their own; nothing is
# written over, the documents it made itself are made again. Python's standard library only – the documents are
# checked here without other programs (pdftotext and LibreOffice only when they are there).
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
answer() { (sleep 1.5; print -rn -- $1; sleep 0.5) | script -q /dev/null zsh -fc "$2" 2>&1 | plain }
if (( ! $+commands[python3] )); then print -r -- "  – no python3: skipped"; return 0; fi

out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/liveserver")
check_has "installed with its two commands" "$out" "lotus html · lotus liveserver"
check_has "help" "$(lotus html help 2>&1 | plain)" "/html all"

# a site: pages in folders, a style sheet, a script, images, what is hidden, a dependency, a minified library, a link
# out of the folder and a page with an umlaut in its name
S=$HOME/site
zf_mkdir -p $S/css $S/js $S/img $S/docs $S/.git $S/node_modules/pkg $HOME/outside
python3 - $S/img <<'PY'
import struct, sys, zlib
def png(path, w, h, alpha):
    raw = b"".join(b"\x00" + b"".join(bytes((x * 4 % 256, y * 4 % 256, 140) + ((x * 4 % 256,) if alpha else ())) for x in range(w)) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
png(sys.argv[1] + "/sky.png", 120, 60, False)
png(sys.argv[1] + "/logo.png", 48, 48, True)
PY
cat >| $S/index.html <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head><meta charset="utf-8"><title>Start – Grüezi</title><link rel="stylesheet" href="css/style.css"></head>
<body>
  <img src="img/logo.png" alt="Logo">
  <h1>Willkommen auf <em>meiner</em> Seite</h1>
  <p>Ein <strong>Absatz</strong> mit <a href="https://example.com/">Link</a> → ✓
  <ul><li>Eins<li>Zwei<ol start="3"><li>Drei</ol></ul>
  <table><thead><tr><th>Tag<th>Fach</thead><tr><td>Montag<td>Mathe</table>
  <figure><img src="img/sky.png" alt="Himmel"><figcaption>Ein Himmel</figcaption></figure>
  <p hidden>Geheim</p>
  <script>console.log("nicht sichtbar")</script>
</body>
</html>
EOF
print -r -- $'/* Farben */\nbody {\n\tcolor: #333;\n}\na:hover { color: red !important; }' >| $S/css/style.css
print -r -- $'// Menü\nconst n = 42;\nexport function sum(a, b) { return a / 2 + b; }' >| $S/js/app.js
print -r -- '<title>Über uns</title><h2>Über uns</h2><p>Wir.' >| $S/docs/über.html
print -r -- 'a{b:c}' >| $S/css/bootstrap.min.css
print -r -- 'SECRET=1' >| $S/.env
print -r -- '[core]' >| $S/.git/config
print -r -- 'module.exports = 1' >| $S/node_modules/pkg/index.js
print -r -- 'secret();' >| $HOME/outside/secret.js
ln -s $HOME/outside/secret.js $S/js/link.js

# checks of the documents, with nothing but Python: the parts are there and are XML, the PDF's objects are where its
# table says, and the text that is in them
cat >| $HOME/doc.py <<'PY'
import re, sys, zipfile, zlib
from xml.dom import minidom
kind, path = sys.argv[1], sys.argv[2]
data = open(path, "rb").read()
if kind in ("docx", "odt"):
    z = zipfile.ZipFile(path)
    names = z.namelist()
    for n in names:
        if n.endswith(".xml") or n.endswith(".rels"):
            minidom.parseString(z.read(n))                       # every part is XML
    main = z.read("word/document.xml" if kind == "docx" else "content.xml").decode("utf-8")
    text = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", main)) if kind == "docx" else re.sub(r"<[^>]+>", "", main)
    print("parts:", " ".join(sorted(names)))
    print("colors:", " ".join(sorted(set(re.findall(r'(?:w:color w:val="|fo:color="#)([0-9A-Fa-f]{6})', main)))))
    print("first:", names[0], z.getinfo(names[0]).compress_type)
    print("text:", text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&"))
    print("main:", main)
elif kind == "pdf":
    assert data.startswith(b"%PDF-1.7") and data.rstrip().endswith(b"%%EOF"), "not a whole PDF"
    start = int(re.findall(rb"startxref\s+(\d+)", data)[-1])
    m = re.match(rb"xref\s+0 (\d+)\s+", data[start:])
    n, pos = int(m.group(1)), start + m.end()
    for i in range(1, n):
        entry = data[pos + 20 * i:pos + 20 * i + 20]
        assert data[int(entry[:10]):].startswith(f"{i} 0 obj".encode()), f"object {i} is not where the table says"
    # the text: content streams decoded with the fonts' ToUnicode tables
    streams = {}
    for m in re.finditer(rb"(\d+) 0 obj\n<<((?:(?!endobj).)*?)>>\nstream\n", data, re.S):
        length = int(re.search(rb"/Length (\d+)", m.group(2)).group(1))
        body = data[m.end():m.end() + length]
        if b"/FlateDecode" in m.group(2) and b"/Subtype /Image" not in m.group(2) and b"/Length1" not in m.group(2):
            body = zlib.decompress(body)
        streams[int(m.group(1))] = body
    maps = {}
    for num, body in streams.items():
        if b"beginbfchar" in body:
            for cid, uni in re.findall(rb"<([0-9A-F]{4})> <([0-9A-F]+)>", body):
                maps.setdefault(num, {})[cid.decode()] = bytes.fromhex(uni.decode()).decode("utf-16-be")
    fonts = {}
    for m in re.finditer(rb"/(F\d+) (\d+) 0 R", data):
        obj = re.search(rb"\n" + m.group(2) + rb" 0 obj\n(.*?)\nendobj", data, re.S).group(1)
        tu = re.search(rb"/ToUnicode (\d+) 0 R", obj)
        fonts[m.group(1).decode()] = maps.get(int(tu.group(1)), {}) if tu else {}
    text = []
    for body in streams.values():
        for font, hexed in re.findall(rb"/(F\d+) [\d.]+ Tf .*?<([0-9A-F]*)> Tj", body):
            table = fonts.get(font.decode(), {})
            text.append("".join(table.get(hexed[i:i + 4].decode(), "") for i in range(0, len(hexed), 4)))
    print("pages:", len(re.findall(rb"/Type /Page\b", data)), "fonts:", len(re.findall(rb"/FontFile2", data)),
          "images:", len(re.findall(rb"/Subtype /Image", data)), "links:", len(re.findall(rb"/S /URI", data)))
    print("text:", " ".join(text))
PY
doc() { python3 $HOME/doc.py "$@" 2>&1 }

# ── all of the folder: a folder for the format inside it, the files in their folders ──
cd $S
out=$(lotus html all docx 2>&1 | plain)
check_has "all: what it is" "$out" "All of site  2 pages · 1 style sheet · 1 script"
check_has "all: how many, into what" "$out" "4 files → Word  2 pages · 1 style sheet · 1 script · as code"
check_has "all: where" "$out" "Saved in ~/site/Word"
check_has "all: what was left out, and why" "$out" "Left out: 2 images · 1 minified library (bootstrap.min.css)"
check "a page: its document" test -s $S/Word/index.html.docx
check "the folders as they are" test -s $S/Word/css/style.css.docx
check "a name with an umlaut" test -s $S/Word/docs/über.html.docx
check "not what is hidden" eval '[[ ! -e $S/Word/.env.docx && ! -e $S/Word/.git ]]'
check "not the dependencies" test ! -e $S/Word/node_modules
check "not a link out of the folder" test ! -e $S/Word/js/link.js.docx
check "the originals are as they were" eval '[[ $(<$S/css/bootstrap.min.css) == "a{b:c}" ]]'
d=$(doc docx $S/Word/index.html.docx)
check_has "Word: every part, numbered lines" "$d" "word/numbering.xml"
check_has "Word: the file, a line about it, then the code as it is" "$d" 'text: index.htmlsite · 14 lines · HTML · '
check_has "  – the code" "$d" '<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">'
check_has "Word: HTML's colors – tags, attribute names and values, and the script in the page" "$d" \
  "colors: 0000FF 001080 795E26 800000 A31515 E50000"
styles=$(python3 -c 'import sys, zipfile; print(zipfile.ZipFile(sys.argv[1]).read("word/styles.xml").decode())' $S/Word/index.html.docx)
check_has "Word: each line of the file numbered once, even when it wraps (numbered paragraphs, not lines)" "$styles" \
  '<w:numPr><w:numId w:val="1"/></w:numPr>'
check_has "Word: the code is not spell checked" "$styles" "<w:noProof/>"
d=$(doc docx $S/Word/css/style.css.docx)
check_has "CSS: selectors, properties and values in their colors" "$d" "0451A5"
check_has "CSS: a tab is four spaces" "$d" "/* Farben */body {    color: #333;}"
check_has "the line about a file: folder, lines, language, size" "$d" "site · 5 lines · CSS · "

# again: the folder is ours, its documents are made again – not "Word (2)", not "index.html (2).docx"
lotus html all docx >/dev/null 2>&1
check "again: the same folder" test ! -e "$S/Word (2)"
check "again: the documents made again" test ! -e "$S/Word/index.html (2).docx"
# a document you changed stays yours: the new one goes next to it
print -r -- "my changes" >| $S/Word/js/app.js.docx
lotus html all docx >/dev/null 2>&1
check_eq "a document you changed is never written over" "$(<$S/Word/js/app.js.docx)" "my changes"
check "the new one next to it" test -s "$S/Word/js/app.js (2).docx"
# a folder "PDF" of your own is not used
zf_mkdir -p $S/PDF && print -r -- mine >| $S/PDF/notes.txt
out=$(lotus html all pdf 2>&1 | plain)
check_has "a folder of the same name that is not ours: one of its own" "$out" "Saved in ~/site/PDF (2)"
check_eq "and yours stays as it was" "$(<$S/PDF/notes.txt)" "mine"
d=$(doc pdf "$S/PDF (2)/index.html.pdf")
check_has "PDF: every object where the table says, fonts embedded" "$d" "fonts: "
check_has "PDF: the code as text you can copy" "$d" '<!DOCTYPE html>'
check_has "PDF: umlauts and arrows" "$d" "Grüezi"
check_has "PDF: the file, then the numbered lines" "$d" "text: index.html site · 14 lines"
check_has "  – a number before each line" "$d" "1 <!DOCTYPE html> 2 <html"
rm -rf "$S/PDF (2)" $S/PDF

# ── one file, every format ──
lotus html index.html txt >/dev/null 2>&1
check "Text: the file itself, byte for byte" cmp $S/index.html $S/index.html.txt
lotus html css/style.css md >/dev/null 2>&1
check_has "Markdown: the file in a code block of its language" "$(<$S/css/style.css.md)" $'```css\n/* Farben */'
lotus html js/app.js odt >/dev/null 2>&1
d=$(doc odt $S/js/app.js.odt)
check_has "OpenDocument: mimetype first and not compressed" "$d" "first: mimetype 0"
check_has "OpenDocument: numbered code lines" "$d" '<text:list text:style-name="CodeNumbers">'
check_has "OpenDocument: the code" "$d" "const n = 42;"
lotus html css/style.css odt >/dev/null 2>&1
check_has "OpenDocument: spaces at the start of a line stay (a tab is 4)" "$(doc odt $S/css/style.css.odt)" '<text:s text:c="4"/>'
lotus html js/app.js rtf >/dev/null 2>&1
rtf=$(<$S/js/app.js.rtf)
check_has "RTF: an RTF" "$rtf" '{\rtf1\ansi'
check_has "RTF: umlauts as Unicode" "$rtf" 'Men\u252?'
check_has "RTF: the number of each line" "$rtf" '\tab{\fs16'
out=$(lotus html index.html 2>&1 | plain)
check_has "without a keyboard and without a format: asks for it" "$out" "Into which format?"

# ── a page as a visitor reads it ──
lotus html index.html docx --page >/dev/null 2>&1
d=$(doc docx $S/index.docx)
check_has "page: the heading" "$d" '<w:pStyle w:val="Heading1"/>'
check_has "page: text of the page, without what is hidden" "$d" "Willkommen auf meiner Seite"
check "page: nothing hidden, no script" eval '[[ $d != *Geheim* && $d != *"nicht sichtbar"* ]]'
check_has "page: a table" "$d" "<w:tbl>"
check_has "page: the images in it" "$d" "word/media/image2.png"
check_has "page: a list item numbered 3" "$d" ">3.<"
rels=$(python3 -c 'import sys, zipfile; print(zipfile.ZipFile(sys.argv[1]).read("word/_rels/document.xml.rels").decode())' $S/index.docx)
check_has "page: the link" "$rels" 'Target="https://example.com/" TargetMode="External"'
lotus html index.html md --page >/dev/null 2>&1
md=$(<$S/index.md)
check_has "page as Markdown: heading" "$md" "# Willkommen auf *meiner* Seite"
check_has "page as Markdown: link" "$md" "[Link](https://example.com/)"
check_has "page as Markdown: table" "$md" "| Tag | Fach |"
check_has "page as Markdown: the image where it is" "$md" "![Himmel](img/sky.png)"
lotus html index.html txt --page >/dev/null 2>&1
check_has "page as text" "$(<$S/index.txt)" $'Willkommen auf meiner Seite\n=========='
lotus html index.html pdf --page >/dev/null 2>&1
d=$(doc pdf $S/index.pdf)
check_has "page as PDF: images (one with transparency), the link" "$d" "images: 3 links: 1"
check_has "page as PDF: its text" "$d" "Willkommen auf"
if (( $+commands[pdftotext] )); then
  check_has "pdftotext reads it too" "$(pdftotext $S/index.pdf - 2>/dev/null)" "Montag"
fi

# ── which files ──
out=$(lotus html 'css/*.css' txt 2>&1 | plain)
check_has "a pattern" "$out" "style.css.txt"
check "  – minified files when asked for by name" test -s $S/css/bootstrap.min.css.txt
out=$(lotus html js txt 2>&1 | plain)
check_has "a folder: all of it, into a folder of its own" "$out" "Saved in ~/site/js/Text"
check "  – there" test -s $S/js/Text/app.js.txt
rm -f $S/css/style.css.txt
(cd $S && lotus html css/style.css - > txt)
check "/html … -> txt: the file zsh made for > is gone" test ! -e $S/txt
check "/html … -> txt: and txt was the format" test -s $S/css/style.css.txt
out=$(lotus html nothere.html txt 2>&1 | plain)
check_has "a file that is not there" "$out" "Not found: nothere.html"
out=$(cd $HOME && lotus html all docx 2>&1 | plain)
check_has "never your whole home folder" "$out" "That is your whole home folder"
zf_mkdir -p $HOME/empty
out=$(cd $HOME/empty && lotus html all docx 2>&1 | plain)
check_has "a folder without web files" "$out" "No web files in ~/empty"
out=$(cd $S && lotus html txt 2>&1 | plain)
check_has "no file, no page open in Live Server: which?" "$out" "No page is open in Live Server"

# ── the page open in Live Server's browser ──
zmodload zsh/net/tcp
free_port() {
  local -i p
  for (( p = 42800 + RANDOM % 400; p < 43600; p++ )); do ztcp -l $p 2>/dev/null && { ztcp -c $REPLY; REPLY=$p; return }; done
  return 1
}
free_port; port=$REPLY
(cd $S && lotus liveserver --no-open --port $port >| $HOME/live.log 2>&1 &)
for i in {1..50}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$port/ && break; sleep 0.1; done
cat >| $HOME/tab.py <<'PY'
import base64, os, socket, sys, time
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 3)
s.sendall(("GET /__lotus/ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
           + base64.b64encode(os.urandom(16)).decode() + "\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf:
    buf += s.recv(4096)
data, mask = ("open " + sys.argv[2]).encode(), os.urandom(4)
s.sendall(bytes([0x81, 0x80 | len(data)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
time.sleep(float(sys.argv[3]))
PY
python3 $HOME/tab.py $port /docs/%C3%BCber.html 5 &
tab=$!
for i in {1..30}; do [[ -e $LOTUS_DATA/plugins/liveserver/running/$port.page ]] && break; sleep 0.1; done
rm -f $S/docs/über.html.txt
out=$(cd $S && lotus html txt 2>&1 | plain)
check_has "/html: the page open in the browser" "$out" "docs/über.html  open in the browser right now"
check "  – converted" test -s $S/docs/über.html.txt
kill $tab 2>/dev/null; wait $tab 2>/dev/null
for i in {1..30}; do [[ -e $LOTUS_DATA/plugins/liveserver/running/$port.page ]] || break; sleep 0.1; done
check "the tab closed: no page open any more" test ! -e $LOTUS_DATA/plugins/liveserver/running/$port.page
lotus liveserver stop >/dev/null 2>&1

# ── asked, on a keyboard: what (the newest file first), the format, code or page ──
touch $S/css/style.css
rm -f $S/css/style.css.docx
keys() { (sleep 2; print -rn -- $'\r'; sleep 0.6; print -rn -- $'\r'; sleep 0.6; print -rn -- $'\r'; sleep 0.6; print -rn -- n; sleep 1) |
         script -q /dev/null zsh -fc "cd $S && $LOTUS_ROOT/bin/lotus html" 2>&1 | plain }
out=$(keys)
check_has "asks what – the newest file first" "$out" "What should become a document?"
check_has "  – and offers all of the folder" "$out" "All of site"
check_has "asks the format" "$out" "Into which format?"
check "the newest file, in the first format (Word)" test -s $S/css/style.css.docx

# ── the converter on its own: no __pycache__ in the plugin (Lotus would take it for a change) ──
check "no bytecode in the installed plugin" eval '[[ -z $(print -l $LOTUS_CONF/plugins/liveserver/**/__pycache__(N)) ]]'
out=$(lotus plugin 2>&1 | plain)
check "the plugin is still allowed after all of this" eval '[[ $out != *"changed"* ]]'
