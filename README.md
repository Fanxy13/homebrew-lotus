# Lotus

**A start screen and command center for the macOS terminal.**
Open apps, search and install software, check the weather, ask Apple Intelligence,
control your music, remove image backgrounds on your Mac, set up a Minecraft server –
all from the terminal, under the lotus start screen you know from 1.x.

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

Open a new terminal window. A short setup asks for the interface language, your name,
a theme, whether Lotus should start with every terminal window, and which features to
turn on – then sets up the ones you picked and shows a review before anything is saved.
Run it again any time with `lotus setup`; switch features with `lotus features`.

Want Lotus on a key combination? Add the **[Open Lotus](https://www.icloud.com/shortcuts/0ad5b36d73e745bebbaba4635344382e)**
shortcut, then give it a keyboard shortcut in the Shortcuts app (info button → Add Keyboard Shortcut).

Needs macOS 11 or newer and zsh. [fastfetch](https://github.com/fastfetch-cli/fastfetch)
is installed automatically. Optional tools (Homebrew, yt-dlp, Java, …) are offered
when a command needs them – nothing is installed without asking.

## Lotus 2.2

- **Remove BG** – `/bg remove photo.jpg` cuts out the subject with BiRefNet or InSPyReNet,
  locally on your Mac, and saves a transparent PNG. Drag images into the window, process
  whole folders, and paint what to keep in a small native editor when the AI misses something.
- **Features** – choose which parts of Lotus are on. A feature that is off has no command,
  no settings and downloads nothing.
- **`/lotus log`** – one log for everything Lotus does, with levels, filters, search and a live view.
- **A new setup** – spacious pages, a features page, setup for the features you picked, and a review.

Everything from 2.0 and 2.1 stays, and your settings carry over.

## Commands

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
| Weather | `/weather`, `/weather Tokyo` | ASCII art and a 3-day forecast, no API key |
| AI | `/ai` | The AI terminal: chat, write code, create and change files, run commands – it asks before every change |
| | `/ai what is a symlink?`, `/ai new` | One question (it remembers the conversation for an hour) · start fresh |
| | `lotus ai login` or `/login` | Connect Claude in a minute; also Apple Intelligence, Ollama or an OpenAI-compatible API |
| | `/ai explain`, `summarize`, `write`, `command` | Explain an error, summarize a file, draft text, suggest a command |
| Audio | `/np`, `/play`, `/pause`, `/skip`, `/back` | What is playing, play, pause, next, previous |
| | `/repeat`, `/mute`, `/vu`, `/vd` | Repeat, mute, volume up and down |
| Media | `/lotus visual` | Audio visualizer with 8 modes (space: next mode, `q`: quit) |
| | `/convert <link>` | Save MP3 or MP4 (resolution, frame rate) to `~/Downloads/Lotus` |
| Device tools | `/ios`, `/ios devices` | AirCard, Nugget, Sideloadly, Dopamine with compatibility checks |
| Minecraft | `/minecraft` | Create and start a server, port forwarding guide |
| Images | `/bg remove <image>` | Remove the background on this Mac, save a transparent PNG |
| | `/bg remove`, `/bg remove <folder>` | Drop images into the window · a whole folder with one model load |
| | `/bg remove --edit <image>` | Paint what to keep right after the AI |
| | `/bg models`, `/bg output` | Models on this Mac (download, check, remove) · output folder |
| Shortcuts | `lotus shortcut add yt https://youtube.com` | Your own `/yt`, `/work`, `/gh` … |
| Features | `lotus features`, `lotus features minecraft off` | Turn parts of Lotus on or off |
| Diagnostics | `/lotus log`, `/lotus log level debug` | What Lotus did, with filters and search · how much is logged |
| | `lotus -V <command>` | Print every log line while a command runs |
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
/bg remove ~/Pictures/portrait.jpg   # → ~/Pictures/Lotus/Background Removed/portrait_no_bg.png
```

## Remove BG

```bash
/bg remove ~/Pictures/photo.jpg
/bg remove "~/Desktop/My Photos/beach.heic"
/bg remove                      # then drag one or more images from the Finder into the window
/bg remove --edit portrait.jpg  # open "Draw what you want to keep" right after the AI
```

**Local.** The image is read and written on your Mac. Nothing is uploaded, there is no
cloud API and no account. After the one-time download it works offline.

**Models.** Lotus runs the official models of two research projects:

| Model | Size | Good for |
|---|---|---|
| BiRefNet | 445 MB | Best quality: hair, fur, thin and fine edges |
| BiRefNet Lite | 178 MB | Fast and light – the default on Intel Macs and Macs with less than 8 GB |
| InSPyReNet | 368 MB | Large photos (keeps the aspect ratio on the GPU) |

*Auto* (the default) picks BiRefNet on Apple silicon and BiRefNet Lite on Intel – and
always prefers a model that is already downloaded, so it never downloads a second one by
itself. Apple silicon runs on the GPU through PyTorch MPS, with the CPU as fallback; Intel
Macs use the CPU. If a model or the GPU fails, Lotus says so and offers the alternative.

**Installation.** Nothing is part of the normal Lotus install. The first `/bg remove` shows
what it needs – a Python environment with PyTorch (about 1 GB, once) and the model you
picked – and downloads it only after a yes, into `~/.local/share/lotus`. Every model file
is pinned to one upstream revision and checked against its SHA-256 before use; weights
load without running code (`safetensors`, `torch.load(weights_only=True)`). Python 3.10–3.14
is needed (Homebrew's `python@3.13` works well). `/bg models` downloads, checks and removes
models; turning the feature off in `lotus features` means nothing is ever downloaded.

**Output.** A new file next to nothing else: `photo.jpg` → `photo_no_bg.png`, then
`photo_no_bg_2.png` … The original is never changed. Full resolution, transparent PNG,
color profile kept. Choose the folder in `/settings` or with `/bg output` – a Lotus folder
in Pictures, next to the original, or any folder.

**Manual refinement.** After the AI, press `r` (or use `--edit`): a small window shows the
photo with the AI result bright and the rest dimmed. Paint over what must stay – brush,
eraser, size, undo, redo, clear, reset, invert, preview, apply. Painted areas are always
kept; their outer edge snaps to the object, so a wide brush is fine. The editor needs
Apple's Command Line Tools (`xcode-select --install`), like the AI terminal.

**How it cuts.** Model mask → edge refinement guided by the photo → your KEEP marks
(GrabCut + guided filter) → removal of faint specks → full resolution with a fast guided
filter → edge colors without the old background (blur-fusion foreground estimation), so
there are no halos.

**Settings** (`/settings → Remove BG`): model, backend (Auto, MPS, CPU), output folder,
manual refinement (offer, always, never), preview after processing, model cache.

## Settings

`/settings` – arrow keys to move, Enter or left/right to change, `v` to preview, `q` to close.

- Name, interface language (English, Deutsch, Français, Español), auto-start
- Logo: Classic, Minimal, Large, Terminal or your own ASCII art (`lotus logo import`)
- 13 themes: Matcha, Sakura, Ocean, Sunset, Mono, Midnight, Terminal, Lavender, Arctic, Graphite, Neon, Crimson, Retro
- Greetings, sections, now playing and live updates
- Features: turn each part of Lotus on or off (its settings disappear while it is off)
- Weather city and units, search engine, AI provider, model and how hard it thinks, visualizer mode
- Remove BG: model, backend, output folder, manual refinement, preview, model cache
- Diagnostics: log level (off, errors and warnings, normal, detailed, everything), how long logs are kept, startup details
- Shortcuts, setup again, reset, **uninstall**

Settings are stored in `~/.config/lotus/settings.zsh`. Files from Lotus 1.x and 2.x are
migrated automatically – new settings get their defaults, nothing you chose changes.

## Log

`/lotus log` shows what Lotus did: commands, settings changes, downloads, installs, the AI's
tool use, background removal stages and every error, with the time and the part of Lotus.
`f` filters by level, `/` searches, `⏎` shows the full entry, `l` follows new lines, `y` copies,
`c` clears. Error screens of Remove BG show an error ID (for example `BG-004`) whose details are
in the log.

The file is `~/.local/state/lotus/lotus.log`, rotated at 1 MB (three older files are kept) and
trimmed after the retention time. Keys, tokens and passwords are masked and your home folder
is written as `~`. Normal level writes errors, warnings and important events; `detailed` and
`everything` are for finding problems. `lotus -V <command>` prints the log while a command runs.

## Privacy and security

- No accounts, no tracking, no analytics.
- Lotus only goes online for what you ask: weather, updates, searches, downloads you confirm.
- Installs, downloads and deletions are shown first and need a yes. `sudo` is never run silently.
- API keys come from the macOS Keychain or the environment, never from files. The AI asks before it changes a file or runs a command.
- Links, package names, city names and shortcut names are validated; shortcuts cannot run shell commands.
- `/convert` is meant for content you have the right to download. It does not bypass DRM or paywalls.
- `/ios` only downloads official releases and checks compatibility before it does.
- Remove BG runs on your Mac only. Images are never uploaded; models come from their official
  sources, pinned and checked with SHA-256, and are downloaded only after a yes.
- The log masks keys and tokens and stays on your Mac.

## Repository

| Path | Contents |
|---|---|
| `bin/lotus` | The command – hands each subcommand to a module |
| `lib/core.zsh`, `lib/init.zsh` | Start screen, settings file, shell integration |
| `lib/ui.zsh`, `lib/fuzzy.zsh` | Shared UI components and fuzzy matching |
| `lib/log.zsh` | The log (levels, rotation, masking) – the AI and Remove BG write to the same file |
| `lib/cmd/*.zsh` | One module per feature (app, brew, weather, ai, ios, bg, log, …) |
| `lib/ai/*.swift` | The AI terminal (Claude, Apple Intelligence, Ollama, OpenAI-compatible), built once on first use |
| `lib/bg/` | Remove BG: runtime and model installer, the blooming progress screen (frames in `data/bloom.txt`, made by `scripts/make-bloom.py`, also used by the website), the Python worker (models, matting), the Swift editor |
| `lib/settings.zsh`, `lib/lang/` | Settings menu and translations (`<group>.<lang>.zsh` load with their screen) |
| `data/` | Commands, features, Remove BG models, themes, app catalog, iOS tools, project links |
| `logos/` | Built-in logos (`scripts/make-logos.py` derives them from the classic lotus) |
| `docs/` | Website, deployed with `data/` and `logos/` by `.github/workflows/pages.yml` |

## License

MIT. Remove BG downloads third-party models and Python packages at first use; their
licenses and attributions are in [THIRD_PARTY.md](THIRD_PARTY.md).
