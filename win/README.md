# Lotus for Windows – beta

A native PowerShell 7 module for Windows 11 (or 10) and Windows Terminal: no WSL, no Git Bash, no compatibility layer,
no administrator rights. It is a port of the zsh engine (`lib/`) and reads the same files: `settings.zsh`, `data/`,
`logos/`, `lib/lang/` and the version, keys and defaults in `lib/core.zsh`.

**Status:** tested on every change on GitHub's Windows machines – Windows x64 and Windows 11 Arm64, PowerShell 7
(`.github/workflows/windows.yml`), about 350 Pester tests, none skipped on x64 but the downloads of `/convert` (on Arm64
also the conversions of `/img`: that machine has no winget and no ImageMagick that works). It has not yet been used by
people in a real Windows Terminal window: what the tests cannot see (how a screen looks, PowerShell's Enter key in a
real window, a real install with winget) is the next thing to try. What works where:
[data/platform-matrix.tsv](../data/platform-matrix.tsv) – *yes* only where a test ran on Windows.

## Install

In PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex
```

It copies Lotus into `%LOCALAPPDATA%\lotus\app`, puts `bin\lotus.cmd` into your user PATH (so `lotus` works in cmd.exe
and the Run dialog too), offers fastfetch – with winget, or the release `data\vendor.tsv` pins, checked against its
SHA-256 – with the command first and a question, and adds a block to your profile (`$PROFILE.CurrentUserAllHosts`) so
that Lotus loads in every PowerShell window. Then the setup starts. `lotus update` runs the installer of the newest
version; `lotus uninstall` takes everything out again (the folder, your PATH entry, the profile block, your settings).
Options for scripts are environment variables – `LOTUS_DEST`, `LOTUS_NO_PATH=1`, `LOTUS_NO_PROFILE=1`,
`LOTUS_FASTFETCH=winget|pinned|no`, `LOTUS_YES=1` (see the top of `install.ps1`).

Your files: settings in `%APPDATA%\lotus`, cache, state and data in `%LOCALAPPDATA%\lotus` (`XDG_*` and the `LOTUS_CONF`,
`LOTUS_CACHE`, `LOTUS_STATE`, `LOTUS_DATA` variables are honored). API keys are kept with DPAPI: only your Windows
account on this PC can read them.

## What is here

Everything of Lotus that Windows can have, with the program that does the work on the other systems:

| | |
|---|---|
| The start screen | the logo painted in the theme's gradient (OKLab, the same as zsh – the contract tests compare all 96 paintings), fastfetch with the same generated config, the greeting in 15 languages, now playing (from Windows' media controls through fastfetch – no album cover yet), the pet of the day |
| The shell | PSReadLine's Enter key turns `/weather Paris` into `lotus weather Paris` – also your shortcuts, pasted links, `open <app>`, a pet's name; the colored prompt; a command that `/help` or `/ai` prepared lands on the next line |
| Setup and settings | the wizard with the blooming lotus, `/settings`, features, themes (and your own), logos, shortcuts, `lotus doctor`, the log viewer, texts in English, German, French and Spanish ("this PC" where the texts say "this Mac") |
| Apps and software | `/app` (the Start menu's apps by name), `/install` (the app catalog: every app with a winget id) and `/brew` (winget search and install – the exact command first, then a question; winget asks its own questions in the open) |
| Pets | adopt, talk (they think with `/ai`), feed, `/zetamac`, `/help` with a pet, reactions, your own kinds from the website's prompt |
| AI | `/ai`: a chat and answers from Claude (`lotus ai login`), Ollama or an OpenAI-compatible API – streamed, with the conversation of the last hour; `explain`, `write`, `summarize`, `command` (suggested, never run). Without tools: it cannot read or change files or run commands on Windows |
| Converters | `/img` with ImageMagick, `/convert` with yt-dlp and ffmpeg (all from winget after a yes), `/html` with Python 3.9+ |
| More | `/liveserver` (this PC only), `/weather`, `/clock` (all six designs), `/caffeine` (SetThreadExecutionState), music and volume (media keys, Core Audio), the visualizer, `/web` and the searches, `/meshchat` (`meshchat.exe`) |
| Remove BG | `/bg remove` (images, folders, the drop zone), `/bg paste`, `/bg models`, the blooming lotus while it works – the Mac's worker (`lib/bg/worker.py`) with PyTorch's Windows build on the processor, in Lotus' own Python environment – or BiRefNet on a graphics card through DirectML: converted once on the PC (`lib/bg/onnxprep.py`), the card found as DirectML finds it (`lib/bg/gpu.py`); built, not yet tried on a real card. HEIC and AVIF through Windows' imaging component. x64 only: OpenCV and torchvision have no build for Windows on Arm. Without the drawing editor |
| Minecraft | `/minecraft`, `/mc <name>`: the setup (Vanilla from Mojang, Paper from PaperMC, Java found or fetched from adoptium.net – each checked against its checksum), the control center with its three pages (the little world, players, ping and TPS from LotusBridge; the icon, the description, plugins from Modrinth; the log and its command line), deleting to the Recycle Bin. The server runs in a hidden PowerShell of its own (`mc/run.ps1`): commands go to it through `.lotus\input`, its console to `.lotus\console.log`, and Windows stays awake while it runs. `start.cmd` runs it in a window of its own |

Not on Windows yet: the AI terminal with its tools and the web chat (the Swift program has no Windows build), a model
that Lotus runs itself, plugins (PowerShell has no sandbox Lotus could use), Remove BG on Windows on Arm (OpenCV and
torchvision have no build there) and its drawing editor, Live Server for the phones in the Wi-Fi, the album cover. The iPhone tools are for
macOS only. These commands say so instead of failing quietly.

## The code

| | |
|---|---|
| `Lotus.psd1`, `Lotus.psm1` | the module; only `lotus` is exported |
| `Private/` | loaded with the module: paths, data, settings, the language files, the log, colors, fuzzy matching, the UI, the platform (Windows API through `DefinePInvokeMethod`, DPAPI, the PATH, Python), the start screen, the profile hook, the shell adapter |
| `Public/` | one file per command group, loaded the first time it is used (`Public/lotus.ps1` is the dispatcher) |
| `mc/run.ps1` | runs a Minecraft server in the background for the control center (`Public/mcc.ps1`) – started hidden, on its own |
| `tests/` | Pester 5: the module, the contract with the zsh engine (`tests/contract/expected`, written by `zsh tests/contract/zsh.zsh`), a lint for PowerShell's traps (a variable in two cases is one variable; a typographic apostrophe ends a string), and each command – against fakes where a real one would cost money or change the computer (a fake AI on 127.0.0.1, a fake yt-dlp) |
| `meshchat/` | MeshChat for Windows (C#), a program of its own |

## Running the tests

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester -Path win/tests -Output Detailed
```

They run anywhere PowerShell 7 does (macOS and Linux too – the Windows parts are skipped there) and touch nothing of
yours: every file gets folders of its own, no keyboard is waited for, the environment comes back afterwards.
