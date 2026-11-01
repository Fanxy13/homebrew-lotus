# Lotus for Windows – preview

A native PowerShell 7 module for Windows 11 and Windows Terminal: no WSL, no Git Bash, no compatibility layer.
**Status: a foundation.** It was written without a Windows machine. The 15 tests in `tests/` pass on PowerShell 7.6.9 on a Mac (the code paths for
non-Windows systems); the Windows paths run for the first time in CI (`.github/workflows/test.yml`, the job "Windows"). Until then nothing
that needs Windows itself is claimed to work.

## What is here

| | |
|---|---|
| `Lotus.psd1`, `Lotus.psm1` | the module: `Import-Module win/Lotus.psd1` gives you the command `lotus` |
| `Private/Paths.ps1` | where the program files and your files are (`%APPDATA%\lotus`, `%LOCALAPPDATA%\lotus`; `LOTUS_CONF`, `LOTUS_CACHE`, `LOTUS_DATA`, `LOTUS_ROOT` override) |
| `Private/Data.ps1` | the files shared with the zsh engine: `data/themes.tsv`, `data/commands.tsv`, the version in `lib/core.zsh` |
| `Private/Settings.ps1` | `settings.zsh`, the same file format on every system |
| `Private/Hook.ps1` | the block in `$PROFILE.CurrentUserAllHosts` (`# >>> lotus >>>` … `# <<< lotus <<<`) |
| `Private/Start.ps1` | the start screen: the logo in the theme's color next to fastfetch's information |
| `../install.ps1` | the installer: copies Lotus to `%LOCALAPPDATA%\\lotus\\app`, offers fastfetch (command first, then a question), writes the profile block |
| `Public/lotus.ps1` | `lotus`, `lotus version`, `doctor`, `themes`, `settings [get\|set]`, `setup --hook`, `unhook`, `uninstall`, `help` |

Every other command says that it is not available on Windows yet and links to the table of what works where. Nothing is faked.

## What is next (see `dev/3.0/PROGRESS.md`)

The setup wizard, settings screen, features, apps and package installs through winget (preview of the command first, then a question),
the AI program for Windows (a static build, pinned by its sha256 like the Linux one), music controls (Windows' media session),
keep awake (`SetThreadExecutionState`), notifications, the image converter, plugins (no sandbox is available to PowerShell: every
plugin would need the approval that a full-access plugin needs on the other systems), the installer (`install.ps1`), and the
packages for winget and Scoop.

## Running the tests

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester -Path win/tests -Output Detailed
```
