# Changelog

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
