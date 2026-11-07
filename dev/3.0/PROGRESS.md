# Lotus 3.0 – progress

The one file to read first when this work is picked up again (after a break, or by another session).
Update it at the end of every step: what was done, what was verified and how, what is left.

- Released as **v3.0.0** on 2026-11-01: commit 51e7a71 on `main` with the tag, then a second commit with the digests of the AI program for Linux
  (`data/vendor.tsv`) and the cask checksum, and the GitHub release (the two AI programs are its assets). Branch `v3` (worktree `~/Code/lotus-v3`) was its base.
- Commits are made as Fanxy13 without a co-author line (the owner's rule). Pushing: `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`.
- What is not in the release is in "Open" below (Windows beyond its first module, `/install` and `/brew` on Linux, Remove BG on Linux …).
- Rule for every status: **tested** means a test ran on that platform and passed; **built** means the code is there
  but no test has run on that platform yet; **planned** means nothing is written. Never write "works" for built.

Documents of this folder

| File | What it is |
|---|---|
| `MATRIX.md` | Every feature, per platform: how it works today, how it will work on Linux and Windows, status |
| `ARCHITECTURE.md` | The design: shared data, the platform layer, shell adapters, the Windows module, the AI, packaging, CI |
| `PROGRESS.md` | This file |

## Test environment (this Mac, Apple silicon, macOS 27)

| What | Where | Notes |
|---|---|---|
| Linux containers | Colima VM (`colima start --cpu 4 --memory 6 --disk 80 --vm-type vz --vz-rosetta`), Docker 28 | `colima stop` / `colima delete` removes it |
| Test images | `tests/docker/{ubuntu,debian,fedora,arch}.Dockerfile` → `lotus-test:<distro>` | Ubuntu 24.04, Debian 12, Fedora 42 (arm64), Arch (amd64 through Rosetta). Chromium is in Debian, Fedora, Arch; Ubuntu ships it only as a snap, so the page checks skip there |
| Run the tests | `tests/docker/run.sh <distro> [test…]`, all files in parallel: `tests/docker/par.sh <distro>` | `LOTUS_TEST_PRIV=1` runs privileged as root (needed for the bubblewrap sandbox tests) |
| AI program for Linux | `tests/docker/swift-static.sh [arm64\|x86_64]` → `tests/docker/.build/lotus-ai-linux-<arch>` | one static file (Swift 6.1 Static Linux SDK, musl, 60 MB, 24 MB gzipped); runs on Debian, Ubuntu, Fedora and Alpine (tested). The tests find it through `LOTUS_PREBUILT_DIR` |
| Compile check only | `tests/docker/swift-build.sh` | errors of the Linux build, nothing else |
| macOS type check | `xcrun swiftc -typecheck -parse-as-library -swift-version 5 lib/ai/*.swift` | must stay clean |
| PowerShell 7.6.9 | the release tarball for macOS arm64, its sha256 compared with the digest GitHub publishes; unpacked into a folder of its own, used only for the Lotus tests, then deleted | run with the owner's yes. Pester 5.9.1 was saved from the PowerShell Gallery into a folder of its own |
| Windows | none here | the PowerShell tests run here on macOS (the code paths for `$IsWindows = $false`); the Windows paths (`%APPDATA%`, winget, Windows Terminal) are tested only by GitHub Actions (`windows-latest`) |
| Logs of local runs | `~/.local/share/lotus-dev/logs/` | |

## Lotus for Windows (branch `claude/vigilant-turing-cngtn7`, 2026-11-06 – 11-07)

The module grew from its foundation into a port of the whole zsh engine that Windows can have. It is in `main` as
bffcfa4 (pull request #13, squashed; no release – the cask stays at 3.2.0, and Windows installs from `main`). The
commits of the pull request: the start screen and shell (57bc059), winget for `/install` and `/brew` (e4f7866), the
pets and `/zetamac` (877e614), `/ai` without the AI program (7e151cf), the installer with `lotus.cmd`, the user PATH and
the pinned fastfetch (ed16f5d), `/convert`, `/img`, `/liveserver` and `/html` (1c5624b), the docs (24ccc99), and an
ImageMagick that works before one that comes first in the PATH (936ef17).

- **Tested**: `.github/workflows/windows.yml` on every push – Pester on Windows x64 (349 passed, 0 failed, 3 skipped:
  the downloads of `/convert`, whose stand-ins cannot run on Windows) and Windows 11 Arm64 (342 passed, 0 failed,
  10 skipped: also the seven conversions of `/img` – that machine has no winget, and its `magick.exe` cannot write
  images), the files Windows PowerShell 5.1 must read, and every winget id of the catalog against the real winget. Locally (Linux, PowerShell
  7.6.9, Pester 5.9.1 from nuget.org): the same suite, and `zsh tests/run.zsh contract pets zetamac wording liveserver html`.
  The zsh engine with the branch's changes to it (the pets' and the wizard's texts without Apple Intelligence, the
  doctor, now playing, liveserver.py and convert.py with their Windows branches): `test.yml`, started by hand on the
  branch at 7a36350 – green on both Macs (Apple silicon: 848 passed, 0 failed), Ubuntu, Debian, Fedora, Arch, Windows
  and the site.
- **Built, not tested on Windows**: the download of `/convert` (tested with stand-ins on Linux), `lotus update`, the media
  keys and the visualizer, opening an app (finding it is tested), anything that needs a real Windows Terminal window
  (how screens look, PSReadLine's Enter key there). Next: try it by hand on a Windows 11 PC.
- **Not on Windows**: the AI terminal and web chat (the Swift program needs a Windows build), MLX, Remove BG, plugins
  (no sandbox for PowerShell), Minecraft, Live Server for the phones in the Wi-Fi, the album cover, `/ios`.
- The statuses are in `data/platform-matrix.tsv` (with the new mark *built*) and `data/platforms.tsv` (Windows: beta).
  `MATRIX.md` below is the plan from 3.0 and its L/W column is not kept up to date.

## Decisions of the owner

1. Running PowerShell here to test the Windows module: **yes** (asked 2026-11-01, "both" local and CI). Done with a verified tarball; deleted afterwards.
2. Pushing the work branch `v3` so that GitHub Actions can test Windows and the Linux distributions: **yes**, as a branch only – no tag, no release, `main` is not touched.
3. Still the owner's: a release (needs the word "push"), and what to do with the unreleased AI design-kit work in the main checkout (based on 2.15.2; it has to be merged on purpose).
4. Not done: relaxing the Colima VM's `kernel.apparmor_restrict_unprivileged_userns` (refused by the safety check). The sandbox tests run in `--privileged -u root` containers instead (`LOTUS_TEST_PRIV=1`).
5. The installer of the released line (`install.sh` on `main`) downloads fastfetch from URLs that now answer 404 (the release
   ships `fastfetch-macos-universal.tar.gz`). The new `install.sh` here fixes it (pinned digests in `data/vendor.tsv`);
   a hotfix of the old line is possible if wanted.
6. Lotus for Windows into `main`: **yes** ("push it", 2026-11-07) – merged as #13 (squashed), without a release. A release
   (version, tag, cask) is still the owner's.

## Phases

| # | Phase | Status | Notes |
|---|---|---|---|
| 1 | Repository audit and compatibility matrix | done | `MATRIX.md` written from the code, not from memory |
| 2 | Cross-platform architecture | done | `ARCHITECTURE.md`; platform layer `lib/platform*.zsh` for macOS and Linux; Windows has its own module (`win/`) |
| 3 | Port the features | in progress | Linux: see "Linux, tested". Windows: the foundation only (below) |
| 4 | Platform extras | in progress | Linux: systemd inhibit, MPRIS, notify-send, XDG trash, desktop detection. Windows: not started |
| 5 | Install and setup | in progress | `install.sh` (macOS, Linux) and `install.ps1` (Windows) are tested end to end; the setup wizard has no shell step yet; `lotus update` on Linux is untested |
| 6 | Website | done for macOS and Linux | systems section with the table of what works where, install tabs per system (the visitor's system first), questions; `scripts/check-site.py`; Windows says "in development" |
| 7 | Tests and CI | running, green | `.github/workflows/test.yml` (macOS arm64 and Intel, four Linux distributions in containers, Windows with Pester, the site check) and `build-ai.yml`; green on commit 2e3b69d (below) |
| 8 | Release docs | drafted | README and CHANGELOG ("Unreleased – Lotus 3.0") say what is tested; release notes are written when there is a release |
| 9 | Video package | done (text) | `dev/3.0/video/`: script, storyboard, commands, recording, editing, YouTube. Nothing recorded |

## CI (GitHub Actions, branch `v3`, pull request 6)

The first run (commit c22087a) was green on the four Linux distributions (Ubuntu, Debian, Fedora, Arch, x86_64, privileged containers), on Windows
(the 15 Pester tests on `windows-latest`, so the Windows paths ran for the first time and passed), for both static builds of the AI program (x86_64 and arm64),
the website check and MeshChat. The two Macs (arm64 and Intel) failed. What the CI found, and what was done:

| Found | Done |
|---|---|
| macOS: `/html` named a home folder that is a link (`/var` → `/private/var`) wrongly | fixed in `lib/cmd/html.zsh`; the two "pre-existing" html failures on my Mac were this |
| macOS: BSD `script` needs a terminal, a CI job has none | the test helper `tpty` uses python's `pty` module on every system (also fixed the `liveserver` check on my Mac) |
| macOS: `liveserver`, `html` (its Live Server part) and `minecraft` start servers and a game and talk to them on 127.0.0.1; on a CI Mac those connections time out | these three files are left out of the CI Mac's run (they run on a real Mac: `zsh tests/run.zsh liveserver html minecraft`); the reason is not found yet |
| Fedora: `llm` failed twice in one run and not in the next (timing under load) | the CI runs two test containers at a time, and `par.sh` prints the failed checks |

Commit 2e3b69d: every job of the workflow "Tests" is green, in the push run and in the pull request run.

## Windows (win/), tested on PowerShell 7.6.9 here

`Lotus.psd1`, `Lotus.psm1`, `Private/{Paths,Data,Settings,Hook,Start}.ps1`, `Public/lotus.ps1`, `install.ps1`. `lotus`, `version`, `doctor`,
`themes`, `settings [get|set]`, `setup --hook`, `unhook`, `uninstall`, `help`, and the start screen (logo in the theme's color next to fastfetch).
Everything else says "not available on Windows yet". 15 Pester tests pass (`Invoke-Pester -Path win/tests`), among them the settings file that
the zsh engine wrote (`win/tests/fixtures/settings.zsh`), read and changed by PowerShell. Not tested: anything that needs Windows itself
(`%APPDATA%` paths, winget, Windows Terminal, the real profile) – CI does that.

## Linux, tested (container runs of this branch; macOS result next to it)

| Test file | Ubuntu 24.04 | Other | macOS |
|---|---|---|---|
| aiserver (web chat, tools, permissions, stats) | 234 pass, 0 fail (page viewer skipped: no Chromium) | Debian 251 / 0 | 253 / 0 |
| autocheck (which commands auto mode runs without asking, 38 cases) | – | Debian 38 / 0 | 38 / 0 |
| art (logos, album cover over MPRIS) | 66 / 0 | | 57 / 0 |
| img (/img convert with ImageMagick) | 23 / 0 | Debian 23 / 0, Fedora 23 / 0 | 25 / 0 |
| minecraft | 163 / 0 | | 166 / 5 (the same 5 fail on untouched 2.23.0 on this Mac) |
| plugin (sandbox needs bubblewrap) | 13 / 0 without a sandbox (plugins are refused), 61 / 0 privileged | | 63 / 0 |
| llm (local model logic with a stand-in server) | 13 / 0 | Debian 16 / 0 | 13 / 0 |
| bash (the adapter in a real pseudo terminal, the lines in the startup files) | 24 / 0 | Debian 24 / 0, Fedora 24 / 0 | 15 / 0 (the system bash is 3.2: the live part is skipped) |
| install (install.sh from start to end: install, again, other login shell, uninstall, no zsh) | 24 / 0 | Debian 24 / 0, Fedora 23 / 0 | 21 / 0 |

### Full runs (2026-11-01, `LOTUS_TEST_PRIV=1 tests/docker/par.sh <distro>`, every test file in a container of its own)

| System | Result | What failed, and what became of it |
|---|---|---|
| macOS (this Mac, Apple silicon) | 1082 pass, 8 fail | the same 8 as on untouched 2.23.0 on this Mac: 2 html (`/private/var` against `HOME`), 1 liveserver (`script` has no pty here), 5 Minecraft (session and `lsof` checks). Environment, not code |
| Ubuntu 24.04 | 1010 pass, 4 fail | 3 convert (the test assumed a user who is not root – fixed), 1 liveserver (the test took the last letter of a one-line answer – fixed) |
| Debian 12 | 1005 pass, 26 fail | 22 plugin: **a real bug** – the sandbox hid `/var/run/dbus` and `/run/dbus` as two folders though `/var/run` is a link to `/run` (fixed, each folder once under its real name); the rest as on Ubuntu |
| Fedora 42 | 1015 pass, 15 fail | html (the image had no fonts and the PDF writer looked in Debian's folders only – fonts are found in any font folder now, the image has them), Minecraft (the image has `gio`, which trashes differently – `LOTUS_TRASH=own` makes the test independent), convert and liveserver as above |
| Arch | 694 pass, 4 fail | the image did not exist before (built now); html (no `cmp` in the image), Minecraft (a log line read a moment too early on an emulated CPU – the test waits), convert, liveserver as above |

After these fixes the affected files were run again: html, convert, Minecraft, plugin, bash and install on Ubuntu, Debian and Fedora and html and Minecraft on Arch pass;
liveserver passes on Debian. A complete second run of all four distributions has not been done – the first CI run is that.

Also found by the matrix: the Lotus-owned yt-dlp (`/convert`) always downloaded the macOS build, also on Linux (it picks the file for the system now);
the texts said "macOS user" on Linux.

## What exists

- `lib/platform.zsh`, `lib/platform/{common,macos,linux,pkg}.zsh`: detection (OS, distro, arch, WSL, desktop, session, package
  manager) and the `lotus_os_*` / `lotus_pkg_*` functions the commands call instead of `osascript`, `open`, `pbcopy`,
  `caffeinate`, `sips`, `security` … A function a system cannot offer returns status 2 and prints nothing; the caller says so.
- `data/packages.tsv`: which package provides which program for brew, apt, dnf, pacman, zypper, apk, winget, scoop.
  `data/vendor.tsv`: pinned downloads with their sha256 (fastfetch; the AI program of a release goes here too).
- `lotus_prebuilt` (lib/core.zsh): a program built elsewhere is downloaded from the release, its sha256 is compared with the
  pin, a wrong file is deleted and never run. `LOTUS_PREBUILT_DIR` is the developer override.
- The AI program (`lib/ai/*.swift`) builds on Linux: `Platform.swift` (host facts, sleep lock, clocks, language guess, clipboard,
  open, secret store, `posix_spawn` helpers), `Stream.swift` (streamed answers without `URLSession.bytes`),
  `PageChromium.swift` (view_page with headless Chromium over the DevTools pipe, no port), `PageSurvey.swift` (the shared
  page survey script). `Shell.run` uses `posix_spawn` on Linux because Foundation waits for background children.
- Permission rules for Linux commands (systemctl, ip, apt, dnf, pacman, flatpak, gsettings, clipboard tools …) and private
  paths (keyrings, `.password-store`, Lotus' own `secrets` folder). Tested with `lotus-ai --classify`.
- Linux installer `install.sh`: POSIX sh, checks the system, offers zsh (command shown first, never silent), pinned fastfetch.
- Plugins: `os`, `requires`, per-OS commands in `plugin.conf`; sandbox with bubblewrap; a limited plugin that cannot be
  sandboxed is refused, never run unprotected.
- Bash adapter (see Open, item 1) and the `LOTUS_SHELLS` setting.
- XDG trash written by Lotus itself when no trash program is installed (Minecraft server delete).

## Open (in the order I would do it)

1. Find why 127.0.0.1 connections of the Live Server and Modrinth tests time out on a GitHub Mac (so that those three files can run there too).
2. `/install` and `/brew` on Linux (apps list per package manager, always preview and confirm); `lotus update` tested on Linux. (`/app` on Linux and the shell question in the setup are done and tested.)
3. Windows: setup wizard, settings screen, features, winget (preview first, then a question), the AI program for Windows (static build pinned by
   sha256), music controls, keep awake (`SetThreadExecutionState`), notifications, image converter, plugins (no sandbox: every plugin needs approval),
   packages for winget and Scoop.
4. Remove BG on Linux (Python environment, CPU/CUDA wheels), editor in the browser instead of AppKit.
5. The wording pass for the Swift program and the AI system prompt (the shell texts say "this computer" off the Mac already); the AI system prompt templated per OS.
6. Native local models on Linux/Windows (llama.cpp or Ollama managed by `lotus ai local`) – today `lotus ai local` says how to use them.
7. The release: version, tag, `data/vendor.tsv` digests of the AI program (second commit), Cask checksum, release notes, and the video.

## Log

### 2026-10-31 – start
- Worktree `~/Code/lotus-v3` on branch `v3` from `origin/main` (2.23.0). The main checkout `~/Code/lotus` is not touched.
- Audit of the code base: ~17k lines of zsh, ~10.5k lines of Swift (AI, converter, editor), ~2.4k lines of Python (Remove BG),
  ~3k lines of the HTML converter, ~1.1k lines of Live Server, ~2.3k lines for Minecraft, 23 test files (900+ checks), 2 workflows.
- macOS-only dependencies are fewer than expected: the zsh code uses zsh built-ins (`zstat`, `strftime`, `zf_mkdir`) instead of
  BSD `stat`/`date`. The real macOS ties are `osascript`, `open`, `pbcopy`/`pbpaste`, `caffeinate`, `sips`, `security`,
  `sandbox-exec`, `sw_vers`/`sysctl`, `java_home`, `xcrun swiftc`, Homebrew, AppKit/WebKit in two Swift files and the
  Apple-only AI backends.
- fastfetch (start screen, hardware, now playing) already runs on all three systems.

### 2026-10-31 – the AI on Linux
- Found: `sips` of macOS 27 rejects `--` ("unknown function"); the repo called it that way in several places (Minecraft icon,
  image fallback). Fixed everywhere; three Minecraft checks that failed on this Mac before now pass.
- Found: on Linux Foundation reports the end of a `Process` only when every program that inherited its pipes closed them,
  so `server &` would block a step for as long as the server lives. `Shell.run` uses `posix_spawn` + `waitpid` there.
- Found: glibc before 2.36 has no `arc4random_uniform` (Ubuntu 22.04); the access token now uses `Int.random` (system generator).
- The static musl build runs on any Linux and needs no Swift runtime. The release workflow has to build it with the same
  script and pin its sha256 in `data/vendor.tsv` (two-commit release, like the Cask checksum).
- Chromium refuses to start its sandbox in containers; `view_page` then refuses too, unless `LOTUS_PAGE_NOSANDBOX=1`
  (set only in the test containers). As root it adds `--no-sandbox` itself.
