# Lotus plugins

Add your own things to Lotus – commands, tools for the AI and lines on the start screen – and share them.
A plugin is a folder with a `plugin.conf` and its programs, in any language. Lotus is open source (MIT), and
so is every example here: copy one, change it, put it on GitHub.

```
lotus plugin new my-tool          a plugin to start from, ready to run
lotus my-tool                     its command
lotus plugin check my-tool        is its plugin.conf right?
lotus plugin install <git URL>    someone else's plugin – Lotus shows what it may do and asks
lotus plugin installer            drag plugin folders and packs into the window – several at once
lotus plugin install <pack>       a plugin pack: several plugins with their settings, from one GitHub repository
lotus plugin uninstall <name>     it goes again, with its data – Lotus shows what and asks
```

## What a plugin can bring

| | How you use it | In `plugin.conf` |
|---|---|---|
| **Commands** | `lotus todo add milk`, or `/todo` in a Lotus shell | `command todo = todo.zsh` |
| **AI tools** | `/ai` and the web chat call them when they help – "put milk on my list" | `tool add = todo.zsh add` |
| **A start screen line** | one line under the start screen, e.g. "2 open – lotus todo" | `startup = todo.zsh count` |

A plugin can bring any of them, and as many commands and tools as it likes.

## Access: limited or full

Every plugin says how much it may do. Lotus shows it before you install a plugin and asks you.

**`access = limited`** – the default, and the right choice for most plugins. The plugin runs in a macOS sandbox:

- it reads only its own folder, and writes only its data folder (`~/.local/share/lotus/plugins/<name>`) and the
  temporary folder – nothing of your home folder or other disks
- no internet, unless it says `network = yes`
- no keychain, no `osascript` or Apple Events (it cannot control other apps), no `sudo`
- nothing of Lotus' settings, and never the API keys of the AI – it starts with a clean environment

**`access = full`** – for plugins that work with Lotus itself or with your files. The plugin runs with your rights
and can use Lotus' own functions (its settings, colors, `ui_*` helpers, the log). Lotus asks you before it installs
one, and **again whenever one of its files changes** – a full plugin that was changed after you allowed it does not
run until you allow it again with `lotus plugin allow <name>`. The AI tools of a full plugin always count as `act`:
they ask before they run, unless you let Lotus tools run (in `/permissions`) or use auto mode.

## plugin.conf

One setting per line, `key = value`. Lines that start with `#` are comments, and so is ` # …` after a value.

```
name        = todo                 # the plugin's name: letters, digits and -, the same as its folder
title       = To-do                # what you see
version     = 1.0
author      = Your Name
description = A small to-do list in the terminal
homepage    = https://github.com/you/lotus-todo     # optional
access      = limited              # limited (default) or full
network     = no                   # limited plugins: may it use the internet? yes or no (default no)

command todo = todo.zsh            # lotus todo … runs todo.zsh with the arguments
command      = todo.zsh            # the same, for a command with the plugin's own name

tool add               = todo.zsh add          # a tool for the AI: the program and words that come first
tool add.label         = To-do                 # what you see in the step: ● To-do(milk)
tool add.level         = act                   # read: runs right away · act: asks first (default)
tool add.description   = Add a to-do to the user's list. Use it when the user asks you to remember a task.
tool add.param text    = text, required, What there is to do

startup       = todo.zsh count     # one line under the start screen
startup.every = 60                 # make it again at most every 60 seconds (default 300)
```

Programs are files in the plugin's folder. Lotus starts them by their ending: `.zsh` (zsh), `.sh` (sh),
`.py` (python3), `.js` (node), `.rb` (ruby) – anything else must be executable. Words after the program
(`todo.zsh add`) come before the arguments.

### Parameters of AI tools

`tool <tool>.param <name> = <type>, required|optional, <description>`

| Type | What the AI may give |
|---|---|
| `text` | a short text (at most 120 characters, no control characters) |
| `int(1,999)` | a whole number from 1 to 999 |
| `enum(small\|medium\|large)` | one of these words |
| `path` | a file on this Mac that exists – read like `read_file` (it asks outside the folder); a limited plugin may read this one file |

Lotus checks every value against the type before your program runs, and asks you first when the tool's level is
`act`. Your program gets the values twice: as arguments in the order of the parameters, and as environment
variables `LOTUS_ARG_<NAME>` (`LOTUS_ARG_TEXT`). An optional parameter that the AI left out is empty.

What the program prints is what the AI reads – plain text, short and to the point. Its exit status tells Lotus how
it went: `0` done, `1` failed, `2` the arguments were wrong, `3` the user has to decide (the AI asks them). A tool
gets 60 seconds.

The AI sees a tool as `<plugin>_<tool>` (`todo_add`), with its description and parameters. Write the description
for the AI: what the tool does and when to use it.

### The start screen line

The program prints one short line. Lotus shows the line it printed last time right away and makes a new one in the
background when the old one is older than `startup.every` seconds – so a slow program never slows down the start
screen. Print nothing, and there is no line.

## What a program gets

| Variable | |
|---|---|
| `LOTUS_PLUGIN` | the plugin's name |
| `LOTUS_PLUGIN_DIR` | its folder (programs start there) |
| `LOTUS_PLUGIN_DATA` | its own data folder – keep your files here |
| `LOTUS_ARG_<NAME>` | the values of an AI tool's parameters |
| `LOTUS_VERSION`, `LOTUS_LANG` | Lotus' version, the language of its interface (`en`, `de`, `fr`, `es`) |
| `LOTUS_COLOR_KEY`, `LOTUS_COLOR_ACCENT`, `LOTUS_COLOR_DIM`, `LOTUS_COLOR_LOGO` | the colors of the theme, as color codes like `38;5;147`: `$'\e['$LOTUS_COLOR_KEY'm'` |
| `COLUMNS`, `TERM`, `HOME`, `PATH`, `TMPDIR`, `LANG` | as usual |

Full plugins also get `LOTUS_ROOT`, `LOTUS_CONF`, `LOTUS_CACHE`, `LOTUS_DATA`, `LOTUS_STATE`, `LOTUS_NAME`, `USER`,
`SHELL` and `LOTUS_PWD` – the folder the command was called in (a program starts in its plugin's folder) – and can
load Lotus:

```zsh
source $LOTUS_ROOT/lib/core.zsh && source $LOTUS_ROOT/lib/ui.zsh && lotus_load
ui_success "Hello, $LOTUS_NAME"          # Lotus' own look
lotus_feature_on weather && …            # what is turned on
LOTUS_THEME=rose; lotus_save             # change a setting
lotus_log INFO my-plugin "something"     # Lotus' log (lotus log)
```

## A plugin's settings

Keep what the user chooses in `$LOTUS_PLUGIN_DATA/settings`, one `KEY=value` per line – then a pack can set them
(below) and `lotus plugin pack` takes them along. Read the file line by line; never `source` it:

```zsh
typeset -A cfg=()
[[ -r $LOTUS_PLUGIN_DATA/settings ]] && for line in "${(@f)$(<$LOTUS_PLUGIN_DATA/settings)}"; do cfg[${line%%=*}]=${line#*=}; done
print -r -- "Saves to ${cfg[OUT]:-$HOME/Movies}"
```

## Installing them

`lotus plugin install` takes a folder, a git URL, or a folder in a git repository: `<git URL>#<folder>`
(`lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/todo`). Give it several, or a folder with
plugins in it, and Lotus shows each one short, lets you choose which ones (space), and asks once – naming the ones
with full access.

**`lotus plugin installer`** does the same by dragging: it shows a drop zone, you drag one or more plugin folders or
packs from the Finder into the window (or paste a git link – one on the clipboard is installed with Enter alone),
press Enter, and Lotus checks and shows them and asks. Then the next ones, or Enter to finish.

## Plugin packs

A pack installs several plugins at once, with the settings that make them work together – a "preset" to share. It is
a folder or a git repository with a `pack.conf`:

```
name        = creator-kit
title       = Creator kit
version     = 1.0
author      = Your Name
description = Videos from YouTube songs, a to-do list and GitHub on the start screen

plugin = https://github.com/you/lotus-rsvm                         # a git URL
plugin = https://github.com/Fanxy13/homebrew-lotus#plugins/todo    # a folder in a repository
plugin = ./weather-art                                             # a folder of this pack (. is the pack itself)
plugin = https://github.com/you/lotus-github off                   # installed, but turned off

set rsvm.RSVM_OUT  = ~/Movies/RSVM     # a line RSVM_OUT=… in rsvm's settings file (~ and {data} work)
files rsvm         = ./rsvm            # the files of this folder go into rsvm's data folder
```

```
lotus plugin install https://github.com/you/creator-kit
```

shows the pack, each of its plugins with what it may do and the settings it brings, and asks once. A pack cannot
give a plugin more access than its own `plugin.conf` asks for. `{data}` is the plugin's data folder; a pack's
settings replace the same keys in the settings file and leave the others. `lotus plugin check <folder>` checks a
`pack.conf`, and

```
lotus plugin pack my-setup
```

makes one from the plugins you have: the ones from git by their link, your own copied in, the ones that are off
marked `off`, and their settings – check the `set` lines before you share it, they are yours. An example to start
from: [packs/examples](packs/examples/pack.conf), installed with
`lotus plugin install https://github.com/Fanxy13/homebrew-lotus#packs/examples`.

## The commands

| | |
|---|---|
| `lotus plugin` | your plugins: what they bring, what they may do, whether they are on |
| `lotus plugin new <name> [full]` | a plugin to start from in `~/.config/lotus/plugins/<name>`, with a command, a tool and a start screen line |
| `lotus plugin check <name\|folder>` | check a `plugin.conf` or a `pack.conf` – with what is wrong and how to fix it |
| `lotus plugin install <folder\|git URL\|pack> …` | install plugins or a pack: Lotus shows what they bring and may do, and asks |
| `lotus plugin installer` | drag plugin folders and packs in, or paste a git link – several at once |
| `lotus plugin pack <name> [folder]` | a pack of your plugins and their settings, to share |
| `lotus plugin info <name>` | everything about one plugin |
| `lotus plugin on\|off <name>` | turn it on or off (its files stay) |
| `lotus plugin allow <name>` | allow a full plugin again after its files changed |
| `lotus plugin update <name>` | the newest version of a plugin installed from git |
| `lotus plugin uninstall [name …]` | uninstall plugins with their data (asks) – a name in any case, several at once, or none to choose them from a list |
| `lotus features plugins off` | turn off all plugins at once |

A plugin's commands are `lotus <word>` and, in a Lotus shell, `/<word>` (in new shell windows). A plugin cannot
take a name of Lotus' own commands. What you allowed is kept in `~/.config/lotus/plugins.tsv`.

## Share it

Put the plugin's folder in a git repository – the `plugin.conf` at the top – and others install it with:

```
lotus plugin install https://github.com/you/lotus-todo
```

and get your newest version with `lotus plugin update todo`. Want it in the list of plugins in Lotus' repository?
Open a pull request that adds it to [plugins/README.md](plugins/README.md).

## Examples

In [plugins/](plugins/): **todo** (limited – a command, three AI tools and a start screen line, its list in its data
folder), **github** (limited with the internet, in Python – a repository's stars and releases), **hello** (full –
Lotus' own functions and settings), **liveserver** (full – like Live Server in VS Code: `/liveserver` serves the
folder you are in and reloads the browser when you save; it reads that folder with `LOTUS_PWD`).

```
lotus plugin install ~/path/to/homebrew-lotus/plugins/todo
```

## Good to know

- Start from `lotus plugin new` – it is a working plugin – and run `lotus plugin check` after each change.
- A limited plugin that needs your files cannot have them – that is the point. Ask yourself whether it really needs
  them before you make it full.
- In the sandbox, programs from Homebrew (`/opt/homebrew`) and macOS work; ones in your home folder (a Node from
  nvm, a Python from pyenv) cannot be read – use a full plugin for those, or the ones of Homebrew.
- A plugin is code that runs on your Mac. Install full plugins only from people you trust, and read what
  `lotus plugin install` shows you.
- Lotus' log (`lotus log`) records when a plugin runs; the plugin's own messages go to its output.
