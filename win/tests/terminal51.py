#!/usr/bin/env python3
"""Lotus in a real console of Windows PowerShell 5.1 - the one a new Windows 11 comes with.

Pester (win/tests) runs the whole test suite inside Windows PowerShell 5.1, but without a console: no colors, no
PSReadLine, no profile, no first-start dialogs. This script types into a real one (a ConPTY, the pseudo console Windows
Terminal draws too), the way a person would on a Windows that just came out of the box:

  window 1   the execution policy is Restricted (the CI job sets it): PowerShell may run no script file. The installer is
             typed in (install.ps1, from this checkout instead of GitHub), answers its questions - Lotus' own fastfetch,
             RemoteSigned for the user - and starts the setup, which is clicked through.
  window 2   a new window: the profile loads Lotus, the start screen comes up in colors (no ESC codes written out), the
             prompt is Lotus', /clock and /settings (the Enter key rewrites them), lotus doctor says 5.1, and unhook.
  window 3   cmd.exe, PowerShell 7 not in its PATH: lotus.cmd starts Windows PowerShell.
  window 4   a new window after unhook: Lotus is gone, the prompt is PowerShell's.

What goes wrong shows on the screen that is printed in the log. Needs pyte and pywinpty (pip install pyte pywinpty).

    python win/tests/terminal51.py
"""
import os
import re
import sys
import time
import traceback

for _stream in (sys.stdout, sys.stderr):         # (Python on Windows prints in the code page of the console: the screens have ✓ and box drawing)
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except (AttributeError, OSError):
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'dev', '3.0', 'video', 'windows'))
import record  # noqa: E402  (the console, the screen and the setup wizard of the video's driver)
from record import Console, Recording, fresh_env, hold  # noqa: E402

if not record.WINDOWS:
    sys.exit('This test needs Windows (a ConPTY and Windows PowerShell 5.1).')

POWERSHELL = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
APP = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'lotus', 'app')
ANSI = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Za-z0-9]')
# what PowerShell prints when a command goes wrong (an error in red), and the sequences when a terminal does not read them
ERRORS = re.compile(r'CategoryInfo|FullyQualifiedErrorId|At line:\d+|At [A-Za-z]:\\[^\n]*:\d+ char:\d+|ParserError|is not recognized as|'
                    r'running scripts is disabled|Exception calling|You cannot call a method|Cannot bind|PSSecurityException|UnauthorizedAccess|'
                    r'It did not work')
WRITTEN_OUT = re.compile(r'\[\d+(;\d+)*m')

rec = Recording(os.environ.get('LOTUS_TERMINAL_CAST', 'terminal51.cast'))
problems = []


def check(ok, what, console=None):
    print(('  ok    ' if ok else '  FAIL  ') + what, flush=True)
    if not ok:
        problems.append(what)
        if console is not None:
            show(console, 'the screen')
    return ok


def show(console, title):
    print(f'---- {title} ' + '-' * (60 - len(title)), flush=True)
    print('\n'.join(line for line in console.lines() if line.strip()), flush=True)
    print('-' * 66, flush=True)


def output_since(index):
    """Everything the console wrote since the event with this index, without its escape sequences."""
    return ANSI.sub('', ''.join(e[2] for e in rec.events[index:] if e[1] == 'o'))


def no_errors(index, what):
    text = output_since(index)
    found = ERRORS.search(text)
    if found:
        line = next((ln for ln in text.splitlines() if found.group(0) in ln), found.group(0))
        check(False, f'{what}: no error in the output - found "{line.strip()[:120]}"')
    else:
        check(True, f'{what}: no error in the output')


def answer(c, question, reply='y', timeout=300):
    """Read-Host asks '? <question> [y/N]: ' - the reply is typed after it."""
    rx = re.compile(re.escape(question) + r'\s*\[y/N\]:\s*$', re.M)
    c.wait_for(lambda: rx.search(c.text()), question, timeout, quiet=0.6)
    hold(0.6)
    c.type(reply, enter=True)


def window_env():
    """The environment of a window opened now. The job that runs this is PowerShell 7 and hands its PSModulePath down - PowerShell
    7's own PSReadLine and Security modules, which Windows PowerShell cannot load - so that one is left out, as on any PC."""
    env = fresh_env()
    for name in [n for n in env if n.upper() in ('PSMODULEPATH', 'POWERSHELL_DISTRIBUTION_CHANNEL', 'PSEXECUTIONPOLICYPREFERENCE')]:
        del env[name]
    return env


def clean_path():
    """PATH without PowerShell 7: lotus.cmd then has only Windows PowerShell to take."""
    env = window_env()
    env['PATH'] = ';'.join(p for p in env['PATH'].split(';') if p and not os.path.exists(os.path.join(p, 'pwsh.exe')))
    return env


# The pages of the setup, by what they say, and what a person does on them (the video's driver knows the pages of the first Lotus for
# Windows; Remove BG added three: its model, its folder, and when to download it). The language and the name are asked first.
PAGES = [
    ('language', r'Welcome to Lotus', 'enter'),
    ('name', r'What should Lotus call you\?', 'name'),
    ('theme', r'Pick a theme', 'enter'),
    ('start', r'Show Lotus when a terminal', 'enter'),
    ('features', r'Which features', 'enter'),
    ('city', r'Your city for /weather', 'city'),
    ('ai', r'AI answers with /ai|The AI terminal', 'enter'),
    ('bg model', r'Auto picks the best one', 'enter'),
    ('bg folder', r'Where the transparent PNGs go', 'enter'),
    ('bg download', r'When should Lotus download the model', 'enter'),
    ('pet', r'Adopt a pet', 'enter'),
    ('pet name', r'What is your (cat|dog) called', 'enter'),
    ('review', r'Lotus is ready', 'enter'),
]


def wizard(c):
    """The setup, page by page, whatever order and whichever pages: each page is answered once, the screen tells which it is."""
    done = []
    while True:
        text = c.text()
        page = next(((n, rx, act) for n, rx, act in PAGES if re.search(rx, text)), None)
        if page is None:
            if done and done[-1] == 'review' and c.at_prompt():
                return done
            c.wait_for(lambda: any(re.search(rx, c.text()) for _, rx, _ in PAGES) or (done and done[-1] == 'review' and c.at_prompt()),
                       'the next page of the setup' + (f' (after: {done[-1]})' if done else ''), 90, quiet=0.8)
            continue
        name, rx, act = page
        hold(0.8)
        if act == 'name':
            c.key(*['bs'] * 14, gap=0.05)
            c.type('Alex')
            hold(0.4)
            c.key('enter')
        elif act == 'city':
            c.type('Paris')
            hold(0.4)
            c.key('enter')
        else:
            c.key('enter')
        done.append(name)
        c.wait_for(lambda: not re.search(rx, c.text()) or c.at_prompt(), f'the setup to leave the page "{name}"', 40, quiet=0.3)
        if name == 'review':
            c.wait_for(c.at_prompt, 'the prompt after the setup', 90, quiet=1.5)
            return done


# ── window 1: the install ────────────────────────────────────────────────────

def install():
    """a fresh Windows PowerShell 5.1: the install line, its questions, the setup"""
    mark = len(rec.events)
    env = window_env()
    env['LOTUS_SRC'] = REPO                       # install.ps1 copies this checkout instead of downloading main
    env['LOTUS_FASTFETCH'] = 'pinned'             # Lotus' own fastfetch (checked against its SHA-256)
    c = Console(rec, [POWERSHELL, '-NoLogo'], env=env)
    c.prompt(90)
    rec.mark('window 1: a Windows PowerShell as it comes with Windows 11')
    c.type('$PSVersionTable.PSVersion.ToString() + " / " + (Get-ExecutionPolicy)', enter=True)
    c.prompt(20)
    check(re.search(r'5\.1\.\d+\S* / Restricted', c.text()) is not None, 'this is Windows PowerShell 5.1 and its policy is Restricted', c)
    c.key('ctrl-l')
    c.type("[string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture + ' | ' + $env:PROCESSOR_ARCHITECTURE + ' | ' + [Environment]::Is64BitProcess + ' | ' + $ExecutionContext.SessionState.LanguageMode", enter=True)
    c.prompt(20)
    show(c, 'the machine (processor by .NET | by the environment | 64-bit process | language mode)')
    before = len(rec.events)
    c.type(f"Import-Module '{os.path.join(REPO, 'win', 'Lotus.psd1')}'", enter=True)
    c.prompt(20)
    blank = re.sub(r'\s+', '', output_since(before))
    check('runningscriptsisdisabled' in blank, 'the premise: a module (a script file) does not load under Restricted', c)
    c.key('ctrl-l')
    c.prompt(10)

    rec.mark('the install line')
    mark = len(rec.events)                        # (the error of the premise above is not one of the install)
    c.paste(f'iex (Get-Content -Raw "{os.path.join(REPO, "install.ps1")}")', enter=True)    # (irm <url> | iex, from this checkout)
    answer(c, 'Download it?')                     # fastfetch
    answer(c, 'Set it now (for your user only)?') # RemoteSigned
    c.wait_for(lambda: 'Welcome to Lotus' in c.text() or c.at_prompt(), 'the setup, or the prompt without it', 240, quiet=2.0)
    if check('Welcome to Lotus' in c.text(), 'the installer starts the setup when it is done', c):
        pages = wizard(c)
        print('  the setup went through: ' + ', '.join(pages), flush=True)
        check('review' in pages and 'name' in pages, 'the setup went through to its end', c)
    text = output_since(mark)
    check('Lotus is in' in text, 'the installer copied Lotus')
    check('ExecutionPolicy RemoteSigned for your user' in text, 'it set RemoteSigned for the user')
    check('Done. Open a new PowerShell window.' in text, 'it said it is done')
    check(os.path.exists(os.path.join(APP, 'win', 'Lotus.psd1')), 'the module is in %LOCALAPPDATA%\\lotus\\app')
    check(os.path.exists(os.path.join(APP, 'vendor', 'fastfetch', 'fastfetch.exe')), "Lotus' own fastfetch is there")
    no_errors(mark, 'the install')
    show(c, 'window 1 after the setup')
    # Lotus asks the console for ANSI sequences before it draws: ENABLE_VIRTUAL_TERMINAL_PROCESSING (4) is in the mode of the output
    c.key('ctrl-l')
    c.paste("& (Get-Module Lotus) { Enable-LotusVirtualTerminal; $g = Get-LotusNative 'kernel32.dll' 'GetStdHandle' ([IntPtr]) @([int]); "
            "$m = Get-LotusNative 'kernel32.dll' 'GetConsoleMode' ([bool]) @([IntPtr], [uint32].MakeByRefType()); "
            "$a = [object[]]@($g.Invoke($null, @(-11)), [uint32]0); [void]$m.Invoke($null, $a); 'VTMODE=' + $a[1] }", enter=True)
    c.wait(r'VTMODE=\d+', 30, quiet=0.8)
    mode = int(re.search(r'VTMODE=(\d+)', c.text()).group(1))
    check(mode & 4 == 4, f'Enable-LotusVirtualTerminal: the console mode of the output has ENABLE_VIRTUAL_TERMINAL_PROCESSING (mode {mode})', c)
    c.type('exit', enter=True)
    time.sleep(1.5)


# ── window 2: a new window ───────────────────────────────────────────────────

def new_window():
    """a new window: the profile loads Lotus - start screen, prompt, /clock, /settings, doctor, unhook"""
    mark = len(rec.events)
    c = Console(rec, [POWERSHELL, '-NoLogo'], env=window_env())
    rec.mark('window 2: the profile loads Lotus')
    c.wait_for(c.at_prompt, 'the start screen and the prompt', 120, quiet=2.0)
    hold(1)
    text = output_since(mark)                     # (the screen holds only the last rows: the start screen is taller)
    show(c, 'the start screen')
    check('Alex' in text, 'the start screen greets by name', c)
    check(not WRITTEN_OUT.search(text), 'no color codes written out as text', c)
    if os.path.exists(os.path.join(APP, 'vendor', 'fastfetch', 'fastfetch.exe')):
        check('Hardware' in text and 'CPU' in text, 'fastfetch drew the system next to the logo', c)
    last = [ln for ln in c.lines() if ln.strip()][-1]
    check(re.match(r'^[\w.-]+@[\w.-]+ \S*>\s*$', last.strip()) is not None, "the prompt is Lotus' (user@computer folder>)", c)
    no_errors(mark, 'the new window')

    # /clock: the Enter key rewrites it to "lotus clock" - then q leaves the full-screen clock
    mark = len(rec.events)
    c.type('/clock', enter=True)
    hold(3)
    check(any('\x1b[?1049h' in e[2] for e in rec.events[mark:] if e[1] == 'o'), '/clock opens the full-screen clock', c)
    c.key('q')
    c.prompt(30)
    check('lotus clock' in c.text(), '/clock became "lotus clock" on the line', c)
    no_errors(mark, '/clock')

    # /settings
    mark = len(rec.events)
    c.key('ctrl-l')
    c.type('/settings', enter=True)
    c.wait(r'Settings', 30, quiet=1.0)
    show(c, '/settings')
    c.key('esc')
    c.prompt(30)
    no_errors(mark, '/settings')

    # lotus doctor
    mark = len(rec.events)
    c.key('ctrl-l')
    c.type('lotus doctor', enter=True)
    c.prompt(120, quiet=1.5)
    shown = output_since(mark)
    show(c, 'lotus doctor')
    check(re.search(r'Windows PowerShell 5\.1', shown) is not None, 'lotus doctor names Windows PowerShell 5.1', c)
    check('✗' not in shown.split('Python')[0], 'lotus doctor has nothing wrong with Windows, PowerShell or the terminal', c)
    no_errors(mark, 'lotus doctor')

    # the policy the installer set stays for this user
    mark = len(rec.events)
    c.key('ctrl-l')
    c.type('Get-ExecutionPolicy -Scope CurrentUser', enter=True)
    c.prompt(20)
    check('RemoteSigned' in c.text(), 'the policy of the user is RemoteSigned', c)

    # unhook takes the profile lines out again (both PowerShells' profiles)
    c.key('ctrl-l')
    c.type('lotus unhook', enter=True)
    c.prompt(30)
    show(c, 'lotus unhook')
    profile = os.path.join(os.path.expanduser('~'), 'Documents', 'WindowsPowerShell', 'profile.ps1')
    check(not os.path.exists(profile) or 'lotus' not in open(profile, encoding='utf-8-sig', errors='replace').read(),
          'the profile has no Lotus lines any more')
    c.type('exit', enter=True)
    time.sleep(1.5)


# ── window 3: cmd.exe ────────────────────────────────────────────────────────

def command_prompt():
    """cmd.exe without PowerShell 7: lotus.cmd takes Windows PowerShell"""
    mark = len(rec.events)
    c = Console(rec, ['cmd.exe'], env=clean_path())
    rec.mark('window 3: cmd.exe, without PowerShell 7')
    c.wait(r'>\s*$', 30)
    c.type('where lotus', enter=True)
    c.wait(r'lotus\.cmd', 30)
    c.type('cls', enter=True)
    hold(1)
    c.type('lotus version', enter=True)
    c.wait(r'\d+\.\d+\.\d+', 60, quiet=1.0)
    hold(1)
    show(c, 'lotus version in cmd.exe')
    check(re.search(r'\d+\.\d+\.\d+', c.text()) is not None, 'lotus.cmd starts Lotus (Windows PowerShell 5.1) and it answers', c)
    c.type('cls', enter=True)
    hold(1)
    before = len(rec.events)
    c.type('lotus doctor', enter=True)
    c.wait_for(lambda: 'Features' in output_since(before) and c.text().rstrip().endswith('>'), 'the end of lotus doctor', 120, quiet=1.5)
    show(c, 'lotus doctor in cmd.exe')
    check('Windows PowerShell 5.1' in output_since(before), 'lotus doctor in cmd.exe runs in Windows PowerShell 5.1', c)
    no_errors(mark, 'cmd.exe')
    c.type('exit', enter=True)
    time.sleep(1)


# ── window 4: after unhook ───────────────────────────────────────────────────

def after_unhook():
    """a new window after unhook: Lotus is gone"""
    mark = len(rec.events)
    c = Console(rec, [POWERSHELL, '-NoLogo'], env=window_env())
    rec.mark('window 4: after unhook')
    c.wait_for(c.at_prompt, 'the prompt', 90, quiet=2.0)
    text = c.text()
    show(c, 'a window after unhook')
    check('Alex' not in text and not re.search(r'[\w.-]+@[\w.-]+ \S*>', text), 'no start screen, and the prompt is PowerShell\'s', c)
    no_errors(mark, 'the window after unhook')
    c.type('exit', enter=True)
    time.sleep(1)


def main():
    for phase in (install, new_window, command_prompt, after_unhook):
        print(f'\n==== {phase.__name__}: {(phase.__doc__ or "").strip()}', flush=True)
        try:
            phase()
        except Exception as e:                     # a phase that gets stuck says where; the next ones still try
            problems.append(f'{phase.__name__}: {type(e).__name__}')
            print(f'  FAIL  {phase.__name__} stopped: {e}', flush=True)
            traceback.print_exc()
    try:
        rec.save()
    except OSError:
        pass
    print('\n==== RESULT: ' + ('every check passed' if not problems else f'{len(problems)} problem(s):'), flush=True)
    for p in problems:
        print('  - ' + p, flush=True)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
