# Lotus

**A start screen and command center for the macOS terminal.**
Open apps, search and install software, check the weather, ask Apple Intelligence,
control your music, set up a Minecraft server – all from the terminal, under the
lotus start screen you know from 1.x.

**[Website](https://fanxy13.github.io/homebrew-lotus/)** ·
**[Commands](https://fanxy13.github.io/homebrew-lotus/commands.html)** ·
**[Docs](https://fanxy13.github.io/homebrew-lotus/docs.html)** ·
**[Changelog](CHANGELOG.md)**

```
                         :                        Bonjour, Gabriel
                        +#-           :-
           -.         +**##*.        =##-         ┌──────────────── Hardware ────────────────┐
         .*##       +#####*#*+     +####+         ├─ CPU       Apple M5 (10C / 10T) @ 4.46 GHz
         *###**-   *##*-  =**#* .*#*+***#:        ├─ RAM       15.26 GiB / 24.00 GiB [■■■■■■····] 63%
         **#*=*#*--##*.:**- =** -.=:=####:        └──────────────────────────────────────────┘
         =###*:... **.:***#+ -..+*- +###*:
   :      *###+:+**:  *+. :--.+###*.+###*.     -  …
   **:     **#+  =+  .        ..*::.+#*+. .=*##-
  .###***=: +#=.+.       -*    .=:= -.+#######*
   ####***+*+..=##+    +##*+    .**.=*++#####*:
   =#####*+-.. +*### -*#####*: *##*  -+**###*.    ♫ Habiba — Boef
    =*#######*:.*### *########==**-:===**#*:        [■■■■■■■■··] 02:48 / 03:35  ▶ playing
      =######*=. =** +########+.*+:*****=
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh
```

or with Homebrew:

```bash
brew install Fanxy13/lotus/lotus
```

Open a new terminal window. A short setup asks for your name, a theme, whether Lotus
should start with every terminal window, and the interface language. Run it again
any time with `lotus setup`.

Want Lotus on a key combination? Add the **[Open Lotus](https://www.icloud.com/shortcuts/0ad5b36d73e745bebbaba4635344382e)**
shortcut, then give it a keyboard shortcut in the Shortcuts app (info button → Add Keyboard Shortcut).

Needs macOS 11 or newer and zsh. [fastfetch](https://github.com/fastfetch-cli/fastfetch)
is installed automatically. Optional tools (Homebrew, yt-dlp, Java, …) are offered
when a command needs them – nothing is installed without asking.

## Lotus 2.0

Lotus 2.0 turns the start screen into an all-in-one terminal utility and launcher.
Everything from 1.x stays, and your settings carry over.

| Area | Command | What it does |
|---|---|---|
| Core | `lotus` | Show the start screen again (e.g. after `clear`) |
| | `/settings` | All settings in one menu |
| | `/lotus cheatsheet` | Every command with an example |
| | `lotus setup` | Run the first-time setup again |
| Apps | `/app spotify`, `open discord` | Open installed apps – typos are fine |
| Installer | `/install`, `/install firefox` | 78 curated apps in 10 categories, installed with Homebrew Cask |
| Homebrew | `/brew vlc`, `/brew install vlc` | Search formulae and casks, install after a preview |
| Web | `/google mac shortcuts`, `/search …` | Search with your engine of choice |
| | `/web github lotus`, `/web youtube.com` | Open a site or search it; pasting a link opens it too |
| | `/lotus web`, `/lotus github` | The Lotus website and GitHub |
| Weather | `/weather`, `/weather Zurich` | ASCII art and a 3-day forecast, no API key |
| AI | `/ai what is a symlink?` | Apple Intelligence on your Mac, Ollama or an OpenAI-compatible API |
| | `/ai explain`, `summarize`, `write`, `command` | Explain an error, summarize a file, draft text, suggest a command |
| Audio | `/np`, `/play`, `/pause`, `/skip`, `/back` | What is playing, play, pause, next, previous |
| | `/repeat`, `/mute`, `/vu`, `/vd` | Repeat, mute, volume up and down |
| Media | `/lotus visual` | Audio visualizer with 8 modes (space: next mode, `q`: quit) |
| | `/convert <link>` | Save MP3 or MP4 (resolution, frame rate) to `~/Downloads/Lotus` |
| Device tools | `/ios`, `/ios devices` | AirCard, Nugget, Sideloadly, Dopamine with compatibility checks |
| Minecraft | `/minecraft` | Create and start a server, port forwarding guide |
| Shortcuts | `lotus shortcut add yt https://youtube.com` | Your own `/yt`, `/work`, `/gh` … |
| Maintenance | `lotus doctor`, `lotus update`, `lotus uninstall` | Check, update, remove |

Unknown commands get a suggestion: `/weatr` shows “Did you mean /weather?”.
The list lives in [`data/commands.tsv`](data/commands.tsv) – the shell, the cheatsheet
and the website all read the same file.

### Examples

```bash
/app spotfy                    # Did you mean "Spotify"? [Y/n]
/install                       # browse categories
/web reddit macos              # search reddit
/ai command list the 5 biggest files here
lotus shortcut add yt "https://www.youtube.com/results?search_query={q}"
/yt lofi                       # your own shortcut
/convert https://example.com/video   # then pick MP3 or MP4
```

## Settings

`/settings` – arrow keys to move, Enter or left/right to change, `v` to preview, `q` to close.

- Name, interface language (English, Deutsch, Français, Español), auto-start
- Logo: Classic, Minimal, Large, Terminal or your own ASCII art (`lotus logo import`)
- 13 themes: Matcha, Sakura, Ocean, Sunset, Mono, Midnight, Terminal, Lavender, Arctic, Graphite, Neon, Crimson, Retro
- Greetings, sections, now playing and live updates
- Weather city and units, search engine, AI provider and model, visualizer mode
- Shortcuts, setup again, reset, **uninstall**

Settings are stored in `~/.config/lotus/settings.zsh`. Files from Lotus 1.x are migrated
automatically.

## Privacy and security

- No accounts, no tracking, no analytics.
- Lotus only goes online for what you ask: weather, updates, searches, downloads you confirm.
- Installs, downloads and deletions are shown first and need a yes. `sudo` is never run silently.
- API keys come from `$LOTUS_AI_KEY` or the macOS Keychain, never from files in this repository.
- Links, package names, city names and shortcut names are validated; shortcuts cannot run shell commands.
- `/convert` is meant for content you have the right to download. It does not bypass DRM or paywalls.
- `/ios` only downloads official releases and checks compatibility before it does.

## Repository

| Path | Contents |
|---|---|
| `bin/lotus` | The command – hands each subcommand to a module |
| `lib/core.zsh`, `lib/init.zsh` | Start screen, settings file, shell integration |
| `lib/ui.zsh`, `lib/fuzzy.zsh` | Shared UI components and fuzzy matching |
| `lib/cmd/*.zsh` | One module per feature (app, brew, weather, ai, ios, …) |
| `lib/ai/lotus-ai.swift` | Apple Intelligence helper, compiled on first use |
| `lib/settings.zsh`, `lib/lang/` | Settings menu and translations |
| `data/` | Commands, themes, app catalog, iOS tools, project links |
| `logos/` | Built-in logos (`scripts/make-logos.py` derives them from the classic lotus) |
| `docs/` | Website, deployed with `data/` and `logos/` by `.github/workflows/pages.yml` |

## License

MIT
