# Changelog

## 2.2.4

- A new `lotus setup`: simpler pages in the Matcha colors, with a small pixel-art lotus that opens a little more with every step – a bud on Welcome, the full flower on Review – and five bars that show where you are
- Choosing English in the setup works again (it used to jump to "Leave the setup?"); on the welcome page the texts switch to the language you point at
- The theme page shows all themes at once, and the lotus takes the colors of the theme you point at
- Name and city are typed into a rounded box; the suggested name is shown dim – Enter keeps it, typing replaces it
- Features are a two-column checklist with the description of the highlighted one below; the review ends with Back and Finish buttons
- Finish lets the lotus open all the way while pollen rises (any key skips it)
- Keys pressed quickly no longer leave `^[[B` on the screen, arrow keys that arrive as `ESC O A` work, resizing the window redraws the page, Ctrl-C leaves the terminal as it was

## 2.2.3

- `/bg paste` removes the background of the image in the clipboard: a screenshot (⌃⇧⌘4), "Copy Image" in a browser or Preview, or images copied in the Finder (then the originals are used)
- The drop zone of `/bg remove` shows when there is an image in the clipboard – press ⏎ to use it
- Images from the clipboard are saved to `~/Pictures/Lotus/Background Removed` when the output is set to "next to the original"; the clipboard is read on your Mac, nothing is uploaded

## 2.2.2

- `/bg remove` without a path shows a drop zone: a dashed frame in your theme colors with a plus in the middle – drag images or folders from the Finder into it
- The last phase of the lotus looks like a real open lotus now: the inner petals stay a cup with a pointed middle petal, the outer ones fan out, no more flat, jagged top
- `/convert` checks yt-dlp first: when it is older than 60 days, Lotus offers to update it (Homebrew, pipx, pip or yt-dlp's own updater)
- When a download fails with errors that mean an old yt-dlp (HTTP 403, "Sign in to confirm", signature errors), Lotus explains it and offers "Update yt-dlp and try again?"
- `lotus doctor` shows the yt-dlp version and marks it when it is outdated

## 2.2.1

- Remove BG has a new progress screen: a lotus that blooms from bud to full flower as the steps finish (and with real download progress), on a lily pad with water ripples and rising pollen, in the colors of your theme
- A clean single-column layout that fits the standard 80 × 24 window: nothing runs through the drawing any more; small windows leave the flower out
- All steps in one line (Model, Image, Subject, Edges, PNG), model, backend, size and time below

## 2.2.0 – Remove BG, features and the log

### Remove BG
- `/bg remove <image>` removes the background on your Mac and saves a transparent PNG – no cloud, no upload, works offline after the one-time download
- Two model families: BiRefNet (also as BiRefNet Lite) and InSPyReNet. *Auto* picks BiRefNet on Apple silicon and BiRefNet Lite on Intel, and prefers a model that is already downloaded
- Apple silicon runs on the GPU (PyTorch MPS) with the CPU as fallback; if the GPU or a model fails, Lotus says so and offers the alternative
- Drag images from the Finder into the window (`/bg remove` without a path); paths with spaces, quotes, parentheses and Unicode work, and nothing typed is ever run as a command
- Folders and several images at once, with one model load for all of them
- "Draw what you want to keep": a small native editor with brush, eraser, size, undo, redo, clear, reset, invert and preview. Painted areas are always kept; their edges snap to the object. Open it with `r` after the AI or with `/bg remove --edit`
- Clean edges: guided-filter refinement on the photo, speck removal, full-resolution output and edge colors without the old background (no halos)
- Never overwrites: `photo_no_bg.png`, `photo_no_bg_2.png` …; originals are only read. Color profiles are kept, HEIC and AVIF are read with macOS' own tools
- A progress screen with a small animated lotus, real stage times and real download progress – never a made-up percentage. Ctrl-C, errors and resizing always give the terminal back intact
- Result screen: open, show in Finder, refine by hand, discard
- First use explains what is downloaded (a Python environment with PyTorch, about 1 GB, and the model) and asks first. Everything goes to `~/.local/share/lotus`, every model file is pinned and checked with SHA-256
- Clear errors with an error ID (`BG-004` …), the reason and what to try; technical details go to the log
- `/bg models` (download, check, remove), `/bg output`, `/bg setup`, `/bg help`; settings in `/settings → Remove BG`; `lotus doctor` checks Python, PyTorch, MPS, models, output folder and the editor

### Features
- Choose which parts of Lotus are on – in the setup, in `/settings → Features` or with `lotus features`. A feature that is off has no command, no settings and downloads nothing; its commands explain how to turn it back on
- The cheatsheet and command suggestions only show what is on; turning Music off also removes now playing from the start screen

### `/lotus log`
- One log for Lotus, the AI terminal and Remove BG: commands, settings changes, downloads, installs, AI tool use, processing stages and every error
- Levels: off, errors and warnings, normal, detailed, everything (`/settings → Diagnostics` or `/lotus log level debug`)
- Interactive viewer with filters, search, details, live mode, copy and clear; `lotus -V <command>` prints the log while a command runs
- Rotated at 1 MB, kept for 7 days by default; keys, tokens and passwords are masked, the home folder is written as `~`
- Optional startup details under the start screen

### Setup
- A new first-time setup: Welcome (language) → You (name, theme, start) → Features → setup of the features you picked (weather city, AI, Remove BG) → Review with Back and Finish. Esc goes back a page; nothing is saved before Finish

### Also
- `who is the goat?` still knows the answer
- Settings from 2.0 and 2.1 are migrated: new settings get their defaults, nothing you chose changes
- `lotus uninstall` also removes the log and the Remove BG models

## 2.1.1

- Connecting Claude is now one step: `/login` in the AI terminal or `lotus ai login` in the shell opens the key page, you paste the key once (hidden), Lotus checks it with Claude, keeps it in the Keychain and switches to Claude right away
- `/model` offers "Claude – connect now" when no key is saved; `/ai` without any AI offers to connect Claude instead of showing an error
- `lotus ai logout` removes the Claude key

## 2.1.0 – The AI terminal

- `/ai` opens a full AI terminal: a framed input box, answers that stream with formatted code, thinking you can watch, and every step the AI takes shown as it happens
- The AI can work on your Mac: list, read and search files, create and change files, run commands. Every change and every command is shown first and needs a yes (`a` allows the rest of the session, `n` lets you say what to do instead); `sudo` is never run
- It remembers: the conversation stays for an hour, also between single `/ai <question>` calls, and is compacted into a summary when it gets long. `/ai new` or `/clear` starts fresh
- New provider: Claude (`lotus ai login`), next to Apple Intelligence, Ollama and OpenAI-compatible APIs. Switch any time with `/model`
- Thinks more: Claude with adaptive thinking, Ollama models with thinking mode, Apple Intelligence decides, plans and checks its own work. Set the depth with `/effort` or in `/settings`
- Inside the AI terminal: `/model`, `/effort`, `/context`, `/compact`, `/clear`, `/copy`, `/help`, `/exit`; esc stops an answer
- `lotus uninstall` also removes the AI memory and saved AI keys

## 2.0.0 – Lotus 2.0

Lotus grows from a start screen into a command center for the macOS terminal. Everything from 1.x stays, settings carry over.

### New commands
- `/app <name>` and `open <name>` open installed apps, with typo-tolerant matching ("Did you mean Spotify?")
- `/brew` searches Homebrew formulae and casks and installs after a clear preview
- `/install` – a catalog of 78 apps in 10 categories, installed through Homebrew Cask, with size, source and status
- `/google`, `/search`, `/web` and pasted links open in the default browser; `/lotus web` and `/lotus github`
- `/weather [city]` with ASCII art, a 3-day forecast and a short cache (Open-Meteo, no API key)
- `/ai` with Apple Intelligence on the Mac, Ollama or any OpenAI-compatible API; `explain`, `summarize`, `write`, `command`, `status`
- `/np`, `/play`, `/pause`, `/skip`, `/back`, `/repeat`, `/mute`, `/vu`, `/vd` audio control
- `/lotus visual` – an audio visualizer with 8 modes
- `/convert <link>` saves MP3 or MP4 (resolution and frame rate) with yt-dlp and ffmpeg
- `/ios` – launcher for AirCard, Nugget, Sideloadly and Dopamine with device detection and compatibility checks
- `/minecraft` – a server setup assistant (Vanilla or Paper, Java, EULA, start script, port forwarding guide)
- `lotus shortcut add yt https://youtube.com` – your own slash commands for links, apps, folders and Lotus commands
- `/lotus cheatsheet`, `/lotus themes`, `lotus logo` and a much more detailed `lotus doctor`

### Better everywhere
- First-time setup wizard: name, theme, auto-start, language (again with `lotus setup`)
- 13 themes (new: Midnight, Terminal, Lavender, Arctic, Graphite, Neon, Crimson, Retro)
- Four built-in logos (Classic, Minimal, Large, Terminal) plus your own ASCII art; narrow windows fall back to a smaller logo
- Unknown commands get a clean error with the closest suggestions
- `lotus update` shows the installed and the available version
- The bottom greeting is off by default (it can be turned on in /settings)
- One shared command list (`data/commands.tsv`) feeds the shell, the cheatsheet and the website
- The website has new pages: commands, themes, ASCII art, apps, iOS tools, Minecraft, shortcuts and documentation – without emojis, in dark and light mode

## 1.1.5
- The logo no longer disappears after a Homebrew update

## 1.1.4
- `lotus update` refreshes only the Lotus tap and stays quiet when everything is current

## 1.1.3
- One logo: the lotus flower from the original screenshot

## 1.1.2
- Homebrew cask uses the new install steps and hooks into the real ~/.zshrc

## 1.1.1
- Lotus is a Homebrew cask: installs without Xcode Command Line Tools and sets itself up

## 1.1.0
- English interface plus Deutsch, Français and Español
- Uninstall Lotus from /settings
- New website

## 1.0.0
- Start screen with logo, system info, greeting in 15 languages and the song that is playing, live
- `lotus`, `/settings`, `lotus update`, `lotus doctor`, `lotus uninstall`
