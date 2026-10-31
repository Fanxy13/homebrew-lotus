# Lotus 3.0 – progress

The one file to read first when this work is picked up again (after a break, or by another session).
Update it at the end of every step: what was done, what was verified and how, what is left.

- Branch: `v3` (worktree `~/Code/lotus-v3`), based on `origin/main` (Lotus 2.23.0).
- Nothing here is released or pushed. A release needs the owner's explicit "push".
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
| Images pulled | `ubuntu:24.04`, `debian:12`, `fedora:42` (arm64), `archlinux:latest` (amd64, through Rosetta), `swift:6.1-noble` | official Docker Hub images |
| PowerShell 7.6.9 | tarball in `~/.local/share/lotus-dev/` (SHA-256 checked against the release notes) | not extracted: running a downloaded binary was blocked by the safety check – waiting for the owner's decision |
| Windows | none here | only GitHub Actions (`windows-latest`) can test Windows; needs a pushed branch |
| Logs of local runs | `~/.local/share/lotus-dev/logs/` | |

## Phases

| # | Phase | Status | Notes |
|---|---|---|---|
| 1 | Repository audit and compatibility matrix | in progress | `MATRIX.md` written from the code, not from memory |
| 2 | Cross-platform architecture | in progress | `ARCHITECTURE.md`; platform layer for zsh next |
| 3 | Native Windows (PowerShell 7) | planned | needs PowerShell to run tests; Windows-only code needs CI |
| 4 | Native Linux | planned | zsh core + platform layer + bash adapter; testable here in containers |
| 5 | Port features and plugins | planned | |
| 6 | Installation and setup | planned | `install.sh` becomes a universal bootstrap, `install.ps1` for Windows |
| 7 | Website | planned | |
| 8 | Testing and CI | planned | baseline on Ubuntu first (below) |
| 9 | Release docs and video package | planned | |

## Log

### 2026-10-31 – start
- Worktree `~/Code/lotus-v3` on branch `v3` from `origin/main` (2.23.0). The main checkout `~/Code/lotus` is not touched:
  it still holds the unreleased AI design-kit work (uncommitted, based on 2.15.2) and has to be merged on purpose later.
- Audit of the code base: ~17k lines of zsh, ~10.5k lines of Swift (AI, converter, editor), ~2.4k lines of Python (Remove BG),
  ~3k lines of the HTML converter, ~1.1k lines of Live Server, ~2.3k lines for Minecraft, 22 test files (860+ checks), 2 workflows.
- macOS-only dependencies are fewer than expected: the zsh code uses zsh built-ins (`zstat`, `strftime`, `zf_mkdir`) instead of
  BSD `stat`/`date`. The real macOS ties are: `osascript` (audio, clipboard images, dialogs), `open`, `pbcopy`/`pbpaste`,
  `caffeinate`, `sips`, `security` (Keychain), `sandbox-exec`, `sw_vers`/`sysctl`, `java_home`, `xcrun swiftc`, Homebrew,
  AppKit/WebKit in two Swift files and the Apple-only AI backends.
- fastfetch (start screen, hardware, now playing) already runs on all three systems.
