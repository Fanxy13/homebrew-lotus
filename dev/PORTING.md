# Building features so that Windows and Linux are easy

The rule since the image editor: **a new feature is written once and runs everywhere; only a thin layer is written per system.**
macOS may come first – but the feature is built so that the next system is a few hours, not a rewrite.

## The four layers

```
 shared by every system (knows no operating system)
 ┌────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 1  The look and the logic      HTML + CSS + JavaScript, pure functions (geometry.js)        │
 │    The work                    Python 3.9+, standard library only (editor.py, liveserver.py) │
 │    The data                    data/*.tsv, strings.json – read by every language              │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
 one small piece per system, behind a name
 ┌────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 2  Adapters                    engine.py: ImageIO (macOS) · ImageMagick (Linux, Windows)     │
 │                                lib/platform/*.zsh and win/Private/Platform.ps1: lotus_os_*    │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
 the shell's part
 ┌────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 3  Glue                        zsh (macOS, Linux): lib/edit/launch.zsh                         │
 │                                PowerShell (Windows): win/Public/<command>.ps1                  │
 │    = find the input, check what is needed, start the shared program with the environment,     │
 │      show its result. About 80 lines. No logic of the feature.                                 │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
 ┌────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 4  Tests that need no system   Node for the pure functions, Python without sockets,          │
 │                                HTTP tests in containers, a browser test where Playwright is   │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
```

## A window? A page and a small server – not a native window

A native window (AppKit, WinUI, GTK) is written three times and tested three times. A page in the browser is written once:
the user already has a browser on every system, a page looks the same on all of them, and it can be tested with a script.

- The server is Python's standard library (`http.server`), on `127.0.0.1` and a port the system picks. It answers only to its own
  host names (`127.0.0.1`, `localhost` – no DNS rebinding), under an address with a secret in it (`/<token>/…`), and its
  changing requests only to the page itself (a header of the page, no foreign origin, no `Sec-Fetch-Site: cross-site`). The
  page has a strict content policy (`script-src 'self'`; no inline script or style). It ends with the tab (a ping every two
  seconds, a goodbye when the page closes, a grace time for a reload), with Cancel and with Ctrl-C, and deletes its working
  files. A picture, a path or a name the page sends is never a path the server opens: the server knows its files.
- The browser is opened by the server (`open`, `os.startfile`, `xdg-open`): three lines in `open_url`.
- Texts are a data file with every language (`lib/edit/web/strings.json`), not zsh files, so that every system reads them.
  A test checks that every language has every key and every `%s`.
- Pure functions for everything that can be wrong in the drawing (what a crop frame may do): no DOM, no network –
  `node tests/edit/geometry.test.js` runs them in a second, on every system that has Node, including CI Macs.

## The adapter: two methods

The image editor asks its engine for two things and nothing else: `writable()` and `convert(src, dst, key, quality, max_px, meta)`.
macOS has the converter of `/img convert` (Swift, ImageIO), Linux and Windows have ImageMagick. A third engine is a third class
(`lib/edit/engine.py`). Windows needs no engine of its own: Python finds `magick.exe` (winget: `ImageMagick.ImageMagick`).
Everything that is a call of the system – opening a file manager, the clipboard, a folder dialog – goes through the
platform layer (`lotus_os_*`, `Platform.ps1`), never straight from a feature.

## A checklist for a new feature

1. Could it be a page and a Python helper? Then it is. A terminal screen only where the terminal is the point.
2. Logic that can be wrong (geometry, parsing, naming, sorting) is a **pure function** with tests that run without a system.
3. Data and texts are files every language reads (`data/*.tsv`, JSON); no feature has its text only in a zsh file.
4. Python 3.9 syntax (`ast.parse(source, feature_version=(3, 9))` is in the tests) – the one a Mac's Command Line Tools bring.
5. No call of `osascript`, `sips`, `open`, `pbcopy`, `security`, `/Users/…` outside `lib/platform/macos.zsh` and an adapter.
6. The glue for a shell is a screen of code: find the input, check Python and the engine (say how to install what is missing),
   start the program with the environment (`LOTUS_LANG`, `LOTUS_THIS`, `LOTUS_FILES_APP`, `LOTUS_COLOR_*`, folders), show
   what it printed. The originals are never changed; a new file gets a new name (`name (2).ext`).
7. Rows in `data/commands.tsv`. A command a system does not have yet is named in `win/Public/help.ps1` (`$script:RowsNotHere`),
   so that its cheatsheet does not list it.
8. `data/platform-matrix.tsv`: a status is `yes` only where a test ran. Write what is not tested, in the note.
9. A test file per layer: `tests/test-<feature>.zsh` (no sockets – runs on CI Macs), `tests/test-<feature>server.zsh` (sockets –
   Linux containers and real Macs; add it to the exclusion list in `.github/workflows/test.yml` for the CI Macs), the programs under
   `tests/<feature>/`.
10. Say in the changelog what the next system needs.

## The image editor, system by system

| | macOS | Linux | Windows |
|---|---|---|---|
| The page, the server, the geometry (`lib/edit`) | shared | shared | shared |
| The engine (`engine.py`) | `ImageIO` → `lotus-img`, built once | `Magick` | `Magick` – nothing to write |
| The glue | `lib/edit/launch.zsh` | the same file | **to do**: `win/Public/img.ps1` |
| Camera data of the original in the cropped copy | yes (ImageIO) | not yet | not yet |
| Tests | engine, geometry, texts on CI Macs; server on a real Mac | all of it in the containers | to do |

What the Windows glue (`Invoke-LotusImgEdit`) has to do – this is all of it:

1. `Find-LotusPython` (3.9 or newer) – say `winget install Python.Python.3.13` if there is none; `Find-LotusMagick` – say
   `winget install ImageMagick.ImageMagick` if there is none.
2. The picture: `Get-LotusImgInputs` (already there for `/img convert`), the drop zone, the clipboard (`--out-dir ~\Downloads\Lotus`).
3. `python lib\edit\editor.py <picture> [--out-dir <folder>]` with `LOTUS_LANG`, `LOTUS_THIS=this PC`,
   `LOTUS_FILES_APP=File Explorer`, `LOTUS_EDIT_DATA`, `LOTUS_IMG_LAST` (the file `/img convert` shares), `LOTUS_DOWNLOADS`,
   `LOTUS_COLOR_KEY/ACCENT/DIM` – through `ConvertTo-LotusNativeArgs` and the helpers of `Platform.ps1` (Windows PowerShell 5.1 too).
4. `/img` without arguments calls it, `/img edit <picture>` too; remove `img edit` and `/img` from `$script:RowsNotHere`.
5. `win/tests/Edit.Tests.ps1`: run `tests/edit/page_test.py`, `engine_test.py` and `server_test.py` with the Python the module
   found (they are plain Python and run on Windows as they are), and the geometry test with Node when it is there.
6. Ship it: `lib/edit` goes into the list of folders in `install.ps1` (next to `lib/live` and `lib/html`) and into the `paths:`
   of `.github/workflows/windows.yml`, so that a change of the editor runs the Windows tests. (`install.sh` and the Homebrew
   cask copy the whole of `lib` already.)

## What stays system-specific on purpose

- `open_url` and `show_file` in `editor.py` (three branches each: `open`, `os.startfile`/`explorer`, `xdg-open`).
- The Swift converter on the Mac: it is the only engine that reads RAW, HEIC and the rest the way Preview does.
- Native windows that already exist (the Remove BG drawing editor, `lib/bg/Editor.swift`) stay as they are; a new one is a page.
