# Storyboard

All terminal scenes: 120 x 30, Matcha theme, JetBrains Mono 16 pt, recorded at 1920 x 1080 or higher, 60 fps if the machine keeps it.
"Mac" = a real Mac. "Linux" = Ubuntu 24.04 on real hardware or a VM, GNOME Terminal or the terminal you ship the screenshots from.

| # | Time | Picture | On-screen text | Typed | Where |
|---|---|---|---|---|---|
| 1 | 0:00 | An empty terminal, cursor blinking. Slow push-in on the cursor | none | none | Mac |
| 2 | 0:12 | Black. The Lotus mark draws itself, the word "lotus" fades in | "Lotus 3.0" · "Your terminal, reimagined." | none | motion graphic (SVG from `docs/js/lotus.js`, MARK) |
| 3 | 0:22 | A new window opens; the start screen appears; a pause; `/clock` opens a clock and closes; `/weather` shows the forecast | "the start screen" · "/clock" · "/weather" | `lotus`, `/clock`, `/weather Amsterdam` | Mac |
| 4 | 1:00 | The install line typed, the setup wizard (name, language, theme, review), then the start screen | "macOS 11 or newer" | the install line for macOS (`commands.md`) | Mac, a fresh user account |
| 5 | 1:30 | The Linux install: the line, the question about zsh with its command, the setup, the start screen | "Linux · no administrator rights" · "zsh: asked first" | the install line for Linux | Linux, a fresh user |
| 6 | 2:15 | Split screen: the same command on both; then the website table scrolling slowly | "The same commands" · "Tested = Yes" | `lotus doctor` on both | Mac + Linux; the table from the site |
| 7 | 2:50 | `/ai`: a question that needs a file read; the permission prompt; the answer. Then `/permissions` | "ask first" · "auto: asks when unsure" | `/ai`, then a question of your own, then `/permissions` | Mac or Linux, with Ollama or a Claude key |
| 8 | 3:40 | `/img convert` on a folder of photos, the bloom screen, the result | "originals are never changed" | `/img convert ~/Pictures/trip --to webp --max 1920` | Mac, then Linux |
| 9 | 4:10 | `/pets`, a pet on the start screen, `/zetamac` for a round | "feed your pet" | `/pets`, `/zetamac` | Mac |
| 10 | 4:40 | `/plugin`, the install question that shows what a plugin may do; on Linux the refusal text when bubblewrap is missing (record it for real, in a container or VM without it) | "limited = sandbox" · "no sandbox: refused" | `/plugin install plugins/todo`, `/todo add milk` | Mac, Linux |
| 11 | 5:10 | The test run: `tests/docker/par.sh` output scrolling, four distributions, the totals line | "Ubuntu · Debian · Fedora · Arch" | `LOTUS_TEST_PRIV=1 tests/docker/par.sh ubuntu` (and the others) | Mac with Docker |
| 12 | 5:40 | Text card only. No recording | "Windows 11 · PowerShell 7 · in development" | none | motion graphic |
| 13 | 5:50 | The install line large, the GitHub link, the lotus closing | the repository address from `data/project.tsv` | none | motion graphic |

When Windows ships (not now): add after 11 a scene "Windows 11, Windows Terminal, PowerShell 7": the install line (winget or Scoop as released),
the start screen, `lotus doctor`; and change scene 12 to the release notes. Only record what the release's table marks as "Yes" on Windows.
