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

Open a new terminal window. A short setup – in the Matcha colors, with a lotus that opens
a little more with every step – asks for the interface language, your name, a theme,
whether Lotus should start with every terminal window, and which features to turn on –
then sets up the ones you picked and shows a review before anything is saved.
Run it again any time with `lotus setup`; switch features with `lotus features`.

Want Lotus on a key combination? Add the **[Open Lotus](https://www.icloud.com/shortcuts/0ad5b36d73e745bebbaba4635344382e)**
shortcut, then give it a keyboard shortcut in the Shortcuts app (info button → Add Keyboard Shortcut).

Needs macOS 11 or newer and zsh. [fastfetch](https://github.com/fastfetch-cli/fastfetch)
is installed automatically. Optional tools (Homebrew, yt-dlp, Java, …) are offered
when a command needs them – nothing is installed without asking.

## Lotus 2.3 – Pets

- **Pets that live in your terminal** – adopt up to three little pixel pets: a cat, a dog or your own kind.
  Type a pet's name and it answers – it thinks with Apple Intelligence on your Mac, has its
  own personality and remembers the last few things you said. In `/ai` it sits in the welcome
  box, and it is the spinner while the AI thinks – blinking and wagging its tail.
- **`/help` with a pet** – your pet asks where you need help, finds the right commands and puts
  the one you pick on your command line.
- **`/zetamac`** – a math game like [Zetamac](https://arithmetic.zetamac.com/): 120 seconds of mental
  arithmetic, and every right answer is a bite for your pets – the more you get right, the longer they
  stay full (up to two days). `/zetamac 60`, `/zetamac hard`.
- **`/feed mochi`** – pets get hungry after half a day (they never get ill). They greet you
  below the start screen, share a tip now and then, sleep at night and react to typos and
  finished work.
- **Your own pet** – copy the prompt from the [Pets page](https://fanxy13.github.io/homebrew-lotus/pets.html),
  let any AI draw your pet, then `lotus pets add`.

## Lotus 2.2

- **Remove BG** – `/bg remove photo.jpg` cuts out the subject with BiRefNet or InSPyReNet,
  locally on your Mac, and saves a transparent PNG. Drag images into the window, process
  whole folders, and paint what to keep in a small native editor when the AI misses something.
- **Features** – choose which parts of Lotus are on. A feature that is off has no command,
  no settings and downloads nothing.
- **`/lotus log`** – one log for everything Lotus does, with levels, filters, search and a live view.
- **A new setup** – spacious pages, a features page, setup for the features you picked, and a review.

Everything from 2.0 and 2.1 stays, and your settings carry over (also from 2.2 to 2.3).

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
| Clock | `/clock`, `/clock retro` | A full-screen clock in your theme: minimal, big, retro, Matrix, analog, world clock |
| Keep awake | `/caffeine on 90`, `/caffeine off` | Keep your Mac awake for a while with macOS' caffeinate |
| AI | `/ai` | The AI terminal: chat, write code, create and change files, run commands – it asks before every change |
| | `/ai what is a symlink?`, `/ai new` | One question (it remembers the conversation for an hour) · start fresh |
| | `lotus ai login` or `/login` | Connect Claude in a minute; also Apple Intelligence, Ollama or an OpenAI-compatible API |
| | `lotus ai local` | Models that run on this Mac with Apple's MLX – no Ollama: download, switch, remove; thinking, context window, answer length, creativity; `lotus ai local restart` starts it again. Nucifera 20B is gpt-oss-20b tuned for Lotus ([nucifera-20b](https://github.com/Fanxy13/nucifera-20b)) |
| | `/ai explain`, `summarize`, `write`, `command` | Explain an error, summarize a file, draft text, suggest a command |
| | `/enhance` in `/ai`, or `/settings` → AI | Improve your prompts before the AI sees them: off, on, or shown first so you choose |
| | `/ai server start`, `/ai server` | Lotus AI in your browser: a web chat on this Mac (127.0.0.1:3000) – the same AI, tools and questions · status, stop, port |
| | `/ai stats` or `/stats` in `/ai` | What the web chat is doing right now, and what the AI did: answers, time, steps by tool – live; answers its questions too |
| Audio | `/np`, `/play`, `/pause`, `/skip`, `/back` | What is playing, play, pause, next, previous |
| | `/repeat`, `/mute`, `/vu`, `/vd` | Repeat, mute, volume up and down |
| Media | `/lotus visual` | Audio visualizer with 8 modes (space: next mode, `q`: quit) |
| | `/convert <link>` | Save MP3 or MP4 (resolution, frame rate) to `~/Downloads/Lotus` |
| Device tools | `/ios`, `/ios devices` | AirCard, Nugget, Sideloadly, Dopamine with compatibility checks |
| Minecraft | `/minecraft`, `/mc <server>` | Create a server, its control center (players, ping, plugins, log), delete a server, port forwarding guide |
| Images | `/bg remove <image>` | Remove the background on this Mac, save a transparent PNG |
| | `/bg remove`, `/bg remove <folder>` | Drop images into the window · a whole folder with one model load |
| | `/bg paste` | The image in the clipboard – a screenshot, "Copy Image", or files copied in the Finder |
| | `/bg remove --edit <image>` | Paint what to keep right after the AI |
| | `/bg models`, `/bg output` | Models on this Mac (download, check, remove) · output folder |
| Pets | `/pets` | Your pets: adopt up to 3, talk, feed, rename, personality, settings |
| | `mochi`, `mochi how was your day?` | Type a pet's name to talk to it – alone for a chat, or with a message |
| | `/feed mochi` | Feed a pet |
| | `/zetamac`, `/zetamac 60 hard` | Math game like Zetamac – every right answer feeds your pets |
| | `/help`, `/help all` | Your pet helps you find a command · every command |
| | `lotus pets add` | Add your own kind of pet from the website prompt (reads the clipboard) |
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

## The AI in your browser

```bash
/ai server start        # starts the web chat and opens it: http://127.0.0.1:3000
/ai server              # status, and a menu: open, stop, restart, port, start with the terminal, other devices
/ai server port 3001    # another port – kept in the settings
/ai stats               # what it is doing right now, and what it did – live, q closes
/ai server stop
```

The web chat is the same AI as `/ai`, not a second one: the AI program of Lotus serves the page
itself (`lotus-ai --serve`, `lib/ai/Server.swift`) with the same providers, instructions
(`data/ai/system.md`), tools (`data/ai-tools.tsv`) and permissions. Answers stream in; a sidebar
keeps your conversations (new, history, clear, delete); Markdown, tables and code blocks with a
copy button; Enter sends, Shift+Enter makes a new line. It works on a phone too, in your theme's colors.
**Expand** on a code block – and **Open** on a file the AI wrote or changed – shows all of it on the right,
like in Claude: with line numbers, scrolling both ways, Copy and Download; drag its edge to make it wider.

**How hard it thinks.** The bars next to the message box open a slider, like the effort setting of
Claude: quick, balanced, thorough, maximum, ultra. Ultra is Claude's highest effort; with every AI it
also plans, checks its work (runs it, reads it back, looks at pages) and goes on longer when it stops
early. It is the same setting as `/effort` in `/ai` and counts from the next message.

**Follow along.** Like in Claude you see what the AI is doing: its thoughts as they come (folded to the
last lines, all of them with a click), every step with a spinner while it runs and how long it took, and
a line at the bottom that says what it is doing right now, for how long and how many steps so far. The
times come from Lotus, so the stopwatch goes on where it was after a reload. The answer is written on
your Mac, not by the page: close the tab and it works on – only the web chat has to run. Come back
any time, also from another device; the sidebar marks the conversation it is working in.

**Performance report.** `/performance` – in `/ai` or the web chat – writes the conversation into a `.txt`
file: the AI and its settings, this Mac, the time and tokens of every step, how much the model read from its
cache and how fast it wrote, where Lotus had to step in, and the logs of that time. The web chat downloads it,
`/ai` saves it in Downloads. Hand it over to improve the AI – API keys are never in it.

**Statistics.** `/stats` in `/ai` (or `/ai stats`) shows what the web chat is doing right now – and when
it asks a question while no page is open, you answer it right there (`y`, `a`, `n`; `x` stops the
answer). Below: answers, time working and thinking, steps, stopped and failed answers – today, in the
last 7 days and in all – the steps by tool, answers per day, terminal or web chat, and which AI. Only
counts and times are kept, never what was said. `/stats` in the web chat shows the same numbers.

**Commands and settings.** Type `/` for the commands of `/ai`: `/help`, `/new`, `/clear`, `/model`,
`/effort`, `/enhance`, `/auto`, `/permissions`, `/settings`, `/memory`, `/context`, `/stats`, `/performance`, `/compact`, `/copy`.
The gear opens the settings – who answers, thinking, improving prompts, ask first or auto, what the AI
may do, what it remembers. They are the same Lotus settings as `/settings` in the terminal; the port,
starting with the terminal and other devices can only be changed there.

**It does not get stuck.** A step the AI already made, with nothing changed since, is not run again – the
third time Lotus ends the tools for that answer. Thinking that repeats itself or goes on far too long is
stopped and the AI is told to act. A `write_file` that would replace a long file with a few lines is not
written; the AI is told to use `edit_file`. Tools called by other names (`open_file`, `bash`) run as the
right tool, and gpt-oss keeps its plan from one tool step to the next. All of this was measured with the benchmark
of [Nucifera](https://github.com/Fanxy13/nucifera-20b) – gpt-oss-20b tuned for Lotus.

**It works in steps.** A bigger task – or several in one message – starts with a short to-do list
(`plan`): one line per step, ticked off as it goes, shown as a checklist in the terminal and the web chat.
The AI thinks only about the step in front of it instead of planning everything in its head, and when it
stops with steps still open, Lotus sends it back to the next one.

**It keeps going.** When the AI stops before it is done – it ran out of room, only thought, or said
what it would do next and stopped there – Lotus lets it go on by itself, at most three times per
message, and says so in a line ("↻ … – Lotus lets it go on (1/3)"). A question to you is an end –
except a short "Should I create the files?" without doing anything: then Lotus tells it to just do it.
The AI is told to act rather than offer, to pick sensible defaults, and to finish the whole job.

**It sees the pages it builds.** When the AI builds a website it looks at it in a real browser –
WebKit, the engine of Safari, without a window – at desktop and phone width (`view_page`). It gets
the title and structure, errors in the browser console with file and line, files that did not load,
styles or scripts that are nearly empty, what is wider than the screen and which element, images
without alt text and form fields without a label; with `inspect` (a CSS selector) also the size,
position, colors and font of elements. Claude gets a screenshot too; the web chat shows it in the
step, iTerm2 and WezTerm in the terminal. After the AI writes an HTML, CSS or JS file, Lotus looks at
the page by itself and tells the AI what it saw – so smaller models notice their mistakes as well.
For photos it uses real ones: `fetch_url` lists the pictures of a page with their addresses.
The page only sees its folder (never private files) and cannot send anything away while it is looked at.

**Better prompts.** With `/settings` → AI → "Improve prompts" (or `/enhance` in `/ai`) the AI first
rewrites your message into a clear prompt – the goal, the details, the expected result – keeping your
language and every name, path, command and quote. "on" shows it and sends it; "ask" shows it first:
send it, send yours as typed, or nothing (Enter, `o`, Esc in the terminal; buttons in the web chat).
Messages of three words or fewer, commands and very long texts go as typed, and so does a message
whose rewrite fails or takes longer than 30 seconds. The conversation keeps what the AI saw.

**Questions in the browser.** When the AI wants to change something it asks in the page, with a
preview: yes, yes and don't ask again, no, or what to do instead. The levels are those of the
terminal – reading runs, changes and commands ask unless allowed or in auto mode ("Yes, don't ask again"
counts for one conversation), installing always asks. The Ask/Auto switch next to the message box and
"Yes, and switch to auto mode" let it work on its own, asking only when unsure; deleting, pushing,
installing, private files and other folders still ask, and `sudo` never runs. Tools that need the
terminal (the clock, Remove BG) stay there.

**Safe by default.** It listens on 127.0.0.1 only and never starts by itself (unless you turn on
`/settings` → AI → "Web chat: start with terminal"). `/ai server open` signs the browser in with
your access key (a cookie); without it the page stays locked. The server answers only to its own
address, every request needs the page's token, and changes must come from the page itself. API keys
never reach the browser. Other devices in your network only when you turn that on – they need the
link with your key, and the connection is not encrypted. An occupied port gets a clear message and an
offer of the next free one; Lotus never changes the port without asking.

## Plugins

Add your own things to Lotus – and share them. A plugin is a folder with a `plugin.conf` and programs in
any language (zsh, Python, Node, Ruby …). It can bring **commands** (`lotus todo add milk`, `/todo`),
**tools for the AI** (`/ai` and the web chat call them: "put milk on my list") and **a line under the
start screen**.

```bash
lotus plugin new my-tool          # a working plugin to start from, in ~/.config/lotus/plugins/my-tool
lotus my-tool                     # its command
lotus plugin check my-tool        # is its plugin.conf right?
lotus plugin install <git URL>    # someone else's – Lotus shows what it may do and asks
lotus plugin installer            # drag plugin folders and packs into the window, several at once
lotus plugin install <pack>       # a plugin pack from GitHub: several plugins with their settings
lotus plugin pack my-setup        # your plugins as a pack to share
lotus plugin uninstall rsvm       # uninstall one with its data (asks) – without a name: choose them
lotus plugin                      # your plugins · on|off|allow|update <name>
```

Every plugin says how much it may do. **Limited** (the default) runs in a macOS sandbox: only its own
folder and data folder, no internet unless it says `network = yes`, no keychain, no other apps, nothing of
your files, Lotus' settings or the AI's keys. **Full** runs with your rights and Lotus' own functions –
Lotus asks you before it installs one, and again whenever its files change. Everything about building one:
[PLUGINS.md](PLUGINS.md); examples (todo, github, hello, liveserver): [plugins/](plugins/), the first three at once as
a pack: `lotus plugin install https://github.com/Fanxy13/homebrew-lotus#packs/examples`.

**Live Server**, like the one in VS Code: install it once, then type `/liveserver` in a project folder (in VS Code's
terminal too). It serves the folder, opens `index.html` – or a menu of all its pages when there is none – and reloads
the browser whenever you save a file (only the styles when you change CSS). Phones and computers in the same Wi-Fi open
it too, at the address it shows – nobody from another network; `--local` keeps it on this Mac. Ctrl-C stops it.

```bash
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/liveserver
/liveserver                       # the folder you are in · /liveserver about.html · --port 8080 · --local · stop
```

## Remove BG

```bash
/bg remove ~/Pictures/photo.jpg
/bg remove "~/Desktop/My Photos/beach.heic"
/bg remove                      # then drag one or more images from the Finder into the window
/bg paste                       # the image in the clipboard (⌘C, "Copy Image", a screenshot with ⌃⇧⌘4)
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

**Clipboard.** `/bg paste` (or ⏎ on an empty line in the drop zone) takes what you copied:
image data such as a screenshot or "Copy Image" from a browser, saved as PNG first, or files
copied in the Finder, used as they are. Lotus reads the clipboard with macOS' own scripting –
nothing extra to install.

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
- Logo: Classic, Minimal, Large, Terminal, Apple, Flag of Earth or your own ASCII art (`lotus logo import`) – in the theme's colors (as a gradient through them, or one color) or their own
- While a song plays, its album cover takes the logo's place: colored character art (two pixels per character, 24-bit color), always in the cover's own colors
- 13 themes: Matcha, Sakura, Ocean, Sunset, Mono, Midnight, Terminal, Lavender, Arctic, Graphite, Neon, Crimson, Retro – or your own from the [Theme Studio](https://fanxy13.github.io/homebrew-lotus/studio.html) on the website, with a live preview (`lotus themes add <name> <8 colors>`)
- Greetings, sections, now playing and live updates
- Features: turn each part of Lotus on or off (its settings disappear while it is off)
- Weather city and units, search engine, AI provider, model and how hard it thinks, improving prompts, visualizer mode
- AI web chat: open its menu, start it with the terminal, allow other devices (with the key)
- Remove BG: model, backend, output folder, manual refinement, preview, model cache
- Pets: your pets, the pet on the start screen, `/help` with a pet, reactions, what pets think with (Apple Intelligence, the AI of `/ai`, nothing)
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
- API keys come from the macOS Keychain or the environment, never from files. By default the AI asks before it changes a file or runs a command; `/permissions` (or `/settings` → AI) sets what it may do – look at files, change files, run commands: allowed, ask first or never. In auto mode (`/permissions` or ⇧⇥) it works on its own in the folder and asks only when Lotus is unsure: before a command runs, Lotus reads it like the shell does and lets it through only when it stays in the folder and destroys nothing – deleting, pushing, installing, sending data, other folders, private files and unknown programs still ask, with the reason. Dangerous commands and private files (keys, `.env`) always ask, `sudo` never runs.
- The AI can use Lotus itself (open or install apps, weather, music, theme, clock, keep awake, features, Minecraft) through one list of tools, `data/ai-tools.tsv`. It only gets the tools of features that are on, every argument is checked against that list, and the commands are run with fixed arguments – never as a shell string the model wrote. Changing things asks first (`/permissions` → "Use Lotus features"), installing an app always asks.
- When the AI looks at a web page it built (`view_page`), WebKit shows only that page's folder – never private files such as `.env` – and blocks everything that could send data away (fetch, XHR, WebSockets, beacons); scripts, styles, fonts and images may load from the internet. Looking at a page counts as reading: free in the folder, asks elsewhere. Screenshots stay in `~/.cache/lotus/ai/pages`.
- The AI can search the web (DuckDuckGo, Wikipedia) and read pages; `/permissions` → "Search and read the web" turns that to ask first or off. Search words go to DuckDuckGo or Wikipedia, pages are fetched directly, without cookies. Only the public internet – addresses on this Mac or in the local network are refused, also after a redirect. Web text is marked as information, never as instructions; in auto mode commands ask again after the AI has read web pages, and an address that carries a lot of data always asks.
- What the AI remembers between conversations (`remember`, `/memory`) is a plain text file next to your settings (`~/.config/lotus/ai-memory.md`); passwords and keys are never kept.
- The web chat (`/ai server`) listens on 127.0.0.1 only and never starts unless you start it. The browser signs in with an access key (`~/.local/state/lotus/ai-server.key`, only you can read it); the server answers only to its own address, checks a per-page token and the origin of every change, and never sends API keys to the browser. Commands from the web follow the same permissions as in the terminal – dangerous ones always ask, `sudo` never runs – and the port and other devices can only be changed in the terminal. Conversations are kept in `~/.local/state/lotus/ai-chats`, readable only by you. `/ai stats` answers the web chat's questions with the access key in a header, only from this Mac, and can do nothing but answer or stop; the statistics (`ai-stats.tsv`) keep counts and times, never what was said.
- Links, package names, city names and shortcut names are validated; shortcuts cannot run shell commands.
- Plugins (`lotus plugin`) show what they may do before they are installed and need a yes. Limited plugins run in a macOS sandbox (only their own folders, no internet unless they ask for it, no keychain, no Apple Events, a clean environment without API keys); full ones run with your rights and must be allowed again after any change to their files. What you allowed is kept in `~/.config/lotus/plugins.tsv`.
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
| `lib/art.zsh`, `lib/cover.pl` | The art left of the start screen: logos in theme or own colors, the album cover of the song that plays, swapped live |
| `lib/cmd/*.zsh` | One module per feature (app, brew, weather, ai, ios, bg, log, …) |
| `lib/ai/*.swift` | The AI terminal (Claude, Apple Intelligence, Ollama, OpenAI-compatible), built once on first use; `Server.swift` is the web chat |
| `lib/ai/web/` | The web chat's page (HTML, CSS, JavaScript – no libraries, nothing from other servers) |
| `lib/ai/download.py` | Downloads a model for `lotus ai local` and reports the bytes received, for Lotus' progress line |
| `lib/ai/Page.swift` | `view_page`: renders a web page in WebKit without a window and reports what a person would notice |
| `lib/bg/` | Remove BG: runtime and model installer, the blooming progress screen (frames in `data/bloom.txt`, made by `scripts/make-bloom.py`, also used by the website), the Python worker (models, matting), the Swift editor |
| `lib/cmd/plugin.zsh`, `plugins/`, `packs/`, `PLUGINS.md` | Plugins: the sandbox, the commands, AI tools and start screen lines of plugins, the installer and packs – the examples and the guide |
| `lib/settings.zsh`, `lib/lang/` | Settings menu and translations (`<group>.<lang>.zsh` load with their screen) |
| `data/` | Commands, features, Remove BG models, themes, app catalog, iOS tools, project links |
| `logos/` | Built-in logos (`scripts/make-logos.py` derives them from the classic lotus, `scripts/make-logo-art.py` draws the Apple and the flag of Earth) |
| `docs/` | Website, deployed with `data/` and `logos/` by `.github/workflows/pages.yml` |


Tests: `zsh tests/run.zsh` (or `zsh tests/run.zsh clock`) runs them in an empty home – your own settings are not touched.

## License

MIT. Remove BG downloads third-party models and Python packages at first use; their
licenses and attributions are in [THIRD_PARTY.md](THIRD_PARTY.md).
