# Lotus 3.0 – cross-platform architecture

Goal: one Lotus on macOS, Linux and Windows, native on each – not a macOS program in a compatibility layer.
Constraint: macOS keeps working exactly as it does today (860+ checks stay green), and every file a user already has
(settings, pets, shortcuts, plugins, AI memory) keeps its format.

## 1. The decision in one picture

```
                         shared by all systems
   data/*.tsv  logos/  data/pets/  data/themes.tsv  data/ai/*.md  lib/lang/*  plugin.conf format
   settings.zsh format  pets.tsv  shortcuts  episodes  ...      (the files are the contract)
   Python helpers: Remove BG worker, Live Server, HTML converter      JavaScript: web chat, website
   Swift: lotus-ai (terminal AI, web chat server, tools)             fastfetch (start screen, hardware, media)
 ───────────────────────────────────────────────────────────────────────────────────────────────────────
   macOS                          Linux                              Windows
   zsh core  (bin/lotus)          zsh core  (the same files)         PowerShell 7 module (win/)
   lib/platform/darwin.zsh        lib/platform/linux.zsh             win/Private/Platform*.ps1
   adapter: init.zsh              adapters: init.zsh, init.bash      adapter: $PROFILE block (PSReadLine)
   Homebrew, cask                 apt dnf pacman zypper flatpak ...  winget, Scoop, Chocolatey
```

Why two engines and not one:

- zsh is native on macOS and on Linux (every distribution packages it). The 17k lines of zsh run on Linux once the
  macOS calls go through a platform layer. A rewrite would risk the Mac for no gain.
- Windows has no zsh. WSL, Git Bash, MSYS and Cygwin are compatibility layers, which the project rules out.
  PowerShell 7 is the native shell there (and runs on all three systems, which lets the Windows code be tested on
  this Mac and in Linux containers).
- A rewrite of the core in a third language (Go, Rust, Python) would replace working code on the system that works best.
  The pieces that must be identical on all systems are therefore **data and helpers, not the shell code**: the files in
  `data/`, the Python and Swift programs, fastfetch. Where the two engines both need the same logic (fuzzy ranking,
  the fastfetch config, pet frames, big clock digits, settings parsing) a **contract test** runs the same cases against
  zsh and PowerShell and compares the output.

Linux and the shell: the core runs in zsh, which the installer adds when it is missing (after asking). The shell the
user types in can be zsh **or bash**: `lib/init.bash` is a thin adapter that calls `bin/lotus` for everything.
fish gets an adapter later if there is demand (a conf.d snippet).

## 2. Directory layout (additions)

```
bin/lotus                      zsh entry (macOS, Linux) – unchanged name and behavior
bin/lotus.ps1, bin/lotus.cmd   Windows entry (shim for the PowerShell module)
lib/platform.zsh               detection, then loads one of:
lib/platform/darwin.zsh        macOS implementations of the lotus_os_* / lotus_pkg_* functions
lib/platform/linux.zsh         Linux implementations
lib/platform/common.zsh        what is the same (validation, version compare, sha256 wrapper)
lib/init.zsh, lib/init.bash    shell adapters
win/Lotus.psd1, Lotus.psm1     the Windows module
win/Private/*.ps1              platform layer, config, ui, themes, render, fuzzy, pets ...
win/Public/*.ps1               one file per command (Invoke-LotusWeather ...)
scripts/make-lang.py           generates lib/lang/*.tsv from the zsh string files (for PowerShell)
install.sh                     POSIX sh bootstrap (macOS, Linux)       install.ps1 (Windows)
packaging/                     PKGBUILD, deb/rpm recipes, Scoop manifest, winget manifest
tests/                         existing zsh tests + tests/contract/ + tests/pester/
dev/3.0/                       these documents
```

## 3. Platform detection (zsh)

`lib/platform.zsh` runs once, early (after the XDG paths in `core.zsh`) and sets:

| Variable | Values |
|---|---|
| `LOTUS_OS` | `macos`, `linux` (never `windows` in zsh) |
| `LOTUS_OS_VERSION` | `sw_vers -productVersion`; on Linux `VERSION_ID` from `/etc/os-release` |
| `LOTUS_DISTRO` | `macos`, or `ID` from `/etc/os-release` (`ubuntu`, `debian`, `fedora`, `arch`, `opensuse-tumbleweed`, `alpine` …) |
| `LOTUS_DISTRO_FAMILY` | `debian`, `rhel`, `arch`, `suse`, `alpine`, `other` (from `ID_LIKE`) |
| `LOTUS_ARCH` | `arm64`, `x86_64` (`uname -m` normalized; on macOS through `hw.optional.arm64`, which is right even under Rosetta) |
| `LOTUS_PKG` | first of `brew` (macOS; also Linuxbrew when it is the only one), `apt`, `dnf`, `pacman`, `zypper`, `apk`; plus `LOTUS_PKG_EXTRA` (`flatpak snap brew`) |
| `LOTUS_DESKTOP` | `aqua`, or `XDG_CURRENT_DESKTOP` lowercased (`gnome`, `kde`, `xfce` …), `none` on a server |
| `LOTUS_SESSION` | `wayland`, `x11`, `tty` (Linux) |
| `LOTUS_WSL` | `1` inside WSL: Lotus then behaves as Linux and says in `doctor` that it runs in WSL (supported as Linux, not as the Windows port) |
| `LOTUS_SHELL` | the interactive shell Lotus is hooked into (`zsh`, `bash`) – set by the adapter |

The same function set is detected in PowerShell by `win/Private/Platform.ps1` (`$IsWindows`, `[Environment]::OSVersion`,
`Get-CimInstance Win32_OperatingSystem`, `$env:PROCESSOR_ARCHITECTURE`, `winget`/`scoop`/`choco` on the `PATH`,
`$env:WT_SESSION`, `$PSVersionTable.PSVersion`).

## 4. The platform layer (the contract)

Every command calls these instead of `osascript`, `open`, `pbcopy`, `caffeinate`, `sips`, `security` … A function that a
system cannot offer returns status 2 ("not supported here") and prints nothing; the caller shows the limit in words.
Nothing is silently skipped.

| Function | macOS | Linux | Windows (PS7 name) |
|---|---|---|---|
| `lotus_os_open <url\|path>` | `open` | `xdg-open`, `gio open`, `sensible-browser` | `Start-Process` (`Open-LotusTarget`) |
| `lotus_os_reveal <file>` | `open -R` | file manager through D-Bus `ShowItems`, else open the folder | `explorer.exe /select,` |
| `lotus_os_open_app <id>` | `open -a` | `gio launch`/`gtk-launch`/`Exec=` of the `.desktop` file | `explorer.exe shell:AppsFolder\<id>` |
| `lotus_os_apps` → name→launch id | `.app` bundles | `.desktop` entries (XDG dirs, Flatpak, Snap) | `Get-StartApps` |
| `lotus_os_clip_copy` (stdin) / `lotus_os_clip_paste` | `pbcopy`/`pbpaste` | `wl-copy`/`wl-paste`, `xclip`, `xsel` | `Set-Clipboard`/`Get-Clipboard` |
| `lotus_os_clip_image <out.png>` | JXA (`clipboard.js`) | `wl-paste -t image/png`, `xclip -t image/png` | `Get-Clipboard -Format Image` |
| `lotus_os_notify <title> <text>` | `osascript` | `notify-send`, `gdbus` | toast |
| `lotus_os_awake <start N\|stop\|status>` | `caffeinate` | `systemd-inhibit`, `gnome-session-inhibit`, `caffeine` | `SetThreadExecutionState` holder process |
| `lotus_os_volume <get\|up\|down\|mute>` | `osascript` | `wpctl`, `pactl`, `amixer` | Core Audio helper |
| `lotus_os_media <play\|pause\|next\|previous\|repeat>` | AppleScript, media keys | `playerctl`, MPRIS over D-Bus | `keybd_event` media keys |
| `lotus_os_secret <get\|set\|del> <service>` | Keychain (`security`) | `secret-tool`, else a `0600` file | Credential Manager / DPAPI file |
| `lotus_os_hw <cpu\|cores\|mem_gb\|gpu\|disk_free>` | `sysctl` | `/proc`, `lscpu`, `nvidia-smi` | CIM |
| `lotus_os_sha256 <file>` | `shasum -a 256` | `sha256sum` | `Get-FileHash` |
| `lotus_os_lan_ip` | `ipconfig getifaddr` | `hostname -I`, `ip route` | `Get-NetIPAddress` |
| `lotus_os_trash <path>` | `trash` / Finder | `gio trash`, `trash-put` | Recycle Bin |
| `lotus_os_proc_cwd <pid>`, `lotus_os_proc_list` | `lsof`, `ps` | `/proc/<pid>/cwd`, `ps` | `Get-CimInstance Win32_Process` |
| `lotus_os_sandbox_run <profile> <cmd…>` | `sandbox-exec` | `bwrap` | none (see §9) |
| `lotus_os_image_engine` | ImageIO helper, `sips` | `magick`, `vips`, `ffmpeg` | `magick`, WIC, `ffmpeg` |
| `lotus_os_java <min-version>` | `java_home` | `JAVA_HOME`, `update-alternatives`, `/usr/lib/jvm` | registry, `JAVA_HOME` |
| `lotus_os_startup <on\|off\|status>` | LaunchAgent | systemd user unit, XDG autostart | Startup folder shortcut |
| `lotus_os_terminal` | `TERM_PROGRAM` | `TERM_PROGRAM`, `VTE_VERSION`, kitty/foot/alacritty vars | `WT_SESSION` |

## 5. Package management behind `/install` and `/brew`

`lotus_pkg_*` hides the package manager. The commands keep their names and cards; only the backend changes.

| Function | What it does |
|---|---|
| `lotus_pkg_backend` | `brew`, `apt`, `dnf`, `pacman`, `zypper`, `apk`, `winget`, `scoop`, `choco`; the order of preference per system |
| `lotus_pkg_search <text>` | rows: `id  kind  version  installed  description  homepage` – parsed from each tool's own output (`apt-cache search`, `dnf search`, `pacman -Ss`, `zypper search`, `winget search`, `scoop search`, `brew search`) |
| `lotus_pkg_info <id>` | the same row for one package |
| `lotus_pkg_installed <id>` | status 0/1 |
| `lotus_pkg_plan <id>` | **the exact command line that would run** (and whether it needs administrator rights). Shown before every install. |
| `lotus_pkg_run <id>` | runs the planned command in the open, after a yes. `sudo` is used only when the plan says so and the user confirmed; Lotus never reads or stores the password and never runs `sudo` in the background |

Rules: names are validated (`lotus_valid_pkg`), nothing is installed without a preview and a yes, no package manager
is forced on anyone, and the catalog (`data/apps.tsv`) gets columns for each system: Homebrew cask, winget id, Flatpak
id and the distribution package names where they differ. Ids are checked against the real repositories before they are
committed (winget-pkgs on GitHub, the Flathub API, the distribution package indexes in the containers).

## 6. Shell adapters

What the adapter provides: the `lotus` command, `/word` triggers, the start screen at shell start, the live now-playing
refresh, the Enter extras (a pasted link opens, `open Spotify` becomes `/app`, an unknown `/word` gets a suggestion, a
pet's name starts a chat), the optional prompt, `unload` after `lotus uninstall`.

- **zsh** (macOS, Linux): `lib/init.zsh`, unchanged. Aliases named `/word`, a ZLE `accept-line` widget, hooks.
- **bash** (Linux, and macOS users who prefer it): `lib/init.bash`. A bash alias name cannot contain `/`, and a command
  with a slash never reaches `command_not_found_handle`. So the adapter wraps Enter in readline: a key sequence bound
  with `bind -x` rewrites `READLINE_LINE` when it starts with `/word` or matches one of the Enter extras, then the
  line is accepted. `PROMPT_COMMAND` and a `DEBUG`-free design are used for the hooks, so other tools that use
  `DEBUG` (direnv, bash-preexec) keep working. Needs bash 4.4 or newer (every supported Linux has it; macOS' system
  bash 3.2 is not supported and says so – macOS users stay on zsh).
- **PowerShell 7** (Windows; works on the other systems too): a profile block that imports the module. `/word` is
  handled by a PSReadLine `Enter` handler that rewrites the line (the same idea as bash) and by
  `$ExecutionContext.InvokeCommand.CommandNotFoundAction` as the fallback for scripts. Windows PowerShell 5.1 is
  not a target of the interactive adapter (it has no `PSReadLine` 2.x features we need on every machine, no ANSI
  by default in older consoles); `lotus` still starts from 5.1 and hands over to `pwsh` when it is installed, or
  offers to install it.
- Setup writes the block into the right file: `~/.zshrc` (`ZDOTDIR` honored), `~/.bashrc`, `~/.config/fish/conf.d`,
  `$PROFILE.CurrentUserAllHosts`. `lotus unhook` removes exactly the block it wrote.

## 7. The Windows module

`win/Lotus.psm1` dot-sources `Private/*.ps1` and `Public/*.ps1`. Rules:

- Native PowerShell 7 only (7.4+ LTS is the floor). .NET types for what PowerShell does not have: console input
  (`[Console]::ReadKey`), ANSI (VT sequences, `$PSStyle`), HTTP (`Invoke-RestMethod`), JSON, hashing, time zones.
- Same screens as zsh (the `ui_*` functions become `Write-LotusHero`, `Read-LotusChoice` …) so that a screenshot of
  `/install` looks the same on all three systems. The look is data: `data/themes.tsv`, `data/bloom.txt`, `logos/`.
- Windows-only calls (registry, CIM, `Get-StartApps`, `SetThreadExecutionState`, Core Audio, toast) live in
  `Private/Platform.Windows.ps1` behind the `lotus_os_*` names above. Everything else is platform-neutral PowerShell, so
  it can be tested under `pwsh` on macOS and Linux; the Windows-only layer is tested by the Windows CI job.
- No `Invoke-Expression` on anything that came from outside. No `-ExecutionPolicy Bypass` baked into shims (the shim
  runs `pwsh -NoProfile -File`, which needs no policy change). Never edits the system `PATH`; uses the user `PATH`
  and says so.
- Console details to respect: Windows Terminal and ConHost with VT enabled (`$PSStyle.OutputRendering`), UTF-8
  output (`[Console]::OutputEncoding`), the cursor-position query (`ESC[6n`) answered through `Console.ReadKey` with a
  timeout, window size from `[Console]::WindowWidth/Height`, Ctrl-C through `[Console]::TreatControlCAsInput`.

## 8. The AI on three systems

One Swift program (`lib/ai/*.swift`), compiled per system:

- **Build.** macOS keeps the on-demand build (`xcrun swiftc`) and may also download a signed, prebuilt binary. Linux and
  Windows users do not have Swift: a CI job builds `lotus-ai` for `linux-x86_64`, `linux-aarch64` (static, `musl`
  Static Linux SDK where it works, else `glibc` on an old base) and `windows-x86_64`, uploads them with checksums to the
  GitHub release, and `lotus ai` downloads the right one after a yes and checks the checksum.
- **Edges.** `#if os(macOS)` / `#if os(Linux)` / `#if os(Windows)` in exactly the places listed in `MATRIX.md` §4: system
  imports, `sysctl`, the sleep assertion, the terminal mode, sockets, secrets, hardware facts. The rest is shared.
- **`view_page`.** WebKit is Apple-only. On the other systems the page is opened with a Chromium-based browser in
  headless mode (Chromium, Chrome, Edge – Edge is on every Windows 11) over the DevTools protocol, with the same survey
  script as today (console messages, overflow, contrast, overlap, clipped text, design counts). When no such browser
  exists the tool says so and the model is told it cannot look.
- **Secrets.** `lotus_os_secret` (above). The browser chat never receives a key: the server adds it to the request.
- **Local models.** `lotus ai local` gets a backend choice: `mlx` (Apple silicon), `llamacpp` (`llama-server`, every
  system, same OpenAI-compatible provider code, GGUF models), or the user's own Ollama. The model catalog gets GGUF rows
  (`gpt-oss-20b` has an official GGUF). The benchmark (`nucifera-20b`) can score a model on any backend.
- **Permissions.** The three levels (allow, ask, never) and the Auto mode stay. The command classifier gets one rule set
  per shell family: POSIX (zsh/bash) and PowerShell/cmd. A command in a shell the rules do not know is always "ask".
- **Prompts.** `data/ai/system.md` says "macOS … zsh … Mac" in places; it becomes placeholders (`{{os}}`, `{{shell}}`,
  `{{machine}}`, `{{pkg}}`) filled per system, so the model never tells a Windows user to run `brew`.

## 9. Plugins and the sandbox

`plugin.conf` gets three optional keys, all backward compatible (a plugin without them behaves as before on macOS):

```
os        = macos linux windows            # where it runs; default: macos
requires  = python3, ffmpeg                # programs it needs; Lotus checks and says what is missing
command x.linux   = x.sh                   # a program for one system; `command x = x.zsh` stays the default
command x.windows = x.ps1
```

A plugin that does not list the current system is listed as "not for this system" and is never started. A plugin that
needs something missing says what and how to install it.

Sandbox for `access = limited`:

- macOS: `sandbox-exec` as today.
- Linux: bubblewrap (`bwrap`) – read-only bind of the plugin folder, writable bind of its data folder, `--unshare-all`
  (network only when `network = yes`), a fresh `/tmp`, no home. When `bwrap` is missing Lotus does not run the plugin
  unprotected: it offers to install `bubblewrap`, or to allow the plugin as `full` (fingerprint approval).
- Windows: PowerShell cannot create an AppContainer or a restricted token by itself. In 3.0 a `limited` plugin is
  therefore shown with a clear notice and needs the same explicit, fingerprint-bound approval as a `full` plugin before
  it runs. A restricted-token launcher (a small compiled helper) is planned; until it exists no document may claim a
  Windows sandbox.

## 10. Installation, update, uninstall

- **macOS:** unchanged (`install.sh`, the Homebrew cask). `install.sh` is rewritten as POSIX `sh` so one file serves
  macOS and Linux (`curl … | sh`); on macOS it still ends in `lotus setup`. The fastfetch fallback download is
  fixed: the release now ships `fastfetch-macos-universal.tar.gz` and the old per-architecture names return 404.
- **Linux:** the bootstrap detects the system, lists what is missing (zsh, curl, git, python3, fastfetch) and offers to
  install it with the system's package manager (the exact command is shown first; `sudo` only after a yes). Without
  root it installs fastfetch from the release tarball into `~/.local/share/lotus/vendor` and tells the user how to get
  zsh. Optional packages (AUR `PKGBUILD`, `.deb`, `.rpm`, a Linuxbrew formula) are built by CI later.
- **Windows:** `install.ps1` (`irm https://…/install.ps1 | iex`): checks PowerShell 7, installs it with winget after a yes
  when missing, downloads Lotus and fastfetch (zip, checksum checked), writes the profile block, runs the setup.
  Optional: a Scoop bucket (a manifest file in this repository), a winget manifest, Chocolatey.
- **Update:** `lotus update` runs the installer path that matches how Lotus was installed (cask, script, package
  manager). **Uninstall:** removes the profile block, files, secrets and caches, as today, and asks first.
- **Existing installs:** `LOTUS_CONFIG_VERSION` migrations stay additive: new settings get defaults, old keys are
  never rewritten. `LOTUS_PET_BRAIN=apple` on a system without Apple Intelligence falls back to the AI provider that is
  set, or to short phrases – the setting itself is left alone.

## 11. Security rules that hold on every system

1. Never run a command from untrusted text; validate URLs and package names before they reach a shell.
2. Show what will run (the exact command line) before any install, update or removal, and ask. Destructive
   operations (uninstall, delete, reset) always ask.
3. No silent `sudo`. No passwords, Apple ID or Windows credentials are read, stored or logged by Lotus.
4. No API key in the repository, the website or the browser. Keys live in the system's secret store; where there is none,
   a `0600` file with a warning.
5. The AI web server binds `127.0.0.1` by default and has the same permission checks as the terminal.
6. Downloaded programs (fastfetch, yt-dlp, llama-server, `lotus-ai`) come from the project's GitHub releases over HTTPS and
   are checked against a published checksum before they are made executable.

## 12. Testing

| Layer | How | Where |
|---|---|---|
| zsh unit/integration tests | `tests/run.zsh` (existing) | macOS, and containers: Ubuntu 24.04, Debian 12, Fedora 42, Arch (amd64) |
| Platform layer | one test file per function group, fake commands on a temporary `PATH` (as `test-convert` does for yt-dlp) | all |
| Contract tests | `tests/contract/cases/*.tsv` run by `tests/contract/run.zsh` and `tests/contract/run.ps1`; the outputs are diffed | macOS, Linux; PowerShell on macOS, Linux, Windows |
| PowerShell module | Pester 5 (`tests/pester/*.Tests.ps1`) | `windows-latest`, and `pwsh` on macOS/Linux |
| Installers | `install.sh` in clean containers (with and without root, with and without zsh); `install.ps1` on the Windows runner | CI |
| Swift AI | `swift build` in `swift:6.1` containers; the AI server tests against `tests/fake-openai.py` | Linux container; macOS; Windows runner |
| Website | link check, command-copy check, headless screenshots | CI, local |

A feature is listed as supported on a system only when its test ran there. The matrix keeps the status words honest.
