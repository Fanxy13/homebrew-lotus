# Lotus for Windows – beta

A native PowerShell module for Windows 11 (or 10) and Windows Terminal: no WSL, no Git Bash, no compatibility layer,
no administrator rights – and nothing to update first: it runs in the **Windows PowerShell 5.1 that Windows 11 comes
with**, and in PowerShell 7. It is a port of the zsh engine (`lib/`) and reads the same files: `settings.zsh`, `data/`,
`logos/`, `lib/lang/` and the version, keys and defaults in `lib/core.zsh`.

**Status:** tested on every change on GitHub's Windows machines (`.github/workflows/windows.yml`): the Pester tests in
PowerShell 7 on Windows x64 and Windows 11 Arm64 and – the whole suite – in Windows PowerShell 5.1 on x64, and a real
console with Windows PowerShell 5.1 (a ConPTY, the pseudo console Windows Terminal draws too) on a Windows whose
execution policy is *Restricted*, like a new Windows 11: the install line is pasted in, its questions are answered, the
setup clicked through, a new window loads Lotus from the profile, and `/clock`, `/settings`, `lotus doctor`, `lotus.cmd`
in cmd.exe and `lotus unhook` are used (`win/tests/terminal51.py`). It has not yet been used by people in their own
Windows Terminal window. What works where: [data/platform-matrix.tsv](../data/platform-matrix.tsv) – *yes* only where
a test ran on Windows.

## Install

In PowerShell – the Windows PowerShell 5.1 of Windows 11 is enough, PowerShell 7 works too:

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

**A new Windows 11 lets Windows PowerShell run no script files** (the execution policy is *Restricted*) – not Lotus'
module, and not the profile that loads it. The line above still works, because it is text typed in, not a file. For its
own work the installer takes a policy for that one window (*Process*, ends with the window); for the profile it shows the
command and asks – `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` (your user only: local scripts
run, downloaded ones need a signature; PowerShell 7 has this by default). With *no*, Lotus is installed, `lotus` works in
cmd.exe, and a new PowerShell window prints PowerShell's own error about the profile until the command above is run. A
policy set by your organization is never changed; the installer says so. The profile block goes into the profile of
Windows PowerShell and, when it is installed, of PowerShell 7 (`lotus unhook` takes it out of both); `lotus.cmd` starts
PowerShell 7 when it is there, else Windows PowerShell.

Your files: settings in `%APPDATA%\lotus`, cache, state and data in `%LOCALAPPDATA%\lotus` (`XDG_*` and the `LOTUS_CONF`,
`LOTUS_CACHE`, `LOTUS_STATE`, `LOTUS_DATA` variables are honored). API keys are kept with DPAPI: only your Windows
account on this PC can read them.

## What is here

Everything of Lotus that Windows can have, with the program that does the work on the other systems:

| | |
|---|---|
| The start screen | the logo painted in the theme's gradient (OKLab, the same as zsh – the contract tests compare all 96 paintings), fastfetch with the same generated config, the greeting in 15 languages, now playing (from Windows' media controls through fastfetch) with the album cover of the song in the logo's place – drawn once when the start screen is shown, no live updates yet, the pet of the day |
| The shell | PSReadLine's Enter key turns `/weather Paris` into `lotus weather Paris` – also your shortcuts, pasted links, `open <app>`, a pet's name; the colored prompt; a command that `/help` or `/ai` prepared lands on the next line |
| Setup and settings | the wizard with the blooming lotus, `/settings`, features, themes (and your own), logos, shortcuts, `lotus doctor`, the log viewer, texts in English, German, French and Spanish ("this PC" where the texts say "this Mac") |
| Apps and software | `/app` (the Start menu's apps by name), `/install` (the app catalog: every app with a winget id) and `/brew` (winget search and install – the exact command first, then a question; winget asks its own questions in the open) |
| Pets | adopt, talk (they think with `/ai`), feed, `/zetamac`, `/help` with a pet, reactions, your own kinds from the website's prompt |
| AI | `/ai`: a chat and answers from Claude (`lotus ai login`), Ollama or an OpenAI-compatible API – streamed, with the conversation of the last hour; `explain`, `write`, `summarize`, `command` (suggested, never run). Without tools: it cannot read or change files or run commands on Windows |
| Images and converters | `/img`: the image editor in your browser – crop, turn, mirror, straighten and convert, like the iPhone's Photos (the Mac's page and server, `lib/edit`, with Python 3.9+ and ImageMagick) – and `/img convert` for images and whole folders; `/convert` with yt-dlp and ffmpeg (ImageMagick, ffmpeg and yt-dlp from winget after a yes), `/html` with Python 3.9+ |
| More | `/liveserver` (this PC only), `/weather`, `/clock` (all six designs), `/caffeine` (SetThreadExecutionState), music and volume (media keys, Core Audio), the visualizer, `/web` and the searches, `/meshchat` (`meshchat.exe`) |
| Remove BG | `/bg remove` (images, folders, the drop zone), `/bg paste`, `/bg models`, the blooming lotus while it works – the Mac's worker (`lib/bg/worker.py`) with PyTorch's Windows build on the processor, in Lotus' own Python environment – or BiRefNet on a graphics card through DirectML: converted once on the PC (`lib/bg/onnxprep.py`), the card found as DirectML finds it (`lib/bg/gpu.py`); built, not yet tried on a real card. HEIC and AVIF through Windows' imaging component. x64 only: OpenCV and torchvision have no build for Windows on Arm. Without the drawing editor |
| Minecraft | `/minecraft`, `/mc <name>`: the setup (Vanilla from Mojang, Paper from PaperMC, Java found or fetched from adoptium.net – each checked against its checksum), the control center with its three pages (the little world, players, ping and TPS from LotusBridge; the icon, the description, plugins from Modrinth; the log and its command line), deleting to the Recycle Bin. The server runs in a hidden PowerShell of its own (`mc/run.ps1`): commands go to it through `.lotus\input`, its console to `.lotus\console.log`, and Windows stays awake while it runs. `start.cmd` runs it in a window of its own |

Not on Windows yet: the AI terminal with its tools and the web chat (the Swift program has no Windows build), a model
that Lotus runs itself, plugins (PowerShell has no sandbox Lotus could use), Remove BG on Windows on Arm (OpenCV and
torchvision have no build there) and its drawing editor, Live Server for the phones in the Wi-Fi, live updates of the start screen (now playing and the cover change only when it is shown again). The iPhone tools are for
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

They run anywhere PowerShell 7 does (macOS and Linux too – the Windows parts are skipped there) and in Windows
PowerShell 5.1, and touch nothing of yours: every file gets folders of its own, no keyboard is waited for, the
environment comes back afterwards. The real console test needs Windows, `pip install pyte pywinpty`, and a Windows
PowerShell whose policy you do not mind changing: `python win/tests/terminal51.py` (it is the CI's job; it installs
Lotus into your user profile).

## Windows PowerShell 5.1 and PowerShell 7

One code base for both – what Windows PowerShell 5.1 (.NET Framework 4.8) lacks is not used, or replaced by something both
have. The rules, kept by the lint test, the job *Windows PowerShell 5.1 reads every script* (parses every file in 5.1)
and the whole Pester suite in 5.1:

- Every script of the module has a **byte order mark** (UTF-8): Windows PowerShell reads a file without one as ANSI, so
  a "–" or a "▶" in a string would become several characters, some of them quotes. `install.ps1` and `bin\lotus.ps1` are
  run with `irm | iex` and by the shims: they are ASCII.
- No `??`, `?:`, `&&`, `||`, `` `e ``, `$IsWindows` (the module sets it for 5.1), `ProcessStartInfo.ArgumentList`
  (`Set-LotusProcessArguments`), `Process.Kill($true)` (`Stop-LotusProcessTree`), `Invoke-WebRequest -SkipHttpErrorCheck`
  and `-NoProxy` (`Get-LotusHttpStatus`, `Get-LotusHttpText`), `Add-Type` with newer C# than 5.
- A program PowerShell calls itself gets its arguments through `ConvertTo-LotusNativeArgs`: Windows PowerShell passes
  `print("x")` to Python without its quotes, and drops an empty argument.
- Time zones: .NET Framework knows only the Windows ids; `zones.tsv` (the CLDR table) says which IANA name is which, for
  `/clock`.
- Windows PowerShell does not turn on ANSI colors for its console the way PowerShell 7 does – `Enable-LotusVirtualTerminal`
  asks for them before Lotus draws.
- A profile is read and written the way both read it: plain ASCII as it is, anything else (a user name with an umlaut is
  in the module's path) as UTF-8 with a byte order mark; an ANSI or UTF-16 profile and its line ends are kept.
- `[RuntimeInformation]::OSArchitecture` was empty in a console of the CI: the installer and `Get-LotusOsArchitecture` take
  the environment's `PROCESSOR_ARCHITECTURE` when .NET says nothing.
- The installer takes a policy of its own for its window (Process, Bypass); Windows PowerShell then reports the policy it
  sets for the user as an error ("Security error.", *overridden by a more specific scope*) although it is set – the
  installer looks at what is set (`Get-ExecutionPolicy -Scope CurrentUser`), not at that error.
- A look at Ollama (127.0.0.1) and the pages the tests fetch go through `HttpWebRequest` (`Get-LotusHttpText`): the
  `-NoProxy` of `Invoke-WebRequest` is PowerShell 7's, and Windows PowerShell looks for a proxy first.
- In the tests Windows PowerShell gets a stand-in for `Out-String` (`TestKit.ps1`): PowerShell 7 leaves the color codes out of
  what a test collects with `6>&1 | Out-String` and does not wrap its lines; Windows PowerShell does neither.
