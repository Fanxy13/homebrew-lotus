#!/usr/bin/env python3
"""The recording for the Lotus for Windows video (README.md next to this file says how it is made).

Every scene runs for real in PowerShell 7: the keys are typed into the console at a person's pace, and Lotus, winget,
Ollama, yt-dlp and ImageMagick answer as they do for anyone. What the terminal receives is written to an asciicast v2
file (one event per piece of output, a marker where each scene begins), and the video is cut from that file. Nothing
is staged and nothing is edited inside a scene: a cut only leaves out time.

On Windows the console is a ConPTY (pywinpty), the pseudo console that Windows Terminal draws too. Elsewhere it is a
pty, to try the script out – the scenes that need Windows are skipped there.

    python record.py out.cast                  every scene, from the install line on (Windows)
    python record.py out.cast clock zetamac    only these, in a Lotus that is set up already

Needs pyte, and pywinpty on Windows.
"""
import codecs
import json
import os
import random
import re
import sys
import threading
import time

import pyte

COLS, ROWS = 110, 32
WINDOWS = os.name == 'nt'
HOME = os.path.expanduser('~')
INSTALL = 'irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex'
# Big Buck Bunny's trailer: (c) Blender Foundation | www.bigbuckbunny.org, CC BY 3.0 – free to save
VIDEO = os.environ.get('LOTUS_VIDEO_LINK', 'https://commons.wikimedia.org/wiki/File:Big_Buck_Bunny_Trailer_400p.ogv')
SITE = os.path.join(HOME, 'Projects', 'bakery')
PHOTOS = os.path.join(HOME, 'Pictures', 'Trip')
KEYS = {'enter': '\r', 'esc': '\x1b', 'up': '\x1b[A', 'down': '\x1b[B', 'right': '\x1b[C', 'left': '\x1b[D',
        'bs': '\x7f', 'space': ' ', 'ctrl-c': '\x03', 'ctrl-l': '\x0c'}
# a rehearsal looks for what goes wrong on Windows; it is never cut into the video
REHEARSAL = os.environ.get('LOTUS_VIDEO_REHEARSAL') == '1'
PROMPT = re.compile(r'^(PS .*>|[\w.-]+@[\w.-]+ .*>)\s*$')
random.seed(7)


def fresh_env():
    """The environment of a window opened now: on Windows, PATH as the registry has it (the machine's, then the user's) –
    so that what an installer just added to it (fastfetch from winget, lotus.cmd) is there, as in a new window on any PC."""
    env = dict(os.environ)
    if WINDOWS:
        import winreg

        def path_of(root, key):
            try:
                with winreg.OpenKey(root, key) as k:
                    return winreg.QueryValueEx(k, 'Path')[0]
            except OSError:
                return ''
        machine = path_of(winreg.HKEY_LOCAL_MACHINE, r'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
        user = path_of(winreg.HKEY_CURRENT_USER, 'Environment')
        env['PATH'] = os.path.expandvars(';'.join(p for p in (machine, user) if p))
    return env


def hold(seconds):
    """Time to read what is on the screen (the cut decides how much of it the video keeps)."""
    time.sleep(seconds)


class Recording:
    """One timeline for the whole video: the output of every console and the markers."""

    def __init__(self, path):
        self.path, self.t0, self.events, self.lock = path, time.monotonic(), [], threading.Lock()

    def now(self):
        return round(time.monotonic() - self.t0, 4)

    def out(self, data):
        with self.lock:
            self.events.append([self.now(), 'o', data])

    def mark(self, label):
        with self.lock:
            self.events.append([self.now(), 'm', label])
        print(f'[{self.now():8.2f}] {label}', flush=True)

    def save(self):
        head = {'version': 2, 'width': COLS, 'height': ROWS, 'timestamp': int(time.time()), 'title': 'Lotus for Windows',
                'env': {'SHELL': 'pwsh', 'TERM': 'xterm-256color'}}
        with self.lock, open(self.path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(json.dumps(head) + '\n')
            for e in self.events:
                f.write(json.dumps(e, ensure_ascii=False) + '\n')


class Console:
    """A PowerShell 7 in a pseudo console of COLS × ROWS: what it shows goes into a screen (to wait for) and into the
    recording."""

    def __init__(self, rec, argv, cwd=HOME, env=None):
        self.rec, self.lock, self.last, self.closed = rec, threading.Lock(), time.monotonic(), False
        self.screen = pyte.Screen(COLS, ROWS)
        self.vt = pyte.Stream(self.screen)
        env = dict(env or os.environ)
        if WINDOWS:
            from winpty import PtyProcess
            self.proc = PtyProcess.spawn(argv, cwd=cwd, env=env, dimensions=(ROWS, COLS))
            self._read = lambda: self.proc.read(65536)
            self._write = self.proc.write
        else:
            import fcntl
            import pty
            import struct
            import subprocess
            import termios
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, 0, 0))
            env.setdefault('TERM', 'xterm-256color')

            def own_terminal():                       # the pty is its terminal, so Ctrl-C interrupts as it should
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
            self.proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, cwd=cwd, env=env,
                                         preexec_fn=own_terminal)
            os.close(slave)
            decode = codecs.getincrementaldecoder('utf-8')('replace').decode
            self._read = lambda: decode(os.read(master, 65536))
            self._write = lambda s: os.write(master, s.encode())
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        while True:
            try:
                data = self._read()
            except (EOFError, OSError):
                break
            if not data:
                if WINDOWS and not self.proc.isalive():
                    break
                continue
            with self.lock:
                self.vt.feed(data)
                self.last = time.monotonic()
                cursor = (self.screen.cursor.y + 1, self.screen.cursor.x + 1)
            self.rec.out(data)
            # .NET asks a Unix terminal where the cursor is; ConPTY answers that itself on Windows
            if not WINDOWS and '\x1b[6n' in data:
                self._write(f'\x1b[{cursor[0]};{cursor[1]}R')
        self.closed = True

    # ── what is on the screen ──
    def lines(self):
        with self.lock:
            return [line.rstrip() for line in self.screen.display]

    def text(self):
        return '\n'.join(self.lines())

    def resting(self):
        with self.lock:
            return time.monotonic() - self.last

    def wait_for(self, test, what, timeout=40, quiet=0.5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if test() and self.resting() >= quiet:
                return
            time.sleep(0.05)
        raise TimeoutError(f'{what} – not on the screen after {timeout} s:\n{self.text()}')

    def wait(self, pattern, timeout=40, quiet=0.5):
        rx = re.compile(pattern, re.M)
        self.wait_for(lambda: rx.search(self.text()), pattern, timeout, quiet)

    def at_prompt(self):
        rows = [line for line in self.lines() if line.strip()]
        return bool(rows) and bool(PROMPT.match(rows[-1].strip()))

    def prompt(self, timeout=60, quiet=0.8):
        self.wait_for(self.at_prompt, 'the prompt', timeout, quiet)

    def selected(self):
        """The chosen line of the list being answered – the lowest one, as earlier answers stay above it: ● (Lotus'
        choices), ❯ (the setup) or › (the settings)."""
        chosen = ''
        for line in self.lines():
            s = line.strip()
            if s[:1] in ('●', '❯', '›') and len(s) > 2:
                chosen = s
        return chosen

    # ── keys ──
    def type(self, text, enter=False):
        for ch in text:
            self._write(ch)
            time.sleep(random.uniform(0.045, 0.105))       # about 13 keys a second
        if enter:
            time.sleep(0.4)
            self._write('\r')

    def key(self, *names, gap=0.35):
        for name in names:
            self._write(KEYS.get(name, name))
            time.sleep(gap)

    def select(self, label, limit=30):
        rx = re.compile(label)
        for _ in range(limit):
            if rx.search(self.selected()):
                time.sleep(0.4)
                return
            self.key('down', gap=0.25)
            time.sleep(0.15)
        raise TimeoutError(f'{label} – not in the list:\n{self.text()}')

    def clear(self):
        """A clean window for the next scene – Ctrl+L, as anyone clears PowerShell."""
        self.key('ctrl-l', gap=0.4)


# ── the scenes ────────────────────────────────────────────────────────────────

def install(rec):
    """Window 1: the install line from the website, then the setup it starts."""
    c = Console(rec, ['pwsh', '-NoLogo'])
    c.prompt(90)
    hold(1.5)
    rec.mark('scene:install')
    c.type(INSTALL, enter=True)
    c.wait(r'Install it now\? \[y/N\]|Welcome to Lotus', 300)   # the exact winget command first, then the question
    if re.search(r'Install it now\? \[y/N\]', c.text()):
        hold(1.5)
        c.type('y', enter=True)
    c.wait_for(lambda: 'Welcome to Lotus' in c.text() or c.at_prompt(), 'the setup', 600, quiet=1.5)
    if 'Welcome to Lotus' not in c.text():
        if not REHEARSAL:
            raise TimeoutError(f'the setup did not start after the install:\n{c.text()}')
        rec.mark('rehearsal:setup-by-hand')           # (a rehearsal, on a Lotus that does not start it by itself yet)
        c.type('lotus setup', enter=True)
        c.wait(r'Welcome to Lotus', 90, quiet=1.5)
    rec.mark('scene:setup')
    hold(2)
    c.key('enter')                                    # English
    c.wait(r'What should Lotus call you\?')
    hold(1.2)
    c.key(*['bs'] * 14, gap=0.06)
    c.type('Alex')
    hold(0.6)
    c.key('enter')
    c.wait(r'Pick a theme')
    hold(1.8)
    c.key('enter')                                    # Matcha
    c.wait(r'Show Lotus when a terminal')
    hold(1.2)
    c.key('enter')
    c.wait(r'Which features')
    hold(2.2)
    c.key('enter')
    c.wait(r'Your city')
    hold(0.8)
    c.type('Paris')
    hold(0.5)
    c.key('enter')
    c.wait(r'The AI')
    hold(1.8)
    c.key('enter')                                    # later – Ollama is found by itself
    c.wait(r'Adopt a pet')
    hold(1.6)
    c.key('enter')                                    # a cat
    c.wait(r'What is your cat called')
    hold(1.2)
    c.key('enter')                                    # Mochi
    c.wait(r'Lotus is ready')
    hold(3)
    c.key('enter')                                    # Finish
    c.prompt(90)
    hold(3)
    c.type('exit', enter=True)
    time.sleep(1.5)


def window(rec):
    """A new PowerShell window: the profile loads Lotus, and the start screen comes up."""
    rec.mark('window')
    c = Console(rec, ['pwsh', '-NoLogo'], env=fresh_env())
    rec.mark('scene:start')
    c.prompt(120, quiet=1.5)
    hold(6)
    return c


def weather(rec, c):
    c.clear()
    rec.mark('scene:weather')
    c.type('/weather', enter=True)
    c.prompt(60)
    hold(4)


def pet(rec, c):
    c.clear()
    rec.mark('scene:pet')
    c.type('mochi', enter=True)
    c.wait(r'You\s+›\s*$')
    hold(1.5)
    c.type('what do you like about this PC?', enter=True)
    you = lambda: [line for line in c.lines() if re.search(r'You\s+›', line)]
    c.wait_for(lambda: len(you()) >= 2 and you()[-1].strip().endswith('›'), 'the answer', 240, quiet=1.5)
    hold(4)
    c.key('enter')                                    # Enter alone ends the chat
    c.prompt(30)
    hold(1)


def ai(rec, c):
    c.clear()
    rec.mark('scene:ai')
    c.type('/ai how do I see which apps start with Windows?', enter=True)
    c.prompt(300, quiet=1.5)
    hold(5)


def ai_command(rec, c):
    c.clear()
    rec.mark('scene:ai-command')
    c.type('/ai command the five biggest files in Downloads', enter=True)
    c.wait(r'Put it on the command line', 300, quiet=1.0)
    hold(2.5)
    c.key('enter')
    c.prompt(30)
    hold(3.5)                                         # it waits on the line – Lotus never runs it
    c.key('esc' if WINDOWS else 'ctrl-c')
    c.prompt(10)


def help_pet(rec, c):
    c.clear()
    rec.mark('scene:help')
    c.type('/help', enter=True)
    c.wait(r'Ask\s+›\s*$')
    hold(1.2)
    c.type('make my photos smaller', enter=True)
    c.wait(r'Press 1', 240, quiet=1.0)
    hold(4)
    c.key('esc')
    c.prompt(20)


def catalog(rec, c):
    c.clear()
    rec.mark('scene:catalog')
    c.type('/install', enter=True)
    c.wait(r'Pick a category', 90)
    hold(1.5)
    c.select(r'Browsers')
    c.key('enter')
    c.wait(r'Brave', 180, quiet=1.0)
    hold(3)
    c.select(r'Brave')
    c.key('enter')
    c.wait(r'Install .*\? \[y/N\]', 90)
    hold(3.5)
    c.key('n')
    c.prompt(20)


def brew(rec, c):
    c.clear()
    rec.mark('scene:brew')
    c.type('/brew ripgrep', enter=True)
    c.wait(r'Show details', 120)
    hold(2)
    c.select(r'(?i)ripgrep')
    c.key('enter')
    c.wait(r'Install .*\? \[y/N\]', 90)
    hold(2.5)
    c.key('y')
    c.prompt(400, quiet=1.5)
    hold(2.5)


def app(rec, c):
    c.clear()
    rec.mark('scene:app')
    c.type('/app notpad', enter=True)                # a typo: the name is found anyway
    c.prompt(40)
    hold(3)


def photos(rec, c):
    c.clear()
    c.type(r'cd ~\Pictures\Trip' if WINDOWS else 'cd ~/Pictures/Trip', enter=True)
    c.prompt(10)
    c.clear()
    rec.mark('scene:img')
    c.type('/img convert .', enter=True)
    c.wait(r'Into which format\?', 60)
    hold(1.5)
    c.select(r'WebP')
    c.key('enter')
    c.wait(r'^\s*Quality')
    hold(1.2)
    c.key('enter')                                    # High – 85
    c.wait(r'^\s*Size')
    hold(1.0)
    c.key('enter')                                    # keep the size
    c.wait(r'File Explorer\? \[Y/n\]', 180)
    hold(3)
    c.key('n')
    c.prompt(10)


def video(rec, c):
    c.clear()
    c.type('cd ~', enter=True)
    c.prompt(10)
    c.clear()
    rec.mark('scene:convert')
    c.type(f'/convert {VIDEO}', enter=True)
    c.wait(r'MP4', 180, quiet=1.0)                    # the first look at the link, then MP3 or MP4
    hold(2.5)
    c.select(r'MP3')
    c.key('enter')
    c.wait(r'File Explorer\? \[Y/n\]', 900)
    hold(3)
    c.key('n')
    c.prompt(10)


def live(rec, c):
    c.clear()
    c.type(r'cd ~\Projects\bakery' if WINDOWS else 'cd ~/Projects/bakery', enter=True)
    c.prompt(10)
    c.clear()
    rec.mark('scene:live')
    c.type('/liveserver', enter=True)
    c.wait(r'Live – the page reloads', 90)
    hold(3)
    with open(os.path.join(SITE, 'style.css'), 'a', encoding='utf-8') as f:   # saving in the editor
        f.write('h1 { letter-spacing: .04em; }\n')
    c.wait(r'style\.css', 30)
    hold(2.5)
    c.key('ctrl-c')
    c.prompt(30)
    hold(1)


def html(rec, c):
    c.clear()
    rec.mark('scene:html')
    c.type('/html', enter=True)
    c.wait(r'What should become a document\?', 60)
    hold(1.5)
    c.select(r'index\.html')
    c.key('enter')
    c.wait(r'Into which format\?')
    hold(1.2)
    c.select(r'PDF')
    c.key('enter')
    c.wait(r'What should it show\?')
    hold(1.2)
    c.select(r'The page')
    c.key('enter')
    c.wait(r'Open it\? \[Y/n\]', 90)
    hold(3)
    c.key('n')
    c.prompt(10)


def caffeine(rec, c):
    c.clear()
    c.type('cd ~', enter=True)
    c.prompt(10)
    c.clear()
    rec.mark('scene:caffeine')
    c.type('/caffeine', enter=True)
    c.wait(r'For how long\?', 30)
    hold(1.5)
    c.select(r'1 h')
    c.key('enter')
    c.prompt(30)
    hold(2.5)
    c.type('/caffeine off', enter=True)
    c.prompt(30)
    hold(2)


def clock(rec, c):
    c.clear()
    rec.mark('scene:clock')
    c.type('/clock', enter=True)
    c.wait(r'q quit', 20)
    hold(3.5)
    for _ in range(3):                                # Retro, Matrix, Analog
        c.key('right', gap=0.1)
        hold(3)
    c.key('q')
    c.prompt(20)


OPS = {'+': lambda a, b: a + b, '–': lambda a, b: a - b, '−': lambda a, b: a - b, '-': lambda a, b: a - b,
       '×': lambda a, b: a * b, '÷': lambda a, b: a // b}


def zetamac(rec, c, answers=9):
    c.clear()
    rec.mark('scene:zetamac')
    c.type('/zetamac', enter=True)
    rx = re.compile(r'│\s+(\d+)\s*([+\-–−×÷])\s*(\d+)\s*=')
    seen = None
    for _ in range(answers):
        c.wait_for(lambda: (m := rx.search(c.text())) and m.group(0) != seen, 'a new problem', 20, quiet=0)
        m = rx.search(c.text())
        seen = m.group(0)
        hold(random.uniform(0.5, 1.1))                # a moment to think
        c.type(str(OPS[m.group(2)](int(m.group(1)), int(m.group(3)))))
    hold(0.8)
    c.key('esc')
    c.wait(r'Game over', 20)
    hold(4)
    c.key('esc')
    c.prompt(20)


def settings(rec, c):
    c.clear()
    rec.mark('scene:settings')
    c.type('/settings', enter=True)
    c.wait(r'Settings', 30)
    hold(1.5)
    c.select(r'^› Theme')
    hold(0.8)
    for k in ('right', 'right', 'right'):            # Sakura, Ocean, Sunset – the screen takes each at once
        c.key(k, gap=0.1)
        hold(1.6)
    for k in ('left', 'left', 'left'):                # back to Matcha
        c.key(k, gap=0.3)
    hold(1.2)
    c.key('down')                                     # the colored prompt
    c.key('right')
    hold(1.5)
    c.key('q')
    c.prompt(20)
    hold(1.5)


def doctor(rec, c):
    c.clear()
    rec.mark('scene:doctor')
    c.type('lotus doctor', enter=True)
    c.prompt(120)
    hold(4)


def finale(rec, c):
    c.clear()
    rec.mark('scene:finale')
    c.type('lotus', enter=True)
    c.prompt(60, quiet=1.5)
    hold(5)


# name → (function, needs Windows)
SCENES = {
    'weather': (weather, False), 'pet': (pet, False), 'ai': (ai, True), 'ai-command': (ai_command, True),
    'help': (help_pet, False), 'catalog': (catalog, True), 'brew': (brew, True), 'app': (app, True),
    'img': (photos, False), 'convert': (video, True), 'live': (live, False), 'html': (html, False),
    'caffeine': (caffeine, True), 'clock': (clock, False), 'zetamac': (zetamac, False),
    'settings': (settings, False), 'doctor': (doctor, False), 'finale': (finale, False),
}


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    out, wanted = argv[0], argv[1:]
    rec = Recording(out)
    failed = None
    try:
        if not wanted:
            if not WINDOWS:
                raise SystemExit('The whole recording starts with the Windows install line – name the scenes to try here.')
            install(rec)
        c = window(rec)
        for name, (scene, needs_windows) in SCENES.items():
            if wanted and name not in wanted:
                continue
            if needs_windows and not WINDOWS:
                print(f'(skipped here: {name} needs Windows)', flush=True)
                continue
            scene(rec, c)
            rec.mark(f'end:{name}')
    except Exception as e:                            # the take is kept up to here, and the reason with it
        failed = e
        rec.mark(f'failed:{type(e).__name__}')
        print(f'FAILED: {e}', file=sys.stderr, flush=True)
    finally:
        rec.save()
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
