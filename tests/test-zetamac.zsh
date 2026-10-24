# The math game of the pets (/zetamac): Zetamac's problems, food for the pets, the best score – and a real game
source $LOTUS_ROOT/lib/core.zsh
lotus_load
zf_mkdir -p $LOTUS_CONF
print -r -- $'Mochi\tcat\t\t'$(( EPOCHSECONDS - 20 * 3600 ))$'\nBello\tdog\t\t'$(( EPOCHSECONDS - 2 * 3600 )) >| $LOTUS_CONF/pets.tsv
source $LOTUS_ROOT/lib/cmd/pets.zsh
lotus_lang_group pets
source $LOTUS_ROOT/lib/cmd/zetamac.zsh
_pet_load; _pet_species

# ── the problems: Zetamac's default ranges, the answer always a whole number ──
typeset -A seen=()
bad=
for i in {1..2000}; do
  _zm_problem normal
  set -- ${=ZM_Q}
  case $2 in
    +) (( $1 >= 2 && $1 <= 100 && $3 >= 2 && $3 <= 100 && ZM_A == $1 + $3 )) ;;
    –) (( ZM_A >= 2 && ZM_A <= 100 && $3 >= 2 && $3 <= 100 && $1 - $3 == ZM_A )) ;;
    ×) (( $1 >= 2 && $1 <= 12 && $3 >= 2 && $3 <= 100 && ZM_A == $1 * $3 )) ;;
    ÷) (( $3 >= 2 && $3 <= 12 && ZM_A >= 2 && ZM_A <= 100 && $1 == $3 * ZM_A )) ;;
    *) false ;;
  esac || { bad="$ZM_Q = $ZM_A"; break }
  seen[$2]=1
done
check_eq "normal: every problem in Zetamac's ranges" "$bad" ""
check_eq "normal: all four kinds" "${#seen}" 4
last=$ZM_Q; _zm_problem normal
check "never the same problem twice in a row" test "$ZM_Q" != "$last"
for i in {1..300}; do _zm_problem easy; (( ZM_A <= 100 )) || { bad=$ZM_Q; break }; done
check_eq "easy: small numbers" "$bad" ""

# ── food: every right answer keeps the pets full longer ──
_pet_status 1
check_eq "a pet that ate 20 hours ago is hungry" "$REPLY" "hungry"
_zm_feed 40 normal
check_eq "40 right: 10 hours for the hungry pet, 10 more for the full one" "$reply" "600 1200"
_pet_status 2
check_eq "the status says how long it stays full" "$REPLY" "full for 20 h"
check_has "saved for the next start" "$(<$LOTUS_STATE/pets.tsv)" $'bello\t'
unset PET_N; _pet_load
_pet_status 2
check_eq "read again: still full" "$REPLY" "full for 20 h"
_zm_feed 1000 normal
check_eq "never fuller than two days" "$reply" "2880 2880"
before=$(<$LOTUS_STATE/pets.tsv)
check "nothing right: nothing to eat" test "$(_zm_feed 0 normal; print $?)" = 1
check_eq "and nothing changed" "$(<$LOTUS_STATE/pets.tsv)" "$before"

# ── the best score per level and time ──
_zm_record normal 120 30; check_eq "the first game: no best yet" "$REPLY" 0
_zm_record normal 120 25; check_eq "the best is kept" "$REPLY" 30
_zm_record normal 60 12;  check_eq "each time has its own best" "$REPLY" 0
check_has "and the games are counted" "$(<$LOTUS_STATE/zetamac.tsv)" $'normal\t120\t30\t2'

# ── the command ──
out=$($LOTUS_ROOT/bin/lotus zetamac 2>&1 < /dev/null)
check_has "without a terminal: it says so" "$out" "needs a terminal"
out=$($LOTUS_ROOT/bin/lotus zetamac 45 extreme 2>&1 < /dev/null)
check_has "an unknown word: named" "$out" "I do not know extreme"
check_has "with how to use it" "$out" "/zetamac [seconds] [easy|normal|hard]"
check_has "a /zetamac shortcut in the shell" "$(<$LOTUS_ROOT/data/commands.tsv)" $'/zetamac\tzetamac\t'

# ── a real game in a terminal: right answers count without Enter, a wrong digit is taken back ──
if command -v python3 >/dev/null; then
  rm -f $LOTUS_STATE/zetamac.tsv
  out=$(python3 - $LOTUS_ROOT $HOME <<'EOF'
import os, pty, re, sys, time, select, fcntl, termios, struct
root, home = sys.argv[1], sys.argv[2]
env = dict(os.environ, HOME=home, LOTUS_ROOT=root, TERM="xterm-256color")
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("zsh", ["zsh", root + "/bin/lotus", "zetamac", "10"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
buf, last, n, start = "", None, 0, time.time()
def pump(t=0.05):
    global buf
    if select.select([fd], [], [], t)[0]:
        try: buf += os.read(fd, 65536).decode("utf-8", "replace")
        except OSError: return False
    return True
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
calc = {"+": lambda a, b: a + b, "–": lambda a, b: a - b, "×": lambda a, b: a * b, "÷": lambda a, b: a // b}
while time.time() - start < 14 and pump():
    text = ansi.sub("", buf[-3000:])
    if "Enter:" in text: break
    m = re.findall(r"(\d+) ([+–×÷]) (\d+) = ", text)
    if not m or m[-1] == last or n >= 5: continue
    ans = str(calc[m[-1][1]](int(m[-1][0]), int(m[-1][2])))
    if n == 0:                       # a wrong first digit, then Backspace
        os.write(fd, b"0"); time.sleep(0.2); os.write(fd, b"\x7f"); time.sleep(0.2)
    if n == 1:                       # the last digit first, then ← and the ones before it
        for i, ch in enumerate(reversed(ans)):
            if i: os.write(fd, b"\x1b[D"); time.sleep(0.08)
            os.write(fd, ch.encode()); time.sleep(0.08)
    elif n == 2 and len(ans) > 1:    # ← and → again: the cursor comes back to the end
        os.write(fd, ans[0].encode()); time.sleep(0.08)
        os.write(fd, b"\x1b[D"); time.sleep(0.08); os.write(fd, b"\x1b[C"); time.sleep(0.08)
        for ch in ans[1:]: os.write(fd, ch.encode()); time.sleep(0.05)
    else:
        for ch in ans: os.write(fd, ch.encode()); time.sleep(0.05)
    last, n = m[-1], n + 1
while time.time() - start < 20 and "Enter:" not in ansi.sub("", buf[-3000:]) and pump(0.2): pass
time.sleep(1.5); pump(0.3)
os.write(fd, b"\x1b")
while pump(0.3) and time.time() - start < 25: pass
_, st = os.waitpid(pid, 0)
print("exit", os.waitstatus_to_exitcode(st))
print(ansi.sub("", buf.split("\x1b[2J")[-2] if buf.count("\x1b[2J") > 1 else buf))
EOF
)
  check_has "a game: five right answers" "$out" "5 right"
  check_has "the pets eat them" "$out" "5 bites"
  check_has "Esc ends it cleanly" "$out" "exit 0"
  check_has "the score is kept" "$(<$LOTUS_STATE/zetamac.tsv 2>/dev/null)" $'normal\t10\t5\t1'
fi
