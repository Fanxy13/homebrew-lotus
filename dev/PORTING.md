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
| The glue | `lib/edit/launch.zsh` | the same file | `win/Public/img.ps1` (`Invoke-LotusImgEdit`, about 75 lines) |
| Camera data of the original in the cropped copy | yes (ImageIO) | not yet | not yet |
| Tests | engine, geometry, texts on the CI Macs; the server over HTTP on a real Mac (a CI Mac cannot talk to 127.0.0.1) | engine, server and texts in the containers (the geometry where Node is there); the page in a browser where Playwright is there | `win/tests/Edit.Tests.ps1` on GitHub's Windows machines: the glue, the editor started for a real picture, and the Python and Node programs of `tests/edit` with the machine's Python (the page is not driven in a browser there) |

What the Windows glue (`Invoke-LotusImgEdit` in `win/Public/img.ps1`) does – this is all of it:

1. `Find-LotusPython` (3.9 or newer) – it shows `winget install --id Python.Python.3.13 -e` if there is none; `Find-LotusMagick`
   (the first `magick.exe` that can really write a PNG) – it shows `winget install --id ImageMagick.ImageMagick -e` and asks, if
   there is none (`Install-LotusMagick`, the one `/img convert` has).
2. The picture: `Get-LotusImgInputs` (shared with `/img convert`; a folder is refused with the way to `/img convert`), the drop
   zone (`Read-LotusImgEditPaths`), and with an empty ⏎ the clipboard – an image or files copied in File Explorer
   (`Get-LotusClipboardKind`, `Save-LotusClipboardPicture` in `Platform.ps1`) – whose picture goes to `--out-dir ~\Downloads\Lotus`.
3. `Invoke-LotusPython` runs `lib/edit/editor.py <picture> [--out-dir <folder>]` with `LOTUS_LANG`, `LOTUS_THIS=this PC`,
   `LOTUS_FILES_APP=File Explorer`, `LOTUS_EDIT_DATA`, `LOTUS_IMG_LAST` (the file `/img convert` shares), `LOTUS_DOWNLOADS`,
   `LOTUS_COLOR_KEY/ACCENT/DIM` and `LOTUS_MAGICK` (the ImageMagick that was tried out) – Windows PowerShell 5.1 too.
4. `/img` without arguments calls it when there is a keyboard (the help otherwise), `/img edit|crop|e <picture>` too;
   `$script:RowsNotHere` in `help.ps1` no longer hides the rows of the editor (the list stays, empty, for the next feature).
5. `win/tests/Edit.Tests.ps1`: the commands; the glue with a Python and an ImageMagick that are made up (none, no picture, a
   folder); the editor started by the glue for a real picture, asked for its page and its picture, and ended with Cancel; and the
   programs of `tests/edit` (`page_test.py`, `engine_test.py`, `server_test.py`, the geometry with Node) run with the Python
   the module finds. They are plain Python and run on Windows as they are – only a test that needs POSIX (a folder marked
   read-only still being writable on Windows) says `Skip`.
6. Ship it: `lib/edit` goes into the list of folders in `install.ps1` and into the `paths:` of `.github/workflows/windows.yml`,
   so that a change of the editor runs the Windows tests. (`install.sh` and the Homebrew cask copy the whole of `lib` already.)

What the port taught – for the next feature:

- **A folder that a feature reads at run time must be in the installer's list.** The tests run from a checkout and cannot see a
  missing one; `Install.Tests.ps1` now looks for a file of each folder (this is how `lib/bg` and `lib/mc` were found to be missing).
- **Tell the shared program what the glue has already tried out** (`LOTUS_MAGICK`) instead of letting it search the PATH again:
  the first `magick` of the PATH may be a program that cannot read or write images.
- **What the system does for a feature belongs in the platform layer** – the clipboard of `/bg` moved to `Platform.ps1` and the
  editor uses it too.
- **A row of the help is cut at its first `|`**: `<image|folder>` shows as two columns; write `<image or folder>`.
- **POSIX habits that Windows does not share**: `SO_REUSEADDR` lets a second program take a port that is in use (the server
  turns it off there), and a folder's read-only mark does not stop writing into it.
- **Pester's `BeforeDiscovery` variables are not there in `BeforeAll`**: what the run needs it must find again.

## What stays system-specific on purpose

- `open_url` and `show_file` in `editor.py` (three branches each: `open`, `os.startfile`/`explorer`, `xdg-open`).
- The Swift converter on the Mac: it is the only engine that reads RAW, HEIC and the rest the way Preview does.
- Native windows that already exist (the Remove BG drawing editor, `lib/bg/Editor.swift`) stay as they are; a new one is a page.
