# 🪷 lotus

A beautiful start screen for the macOS terminal: a logo, system info in neat boxes,
hello in 15 languages – and the song you're playing, **live**.

**[→ See it in action](https://fanxy13.github.io/homebrew-lotus/)**

```
                       .                     Bonjour, Gabriel
                      .#.
                     .###.                   ┌──────────────── Hardware ────────────────┐
                    .#####.                  ├─ CPU       Apple M5 (10C / 10T) @ 4.46 GHz
           .        +#####+        .         ├─ RAM       15.26 GiB / 24.00 GiB [■■■■■■····] 63%
           #=.      *#####*      .=#         └──────────────────────────────────────────┘
          …                                   …
                                             ♫ Habiba — Boef
                                               [■■■■■■■■··] 02:48 / 03:35  ▶ playing
```

## Install

**One line:**

```bash
curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh
```

**Or with Homebrew:**

```bash
brew install Fanxy13/lotus/lotus && lotus setup
```

Then open a new terminal window.

## Commands

| Command | What it does |
|---|---|
| `lotus` | Show the start screen again (e.g. after `clear`) |
| `/settings` | Open the settings (same as `lotus settings`) |
| `lotus doctor` | Check the installation |
| `lotus update` | Update to the latest version |
| `lotus uninstall` | Remove lotus completely |

## Settings

`/settings` opens a menu (↑↓ select, ←→ or ⏎ change, `v` preview, `q` done):

- Name, interface language (English, Deutsch, Français, Español)
- Logo (lotus, heart, none) and 5 themes (Matcha, Sakura, Ocean, Sunset, Mono)
- Greeting on top: 15 languages in order or at random
- Greeting at the bottom by time of day: French, German, English or Spanish
- Sections on/off: hardware, session, uptime & date, now playing
- Live updates and interval, colored prompt, hide the “Last login” line
- **Uninstall lotus** – removes everything, also from the open shell

Settings live in `~/.config/lotus/settings.zsh`.

## Now playing

Shows whatever macOS knows as “Now Playing” – Spotify, Apple Music, YouTube in
the browser and more. The lines update live while the start screen is visible.
Once the terminal scrolls or is cleared they stop – `lotus` brings them back.

## Lightweight

- Startup: about 30–40 ms (one fastfetch run, the song is fetched in parallel)
- Live updates: one short query every 2 s (≈ 20 ms CPU), every 5 s when paused.
  Several terminal windows share the result.
- Only active while the start screen is visible.

## Requirements

macOS with zsh (the default since macOS 10.15). [fastfetch](https://github.com/fastfetch-cli/fastfetch)
is installed automatically. Terminal.app shows all colors from macOS 26 on; on
older versions lotus switches to 256 colors by itself.

## License

MIT
