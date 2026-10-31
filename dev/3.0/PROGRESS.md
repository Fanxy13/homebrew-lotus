# Lotus 3.0 – progress

The one file to read first when this work is picked up again (after a break, or by another session).
Update it at the end of every step: what was done, what was verified and how, what is left.

- Branch: `v3` (worktree `~/Code/lotus-v3`), based on `origin/main` (Lotus 2.23.0). Commits so far are "work in progress".
- Nothing here is released, tagged or pushed. A release needs the owner's explicit "push".
- Commits are made as Fanxy13 without a co-author line (the owner's rule).
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
| PowerShell 7.6.9 | tarball in `~/.local/share/lotus-dev/` (SHA-256 checked against the release notes) | **not extracted: running a downloaded binary was blocked by the safety check – the owner decides** |
| Windows | none here | only GitHub Actions (`windows-latest`) can test Windows; needs a pushed branch (the owner decides) |
| Logs of local runs | `~/.local/share/lotus-dev/logs/` | |

## Decisions that are the owner's (blocked, not worked around)

1. Running the downloaded PowerShell binary here (to test the Windows module locally) was refused by the safety check.
2. Relaxing the Colima VM's `kernel.apparmor_restrict_unprivileged_userns` (to run the sandbox tests without `--privileged`) was refused.
   Workaround in use: sandbox tests run in `--privileged -u root` containers (`LOTUS_TEST_PRIV=1`).
3. Pushing a branch so that GitHub Actions can test Windows and the Linux distributions in CI.
4. `~/Code/lotus` (main checkout) holds the unreleased AI design-kit work on top of 2.15.2. It is untouched and has to be merged on purpose.
5. The installer of the released line (`install.sh` on `main`) downloads fastfetch from URLs that now answer 404 (the release
   ships `fastfetch-macos-universal.tar.gz`). The new `install.sh` here fixes it (pinned digests in `data/vendor.tsv`);
   the owner can ask for a hotfix of the old line.

## Phases

| # | Phase | Status | Notes |
|---|---|---|---|
| 1 | Repository audit and compatibility matrix | done | `MATRIX.md` written from the code, not from memory |
| 2 | Cross-platform architecture | done | `ARCHITECTURE.md`; platform layer `lib/platform*.zsh` for macOS and Linux; Windows has its own module (planned) |
| 3 | Port the features | in progress | Linux: everything below under "Linux, tested". Windows: not started (see open) |
| 4 | Platform extras | in progress | Linux: systemd inhibit, MPRIS, notify-send, XDG trash, desktop detection are in. Windows: not started |
| 5 | Install and setup | in progress | new `install.sh` (macOS, Linux) tested in containers; wizard/`lotus setup` not yet adapted for bash; `install.ps1` not started |
| 6 | Website | planned | |
| 7 | Tests and CI | in progress | local container matrix works; GitHub Actions workflow not written yet |
| 8 | Release docs | planned | README, CHANGELOG, docs, release notes for 3.0 |
| 9 | Video package | planned | script, storyboard, commands, B-roll list; nothing invented |

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

Last complete Ubuntu run before the fixes of today: 827 pass, 38 fail. The remaining failures then were art, img, llm,
minecraft, plugin (all fixed above, per file) and one in liveserver ("Lotus says nothing", also failing on the untouched base).
A full run of all four distributions has to be repeated before anything is called finished.

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

1. Bash adapter: **built, not yet covered by a test file.** `lib/init.bash`, `lotus bash-init` (lib/cmd/shell.zsh), hook lines for
   `~/.bashrc` (`lotus_hook`, `LOTUS_SHELLS`). One manual run in a pseudo terminal on Debian showed: the `lotus` function works,
   `/nosuchword abc` is rewritten to `lotus suggest …`, the history keeps the typed line, the prompt gets the theme color.
   Still to do: `tests/test-bash.zsh` (Enter rewriting with a shortcut, pets, links, prefill of `/ai command`), a shell step in the
   setup wizard, the doctor row for `.bashrc`, live now-playing lines in bash (not planned: documented limitation).
2. `/install` and `/brew` on Linux (apps list per package manager, always preview and confirm).
3. `lotus update` and `lotus uninstall` on Linux; installer end-to-end tests in containers.
4. Remove BG on Linux (Python environment, CPU/CUDA wheels), editor in the browser instead of AppKit.
5. The wording pass: "this Mac" → `$LOTUS_THIS` in the remaining shell and Swift texts; the AI system prompt templated per OS.
6. Native local models on Linux/Windows (llama.cpp or Ollama managed by `lotus ai local`) – today `lotus ai local` says how to use Ollama or llama-server.
7. **Windows module** (PowerShell 7): not started. Needs the owner's decisions 1 and 3 for any test.
8. GitHub Actions matrix, packaging (deb/rpm/PKGBUILD/Scoop/winget manifests).
9. Website redesign, docs, README, CHANGELOG, release notes.
10. Video package (text and storyboard only; nothing recorded or invented).

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
