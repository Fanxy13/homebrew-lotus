# Lotus 3.0 – feature compatibility matrix

> What is tested where today: `data/platform-matrix.tsv` (the website's table). This file is the plan of 3.0; its
> **L / W** column is not kept up to date – Lotus for Windows is described in `win/README.md` and `PROGRESS.md`.

Written from the code of Lotus 2.23.0 (grep of every external program and Apple API, then a read of each module),
not from memory. For each feature: how it works on macOS today, how it will work on Linux and on Windows, what the
platforms share, and the status. Statuses use the words of `PROGRESS.md`: **tested**, **built**, **planned**,
or **n/a** (cannot exist on that system – the alternative is named).

Columns: **mac** = today · **Linux** / **Windows** = the plan · **Shared** = what is the same code or data ·
**L / W** = status on Linux / Windows.

Legend of the approaches: *zsh* = the existing zsh code runs there as it is (Linux ships zsh) · *PS7* = a native
PowerShell 7 implementation · *platform layer* = a `lotus_os_*` function with one implementation per system.

## 1. Core

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| Start screen: logo, hardware, session, uptime | zsh + fastfetch, logo art painted by `lib/art.zsh` | zsh, fastfetch for Linux | PS7 port of `lotus_render`/`lotus_build`/`lotus_logo_paint`; fastfetch for Windows | `logos/*.txt`, `data/bloom.txt`, themes, the generated fastfetch JSONC (golden-file test between zsh and PS7) | planned / planned |
| Hardware dashboard (CPU, GPU, RAM, swap, disk) | fastfetch modules | same fastfetch config | same fastfetch config | one config generator per language, identical output | planned / planned |
| Themes and colors (truecolor/256 detection) | `lotus_detect_tc`: `COLORTERM`, `TERM_PROGRAM`, `sw_vers` for Terminal.app | `COLORTERM`, `TERM_PROGRAM`, `VTE_VERSION`, `WT_SESSION`, kitty/alacritty/foot env | Windows Terminal (`WT_SESSION`) and ConHost with VT: truecolor | `data/themes.tsv` | planned / planned |
| Settings file | `~/.config/lotus/settings.zsh`, `KEY='value'` lines | same file | same file format in `%APPDATA%\lotus\settings.zsh` (read and written by PS7) | format | planned / planned |
| Config, cache, data, state folders | `~/.config`, `~/.cache`, `~/.local/share`, `~/.local/state` (XDG names) | same, XDG variables honored | `%APPDATA%\lotus` (config), `%LOCALAPPDATA%\lotus\{cache,data,state}`; XDG variables honored when set | the names inside | planned / planned |
| Setup wizard (welcome, name, language, theme, features) | `lib/cmd/setup.zsh` (922 lines), blooming lotus | zsh, plus a platform step and a dependency step | PS7 port with the same screens | wizard texts in `lib/lang/setup.*.zsh`, `data/lotus-setup.txt`, `data/bloom.txt` | planned / planned |
| Languages (en, de, fr, es) | `lib/lang/*.zsh` (zsh arrays) | zsh | PS7 reads a generated `lang/*.tsv` (made by `scripts/make-lang.py`; the zsh files stay the source) | strings | planned / planned |
| Features on/off | `data/features.tsv`, `LOTUS_FEATURES_OFF` | zsh | PS7 | `data/features.tsv` | planned / planned |
| Command suggestions, fuzzy matching | `lib/fuzzy.zsh` (Levenshtein + scoring), JS twin in `docs/js/fuzzy.js` | zsh | PS7 port, golden test against the zsh results | the score cases | planned / planned |
| Cheatsheet, `/help` | `data/commands.tsv`, pet-guided help | zsh | PS7 | `data/commands.tsv` (rows get an OS column: `all`, `mac`, `linux`, `win`) | planned / planned |
| Shortcuts (`/run`, `shortcut add`) | `open` | platform layer `lotus_os_open` | PS7 `Start-Process` | `~/.config/lotus/shortcuts` format | planned / planned |
| Logging and `lotus log`, `lotus doctor` | `lib/log.zsh`, `lib/cmd/log.zsh`, `lib/cmd/system.zsh` | zsh; doctor checks per OS | PS7; doctor checks per OS | log line format | planned / planned |
| `lotus update` | Homebrew cask reinstall, or `install.sh` | installer path (package-manager paths later) | `install.ps1` path, winget/Scoop later | version lookup on GitHub | planned / planned |
| `lotus uninstall`, `unhook` | removes `~/.zshrc` block, `$HOME/.local/share/lotus`, Keychain items | removes the rc block, files, secrets | removes the profile block, files, Credential Manager items | what is removed | planned / planned |
| Shell integration | `lib/init.zsh`: aliases named `/word`, ZLE `accept-line` widget, `precmd`/`preexec` hooks, `TRAPWINCH` | zsh: same file. bash: new `lib/init.bash` (see ARCHITECTURE: `/word` cannot be a bash alias) | PS7 profile block: PSReadLine Enter handler or `CommandNotFoundAction` | the command table | planned / planned |
| Now playing line, live refresh | fastfetch `media` module, refreshed in the background | fastfetch `media` (MPRIS over D-Bus) | fastfetch `media` (Windows media transport controls) | the cache files | planned / planned |
| Album cover instead of the logo | fastfetch's MediaRemote symbol through Perl `DynaLoader`, `sips` to BMP, `lib/cover.pl` draws | MPRIS `mpris:artUrl` through `playerctl`, then ImageMagick or ffmpeg to BMP, the same `cover.pl` | SMTC thumbnail stream saved by a helper, then ffmpeg/WIC to BMP, the same drawing code in PS7 | the drawing (`cover.pl` logic) | planned / planned |
| Pet greeting under the start screen | `lotus_pet_start` | zsh | PS7 | pets data | planned / planned |
| Locale | forces `en_US.UTF-8` for Lotus' own process when the terminal has none | `C.UTF-8`, else the first UTF-8 locale from `locale -a` | .NET is UTF-16: console output encoding set to UTF-8 | n/a | planned / planned |

## 2. Applications and packages

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| `/app` open an installed app, typos fine | scans `/Applications`, `~/Applications`, `/System/Applications`; `open -a` | XDG desktop entries from `/usr/share/applications`, `~/.local/share/applications`, Flatpak and Snap exports; launch with `gio launch` / `gtk-launch` / `Exec=` | `Get-StartApps` (name and AppUserModelID), launch with `explorer.exe shell:AppsFolder\<id>`; classic `.lnk` in the Start Menu as fallback | `lib/fuzzy.zsh` ranking | planned / planned |
| `/install` catalog by category (78 apps) | `data/apps.tsv`: name, Homebrew cask, categories, `.app`, description | same catalog with new columns: Flatpak id, winget-less ids, distro package names where they differ | same catalog: winget id (verified against the winget-pkgs repository), Scoop name | `data/apps.tsv` v2 (new columns; the website reads the same file) | planned / planned |
| "is it installed?" | cask room + `/Applications/*.app` | `flatpak list`, `dpkg -s` / `rpm -q` / `pacman -Q`, desktop entries | `winget list --id`, Start Menu entry | per-OS function | planned / planned |
| `/brew` search, info, install | Homebrew formulae and casks, JSON from `brew info --json=v2` | unified package interface (`lotus_pkg_*`): apt, dnf, pacman, zypper first; Flatpak and Snap second; Homebrew on Linux when it is there | unified interface: winget first, Scoop and Chocolatey when installed | the cards (`ui_card`), the confirmation, the name validation | planned / planned |
| Installing | `brew install`, output stays visible | the real command is shown first, then run after a yes; `sudo` only when the user confirms, never silently | `winget install --id <id>`; elevation prompts come from Windows | the preview | planned / planned |
| Package-manager bootstrap | offers the official Homebrew installer | nothing to bootstrap (apt/dnf/pacman exist); Flatpak offered when missing | winget ships with Windows 11; offered through the App Installer when missing | | planned / planned |

## 3. Web and utilities

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| `/google`, `/search`, `/web`, URL handling, "paste a link to open it" | `open <url>` | `xdg-open` (or `gio open`, `sensible-browser`) | `Start-Process <url>` | URL validation (`lotus_as_url`), search engines list | planned / planned |
| `/weather` | curl to Open-Meteo, ASCII art | zsh (curl) | PS7 `Invoke-RestMethod` | `data/` art, same API | planned / planned |
| `/clock` (minimal, big, retro, matrix, analog, world) | zsh, `strftime` with `TZ`, `data/dotfont.txt` | zsh | PS7, .NET `TimeZoneInfo` (IANA ids work on Windows with .NET 6+) | `dotfont.txt`, zone list | planned / planned |
| `/liveserver` | Python server with WebSocket reload, LAN address from `ifconfig`/`scutil`/`networksetup` | zsh + Python; LAN address from `hostname -I` / `ip route` in Python's socket code | PS7 start + the same Python (`py` launcher or `python`) | `lib/live/*` | planned / planned |
| `/html` (page or folder to Word, PDF, text) | Python `lotusdoc` (pure Python, bundled) | zsh + Python | PS7 + Python | `lib/html/*` | planned / planned |
| Keep awake `/caffeine` | `caffeinate -d -i -m` | `systemd-inhibit --what=idle:sleep --why=Lotus sleep N`, `caffeine` or `gnome-session-inhibit` as fallbacks | a hidden PS7 process that holds `SetThreadExecutionState(ES_CONTINUOUS \| ES_SYSTEM_REQUIRED \| ES_DISPLAY_REQUIRED)`; `powercfg` untouched | state file `caffeine` (pid, start, end) | planned / planned |
| System notifications | `osascript display notification` (used by the AI web chat) | `notify-send` (libnotify), `gdbus` call as fallback | PowerShell toast through `Windows.UI.Notifications` (Windows PowerShell 5.1 helper) or `BurntToast` when installed | message text | planned / planned |

## 4. AI

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| `/ai` terminal (`lotus-ai`) | Swift, built on first use with `xcrun swiftc` | the same Swift code, built by CI into a release binary (`lotus-ai-linux-x86_64`, `-aarch64`), downloaded by `lotus ai`; a local `swiftc` build when a toolchain exists | the same Swift code, built by CI for Windows (x86_64, arm64 later) | all of `lib/ai/*.swift` with `#if os(...)` at the edges | planned / planned |
| Edges to adapt in the Swift code | `Darwin` (Perf, Server, Stats, Terminal), `IOKit.pwr_mgt` (App: sleep assertion), `AppKit`/`WebKit` (Page: `view_page`), `FoundationModels` (Apple.swift, already behind `canImport`), `sysctlbyname` (Perf), Keychain through `security` | `Glibc`, `FoundationNetworking`, `/proc` and `lscpu`, `systemd-inhibit`, headless Chromium for `view_page` | `WinSDK` (console modes for raw input, Winsock), WMI/registry for hardware, `SetThreadExecutionState`, headless Edge for `view_page` | | planned / planned |
| Terminal raw mode, keys, ANSI | termios | termios (same code, `Glibc`) | `SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_INPUT/PROCESSING` | rendering (`Render.swift`) | planned / planned |
| Providers: Claude, OpenAI-compatible, Ollama | URLSession | URLSession (`FoundationNetworking`) | URLSession (`FoundationNetworking`) | `Providers.swift` | planned / planned |
| API keys | Keychain (`security`) | Secret Service (`secret-tool`) when a keyring runs; else a `0600` file in `~/.config/lotus` with a clear warning | Credential Manager or a DPAPI-protected file (only the same Windows user can read it) | the rule: keys never go to the browser or the website | planned / planned |
| Local model | `mlx_lm.server` (Apple silicon), Nucifera profile | `llama-server` from llama.cpp (OpenAI-compatible, same provider code), GGUF models from Hugging Face; Ollama as the easy path | same, Windows builds of llama.cpp (CPU, Vulkan, CUDA); Ollama | `data/llm-models.tsv` gets GGUF rows | planned / planned |
| Apple Intelligence | FoundationModels | n/a – compiled out | n/a – compiled out | pets and `/ai` fall back to the AI provider that is set, or to short phrases | n/a / n/a |
| Tools (`run_command`, files, web, plan) | zsh | shell is the user's (`bash`/`zsh`) | PowerShell 7 | `Tools.swift` | planned / planned |
| Command classifier (AutoCheck: what may run without asking) | rules for POSIX shell and macOS commands | the same POSIX rules plus Linux admin commands (`systemctl`, `apt`, `mkfs`, `dd` …) | new rule set for PowerShell and cmd (`Remove-Item -Recurse -Force`, `Format-Volume`, `reg delete`, `Invoke-Expression`, `iex`, `Set-ExecutionPolicy`, `net user` …) | the decision levels (allow / ask / never) | planned / planned |
| System prompt | `data/ai/system.md` says "macOS", "zsh", "Mac" | templated: `{{os}}`, `{{shell}}`, `{{machine}}`, package manager | templated | one prompt, placeholders | planned / planned |
| `view_page` (look at a page: console, overflow, contrast, visual bugs) | WKWebView in `Page.swift` with a design survey script | headless Chromium/Chrome (`--headless=new`, DevTools protocol); the same survey script | headless Edge (preinstalled) or Chrome; the same survey script | the survey JavaScript in `Page.swift` | planned / planned |
| AI web server and browser chat | `Server.swift` + `lib/ai/web/*` | same | same | all of it | planned / planned |
| `/ai stats`, `/performance`, benchmark | `Perf.swift`, `Stats.swift` | same, hardware facts from `/proc`, `lscpu` | same, hardware facts from CIM/WMI | report format | planned / planned |
| Prompt improver, plan tool, permissions | `Enhance.swift`, `Tools.swift`, `Auto.swift` | same | same | | planned / planned |

## 5. Media and audio

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| `/np` state | fastfetch `media` (JSON) | fastfetch `media` (MPRIS) | fastfetch `media` (SMTC) | `lotus_np_state` | planned / planned |
| `/play` `/pause` `/skip` `/back` | AppleScript for Spotify and Music, media keys (needs Accessibility) for the rest | `playerctl` (MPRIS); without it a `gdbus`/`busctl` call to `org.mpris.MediaPlayer2.Player` | media keys through `keybd_event` (VK_MEDIA_PLAY_PAUSE, NEXT, PREV), which needs no permission | the messages | planned / planned |
| `/repeat` | AppleScript, Spotify and Music only | MPRIS `LoopStatus` property | n/a for most players – says so; Spotify has no public local control on Windows | | planned / planned |
| `/mute` `/vu` `/vd` | `osascript` volume settings | `wpctl` (PipeWire), `pactl` (PulseAudio), `amixer` (ALSA) – first one found | Core Audio endpoint volume through a small C# type (`Add-Type`) | the volume bar | planned / planned |
| Visualizer (8 modes) | simulated motion that follows play state (macOS gives no audio levels) | same simulation (zsh) | PS7 port | `lib/cmd/visual.zsh` logic | planned / planned |
| `/convert` (YouTube to MP3/MP4) | yt-dlp + ffmpeg, own yt-dlp copy (`yt-dlp_macos`) | yt-dlp + ffmpeg from the package manager; own copy `yt-dlp_linux` / `_linux_aarch64` (checksum checked) | yt-dlp + ffmpeg from winget; own copy `yt-dlp.exe` | the pipeline, progress parsing | planned / planned |
| Blooming progress screen | `lib/bg/progress.zsh` | same | PS7 port | `data/bloom.txt` | planned / planned |

## 6. Image tools

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| `/img convert` | Swift ImageIO program (`lib/img/Convert.swift`), `sips` fallback | engine choice: ImageMagick 7 (`magick`) or libvips, else ffmpeg for PNG/JPEG/WebP/TIFF/BMP; HEIC/AVIF need libheif | ImageMagick (winget) or WIC through .NET; `ffmpeg` fallback | the screens, formats, naming, folder rules, summary | planned / planned |
| `/bg remove` (BiRefNet, InSPyReNet) | Python venv with PyTorch, device MPS or CPU | same venv logic; device CUDA when an NVIDIA GPU and driver are found, else CPU; CPU wheels by default (the PyPI CUDA build is ~2.5 GB) | same; Windows ARM64 has no official PyTorch wheels – says so | `lib/bg/worker.py`, `engines.py`, models | planned / planned |
| `/img` image editor: crop, turn, straighten, convert | a page in the browser (`lib/edit/web`) and its server (`lib/edit/editor.py`); the engine is the converter above (`lib/edit/engine.py`: `ImageIO`) | the same page and server; the engine is ImageMagick (`Magick`) | the same page and server, Python 3.9 and ImageMagick (winget); glue in `win/Public/img.ps1` | the page, the server, the geometry (`geometry.js`), the texts (`strings.json`) | built / soon – `dev/PORTING.md` |
| Draw what to keep (editor) | native AppKit window (`Editor.swift`) | a local web editor (HTML canvas) served on 127.0.0.1 and opened in the browser | same web editor | one editor for both | planned / planned |
| Clipboard images | JXA (`clipboard.js`) | `wl-paste`, `xclip`, `xsel` (image/png) | `Get-Clipboard -Format Image` | the temp-file flow | planned / planned |
| Model management | Hugging Face downloads with progress | same | same | `lib/bg/manage.zsh` | planned / planned |

## 7. Minecraft

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| Java detection | `/usr/libexec/java_home -v N+` | `JAVA_HOME`, `update-alternatives`, `/usr/lib/jvm/*`, SDKMAN; install through the package manager (`openjdk-N-jre-headless`) | registry `HKLM:\SOFTWARE\JavaSoft`, `JAVA_HOME`, Adoptium; install through winget (`EclipseAdoptium.Temurin.N.JRE`) | version rules (Minecraft version to Java version) | planned / planned |
| Server creation (Paper etc.), start script | `start.command` (double-clickable) | `start.sh` | `start.ps1` + `start.cmd` | download logic, `server.properties` | planned / planned |
| Control center: processes, logs, players, ping | `ps`, `lsof -d cwd`, `kill`, `perl setsid` | `ps`, `/proc`, `ss`/`lsof` when present, `setsid` | `Get-CimInstance Win32_Process`, `Get-NetTCPConnection`, `Start-Process -WindowStyle Hidden` | log parsing, query protocol, UI | planned / planned |
| Plugins (Modrinth), LotusBridge | Java plugin + Modrinth API | same | same | `lib/mc/bridge`, `plugins.zsh` logic | planned / planned |
| LAN address for the join hint | `ipconfig getifaddr en0` | `hostname -I`, `ip -4 route get 1.1.1.1` | `Get-NetIPAddress` of the default route | | planned / planned |
| Server icon (64x64 PNG) | `sips` | ImageMagick | ImageMagick/WIC | | planned / planned |
| Keep awake while it runs | `caffeinate -i -w <pid>` | `systemd-inhibit` on the pid | `SetThreadExecutionState` helper | | planned / planned |
| Port forwarding guidance | text | text (router steps, `ufw`/`firewalld` hints) | text (Windows Defender Firewall hint) | the text | planned / planned |
| Delete a server (safe) | moves to Trash | `gio trash` / `trash-put`, else asks | Recycle Bin through `Microsoft.VisualBasic.FileIO` | the safety rules | planned / planned |

## 8. Pets

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| Adopt, rename, personality, feeding, hunger, greetings | `lib/cmd/pets.zsh` (1186 lines) | zsh | PS7 port | `data/pets/*.pet`, `~/.config/lotus/pets.tsv`, `~/.local/state/lotus/pets.tsv` | planned / planned |
| Animations, speech bubbles, blocks | ANSI cursor control | same | same (VT sequences) | frames | planned / planned |
| Conversations | Apple Intelligence (default), or the AI of `/ai` | the AI of `/ai` (default `ai` instead of `apple`), or short phrases | same as Linux | the prompt builder | planned / planned |
| Custom pets (`lotus pets add`, `.pet` files) | clipboard through `pbpaste` | `lotus_os_clip_paste` | `Get-Clipboard` | `.pet` format | planned / planned |
| Zetamac | zsh game loop | zsh | PS7 port, arrow keys and all | rules, food values, best-score file | planned / planned |

## 9. Plugins

| Feature | mac (today) | Linux | Windows | Shared | L / W |
|---|---|---|---|---|---|
| Install, remove, on/off, pack, update | `lib/cmd/plugin.zsh` (1215 lines) | zsh | PS7 port | `plugin.conf`, `plugins.tsv`, `pack.conf` | planned / planned |
| Supported systems and dependencies | none | `os = macos linux windows`, `requires = …` in `plugin.conf`; an incompatible plugin is refused with a message, never run | same | the new keys | planned / planned |
| One program for each system | `command x = x.zsh` | `command x.linux = x.sh`, falls back to `x` | `command x.windows = x.ps1` | | planned / planned |
| Sandbox for `access = limited` | `sandbox-exec` (Seatbelt profile) | bubblewrap (`bwrap`): own folder read-only, data folder writable, no network unless `network = yes`, new PID/IPC namespaces; when `bwrap` is missing, "limited" plugins are offered as "full" only – never run unprotected without saying so | none available to PowerShell. 3.0 behavior: limited plugins run only after the same fingerprint approval as `full`, and say so; a restricted-token launcher is a later step | the permission model, the fingerprint approval | planned / planned |
| Plugin tools for the AI | `tool` entries in `plugin.conf` | same | same | | planned / planned |
| Plugin templates | `lotus plugin new` writes `.zsh` | `.sh`/`.zsh` | `.ps1` | | planned / planned |
| Example plugins | hello, todo, github, meshchat | hello, todo, github; MeshChat is macOS only (CoreBluetooth) and declares `os = macos` | hello, todo, github | | planned / planned |

## 10. Installation, setup, packaging

| Feature | mac (today) | Linux | Windows | L / W |
|---|---|---|---|---|
| Installer | `install.sh` (zsh) and a Homebrew cask | `install.sh` becomes a POSIX `sh` bootstrap that detects the system and hands over; installs zsh/curl/git/python3 only after a yes | `install.ps1` (`irm … \| iex`) | planned / planned |
| Package-manager distribution | Homebrew cask (exists) | AUR `PKGBUILD`, `.deb` and `.rpm` (built by CI), Homebrew formula for Linuxbrew; all optional | Scoop bucket (a JSON manifest in this repository), winget manifest (a pull request to winget-pkgs), Chocolatey later | planned / planned |
| fastfetch | brew or release tarball | package manager or release tarball (`fastfetch-linux-amd64`, `-aarch64`) | release zip (`fastfetch-windows-amd64`) | planned / planned |
| Shell hook | `~/.zshrc` block | `~/.zshrc` or `~/.bashrc` block (and `~/.config/fish/conf.d/lotus.fish` if fish is the shell and the adapter exists) | `$PROFILE` block (`CurrentUserAllHosts`) | planned / planned |
| First launch | wizard | wizard with platform detection | wizard with platform detection | planned / planned |
| Upgrade from an existing macOS install | n/a | n/a | n/a – settings, pets, plugins, shortcuts keep their format; `LOTUS_CONFIG_VERSION` migrations stay additive | planned |

## 11. Website and docs

| Item | State today | 3.0 |
|---|---|---|
| Pages | `docs/*.html` (home, docs, commands, apps, themes, pets, plugins, minecraft, shortcuts, studio, ascii, ios), vanilla HTML/CSS/JS, deployed by `pages.yml` | redesign of the home page and the docs: OS selector, three install paths, platform badges per command and per app, FAQ, release page |
| Data | `data/*.tsv` copied into the site at deploy | same; the commands and apps pages show which system each row works on |
| Rules | no emoji on the website | kept |

## 12. Tests and CI

| Item | Today | 3.0 |
|---|---|---|
| Tests | 22 files, 860+ checks, zsh (`tests/run.zsh`), a fake OpenAI server and a fake Modrinth server | the same suite on Linux (containers) and macOS; Pester tests for the PS7 module; contract tests that run the same cases against zsh and PS7 |
| CI | `pages.yml` (website), `meshchat.yml` (macOS) | matrix: macOS (arm64, Intel), Ubuntu, Debian, Fedora, Arch (containers on `ubuntu-latest`), Windows (`windows-latest`, PowerShell 7); Swift builds for the AI on all three |
