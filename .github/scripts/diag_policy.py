#!/usr/bin/env python3
"""(temporary) What a console of Windows PowerShell 5.1 does on this machine under the execution policy that is set now."""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'dev', '3.0', 'video', 'windows'))
import record  # noqa: E402
from record import Console, Recording  # noqa: E402

POWERSHELL = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
rec = Recording('diag.cast')
c = Console(rec, [POWERSHELL, '-NoLogo'] + sys.argv[1:], env=record.fresh_env())
time.sleep(10)
for command in [
    "(Get-Item 'HKLM:\\SOFTWARE\\Microsoft\\PowerShell\\1\\ShellIds\\Microsoft.PowerShell').GetValue('ExecutionPolicy')",
    '(Get-Module | ForEach-Object Name) -join " "',
    'Import-Module Microsoft.PowerShell.Security',
    'Get-ExecutionPolicy -List',
    '(Get-Module PSReadLine).Version.ToString()',
    "(Get-Command Get-ExecutionPolicy -ErrorAction SilentlyContinue).Source",
    '$ExecutionContext.SessionState.LanguageMode',
]:
    c.type(command, enter=True)
    time.sleep(3.5)
print('\n'.join(line for line in c.lines() if line.strip()))
c.type('exit', enter=True)
time.sleep(1)
