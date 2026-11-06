# Live Server (lib/live, lotus liveserver – built into Lotus): it serves the folder Lotus was called in to this
# Mac and the devices in its Wi-Fi – index.html, or a menu of the folder's pages – and reloads open pages when a
# file changes (only the style sheets when nothing but CSS changed). Nothing outside the folder, no hidden files,
# nobody from another network, only the Mac's own names; --local: 127.0.0.1 only. A second one for the same
# folder opens the first; lotus liveserver stop ends them.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
answer() { (sleep 1.5; print -rn -- $1; sleep 0.5) | tpty zsh -fc "$2" 2>&1 | plain }
if (( ! $+commands[python3] )); then print -r -- "  – no python3: skipped"; return 0; fi
zmodload zsh/net/tcp

# ── nothing to install: it is part of Lotus ──
check_has "help" "$(lotus liveserver help 2>&1 | plain)" "lotus liveserver stop"
check_has "a command of Lotus' own: the cheatsheet lists it" "$(grep -c "^Developer tools	/liveserver	liveserver	" $LOTUS_ROOT/data/commands.tsv)" "1"
lotus features live off >/dev/null 2>&1
check_has "a feature that is off explains itself" "$(lotus liveserver help 2>&1 < /dev/null | plain)" "Live Server is turned off"
lotus features live on >/dev/null 2>&1
check_has "and on again" "$(lotus liveserver help 2>&1 | plain)" "lotus liveserver stop"

# a site: pages in folders, a style sheet, hidden files, a dependency and a link out of the folder
S=$HOME/site
zf_mkdir -p $S/docs/api $S/css $S/.git $S/node_modules/pkg $S/blog $HOME/outside
print -r -- '<!doctype html><html><head><title>About – Grüezi</title><link rel="stylesheet" href="css/style.css"></head><body><h1>About</h1></body></html>' >| $S/about.html
print -r -- '<title>Contact us</title><p>Contact' >| $S/contact.html
print -r -- '<title>Docs home</title><p>docs' >| $S/docs/index.html
print -r -- '<title>Guide &amp; tips</title>' >| $S/docs/guide.html
print -r -- '<p>no title' >| $S/docs/api/reference.htm
print -r -- '<title>First post</title>' >| $S/blog/first.html
print -r -- 'body { color: red }' >| $S/css/style.css
print -r -- 'SECRET=1' >| $S/.env
print -r -- '[core]' >| $S/.git/config
print -r -- '<title>A dependency</title>' >| $S/node_modules/pkg/readme.html
print -r -- 'outside' >| $HOME/outside/secret.txt
ln -s $HOME/outside $S/out
ln -s $HOME/outside/secret.txt $S/leak.txt
head -c 5000 /dev/zero >| $S/clip.mp4

free_port() {
  local -i p
  for (( p = 41800 + RANDOM % 400; p < 42600; p++ )); do ztcp -l $p 2>/dev/null && { ztcp -c $REPLY; REPLY=$p; return }; done
  return 1
}
up() { local i; for i in {1..50}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$1/ && return 0; sleep 0.1; done; return 1 }
code() { curl -s --path-as-is -o /dev/null -w '%{http_code}' "$@" }
free_port; port=$REPLY B=http://127.0.0.1:$REPLY

# ── where it serves: never your whole home folder ──
check_has "the home folder is refused" "$(cd $HOME && lotus liveserver --no-open 2>&1 | plain)" "your whole home folder"
check_has "a folder that is not there" "$(cd $S && lotus liveserver nothing --no-open 2>&1 | plain)" "There is no nothing"
check_has "a port it cannot have" "$(cd $S && lotus liveserver --port 80 --no-open 2>&1 | plain)" "A number from 1024 to 65535"

# ── started in the folder (Lotus tells a full plugin where: LOTUS_PWD) ──
(cd $S && lotus liveserver --no-open --port $port >| $HOME/live.log 2>&1 &)
check "it answers" up $port
out=$(plain < $HOME/live.log)
check_has "it says where" "$out" "Address     $B  → a menu of 6 pages"
check_has "and how it stops" "$out" "Ctrl-C stops it"
check_has "the folder Lotus was called in" "$out" "Live Server  ~/site"
menu=$(curl -s $B/)
check_has "no index.html: the menu" "$menu" "<h1><span>site</span></h1>"
check_has "the pages by their titles" "$menu" '<span class="name">About – Grüezi</span><span class="file">about.html</span>'
check_has "in folders, an index first" "$menu" 'class="page home" href="/docs/index.html"'
check_has "without a title: the file" "$menu" '<span class="name">reference.htm</span>'
check "a few pages: no filter" eval '[[ $menu != *class=\"filter\"* ]]'
check "not the dependencies" eval '[[ $menu != *"A dependency"* ]]'
check_has "it reloads too" "$menu" '<script src="/__lotus/reload.js"></script>'
check_has "the menu is always there" "$(curl -s $B/__lotus/)" "About – Grüezi"
page=$(curl -s $B/about.html)
check_has "a page gets the reload script before </body>" "$page" '<h1>About</h1><script src="/__lotus/reload.js"></script></body>'
check_has "as UTF-8" "$(curl -sI $B/about.html)" "Content-Type: text/html; charset=utf-8"
check_has "never from the cache" "$(curl -sI $B/css/style.css)" "Cache-Control: no-store"
check_has "a folder without its / is sent to it" "$(curl -sI $B/docs)" "Location: /docs/"
check_has "a folder's index.html" "$(curl -s $B/docs/)" "<title>Docs home</title>"
check_has "a folder without one: its menu" "$(curl -s $B/blog/)" "First post"
check_eq "a dependency is served" "$(code $B/node_modules/pkg/readme.html)" 200
check_has "a part of a video (Safari asks so)" "$(curl -s -D - -o /dev/null -H 'Range: bytes=100-199' $B/clip.mp4)" "Content-Range: bytes 100-199/5000"
check_has "the reload script" "$(curl -s $B/__lotus/reload.js)" "new WebSocket"

# ── nothing outside the folder, nothing hidden, only for this Mac ──
check_eq "no .." "$(code $B/../outside/secret.txt)" 404
check_eq "no %2e%2e" "$(code $B/%2e%2e/outside/secret.txt)" 404
check_eq "no ..%2F" "$(code $B/..%2Foutside%2Fsecret.txt)" 404
check_eq "no link out of the folder" "$(code $B/out/secret.txt)" 404
check_eq "no file link out of it" "$(code $B/leak.txt)" 404
check_eq "no .env" "$(code $B/.env)" 404
check_eq "no .git" "$(code $B/.git/config)" 404
check_eq "another name for this Mac is refused" "$(code -H 'Host: evil.example:80' $B/about.html)" 403
check_eq "localhost works" "$(code -H "Host: localhost:$port" $B/about.html)" 200
check_has "not here: a page that says so" "$(curl -s $B/nope.html)" "Not here: /nope.html"

# ── the Wi-Fi: its devices, nobody else ──
cat >| $HOME/wifi.py <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import liveserver as L
mac = '''lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
\tinet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
\tinet6 fe80::1c%en0 prefixlen 64 secured scopeid 0xe
\tinet 192.168.178.23 netmask 0xffffff00 broadcast 192.168.178.255
awdl0: flags=8943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1500
\tinet 169.254.7.7 netmask 0xffff0000
utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
\tinet 10.8.0.2 --> 10.8.0.2 netmask 0xffffff00
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
\tinet 85.1.2.3 netmask 0xffffff00 broadcast 85.1.2.255
'''
nets = L.networks(mac)
print(" ".join(f"{n}={i}" for n, i in nets))
print(" ".join(f"{ip}:{'yes' if L.allowed(ip, nets) else 'no'}" for ip in sys.argv[2:]))
ports = L.hardware_ports("Hardware Port: Ethernet\nDevice: en5\nEthernet Address: x\n\nHardware Port: Wi-Fi\nDevice: en0\n\nHardware Port: iPhone USB\nDevice: en7\n")
print(ports)
for iface, ip in (("en0", "192.168.178.23/24"), ("en0", "172.20.10.2/28"), ("en7", "172.20.10.3/28"), ("bridge100", "192.168.2.1/24"), ("en5", "10.0.0.4/16"), ("en9", "10.1.0.4/16")):
    print(L.where(iface, L.ipaddress.IPv4Interface(ip), ports))
EOF
out=(${(f)"$(python3 -B $HOME/wifi.py $LOTUS_ROOT/lib/live 192.168.178.40 ::ffff:192.168.178.9 127.0.0.1 192.168.1.40 10.8.0.5 85.1.2.9 8.8.8.8)"})
check_eq "the Wi-Fi's network – not the VPN, AirDrop or an internet address" "$out[1]" "en0=192.168.178.23/24"
check_eq "this Mac and the Wi-Fi in, nobody else" "$out[2]" \
  "192.168.178.40:yes ::ffff:192.168.178.9:yes 127.0.0.1:yes 192.168.1.40:no 10.8.0.5:no 85.1.2.9:no 8.8.8.8:no"
check_eq "the Mac's network ports by name" "$out[3]" "{'en5': 'Ethernet', 'en0': 'Wi-Fi', 'en7': 'iPhone USB'}"
check_eq "each address says whom it is for" "${(j:|:)out[4,-1]}" "phones and computers in this Wi-Fi|your iPhone, whose hotspot the Mac uses|your iPhone, whose hotspot the Mac uses|devices the Mac shares its internet with|devices in this network (Ethernet)|devices in this network"
check_eq "a Wi-Fi address that is not the Mac's is refused" "$(code -H 'Host: 192.168.178.250' $B/about.html)" 403
ip=$(python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); import liveserver as L; print(*L.Lan(True).addresses()[:1])" $LOTUS_ROOT/lib/live 2>/dev/null)
if [[ -n $ip ]]; then
  check_has "it says the Wi-Fi address" "$(plain < $HOME/live.log)" "Wi-Fi       http://$ip:$port"
  check_eq "the Mac's Wi-Fi address works" "$(code http://$ip:$port/about.html)" 200
else
  check_has "no Wi-Fi: it says so" "$(plain < $HOME/live.log)" "Wi-Fi       not in a Wi-Fi now"
fi

# ── live: a page that is open hears about every change ──
cat >| $HOME/ws.py <<'EOF'
import base64, os, socket, sys
port, n = int(sys.argv[1]), int(sys.argv[2])
s = socket.create_connection(("127.0.0.1", port), 3)
key = base64.b64encode(os.urandom(16)).decode()
s.sendall(f"GET /__lotus/ws HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
buf = b""
while b"\r\n\r\n" not in buf:
    buf += s.recv(4096)
head, buf = buf.split(b"\r\n\r\n", 1)
print(head.split(b"\r\n")[0].decode(), flush=True)
s.settimeout(8)
try:
    while n:
        while len(buf) < 2 or len(buf) < 2 + (buf[1] & 127):
            buf += s.recv(4096)
        op, ln = buf[0] & 15, buf[1] & 127
        data, buf = buf[2:2 + ln], buf[2 + ln:]
        if op == 1:
            print(data.decode(), flush=True)
            n -= 1
except OSError:
    print("no answer", flush=True)
EOF
python3 $HOME/ws.py $port 2 >| $HOME/ws.log &
ws=$!
sleep 0.8
print -r -- 'body { color: blue }' >| $S/css/style.css
sleep 1.2
print -r -- '<title>Contact</title><p>new' >| $S/contact.html
for i in {1..40}; do kill -0 $ws 2>/dev/null || break; sleep 0.1; done
kill $ws 2>/dev/null
ws=$(<$HOME/ws.log)
check_has "a WebSocket" "$ws" "HTTP/1.1 101 Switching Protocols"
check_eq "CSS: only the styles, then a page: a reload" "${${(f)ws}[2,3]}" "css reload"
out=$(plain < $HOME/live.log)
check_has "the terminal shows what changed" "$out" "↻ css/style.css  styles only"
check_has "every change" "$out" "↻ contact.html"
check_has "and what was not there" "$out" "404 /nope.html"

# ── one per folder; stop ──
out=$(cd $S && lotus liveserver --no-open 2>&1 | plain)
check_has "the same folder again: the one that runs" "$out" "Already running in another window: $B/"
out=$(lotus liveserver stop 2>&1 | plain)
check_has "lotus liveserver stop" "$out" "Stopped $B  ~/site"
check "and it is gone" eval '! curl -s -m 1 -o /dev/null $B/'
for i in {1..20}; do [[ $(<$HOME/live.log) == *Stopped* ]] && break; sleep 0.1; done
check_has "its window says so" "$(plain < $HOME/live.log)" "✓ Stopped $B"
check_has "none left" "$(lotus liveserver stop 2>&1 | plain)" "No live server is running"
sleep 30 &
other=$!
print -r -- "$other"$'\n'"$S" >| $LOTUS_STATE/live/running/$port
check_has "a number macOS gave to another program is not stopped" "$(lotus liveserver stop 2>&1 | plain)" "No live server is running"
check "it still runs" kill -0 $other
check "and the old note is gone" test ! -e $LOTUS_STATE/live/running/$port
kill $other 2>/dev/null

# ── a page of its own, and index.html ──
(cd $S && lotus liveserver about.html --no-open --port $port >| $HOME/live.log 2>&1 &)
up $port
check_has "a page given: that page" "$(plain < $HOME/live.log)" "Address     $B/about.html"
lotus liveserver stop >/dev/null 2>&1
for i in {1..30}; do curl -s -m 1 -o /dev/null $B/ || break; sleep 0.1; done

# ── --local: only this Mac ──
(cd $S && lotus liveserver --local --no-open --port $port >| $HOME/live.log 2>&1 &)
up $port
check_has "--local says so" "$(plain < $HOME/live.log)" "Wi-Fi       off – only this Mac (--local)"
check_eq "and still works here" "$(code $B/about.html)" 200
if [[ -n $ip ]]; then
  check "not from the Wi-Fi" eval '! curl -s -m 1 -o /dev/null http://$ip:$port/'
fi
lotus liveserver stop >/dev/null 2>&1
print -r -- '<title>Home</title><p>home' >| $S/index.html
for i in {1..30}; do curl -s -m 1 -o /dev/null $B/ || break; sleep 0.1; done
(cd $S && lotus liveserver --no-open --port $port >| $HOME/live.log 2>&1 &)
up $port
check_has "with an index.html: that one" "$(plain < $HOME/live.log)" "Address     $B  → index.html"
check_has "it is the start page" "$(curl -s $B/)" "<title>Home</title>"
menu=$(curl -s $B/__lotus/)
check_has "the menu is still there" "$menu" "About – Grüezi"
check_has "seven pages: a filter" "$menu" 'class="filter"'
lotus liveserver stop >/dev/null 2>&1

# ── the QR code for the phone's camera ──
cat >| $HOME/qr.py <<'EOF'
import hashlib, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import qrart
def h(text, level="M"):
    rows = qrart.encode(text, level)
    flat = "\n".join("".join("1" if c else "0" for c in r) for r in rows)
    return f"{len(rows)} " + hashlib.sha256(flat.encode()).hexdigest()[:16]
print(h("http://192.168.178.23:5500"))
print(h("http://192.168.178.23:5500", "L"))
print(h("http://172.20.10.2:5500/docs/über uns.html"))
print(h("a"))
print(h("http://192.168.2.1:5577/" + "x" * 150))
try:
    qrart.encode("x" * 400)
except ValueError:
    print("too long")
rows = qrart.encode("http://192.168.178.23:5500")
n = len(rows)
ring = lambda x0, y0: all(rows[y0 + y][x0 + x] == (max(abs(x - 3), abs(y - 3)) != 2) for x in range(7) for y in range(7))
print("finders" if ring(0, 0) and ring(n - 7, 0) and ring(0, n - 7) else "no finders",
      "timing" if all(rows[6][i] == (i % 2 == 0) and rows[i][6] == (i % 2 == 0) for i in range(8, n - 8)) else "no timing")
print(len(qrart.render(rows)), n + 4)
EOF
out=(${(f)"$(python3 -B $HOME/qr.py $LOTUS_ROOT/lib/live 2>&1)"})
# these hashes are of codes that OpenCV's QR reader decoded back to the text (all versions 1–10, levels L and M)
check_eq "QR: the address of a phone is a version 2 code" "$out[1]" "25 ebf63ab2d26af171"
check_eq "QR: level L is another code of the same size" "$out[2]" "25 9ac19ddc17342597"
check_eq "QR: a longer address with an umlaut" "$out[3]" "29 337891f3acdf29b5"
check_eq "QR: the smallest" "$out[4]" "21 e8ab680854e4019c"
check_eq "QR: a long one steps up a version (version 9)" "$out[5]" "53 2fd165d1c0c25ef4"
check_eq "QR: what is too long for one is said" "$out[6]" "too long"
check_eq "QR: finder and timing patterns are where they belong" "$out[7]" "finders timing"
check_eq "QR: two rows of modules to a row of the terminal, a quiet zone around" "$out[8]" "15 29"
if python3 -c 'import cv2, numpy' 2>/dev/null; then
  cat >| $HOME/qrdecode.py <<'EOF'
import random, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import cv2, numpy as np, qrart
random.seed(3)
readers = [cv2.QRCodeDetector(), cv2.QRCodeDetectorAruco()]
def reads(rows, text):
    n = len(rows) + 8
    img = np.full((n * 8, n * 8), 255, np.uint8)
    for y, row in enumerate(rows):
        for x, d in enumerate(row):
            if d:
                img[(y + 4) * 8:(y + 5) * 8, (x + 4) * 8:(x + 5) * 8] = 0
    return any(r.detectAndDecode(img)[0] == text for r in readers)
bad = 0
for level in "LM":
    for length in range(1, 130, 4):
        text = "http://" + "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789/:.-_") for _ in range(length))
        try:
            rows = qrart.encode(text, level)
        except ValueError:
            continue
        bad += not reads(rows, text)
print("all read" if not bad else f"{bad} not read")
EOF
  check_eq "QR: OpenCV reads what it makes back to the text" "$(python3 -B $HOME/qrdecode.py $LOTUS_ROOT/lib/live 2>&1)" "all read"
else
  print -r -- "  – no OpenCV: its reading of the QR codes is skipped"
fi

# on a keyboard: the code of the first network when it starts, Tab for the next, Shift-Tab back; in place while
# nothing else was written, below what came otherwise. Two networks, as a Mac sharing its internet has.
fake=$HOME/ifconfig.sh
cat >| $fake <<'EOF'
#!/bin/sh
printf 'en0: flags=8863<UP> mtu 1500\n\tinet 192.168.178.23 netmask 0xffffff00 broadcast x\nbridge100: flags=8863<UP> mtu 1500\n\tinet 192.168.2.1 netmask 0xffffff00 broadcast x\n'
EOF
chmod +x $fake
qrsession() {   # <what the keyboard does, in the order of a subshell> [options of lotus liveserver] – on $qrport
  ( eval "$1" ) | LOTUS_LIVE_IFCONFIG=$fake script -q /dev/null zsh -fc "cd $S && $LOTUS_ROOT/bin/lotus liveserver --no-open --port $qrport $2" 2>&1 | tr -d '\r'
}
free_port; qrport=$REPLY
tab=$'\t' shifttab=$'\e[Z' ctrlc=$'\x03'
raw=$(qrsession "sleep 2.5; print -rn -- '$tab'; sleep 0.8; print -rn -- '$tab'; sleep 0.8; print -rn -- '$shifttab'; sleep 0.8; print -rn -- '$ctrlc'; sleep 1.5")
txt=$(print -r -- $raw | plain)
check_has "QR: the code of the first network when it starts" "$txt" "QR code  http://192.168.178.23:$qrport  for phones and computers in this Wi-Fi"
check_has "QR: how to switch" "$txt" "Scan it with the iPhone's camera · Tab: next network (1/2) · Shift-Tab: back"
check_has "QR: Tab shows the code of the next network" "$txt" "QR code  http://192.168.2.1:$qrport  for devices the Mac shares its internet with"
check_has "QR: and says which one it is" "$txt" "next network (2/2)"
check_eq "QR: start, Tab, Tab, Shift-Tab: four codes drawn" "$(print -r -- $txt | grep -c '^  QR code  ')" 4
up=$'\e[19A\e[J'
check "QR: drawn in place – up over the one that was there, and away with it" eval '[[ $raw == *"$up"* ]]'
check_has "QR: Ctrl-C still stops it" "$txt" "✓ Stopped http://127.0.0.1:$qrport"
free_port; qrport=$REPLY
raw=$(qrsession "sleep 2.5; curl -s -o /dev/null http://127.0.0.1:\$qrport/nope.html; sleep 0.6; print -rn -- '$tab'; sleep 0.8; print -rn -- '$ctrlc'; sleep 1.5")
txt=$(print -r -- $raw | plain)
check_has "QR: a line written in between (a page that is not there)" "$txt" "404 /nope.html"
check_eq "QR: the code of the next network goes below it – two codes" "$(print -r -- $txt | grep -c '^  QR code  ')" 2
check "QR: nothing is drawn over what was written" eval '[[ $raw != *"$up"* ]]'
free_port; qrport=$REPLY
raw=$(qrsession "sleep 2.5; print -rn -- '$ctrlc'; sleep 1.5" --no-qr)
txt=$(print -r -- $raw | plain)
check "QR: --no-qr: none" eval '[[ $txt != *"QR code"* ]]'
check_has "QR: --no-qr: still live" "$txt" "✓ Live – the page reloads when you save."
# a second one for the same folder: the address and the code, without keys
(cd $S && LOTUS_LIVE_IFCONFIG=$fake lotus liveserver --no-open --port $port >| $HOME/live.log 2>&1 &)
up $port
out=$(cd $S && LOTUS_LIVE_IFCONFIG=$fake script -q /dev/null zsh -fc "$LOTUS_ROOT/bin/lotus liveserver --no-open" 2>&1 | plain)
check_has "QR: the second one for a folder shows the code too" "$out" "QR code  http://192.168.178.23:$port"
check "QR: and no Tab it would not hear" eval '[[ $out != *"Tab:"* ]]'
lotus liveserver stop >/dev/null 2>&1
for i in {1..30}; do curl -s -m 1 -o /dev/null $B/ || break; sleep 0.1; done
check "QR: without a terminal there is none (the log of the first run)" eval '[[ $(plain < $HOME/live.log) != *"QR code"* ]]'

# ── it was a plugin before: the old one goes, with its running servers and the list of documents /html made ──
P=$LOTUS_CONF/plugins
mkold() {   # <author>
  zf_mkdir -p $P/liveserver $LOTUS_DATA/plugins/liveserver/running $LOTUS_DATA/plugins/todo
  print -r -- $'name        = liveserver\ntitle       = Live Server\nauthor      = '$1$'\ndescription = old\naccess      = full\ncommand liveserver = liveserver.py' >| $P/liveserver/plugin.conf
  print -r -- 'print old' >| $P/liveserver/liveserver.py
  print -r -- $'5551\n/somewhere\nwifi' >| $LOTUS_DATA/plugins/liveserver/running/5551
  print -r -- $'/somewhere/Word/a.docx\t10\t20' >| $LOTUS_DATA/plugins/liveserver/made.tsv
  print -r -- 'docx|page' >| $LOTUS_DATA/plugins/liveserver/html-last
  print -r -- $'todo\ton\tlimited\tabc\nliveserver\ton\tfull\tdef' >| $LOTUS_CONF/plugins.tsv
}
tty() { tpty zsh -fc "$LOTUS_ROOT/bin/lotus version" 2>&1 | plain }
mkold Somebody
out=$(tty)
check "a plugin of someone else with that name stays" test -e $P/liveserver/plugin.conf
lines=("${(@f)out}")      # an array – one line of output is still a list, not a word to take a letter from
check_eq "  – and Lotus says nothing" "${lines[-1]//[[:space:]]/}" "$LOTUS_VERSION"
check "  – (not a word about a plugin)" eval '[[ $out != *plugin* ]]'
rm -rf $P/liveserver $LOTUS_DATA/plugins
mkold Lotus
out=$(tty)
check "Lotus' own old plugin is gone" test ! -e $P/liveserver
check "  – and its data folder" test ! -e $LOTUS_DATA/plugins/liveserver
check_has "  – it says so" "$out" "Live Server and /html are part of Lotus now – the old liveserver plugin was removed."
check_eq "  – a server that still runs is found by the new Live Server" "$(<$LOTUS_STATE/live/running/5551)" $'5551\n/somewhere\nwifi'
check_has "  – the documents it made are not forgotten" "$(<$LOTUS_STATE/live/made.tsv)" "/somewhere/Word/a.docx"
check_eq "  – nor the last choice of /html" "$(<$LOTUS_STATE/html-last)" "docx|page"
check_eq "  – its entry is gone, the others stay" "$(<$LOTUS_CONF/plugins.tsv)" $'todo\ton\tlimited\tabc'
check "  – other plugins' data stays" test -d $LOTUS_DATA/plugins/todo
out=$(tty)
check "  – and nothing is said the next time" eval '[[ $out != *"part of Lotus now"* ]]'
print -r -- $'5551' >| $LOTUS_STATE/live/running/5551      # a note without a server: cleaned up by stop
check_has "a stale note does not make a live server" "$(lotus liveserver stop 2>&1 | plain)" "No live server is running"
