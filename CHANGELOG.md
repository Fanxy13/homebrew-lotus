# Changelog

## 2.6.0 – The AI knows more

- The AI in `/ai` can use the internet: it searches the web (DuckDuckGo, Wikipedia when that does not answer – no account) and reads pages as clean text – documentation, release notes, articles, GitHub READMEs, Wikipedia without its menus, and Apple's developer documentation with its code examples. It looks things up instead of guessing and names its sources; long pages are read in parts. Works with Claude, the model on your Mac and Apple Intelligence
- It remembers you: what will matter later – how you like answers, your projects, decisions – it keeps with `remember` and knows in every new conversation. `/memory` shows the list, `/memory clear` forgets it; it is a plain text file you can edit (`~/.config/lotus/ai-memory.md`). Passwords and keys are never kept
- Folder notes: a `LOTUS.md`, `AGENTS.md` or `CLAUDE.md` in the folder tells the AI how to work there – it reads it by itself
- Safe by design: only the public internet – addresses on this Mac or in the local network (localhost, 192.168.…, the router, `.local`) are refused, also after a redirect. Text from the web is information for the AI, never an order; in auto mode commands ask again after the AI has read web pages, and an address that carries a lot of data always asks. `/permissions` → "Search and read the web": allowed (the default), ask first or never – also in `/settings` → AI
- Apple Intelligence knows when a question needs the internet ("the newest …", "search …") and searches instead of answering from memory; "remember that …" is kept reliably
- Offline, the AI says so ("is this Mac online?") and tries a failed search once more

## 2.5.1 – Auto mode

- Auto mode for `/ai`: the AI works on its own in the folder and asks only when Lotus is unsure. Switch it in `/permissions` (the new first row, "Mode"), with ⇧⇥ (Shift-Tab) in the input box, or in `/settings` → AI. While it is on, the bottom line says `⏵⏵ auto`
- In auto mode it reads, creates and changes files in the folder without a question. Before a command runs, Lotus reads it the way the shell does and lets it through only when it is sure the command stays in the folder and destroys nothing – looking at things, `git status`, `diff`, `add`, `commit`, builds and tests (`swift build`, `npm test`, `pytest`, `cargo`, `make`), creating and moving files here, downloads without sending data
- It still asks – and says why ("Auto mode asks: it deletes files") – before deleting, `git push`, `pull`, `reset` or `checkout`, installing (`brew install`, `npm i <package>`, `pip install`), sending data to the internet, `ssh`, other folders, private files (`.env`, `~/.ssh`), commands built at run time (`$(…)`, `eval`), code that flows in (`curl … | python3`), things that keep running in the background and programs it does not know. Dangerous commands still always ask and `sudo` never runs
- Ask first stays the default

## 2.5.0 – The AI on your Mac works on your Mac

- Fixed: gpt-oss on this Mac still often could not use the computer, and its answers sometimes showed raw arguments like `{"path":"notes.txt"}` instead of doing something. Lotus now reads every way gpt-oss writes a tool call: when the model server cuts off the end of the call, when the tool name comes before the channel (as in earlier steps of the conversation), and `to=functions.read_file<|constrain|>json` without a space – which Lotus read as a tool called "read_filejson", so gpt-oss tried again and again without anything on screen
- Qwen, Devstral and other models on this Mac: tool calls written as `<tool_call>` blocks (JSON or `<function=…>`) are used too when the model server leaves them in the text
- A tool call a model gets wrong is shown now – a red line says what happened (no such tool, a missing path, arguments that are not valid JSON) – so you see what the AI does instead of only "thought for …" lines

## 2.4.6

- Fixed: gpt-oss on this Mac could not use the computer. It writes its tool calls as text, which the model server does not turn into tool calls, so `/ai` hid them and answered nothing. Lotus reads them now: gpt-oss lists, reads, searches, creates and changes files and runs commands like the other models do. Its short notes before a step are shown
- New: you decide what the AI may do – `/permissions` in `/ai` and `/settings` → AI: work on this Mac at all, look at files in the folder or elsewhere, change files in the folder or elsewhere, run commands. Each one is allowed, asks first or never (the default is what it was: reading in the folder is free, everything else asks). Dangerous commands and private files (keys, `.env`) always ask, `sudo` never runs. Listing a folder outside the working folder asks like reading does

## 2.4.5

- Fixed: `/model` in `/ai` did not list the model on this Mac (`lotus ai local`) – only Apple Intelligence and Claude. It does now: pick it and Lotus starts the model, `/ai` opens again with it and the conversation continues. The choice is kept for the next `/ai`

## 2.4.4

- Fixed: while the AI thinks, `/ai` showed only the line with your pet's eyes. Now your whole pet is the spinner, with ears, body and tail, blinking and wagging next to "Thinking…". In a window too small for it you still get the one-line face
- Fixed: a model that thinks and then never answers (it used its whole answer length for thinking) left `/ai` silent. Now `/ai` says what happened and how to fix it, or shows the thoughts if the model wrote nothing else

## 2.4.3

- Fixed: gpt-oss on this Mac showed its raw output (<|channel|>analysis … <|channel|>final …) – `/ai` now shows only the answer. Thoughts of local models (gpt-oss channels, Qwen's <think>) are kept apart from the answer
- Fixed: after such an answer the next question failed ("You have passed a message containing <|channel|> tags") – saved conversations are cleaned before they go back to the model
- Thinking is quiet in `/ai`: while the AI thinks your pet's face is the spinner, afterwards one short line says how long it thought – then only the answer
- The model manager (`lotus ai local`) looks better: memory and disk at the top, and every model with a small bar of how much memory it needs – green fits, yellow is tight, red is too big – its size, whether it is downloaded or in use, and what it is good at, in clean columns
- Downloads have Lotus' own progress bar with percent, speed and time left instead of Hugging Face's output; esc stops one, the next start continues where it stopped. If Lotus ends, the download ends with it
- "Faster downloads": connect a free Hugging Face account in the manager – the token page opens, you paste the token (hidden), Lotus checks it and keeps it in the Keychain. Downloads use it from then on, and the "unauthenticated requests" notice is gone either way
- Models from Hugging Face show their size before the download

## 2.4.2

- Fixed: with a model on this Mac, `/ai` said "The AI service is not reachable" – the model was stopped again right after it had loaded. It now stays while `/ai` runs and still leaves the memory when `/ai` ends, also after Ctrl-C

## 2.4.1

- `lotus ai local` is a manager now: all five models with size, what they are good at and whether they are downloaded or in use – pick one to download it, switch to it or remove it; "Remove everything" deletes all models and the MLX environment. Also as commands: `lotus ai local use <model>`, `lotus ai local remove <model|all>`
- Settings for the models on this Mac (in the manager, `lotus ai local settings` and `/settings` → AI): thinking (quick without thinking, balanced, thorough, maximum), context window (8K–128K – longer conversations are summarized when they reach it), answer length (2K–32K), creativity (precise, balanced, creative) and a memory saver (the context in 8 bits)
- `/ai` shows the model's name ("gpt-oss 20B · on this Mac") instead of a folder path

## 2.4.0 – AI on your Mac

- `lotus ai local` puts an AI model on your Mac – no Ollama, no account: five models to choose from – gpt-oss 20B (thinks, best fit for 24 GB), Qwen3.6 27B (thinks, strongest coder), Qwen3-Coder 30B (fast coder), Devstral Small 2 (coding agent), Qwen3 14B (thinks, light) – with size, what each is good at and whether it fits your memory, sets up Apple's MLX in Lotus' own environment and downloads the model you pick, pinned to one revision. Any MLX model from Hugging Face works too: `lotus ai local mlx-community/<model>`
- `/ai` starts the model when it opens (a few seconds) and closes it when it ends, so the memory is free again. It only listens on 127.0.0.1; thinking models show their thoughts
- New AI provider "On this Mac (MLX)" in `/settings` → AI, `lotus ai status` shows it, `lotus ai local remove` deletes the models, `lotus uninstall` too

## 2.3.1

- The pets are little pixel sprites now: block characters, two by two pixels each, with one-pixel eyes – a cat with pointed ears and a curly tail, and a dog seen from the side with a floppy ear, a snout and a wagging tail. They blink, talk, chew, wag and sleep (`scripts/make-pets.py` draws them)
- Your pet comes along into `/ai`: it sits in the welcome box next to "Lotus AI", and while the AI thinks its face is the spinner and blinks now and then
- Your own pets may be drawn with the same block characters (the prompt on the Pets page asks for them); everything else is still left out of a drawing

## 2.3.0 – Pets

### Pets that live in your terminal
- Adopt up to three little ASCII pets: a cat and a dog come with Lotus, and you can add your own kind. The setup offers a pet, `/pets` adopts, renames, feeds and says goodbye
- Type a pet's name in the shell to talk to it: the name alone starts a little chat, with words after it the pet answers once (`mochi how was your day?`). The words appear while its mouth moves
- Pets think with Apple Intelligence on your Mac: each one has its own personality (change it in `/pets`), remembers the last few things you said and answers in your language. Without Apple Intelligence they still say hi in short phrases; they can also use the AI of `/ai`, or nothing at all
- `/help` with a pet: it asks where you need help, picks the right commands and shows them – press 1, 2 or 3 and the command is ready on your command line. `/help all` lists every command
- `/feed <name>`: pets get hungry after half a day (they never get ill), the snack flies in, they chew and say thanks
- A pet says hi below the start screen – a different one every day, with a tip about a Lotus command now and then, and asleep at night. It only shows up when there is room, so nothing scrolls away
- Pets tilt their head at a typo in a command and cheer when Remove BG or a download is done
- Your own pet: copy the prompt from the new Pets page on the website, let any AI draw your pet, then `lotus pets add` reads the answer from the clipboard, checks it and saves it. Pet files are only read as data; drawings keep plain ASCII
- Settings in `/pets` → Settings and `/settings` → Pets; the whole feature can be turned off with `lotus features pets off`. `lotus doctor` shows your pets and how they think

### Also
- `/help` exists now (with or without pets) and opens the cheatsheet when you have no pet
- Text fields react to Ctrl-C right away

## 2.2.6

- When the setup is finished, the lotus opens all the way and its pollen flies up and writes "Hello" in big dots – Hallo, Bonjour or Hola in the other languages – and, a little smaller, your name, centered above the flower; then the dots twinkle for a moment (any key skips it)
- A new dot font for it (`data/dotfont.txt`) with upper and lower case, digits, umlauts and common accents; names it cannot draw are shown as plain text

## 2.2.5

- The setup looks the same in every language: the answers start on the same line on every page, with the same spacing – in German the welcome page used to lose its spacing and everything moved
- Descriptions are no longer cut off: they sit in their own column and continue on the next line (for example "Automatic" for the Remove BG model)
- A bit wider pages, the description of a feature may take two lines, the review shows the whole output folder

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
