# Changelog

## 3.3.1 – Face Blur, and the image editor on Windows

Two things in this release: Face Blur, a third tab of the image editor that hides the faces of a picture – found by a small AI that runs in the page, on this computer – and the image editor on Windows. And a fix for Lotus for Windows: its installer now ships Remove BG's worker and the sources of the Minecraft plugin, which an installed copy was missing.

### Face Blur

- **A third tab in the image editor, Face Blur** (`/img`): it finds the faces in the picture and hides them – tap a face (on the picture or in the row of faces under it) to leave it out, **Blur all** / **Show all**, a pencil with three brushes to draw over anything else that should go (**Undo**, **D**), and how it is hidden: **Blur**, **Pixelate** or **Black**, and how strongly. Every tab shows the picture with what is hidden; Done saves it, turned, mirrored, straightened and cropped as the other tabs say.
- **The AI runs in the page, on this computer**: YuNet (Shiqi Yu et al., MIT – `THIRD_PARTY.md`), 53,000 numbers in `lib/edit/web/faces.bin` (about 210 KB), run by about 250 lines of plain JavaScript (`lib/edit/web/faces.js`) in a worker – nothing to install, nothing uploaded, the same on macOS, Linux and Windows. It looks at a copy of 640 pixels and its smaller copies for the big faces, and at a copy of 1280 pixels for the small faces of a big photo: a group photo of 2048 × 1150 with 94 faces takes about two seconds. `scripts/make-face-model.py` makes the file again from OpenCV's ONNX file, with Python's standard library alone.
- Checked against the reference: the network gives the numbers of ONNX Runtime (at most 4 millionths apart on a photo and on noise), and on nine photos with 99 faces it finds the same faces as OpenCV's own YuNet code, with boxes less than 0.002 pixels apart.
- Blurred at the strength the tab starts with (0.8), or black, a face cannot be found again by the detector itself; big pixels keep the rough shape of a face (the detector still finds it, a person may not). A picture with hidden faces is saved **without its camera data** – the place would tell where it was taken.
- Hiding is pure functions too (`lib/edit/web/blur.js`): a soft-edged ellipse per face and round brush lines, a blur (three box blurs, made on a smaller copy where it is wide), blocks counted from the picture's corner, black; nothing outside a shape changes, and see-through pixels stay see-through. The page shows a copy of at most 2048 pixels; the saved picture is worked out in pixels of the picture itself, piece by piece, and drawn over it with the picture's own matrix.
- Not found: faces turned on their side, and very small faces in a big photo (under about 1 % of its width) – the pencil is for them.
- Tests: `tests/edit/faces.test.js` (the model file, the network's steps, boxes, a real portrait as it is, five times as big, half as big and mirrored, pictures without a face, and that the detector cannot find what was hidden), `tests/edit/blur.test.js` (19: shapes, rectangles, each kind of hiding, nothing outside a shape changes, the small copy looks like the saved picture, see-through pixels), and in Chromium (`tests/edit/ui.test.js`, 10 more): faces found, left out, drawn over, the kinds and the strength, the saved picture (the face left out is found in it, the hidden ones are not, the rest of the picture is the same to the pixel), mirrored and straightened, turned a quarter, a crowd of 36 on a desktop and on a phone. Fixed in the old browser test: a check of the Reset button that ran before the page had drawn.

### The image editor on Windows

- **`/img` and `/img edit` on Windows** (beta) – the image editor of the Mac and Linux, in your browser: crop, turn, mirror and straighten a picture and convert it, like the iPhone's Photos. It is the same page, server and geometry of the crop (`lib/edit`); Windows adds only `win/Public/img.ps1`, a screen of glue that finds Python 3.9 or newer and ImageMagick (it shows the `winget install` command when one is missing and asks before anything is installed), reads the picture – a path, a drop into the Windows Terminal window, or with an empty ⏎ an image or files copied in File Explorer – and starts the server with Lotus' language and colors. A picture from the clipboard is saved in `Downloads\Lotus`. `/img edit`, `/img crop` and `/img e` do the same; a bare `/img` opens the editor when there is a keyboard and shows the help when there is none. As on Linux, the cropped copy has no camera data yet.
- **The Windows installer shipped too little**: it copied only `lib/lang`, `lib/live` and `lib/html`, so an installed Lotus for Windows had no `lib/bg` (the worker, the graphics card probe and the requirements of Remove BG) and no `lib/mc` (the sources of the LotusBridge plugin) – both worked from a checkout, which is what the tests use. It now copies `lib/edit`, `lib/bg` and `lib/mc` too, and the install test looks for a file of each folder. (`lotus update` runs the installer again.)
- Smaller: the help of `/img` on Windows cut `/img convert <image|folder>` into two columns at the `|` in it (it reads `<image or folder>` now, as on the Mac); the clipboard – an image, or files copied in File Explorer – moved from `/bg` into the platform layer (`Platform.ps1`) and both use it; the editor is told which ImageMagick to use (`LOTUS_MAGICK`: another program may bring a `magick.exe` that cannot read or write images and stand first in the PATH); on Windows the server does not share its port (`SO_REUSEADDR` there would let a second program take a port that is in use).
- Tests (`win/tests/Edit.Tests.ps1`, on GitHub's Windows machines): the commands and the glue (no Python, no ImageMagick, no picture, a folder), the editor started by the glue on a real picture – its page, the picture, the secret in the address, Cancel and the clean-up – and the programs of `tests/edit` run with the Python and the Node of the machine: the page's texts and policy, the engine with `magick.exe`, the server over HTTP, the geometry of the crop. Not tested on Windows: the page driven in Edge or Chrome by script, the drop of a file into the terminal and the clipboard. On Windows on Arm the real run is left out – that machine has no ImageMagick that can write a picture.

## 3.3.0 – Lotus for Windows (beta), and an image editor in your browser

Two things in this release: the image editor (`/img`, macOS and Linux – Windows follows), and Lotus for Windows, which is in beta.

### The image editor

- **`/img` opens the image editor** – crop, turn, mirror and straighten a picture in a window that looks like the crop screen of the iPhone's Photos app: dark, a frame with corner and edge handles (a grid while you drag), a shape button (Freeform, Original, Square, 16:9, 4:3, 3:2, 5:4, 7:5, Portrait / Landscape), the turn and mirror buttons, a dial for straightening (−45° to 45°) under the picture, Reset, Cancel and Done. Everything outside the frame is gone. Drop a picture into the terminal window (or ⏎ for the clipboard), or `/img edit <image>`; `/img convert` for folders and many images stays as it was.
- **The conversion tools are in the window**: the second tab, Convert, has the format (what the system can write: JPEG, PNG, HEIC, AVIF, WebP, TIFF, GIF, BMP, PDF, ICO), the quality (Best, High, Medium, Small), the size (as it is, 4K … 640 px, never larger), a preview of the finished picture and the name it will get. Done saves a **new** picture next to the original – `photo edited.jpg`, never over a file – and the original is never changed. The last quality is shared with `/img convert`.
- **How it is built – so that Windows and Linux are easy**: the page (`lib/edit/web`: HTML, CSS and JavaScript, no framework, no download), its server (`lib/edit/editor.py`: Python's standard library, `127.0.0.1` only, a secret in the address, the page's own host names and requests only, ends with the tab) and the geometry of the crop (`lib/edit/web/geometry.js`: pure functions, tested with Node) are the same on every system and know no operating system. Only the image engine differs (`lib/edit/engine.py`): on a Mac the converter of `/img convert` (Apple's ImageIO, `lib/img/Convert.swift`, which now also copies the camera data of the original to the cropped copy), elsewhere ImageMagick. `lib/edit/launch.zsh` is the whole glue of macOS and Linux. `dev/PORTING.md` says how every feature is built from now on: shared code, a small adapter per system, the glue, tests that need no system.
- The page speaks English, German, French and Spanish (`lib/edit/web/strings.json`); a phone-sized window works too.
- Tests: the geometry (`tests/edit/geometry.test.js` – turning, mirroring, straightening, what a handle may do, random drags that must stay inside the picture), the engine and the session of a picture (`tests/edit/engine_test.py`), the page's texts and content policy (`tests/edit/page_test.py`), the server over HTTP – who is let in, saving, how it ends (`tests/edit/server_test.py`), and the page in Chromium with the mouse (`tests/edit/ui.test.js`, where Playwright is at hand).
- On Linux the editor works with ImageMagick; the cropped picture has no camera data there yet. Windows: soon – the same page and server, the glue is `win/Public/img.ps1`.

### Lotus for Windows (beta)

- **Lotus runs natively on Windows**: a PowerShell module for Windows 11 (or 10) and Windows Terminal – no WSL, no administrator rights. One line in PowerShell installs it: `irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.ps1 | iex`. It is a port of the zsh engine that reads the same files – `settings.zsh`, `data/`, `logos/`, `lib/lang/`, the keys and defaults of `lib/core.zsh` – so a settings file, a theme, a pet or a shortcut means the same on every system
- **It runs in the Windows PowerShell 5.1 that Windows 11 comes with** – nothing has to be updated first (everyone who tried the first version had to install PowerShell 7). The module, the installer and the shims run in Windows PowerShell 5.1 and in PowerShell 7 from one code base: the scripts have a byte order mark (5.1 reads a file without one as ANSI and would break every "–" and "▶"; `install.ps1` and `bin\lotus.ps1` stay ASCII), what only .NET Core has is replaced by what both have, a program PowerShell calls itself gets its arguments escaped (5.1 passed `print("x")` to Python without its quotes, so Python was not found), `/clock` reads IANA time zones through a table where .NET Framework knows only Windows ids, Lotus asks the console for colors, and the profile is read and written the way both PowerShells read it (a user name with an umlaut works). A new Windows 11 lets Windows PowerShell run no script files at all (*Restricted*): the installer takes a policy for its own window and shows the command that fixes it for your user – `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` – before it asks; the profile block goes into the profile of Windows PowerShell and, when it is installed, of PowerShell 7, and `lotus.cmd` takes PowerShell 7 when it is there, else Windows PowerShell. Tested on every change on GitHub's Windows machine (x64): every script is parsed by 5.1, the whole Pester suite runs in it (the installer also under made-up policies), and a real console (a ConPTY, like Windows Terminal's) with 5.1 on a Windows whose policy is *Restricted* gets the installer pasted in, its questions answered, the setup clicked through, then a new window that loads Lotus from the profile – the start screen with fastfetch in colors, the Enter key (`/clock`), `/settings`, `lotus doctor`, the colored prompt – `lotus unhook`, and `lotus` in cmd.exe
- **What it has**: the start screen (the logo in the theme's gradient, fastfetch, the greeting, now playing, the pet of the day), the `/commands` in PowerShell (its Enter key turns `/weather Paris` into `lotus weather Paris`), the setup wizard, `/settings`, themes, logos, shortcuts, features, `lotus doctor`, the log, `/app`, `/install` and `/brew` with **winget** (the exact command first, then a question), `/weather`, `/clock`, `/caffeine`, music and volume, the visualizer, `/web`, the pets and `/zetamac`, `/ai`, `/img`, `/convert`, `/liveserver`, `/html` and `/meshchat` – texts in four languages, with "this PC" and File Explorer where the Mac's texts say "this Mac" and Finder
- **`/ai` on Windows** is a chat and answers – Claude (the key checked with Claude, then kept with DPAPI for your Windows account), Ollama or an OpenAI-compatible API, streamed into the window, the conversation of the last hour remembered – plus `explain`, `write`, `summarize` and `command`. The AI terminal with its tools and the web chat are the Swift program's and not on Windows yet; the instructions say so to the AI (`data/ai/system.md`, "windows")
- Software comes from winget, always after a yes: fastfetch (or a pinned release, checked against its SHA-256), ImageMagick for `/img`, yt-dlp and ffmpeg for `/convert`. Every winget id of the app catalog (61 of its 78 apps) is checked against the real winget on every change
- **Remove BG on Windows** (x64): `/bg remove`, `/bg paste` and the drop zone with the blooming lotus of the Mac – the same worker (`lib/bg/worker.py`) and models, in Lotus' own Python environment with PyTorch's Windows build, on the processor (*Auto* is BiRefNet Lite there). Windows has no signal Lotus could send the worker: it stops when Lotus makes a file in its session folder. HEIC and AVIF go through Windows' own imaging component (WIC); the memory comes from `GlobalMemoryStatusEx`. Windows on Arm says why it cannot run it (OpenCV and torchvision have no build there on PyPI; PyTorch has one); the drawing editor stays the Mac's. A job of the Windows workflow sets it up and cuts out a picture for real
- **Remove BG on the graphics card** (Windows): with a card that DirectX 12 can use – NVIDIA, AMD or Intel – `/bg setup` adds DirectML (ONNX Runtime and onnx, about 40 MB from PyPI, `lib/bg/requirements-windows-gpu.txt`) and converts BiRefNet and BiRefNet Lite once on the PC, from the weights Lotus checked (`lib/bg/onnxprep.py`; nothing else is downloaded for it). DirectML has no deformable convolution, so for the conversion BiRefNet's are rewritten from GridSample and 1 × 1 convolutions, which it runs – torchvision's numbers to 1e-5. The card is found the way DirectML finds it (DXGI, `lib/bg/gpu.py`, without Windows' software adapter), the one with the most memory of its own first. `/bg remove --gpu` and `--cpu`, *Backend* in `/settings → Remove BG`; *Auto* takes the card when the model is prepared for it. A card that fails leaves the work to the processor – during the setup, which then drops the conversion (it also does when the card gets the setup's test picture wrong: the disc has to come out as the disc), and on a cut-out, which offers the processor once; with no card nothing changes. `lotus doctor` names the card. **Not yet tried on a real card**: GitHub's Windows machines have none (and DirectML refuses Windows' software adapter), so a new job of the Windows workflow converts both models with their real weights and compares what they give with PyTorch's result, on the processor: the same alpha to 7 · 10⁻⁵ on every picture (BiRefNet Lite converted in 29 s with 2.6 GB of memory into 184 MB, BiRefNet in 53 s with 4.4 GB into 933 MB). On that machine ONNX Runtime falls back to the processor on its own when DirectML cannot start – Lotus checks which one really runs and says so
- **The Minecraft server on Windows**: `/minecraft` and `/mc <name>` – the setup (Vanilla or Paper, Java found or fetched from adoptium.net into Lotus' folder, all checked against their checksums), the control center with its three pages, plugins from Modrinth, LotusBridge for ping and TPS, deleting to the Recycle Bin (a folder too big for it is never deleted for good without Windows asking). The server runs in a hidden PowerShell of its own, so closing the terminal does not stop it; commands reach it through `.lotus\input`, Windows stays awake while it runs, and `start.cmd` runs it in a window of its own. A job of the Windows workflow runs a Paper server for real
- **The album cover on Windows**: while a song plays, the start screen shows its cover in the logo's place, in the cover's own colors, two pixels per character – as on the Mac (`lib/cover.pl`, drawn in PowerShell: the same bytes on every test picture). Windows' media controls hand the picture over (asked in a Windows PowerShell, only when now playing says a song plays, and once per song: the picture and the drawing are kept in the cache's `covers` folder), Windows' own image component opens it (jpeg, png, gif, bmp – by their first bytes), and `/settings → Now playing` has the switch *Album cover instead of the logo*. Tested on GitHub's Windows machine with a stand-in player in Windows' media controls; it does not change while the start screen is on (no live updates yet, nor of the now playing lines).
- Not on Windows yet: the AI terminal and web chat, a local model, plugins, Remove BG on Windows on Arm and its drawing editor, Live Server for the phones in the Wi-Fi, live updates of the start screen; the iPhone tools are macOS only. Those commands say so. **Beta**: tested on every change on GitHub's Windows machines (x64 and Arm64) – about 400 tests – but not yet by people in a real window. The table "What works where" says what is tested on Windows and gets a new mark, *Built*: the code is there, not yet tested on that system
- For all systems: a contract between the two engines (`tests/contract`, `zsh tests/run.zsh contract`) – what zsh makes of colors, fuzzy scores, the settings file, the language files, the logos, the fastfetch configs and the greetings, which PowerShell must match byte for byte
- Fixed on Linux and the Mac too: fastfetch prints only a color reset when nothing plays, so the start screen showed two empty lines instead of "Nothing playing"; the pets, their doctor rows and the setup wizard named Apple Intelligence where the pets think with `/ai` (Linux); Live Server and `/html` gained the Windows branches they need without changing what they do elsewhere

## 3.2.0 – a QR code for the phone

- **`/liveserver` shows a QR code** for the address a phone opens: point the iPhone's camera at the screen and Safari opens the page – no typing of `192.168.178.23:5500`. It is drawn in the terminal in black and white, two rows of modules to a row of text so they come out square, whatever the theme (a QR code needs a light ground)
- **Tab shows the code of the next network** – your Wi-Fi, the iPhone whose hotspot the Mac uses, the devices it shares its internet with – and **Shift-Tab** the one before; the line under the code says which one it is ("next network (2/2)"). The code is drawn in place while nothing else was written; after a line of the log (a save, a page that is not there) the next one comes below it, so nothing is drawn over what was written. Ctrl-C stops the server as before and gives the terminal back as it was (no echo of keys while it runs)
- When the Mac joins another network while the server runs – the iPhone's hotspot, say – the terminal says the new address and shows its code
- A second `/liveserver` for a folder that is already served shows the address and the code too. `--no-qr` leaves it out; with `--local`, or without a terminal (a pipe, a script, a server in the background), there is none
- The code is made by `lib/live/qrart.py`, written out in Python's standard library (3.9 and newer): QR codes of version 1 to 10 in byte mode, error correction M (L when an address only fits that way), the best of the 8 masks. OpenCV's QR reader decoded what it makes – every version 1–10, both levels, addresses with umlauts – and `zsh tests/run.zsh liveserver` checks the codes of a few addresses against fixed values, the patterns every reader looks for, and – where OpenCV is installed – that it reads them back
- Tests: Tab, Shift-Tab and Ctrl-C on a keyboard (a pseudo-terminal, two networks from a stand-in for `ifconfig` – `LOTUS_LIVE_IFCONFIG`), in place or below a line of the log, `--no-qr`, the second server for a folder, no code without a terminal

## 3.1.0 – MeshChat, built in and on Windows, with /tell; Apple Intelligence with more room

What is tested on which system is the table on the website ("What works where"). MeshChat between real computers – Bluetooth from one to the other – is not yet tried: the
protocol, the mesh, the encryption and the screen are tested on every system, the test with real Macs and Windows computers is in `lib/meshchat/README.md`.

- **MeshChat: `/tell <name> <message>`** – to one person only. Every Mac and Windows computer on the way passes it on, only the recipient can read it: the text is end-to-end encrypted for their box key (X25519, HKDF-SHA256, ChaCha20-Poly1305 – CryptoKit on a Mac, BouncyCastle on Windows; nothing self-made), the sender's and the recipient's keys bound to it, the packet signed like every other one. Who writes to whom stays visible, and the README says so. The person is found by name (in any case, with spaces), the first letters of a name, the four letters of their key, or both (`Bob.k3f9`); `/msg`, `/w`, `/whisper` and `/pm` too. Shown as `→ Bob:` and `→ you:`, kept in your history. The box key comes with every "I am here" (at its end – MeshChat 2.0 and 2.1 skip it); when it has not come yet, the message waits for it, a minute at most, and MeshChat asks for it. A MeshChat before 2.2 neither shows nor passes on a `/tell`, and gets none: MeshChat says so. In the demo, Ada and Grace answer a `/tell` privately – Grace's goes through Ada, who cannot read it; the demo now ticks your own node too, as the real chat does – before, it never said "I am here", and Ada and Grace only knew you once you wrote. Tests on both, with the published results of X25519 (RFC 7748) and ChaCha20-Poly1305 (RFC 8439); the test vectors have a private message sealed with a fixed one-time key, checked byte for byte both ways. MeshChat 2.2.0
- **Apple Intelligence: more room, and it goes on by itself.** Its window stays what Apple made it – 4096 tokens for the instructions, the tools, the conversation and the answer together – but Lotus spends it better: each request gets only the tools it needs (a question about files three, a change five or six, a conversation none) with short descriptions – less than half the room the long ones took – and the conversation gets the room that is left instead of the last 3200 characters, about 7600 characters in a conversation; one long answer is shortened instead of pushing out everything before it
- A bigger change is done one step of its plan at a time, each step in a fresh session that is told the request, the plan and what is done – so a long task no longer fills the window, and a step that ends early no longer ends the task. A step that should have changed something and changed nothing gets one more try, told so; at the end it says in a few sentences what was done. When the model stops answering for a minute or its window is full, Lotus goes on in a fresh session that knows what is done (twice) instead of stopping with an error; a step that still does not get through is taken up again by the agent's "go on". A text that starts repeating itself is cut after the first time – a refrain with other words in between is no circle, code is cut only after six times. "Go on" from the agent now goes on with the same task and its tools – before, Apple Intelligence sorted it as a new message and often lost the tools. The rules are in `lib/ai/Small.swift`; `zsh tests/run.zsh smallmodel` checks them on every system
- Smarter sorting and planning: the sorter has examples for each kind of request, the planner writes steps that name the file or command and end with a quick check; a short follow-up ("make it blue") keeps the exchange before it
- The instructions (`data/ai/system.md`): the ones for small models are rewritten as short rules – look before you change, one tool call at a time, never the same call twice, say each thing once, say when you do not know; every AI is told to keep going until the request is done instead of ending with what it is about to do, what to do when it goes in circles, and to start with the answer
- **The chat by days** – before each day a line that says which: `── Today ──`, `── Yesterday ──`, `── 3 days ago ──`, `── 1 week ago ──`. Within a week each day has its own line; further back they go together by weeks, months and years. Drawn anew every time, so at midnight Today becomes Yesterday, in this computer's time zone. In the language of Lotus (`lotus settings`: Deutsch says `── Heute ──`, `── Gestern ──`, `── vor 1 Woche ──`; Français, Español) – on Windows in the language Windows is shown in. A time in the history that cannot be – a damaged line – is put far away instead of stopping the chat (on Windows it stopped it). MeshChat 2.1.0 on a Mac and on Windows
- **MeshChat for Windows** – `meshchat.exe`, a program of its own for Windows 10 (version 2004) and Windows 11, x64 and ARM64: the same chat as `lotus meshchat`, so Windows computers and Macs nearby chat together over Bluetooth LE. One file with .NET inside – nothing to install; in cmd, PowerShell or Windows Terminal, or with a double click. `meshchat demo`, `doctor`, `history`, `nick`, `set links`, `relay`, `selftest` – as on a Mac. Its sources are in `win/meshchat` (C#); the CI builds it on every change and keeps the two files with the run
- Installed with one line in PowerShell, no browser: `irm https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/win/meshchat/install.ps1 | iex` – the newest release `meshchat-windows-v…`, its SHA-256 checked against the release's `SHA256SUMS.txt`, into `%LOCALAPPDATA%\Programs\MeshChat`, your PATH and the Start menu; the same line updates it, `MESHCHAT_UNINSTALL=1` removes it. Windows PowerShell 5.1 is enough. Browsers block or warn about the unsigned program; the README says how to let it through. The workflow makes the release when run by hand with *publish* – a pre-release of its own, never Lotus' latest – and installs from it with Windows PowerShell 5.1 to check
- The same protocol, byte for byte: the mesh, the signatures (Ed25519 from BouncyCastle, MIT), the frames and what is kept are a line-by-line port of `lib/meshchat`. `lib/meshchat/Tests/vectors.txt` holds what fixed inputs must give – a key, a HELLO, the three kinds of messages signed, their frames; the Windows code checks it, the Mac's tests check it with CryptoKit, and in the CI the Mac writes packets it signed for the Windows code to check. Both directions, on every change
- Windows' own Bluetooth (WinRT): it finds and connects to the others as a Mac does, and – where the adapter can – offers the service so the others connect to it. Windows cannot put the name with the token into its advertisement, so the others connect to a Windows computer at once; two links at the same moment are made one, as between Macs. `meshchat doctor` says what Windows reports: the adapter, Low Energy, whether it can be found, the radio, *Let apps control device radios*, who is heard nearby. What it keeps is in `%LOCALAPPDATA%\lotus\data\meshchat`, the same files as on a Mac
- Tests: `dotnet run --project win/meshchat/MeshChat.Tests` (and `meshchat selftest` on Windows) – the same scenarios as the Mac's tests on a simulated radio, 443 checks (442 on Windows, which has no Unix file modes to check); a new workflow, *MeshChat for Windows*, runs them on Linux and Windows and builds the program; the *MeshChat* workflow checks the bytes both ways on a Mac. **Not yet tried between real computers** – the test is in `win/meshchat/README.md`
- **MeshChat is part of Lotus now** – no plugin to install: `/meshchat` is there on every Mac after an update, in `lotus cheatsheet` (a category of its own, Chat), in the pets' knowledge, in the website's commands and in its documentation. It is one feature, "MeshChat" (`lotus features meshchat off` turns it off). Its files are in `lib/meshchat` (the Swift program, its tests, the program that builds it) and `lib/cmd/meshchat.zsh`, what it keeps in `~/.local/share/lotus/meshchat`
- Still in a sandbox: MeshChat reads what any Mac nearby sends, so it runs where it ran as a limited plugin – in Lotus' sandbox (sandbox-exec), with a clean environment: it reads only `lib/meshchat`, writes only its data folder and has no network – nothing of Lotus' settings, never the AI's keys. Without a sandbox it does not start
- The old `meshchat` plugin is removed the first time Lotus starts after the update – only Lotus' own one, by its `plugin.conf`; a plugin of someone else with that name stays – and what it kept comes along: this Mac's identity (the Macs nearby know you by the same fingerprint), your name, the settings, the history and the rooms of MeshChat 1. Nothing is deleted before it has moved; when MeshChat has a data folder already, what is in it stays. Lotus says so once
- macOS only, as before: elsewhere `/meshchat` says that it runs on macOS only (CoreBluetooth and CryptoKit are Apple's). "What works where" has a line for it: partly on macOS – it has not yet run between real Macs
- A Mac nearby with another version of MeshChat now says `lotus update` instead of `lotus plugin update meshchat`; `lotus uninstall` removes MeshChat's data too (this Mac's identity, the history, the build)
- Tests: `zsh tests/run.zsh meshchat` – the command, the feature and the old plugin going away (with its identity, name and history, and what stays when both are there) run on every system now; on a Mac, as before, the build inside the sandbox, the selftest, the chat in a terminal and the doctor. The MeshChat workflow follows the new folders. `tests/test-plugin-install.zsh` counts three plugins in `plugins/`

## 3.0.0 – Linux, and the way to Windows

What is tested on which system is the table on the website ("What works where") and `dev/3.0/PROGRESS.md`; nothing is claimed for a system it was not tested on.
Windows is not in this release: a first PowerShell 7 module is in the repository (`win/`, `install.ps1`) and is tested in CI, but it can only show the start screen, the
themes, the settings and `lotus doctor` – every other command says that it is not available on Windows yet.

- **Linux (beta).** Lotus runs on Ubuntu, Debian, Fedora and Arch with zsh or bash. The tests run in containers on all four
  (`tests/docker/par.sh <distro>`), and GitHub Actions runs them on every push: the four distributions, both kinds of Mac and Windows.
- **One platform layer.** Commands no longer call `osascript`, `open`, `pbcopy`, `caffeinate`, `sips` or `security` themselves: they
  call `lotus_os_*` and `lotus_pkg_*` (`lib/platform/`), which have a macOS and a Linux implementation. What a system cannot do says so
  in words; nothing is silently skipped. Package managers: apt, dnf, pacman, zypper, apk and Homebrew – always the exact command first,
  then a question; `sudo` only in the open, never a stored password.
- **Install on Linux:** `install.sh` is plain `sh` (it also reads under dash) and installs into `~/.local` – no administrator rights;
  zsh is installed only after a yes. fastfetch comes from a pinned release with its sha256 (`data/vendor.tsv`). The old script fetched
  fastfetch from addresses that no longer exist.
- **bash.** `lib/init.bash` shows the start screen, forwards `/commands` (Enter rewrites the line before bash reads it), keeps your
  history and colors the prompt. It needs bash 4.4; `lotus setup` writes the lines into `~/.zshrc`, `~/.bashrc` or both (`LOTUS_SHELLS`).
- **The AI on Linux.** The Swift program builds there: one static file (Swift's Static Linux SDK, runs on any Linux). Without a Swift
  compiler Lotus downloads it for the release and compares its sha256 with the pin; a wrong file is deleted, never run. The AI
  looks at the pages it builds with headless Chromium, Chrome or Edge over a pipe – no port is opened. Commands run with `posix_spawn`
  (Foundation would wait for a server the AI started with `&`). Permission rules know `systemctl`, `ip`, `apt`, `dnf`, `pacman`,
  `flatpak`, `gsettings`, the clipboard tools and more; keyrings, `.password-store` and Lotus' own `secrets` folder are private.
- **Plugins** say which systems they are for (`os = macos linux`), what they need (`requires`) and can have a command per system.
  Limited plugins run in bubblewrap on Linux; where it cannot start, they are refused – never run unprotected.
- **Images and covers off the Mac:** `/img convert` with ImageMagick, the album cover over MPRIS (playerctl; only real pictures are
  opened), the trash of your desktop (or Lotus' own, in the freedesktop.org format) for deleted Minecraft servers.
- **Fixed on the Mac:** `sips` of macOS 27 rejects `--`; the Minecraft server icon and the image fallback called it that way.
- Local models that Lotus runs itself (MLX) stay Apple silicon only; `lotus ai local` says how to use Ollama or llama.cpp elsewhere.
- Not yet: Windows beyond the first module, `/install` and `/brew` on Linux, Remove BG on Linux. (`/app` works on Linux: it opens the desktop entries of your system.)
- Tests: `tests/test-bash.zsh`, `tests/test-install.zsh` (the installer from start to end: install, again, uninstall, no zsh),
  `tests/test-autocheck.zsh` (which commands auto mode runs without asking); the others run on Linux too.

## 2.23.0 – Live Server and /html, built in

- **Live Server and `/html` are part of Lotus now** – no plugin to install: `/liveserver` and `/html` are there after an update, in `lotus cheatsheet`, in the pets' knowledge and in the website's commands. They are one feature, "Live Server" (`lotus features live off` turns both off). The old `liveserver` plugin is removed the first time Lotus starts after the update – only Lotus' own one, by its `plugin.conf`; a plugin of someone else with that name stays – and what it knew comes along: servers that still run (`/liveserver stop` finds them), the list of documents `/html` made, and its last choice. Lotus says so once. Its files are in `lib/live` and `lib/html`, what they keep in `~/.local/state/lotus/live`
- Live Server answers the phones and computers in the same Wi-Fi: the terminal shows the address for each network the Mac is in and whom it is for – this Wi-Fi, the iPhone whose hotspot the Mac uses, the devices it shares its internet with – and a new one when the Mac changes networks while it runs. Nobody from another network gets an answer (a VPN, AirDrop, an address of the internet), and only the Mac's own names work. `--local` keeps it on this Mac
- `/html`: web pages, style sheets and scripts as Word (.docx), PDF, Text, Markdown, OpenDocument (.odt) or RTF. `/html` takes the page that is open in the browser (Live Server's pages tell it which one is in front); without one it asks – the newest file first, all of the folder, or another file. `/html all` puts every page, style sheet and script into a folder of their own inside the project (`my-site/Word`, the folders as they are); `/html about.html pdf`, `/html css`, `/html *.css` for some of them. `/html … -> txt` works too: the file zsh makes for the `>` goes away again
- As code: the file as it is written, colored like VS Code's light theme – HTML with the CSS and JavaScript in it, CSS, SCSS, JavaScript, TypeScript, JSON – the file's name and a line about it on top, and the number of each line in front of it: a long line that wraps keeps its one number, so line 18 is line 18 of the file. Word, OpenDocument and RTF get A4 pages, a footer with the file and the page, no spell checking in the code. Text is the file itself, byte for byte – for uploads that refuse `.html`
- As a page (`--page`, or the second question): what a visitor reads – headings, paragraphs, lists (numbered as on the page), tables, links, images of the folder (a PNG keeps its transparency), quotes and code – without scripts, styles and what is hidden
- PDFs are written by hand, with the Mac's own Arial and Menlo embedded (only the letters used), text you can copy and search, clickable links, tables that keep their head on the next page and columns as wide as their content needs. A character none of the Mac's fonts has (emoji) is a "?", and /html says how many
- Nothing is written over: a document you changed stays, the new one gets "(2)"; the documents /html made itself are made again, and its folders are never converted again or reloaded by Live Server. Left out of `all`, and said so: images, fonts, minified libraries (`bootstrap.min.css`), hidden files, `node_modules`, links out of the folder
- Python's standard library only (3.9, the one of Apple's Command Line Tools, and newer) – nothing to install, nothing leaves the Mac, no bytecode written into Lotus' folder
- Tests: `zsh tests/run.zsh liveserver html` – Live Server's rules (the Wi-Fi, the folder, the reload), every format of `/html` through Lotus with the documents checked by nothing but Python (every part of a .docx and .odt is XML, every object of a PDF where its table says, the text in it), the page open in the browser, a keyboard choosing, what is never written over, and the old plugin going away; `tests/test-plugin-install.zsh` counts four plugins in `plugins/`

## Also in 3.0.0 – MeshChat (a plugin)

- A new plugin, MeshChat: one chat with everyone around you over Bluetooth Low Energy – no internet, no Wi-Fi, no server, no rooms. Install it with `lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat`, then `/meshchat` on every Mac: they find each other. `/meshchat demo` tries it without a second Mac: two simulated people, one of them a relay away
- A mesh, as far as it goes: every Mac shows every message and passes it on – each message starts with the most the protocol allows, 16 relays – so Macs out of each other's range chat through the ones in between. Each message is shown once, however many paths it takes; a Mac that comes back into range gets what it missed – up to 32 messages from the last 14 minutes. One sender's share is 40 messages at once, then one a second. Links are made and remade by themselves, with retries that slow down (every 5 minutes after 8 failures) and end when the other Mac is gone, and scanning in bursts to spare the battery
- Public, and signed: anyone nearby can read the chat – nothing is encrypted, there is nothing secret to encrypt with – but every message is signed by its sender (Ed25519, Apple's CryptoKit), so no one can write in someone else's name or change a message on the way. Nothing that fails a check is shown or passed on; nothing but the service and a random token is in advertisements
- How far someone is: `/where Grace` – a neighbour from the strength of its Bluetooth signal (≈ 2 m), anyone further along the way through the mesh (you → Ada ≈ 2 m → Grace ≈ 8 m), from the links and signals every Mac lists in its "I am here". Rough estimates, said as such; the line of who is here shows a neighbour's distance (Ada ● 2m)
- The chat: you on top, what is said with its time (⇢1: one relay), who is here and how (● a direct link), Bluetooth and the mesh below. `/who`, `/where`, `/nick`, `/status`, `/quit`; ctrl-c, ctrl-z and a closed window all give the terminal back as it was. `lotus meshchat relay` turns a Mac into a silent relay
- A limited plugin without internet: it sees only its own folder and keeps its history and this Mac's identity in its data folder, readable by you only. macOS asks once whether your terminal may use Bluetooth – Apple's Terminal can ask (its dialog gives no reason), as can iTerm2, Ghostty, kitty and Visual Studio Code; in a terminal app that cannot, MeshChat tries Bluetooth in a separate process first and says which one to use instead of vanishing. `/meshchat doctor` explains a missing permission, Bluetooth that is off, a failed build and failed links. The Swift program is built once into the data folder (Command Line Tools), like Lotus' own AI terminal
- MeshChat 2 replaces the rooms of the first version that was here (room codes, encrypted for the room): there are none any more, and the two versions do not link – each tells the other to update. The rooms of MeshChat 1 stay in the data folder until you delete them; `/meshchat doctor` names the folder
- Tests: `lotus meshchat selftest` – the protocol on a simulated radio (published test vectors, packets and their limits, multi-hop, a chain of 19 Macs for the hop limit, duplicates, fragments, forged and broken packets, floods, out of range and back); `zsh tests/run.zsh meshchat` – through Lotus, built in the sandbox, the chat driven in a terminal; and a workflow that runs both on a Mac. **Not yet tried between real Macs:** the Bluetooth part is built and checked on every change, but has not run on Bluetooth hardware – the test with three Macs is in plugins/meshchat/README.md
- `tests/test-plugin-install.zsh` counts five plugins in plugins/

## 2.22.0 – Image converter

- `/img convert` – images and whole folders into JPEG, PNG, HEIC, AVIF, WebP, TIFF, GIF, BMP, PDF or ICO, with macOS' own image engine (ImageIO). It reads what Preview reads: HEIC from the iPhone, WebP, AVIF, PSD, SVG, JPEG XL, RAW photos …
- A clean screen: a drop zone for images, a folder or the clipboard; then the format (each with what it is good for), the quality (95, 85, 70, 50 – for JPEG, HEIC, AVIF and WebP) and the size (keep, 4K, 2560, Full HD, 1280, 640 px). It remembers your last choice
- While it works, the lotus blooms in your theme's colors with the real progress – the image it is on, its size before and after (3000 × 2000 → 1920 × 1280 · 599 KB → 75 KB), the format, quality and size limit, and how many at a time. Then how many were converted, how much smaller they are and where they are
- Folders: every image in it, into a folder for the new format inside it (`Holiday/WebP`). A single image gets its new file next to it. The originals are never changed, nothing is overwritten (`photo (2).jpg`)
- Photos come out the right way up – also in WebP and AVIF, which do not know the camera's rotation. Camera data stays; transparency turns white in JPEG; an icon becomes a square of at most 256 px; images are made smaller, never larger
- Several images at a time (one per performance core). Ctrl-C stops cleanly and leaves no half file behind
- Without questions: `/img convert <image|folder>… --to webp --quality 80 --max 1920` · `/img formats` shows what this Mac reads and writes
- The converter is a small Swift program (lib/img/Convert.swift) that Lotus builds once; without the Command Line Tools it uses macOS' `sips`
- /zetamac: ← and → move between the digits of your answer, a digit goes where the cursor is – type the last digit first, then the ones before it. ⌫ deletes the digit before the cursor
- A pet's "full for" is rounded to the nearest hour (a second could turn 20 h into 19 h)
- Ctrl-C on the blooming lotus (Remove BG, /convert, /img convert, RSVM) sometimes ended Lotus at once instead of stopping cleanly: it could interrupt a frame while it was drawn, and zsh took the interrupted write for an error. Now it stops, says how far it got and cleans up

## 2.21.0 – Convert blooms

- `/convert` downloads on the progress screen of Lotus: the lotus blooms in your theme's colors with the real progress – the video's title on top, then the step ("Downloading the video", "Downloading the sound", "Putting it together", "Making the MP3", a new frame rate), the bar with percent, MB, speed and time left, all steps, and below what it becomes: MP3 or MP4, the resolution and frame rate, the length and the site. yt-dlp's own lines no longer scroll by; when something fails they still say why. Ctrl-C stops it cleanly
- The update question came back after every yes: on a Mac where Homebrew belongs to another macOS user, `brew upgrade yt-dlp` cannot work, so yt-dlp stayed old. Lotus now says so and offers its own yt-dlp instead – the official macOS build from github.com/yt-dlp, checked against the release's SHA-256 before it is used, in `~/.local/share/lotus/runtime/yt-dlp`. Only /convert uses it, it updates itself, and nothing outside Lotus' folder changes (no sudo)
- Asked only when it helps: /convert compares yt-dlp with the newest release (looked up at most once a day) and offers an update when it is a month behind – never when it is the newest, however old that is. After a "no" or an update that could not be done, it asks again in a week, or when a download fails because of it
- `lotus doctor` says how far yt-dlp is behind the newest, and whether it is Lotus' own
- Done shows the size (KB or MB), and a length of 19 seconds reads 0:19

## 2.20.0 – A math game for the pets

- `/zetamac` – a math game like the Arithmetic Game on arithmetic.zetamac.com: 120 seconds, as many problems as you can. Normal has Zetamac's default ranges – (2–100) + (2–100) and (2–12) × (2–100), subtraction and division as these in reverse – and an answer counts as soon as it is right, without Enter. A bar shows the time running out, your pets watch and eat along with every right answer
- Every right answer is a bite for each of your pets: 15 minutes longer full (10 on easy, 20 on hard), up to two days. After the game one of them eats and says how long it is full now
- `/zetamac 60`, `/zetamac 300 hard`, `/zetamac easy` – any time from 10 to 600 seconds; the best score for each level and time is kept. Enter plays again, Esc goes back
- In `/pets` the game is an entry below your pets, and pets know about it: a hungry one may suggest a round
- A pet's status says how long it stays full ("full for 9 h") instead of when it last ate – a big meal from the game lasts longer than half a day
- Tests: Zetamac's ranges, the food, the best score, and a real game in a terminal – a wrong digit taken back, five right answers, Esc

## 2.19.2 – Deleting a server, made safe

- A move into the Trash that failed (a server on an external disk and too little room on the Mac for the copy) deleted the folder for good anyway and said it was in the Trash. Now a failing move deletes nothing, takes back what it had copied, and says so; a server on another disk goes to that disk's own Trash, or Lotus asks you to delete it in Finder
- A server deleted while it was still preparing (Paper's first start, LotusBridge being built) left the patcher running in the deleted folder – stopping now ends run.zsh's whole process group
- A server started by its own start.command with a restart loop came back from the Trash after the delete. Before deleting, Lotus now looks for anything of the server still running in its folder – java, start.command, run.zsh, the patcher – and stops short until it is gone. A terminal that merely sits in the folder does not count
- A server that cannot be deleted (a link, a folder outside `~/Minecraft`) is said so before anything is stopped, not after the players were kicked
- The settings page: the preview of the server list shows again at 80 × 24, "Supprimer le serveur" and "Borrar servidor" are no longer cut off, and typing a long name shows its end – where the cursor is
- Tests for each of these

## 2.19.1 – Delete a Minecraft server

- A server can be deleted: in its control center under Settings → Delete server, or with `/minecraft` → Delete a server (which does not start it first). Lotus shows what goes – the folder with the world, plugins, settings and log, and its size – and deletes only when you type the server's name
- A running server is stopped first, the world saved; only then its folder goes – to the Trash, so it can come back until you empty it (where there is no Trash, it is removed). q while it is still stopping calls the delete off
- Only a server folder right in `~/Minecraft` is ever deleted: never the Minecraft folder itself, your home folder, a folder without `start.command`, a link, or a server that still runs
- Tests: what may never be deleted, a wrong name, a running server stopped and then deleted, the Trash with two servers of the same name, no Trash, no keyboard; a log test that checked the console before the fake server had written its last line now waits for it

## 2.19.0 – Minecraft control center

- A control center for your Minecraft server: `/mc <name>`, or `/minecraft` → Open a server (a new server opens in it too). Full screen, in your theme's colors, three pages – Tab switches, or 1, 2, 3
- **Stats**: whether it runs and for how long (starting with the spawn area in percent), players online with their ping as bars, how long they are online, game mode, health and world, the TPS and tick time, memory used of what it may use, CPU, the world's size and the address friends join with, then the newest joins, chats and advancements. Next to it a little Minecraft world drifts by – hills of grass, dirt and stone with ores, oaks, flowers, water with lotus flowers, blocky clouds, a square sun and moon with stars at night – drawn in half blocks from the theme's colors, with one figure walking for every player online (a creeper waits when nobody is). It stands still while the server is stopped. Enter on a player: op, deop, kick, ban, creative, survival, whitelist
- **Settings**: the server icon – drag in any picture, Lotus cuts the middle square to 64 × 64 PNG (a grass block in your colors until there is one); the description (MOTD), written the way Java reads it, so umlauts and emoji work; the folder in Finder; plugins. A preview shows the server as friends see it in their list
- **Plugins** (Paper): search Modrinth while you type – only plugins for Paper, Spigot, Bukkit or Purpur and your server's version, the most downloaded first when nothing is typed, more as you scroll. Enter installs the newest release, required plugins come along, every file is checked against its SHA-512 and comes only from Modrinth's own download server; an update replaces the old file. Your own plugin: d and drag the .jar in (a Fabric or Forge mod is named as such and refused). x removes one, its settings folder stays
- **Log**: the console in color – chat, joins, warnings, errors; f shows only chat and players, or only problems; scroll back, End follows again. `/` types a command like in Minecraft, `t` chats as the server, ↑ brings earlier commands back
- The server runs in the background, in its own session: leaving the control center can keep it running (q asks: leave, stop it and leave, or stay), Ctrl-C and a closed window do not stop it, and `/mc <name>` finds it again with its whole log. s stops or starts, r restarts (both ask when players are online), o opens the folder. The Mac stays awake while it runs (`caffeinate`, the display may sleep). Without an accepted EULA it asks for it first; a taken port and a crash are named
- Ping and TPS: only the server knows them. For Paper servers Lotus builds LotusBridge on your Mac – a tiny plugin, compiled with the JDK's javac against the server's own API, that writes one file with the numbers every two seconds, nothing else. Built once per server version; Vanilla servers say that only Paper tells
- A server started some other way (double-clicked `start.command`) is found by its folder and shown from `logs/latest.log`; s stops it with SIGTERM (Minecraft saves first)
- The AI's `minecraft_start` starts the server in the background too and points to `/mc <name>`
- In English, German, French and Spanish
- Tests: a fake server through start, console commands, opening again, stop, crash, the EULA; Vanilla and Paper log lines; server.properties with umlauts and emoji; every page in four window sizes; the world in two themes; a fake Modrinth for search, install, checksums, dependencies and the download address; dragged plugins and mods; building LotusBridge with javac; a server started elsewhere

## 2.18.3 – Live Server

- A new plugin, Live Server – like the one in VS Code. Install it with `lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/liveserver`, then type `/liveserver` in a project folder, in VS Code's terminal too. It serves the folder on this Mac (port 5500, or the next free one), opens `index.html` – or, when there is none, a menu of all the folder's pages with their titles, by folder, with a filter – and reloads the page whenever you save a file. When only CSS changed, just the style sheets swap and the page keeps its place. The terminal shows every change and the files a page asked for that are not there; Ctrl-C stops it
- `/liveserver about.html` opens that page, `/liveserver docs` serves another folder, `--port 8080`, `--no-open`. A second `/liveserver` in the same folder opens the one that runs; `/liveserver stop` stops the ones in other windows
- Only yours: it listens on 127.0.0.1 and answers only to 127.0.0.1 and localhost, serves nothing outside the folder (no `..`, no links that point out of it), no hidden files like `.git` or `.env`, and never your whole home folder. It has full access because it reads the folder you start it in and opens the browser – a limited plugin sees only its own folder. Python's standard library, nothing to install
- Plugins with full access know the folder their command was called in: `LOTUS_PWD` (their programs start in the plugin's own folder)
- Tests: the menu, index.html and folders, parts of a video, reloads over the WebSocket (styles only, then the page), what stays out (`..`, `%2e%2e`, links, hidden files, other host names, the home folder), one server per folder, stop; limited plugins do not learn the folder

## 2.18.2 – Theme Studio

- A new page on the website: the [Theme Studio](https://fanxy13.github.io/homebrew-lotus/studio.html). Pick the eight colors of a theme – start from a built-in one or shuffle – and a start screen and the `/settings` menu change with every color, the logo drawn cell by cell with its gradient like in the terminal. Colors that are hard to read on a dark terminal are marked. A link shares the theme, and the page remembers yours
- Your own themes in Lotus: `lotus themes add <name> <8 colors>` – the line the studio gives you – saves it in `~/.config/lotus/themes.tsv` and uses it at once; it shows up in `/settings` → Theme and `/lotus themes` next to the built-in ones. `lotus themes remove <name>` takes it out again (back to Matcha if it was in use). A built-in theme is never replaced
- Tests: adding with hex or r;g;b colors, the same name again, wrong names and colors, a running shell that sees the new colors, removing

## 2.18.1 – Logo gradient

- The logo fades through the colors of your theme, from top to bottom – in every theme: Matcha goes from yellow over pink to green, Neon from yellow over magenta to cyan, Ocean from mint to blue. `/settings` → Logo gradient, right under Logo in theme colors (on by default; off gives the logo one color again, and it only shows while the logo takes the theme's colors). Your own logo gets it too
- The colors are mixed in OKLab, so the shades in between stay clear (pink to green is no muddy brown), and solid parts get a step every half character
- Tests: the gradient's colors and steps in two themes, solid blocks without gaps

## 2.18.0 – Album covers and new logos

- While a song plays, its album cover takes the logo's place on the start screen: colored character art, two pixels per character in 24-bit color (or the nearest of 256), as big as the logo's room – 48 × 24 characters in a wide window, smaller in a narrow one, never over the info. Always in the cover's own colors, never the theme's. It comes and goes live: another song shows its cover, a pause or the end brings the logo back. `/settings` → Now playing → Album cover instead of the logo (on)
- Two new logos: Apple and the Flag of Earth (Oskar Pernefeldt's seven interlocking rings), drawn with quadrant blocks
- Logos in their own colors: `/settings` → Logo in theme colors (on by default) – off shows the lotus in pink from tip to base, the Apple in its six stripes of 1977 and the flag in blue and white. Your own logo keeps the theme's color
- Block art in Terminal.app: it leaves a thin gap above every block character, which cut pictures into stripes – lit top halves are now drawn as background, so logos and covers are solid
- `/convert`: when yt-dlp could not read a link, Lotus said "private, removed or not supported" and stopped – yt-dlp's real reason was thrown away. Now it says why in yt-dlp's words (also in the log), tries once more by itself (YouTube often refuses once), offers a newer yt-dlp when the site changed, and stops at once for private or removed videos. A message of a single line showed only its first letter
- The pets know about covers and the new logos
- Tests: painting in theme, own and 256 colors, the cover from a picture, which art fits the window, live swaps between cover and logo; `/convert` with a yt-dlp that fails in different ways

## 2.17.1 – Plugin uninstaller

- `lotus plugin uninstall [name …]` (`/plugin uninstall`): a plugin goes again – its folder, its data, its commands, AI tools and start screen line. Lotus shows what goes, with the size of its data, and asks once. The name in any case (`lotus plugin uninstall RSVM`), several at once, or no name for a list to choose them from; `remove` does the same
- The pets know it too
- Tests: uninstalling by name in capitals, a name that is not there, several at once, choosing from the list, without a terminal

## 2.17.0 – Plugin installer and packs

- `lotus plugin installer` (`/plugin installer`): drag one or more plugin folders or packs from the Finder into the window – like Remove BG – or paste a git link (one on the clipboard is installed with Enter alone). Lotus checks each one, shows what it brings and may do, lets you leave some out with the space bar and asks once, naming the plugins with full access; then the next ones
- Plugin packs: a GitHub repository (or a folder) with a `pack.conf` installs several plugins at once with their settings – `plugin = <git URL, <git URL>#<folder> or ./folder> [off]`, `set <plugin>.<KEY> = <value>` (`~` and `{data}` work), `files <plugin> = <folder>`. `lotus plugin install <pack>` shows the pack and every plugin and asks once; a pack never gives a plugin more access than its own `plugin.conf` asks for. `lotus plugin pack <name>` makes a pack from your plugins and their settings, `lotus plugin check <folder>` checks a `pack.conf`, and [packs/examples](packs/examples/pack.conf) installs the three examples at once
- `lotus plugin install` takes several plugins, a folder with plugins in it, and a folder in a git repository (`https://github.com/Fanxy13/homebrew-lotus#plugins/todo`); one repository is fetched once for all of its plugins. `update` keeps a plugin that is off turned off. A plugin's settings have a place now – `$LOTUS_PLUGIN_DATA/settings`, `KEY=value` lines – and ` # …` after a value in `plugin.conf` is a comment, as the guide always showed
- The pets know what is new: what they know about Lotus (`data/pets/lotus.tsv` – plugins, the installer and packs, the AI's plans and `/effort` up to ultra, the web chat's effort slider and code panel, the model on this Mac) for the features that are on, and your plugins – they talk about them, `/help` finds their commands, and they are in the tips. The tips on the start screen work again (they broke off since 2.3). The AI knows the installer and packs too
- RSVM, a plugin made with this ([Fanxy13/RSVM](https://github.com/Fanxy13/RSVM)), 1.1: Lotus' own look – a menu with the arrow keys, drop zones for MP3s (several at once), the background video and the folder, a progress bar for the download and the video, "show it in the Finder"
- Tests: packs (settings, files, on and off, a broken `pack.conf`), choosing from several, a folder of plugins, the installer with dropped folders and paths with spaces, a pack made from your plugins, what the pets know

## 2.16.0 – Plugins

- Plugins: add your own things to Lotus – and install the ones others made. A plugin is a folder with a `plugin.conf` and programs in any language (zsh, sh, Python, Node, Ruby, or any program). It can bring commands (`lotus todo add milk`, `/todo` in a Lotus shell), tools for the AI in `/ai` and the web chat (Lotus checks every value, and a tool that changes something asks first), and a line under the start screen (made in the background, so the start stays fast)
- Two kinds of access, shown before a plugin is installed: limited – the default – runs in a macOS sandbox that sees only the plugin's own folder and data folder, with no internet unless the plugin says `network = yes`, no keychain, no Apple Events, nothing of your files or Lotus' settings and never the AI's API keys; full runs with your rights and Lotus' own functions, is allowed by you, and has to be allowed again whenever one of its files changes
- `lotus plugin` lists them; `new <name> [full]` makes a working plugin to start from, `check` says what is wrong in a `plugin.conf`, `install <folder or git URL>` shows what a plugin brings and may do and asks, `info`, `on`/`off`, `allow`, `update` (git), `remove`. `lotus features plugins off` turns them all off
- Open source and made to share: the guide [PLUGINS.md](PLUGINS.md), three examples in [plugins/](plugins/) – todo (limited: a command, three AI tools, a start screen line), github (limited with the internet, in Python), hello (full: Lotus' own functions) – a new page on the website, and the AI knows how to make a plugin for you
- Tests: making, checking and installing plugins, the sandbox (your files, writing, settings, keychain, Apple Events, API keys, the network with and without `network = yes`, one file given to a tool), full access allowed again after a change, the AI's list of tools and a tool the AI calls, the start screen line, on/off and remove

## 2.15.2 – Memory and pictures

From a `/performance` report of a web chat with Nucifera (two messages, 29 minutes):
- The model on this Mac no longer runs out of memory in a long conversation: mlx kept up to ten conversations in its prompt cache, each a whole conversation – at 37,000 tokens that filled a 24 GB Mac, Metal stopped with "Insufficient Memory" and the answer broke off. Lotus now starts the model server with a cache for four conversations within a sixth of the memory (`--prompt-cache-size 4 --prompt-cache-bytes`)
- A crashed model server is started again: after running out of memory mlx still answered, but every request failed ("generation thread died") until it was started again by hand. Lotus now starts it again by itself and lets the AI go on where it stopped; `/ai`, the web chat and the new `lotus ai local restart` also start a crashed server again, and one that an older Lotus started without the cache limit
- Pictures: `fetch_url` on a picture says it loads and works in `<img src>` – before it failed with "That is not a page or text", and the AI tried address after address. A Wikimedia thumbnail in a width Wikimedia does not make (480 px – it answers 400) gets the address that works, in `fetch_url` and in what `view_page` reports
- When Lotus stops a long thinking and the task has no plan yet, it tells the AI to write one with `plan` – before, it said "do not plan any further", and the AI never made one
- `/performance` names running out of memory, and an unknown prompt size is no longer shown as "-1 tokens"
- Tests: the cache limit, a crashed server and one without the limit started again, `lotus ai local restart`, the message when the model ran out of memory

## 2.15.1 – Fixes from a long run

From a `/performance` report of a website task with Nucifera (23 minutes):
- The Mac stays awake while the AI answers: a long answer of a model on this Mac no longer stalls when the Mac goes to sleep because nobody touches it. Closing the lid on battery still puts it to sleep – `/performance` now measures how long the Mac slept and no longer counts that time as thinking (the report said "thinking took 94% of the time" for 14 minutes of a closed lid)
- The plan stays right: when the AI writes a file of its plan, looks at the page or runs the script, Lotus ticks that step off itself and tells the AI the next one – in the web chat the checklist changes where it is. Before, the AI forgot to tick off, and when Lotus had to stop a thinking it sent the AI back to a step that was already done (it wrote style.css a second time)
- When `view_page` finds nothing to fix, the AI is told the check is done – no more checking in its thinking until it goes in circles
- The last answer in the language of the request: after many steps gpt-oss answered in Spanish. Lotus now names the language of the request in its notes to the AI (the summary when the plan is done, going on)
- Pictures from Wikipedia: it links them at thumb.wikimedia.org with tracking parameters now, so the AI got 250-pixel thumbnails for the page. They are given at 960 pixels again, without the parameters
- `/performance`: the model server's note "Received tools but model does not support tool calling" (on every request with gpt-oss – mlx leaves the tool calls to Lotus) is counted in one line instead of repeated, and a `BrokenPipeError` is named for what it is – a request Lotus ended itself when it stopped a thinking
- Tests: the steps Lotus ticks off itself, the next step it names, the language of the request, the model server's log in the report

## 2.15.0 – Step by step

- The AI works in steps: a bigger task – or several things in one message – starts with a short to-do list, written with a new tool, `plan`: one line per step, in order, each small enough for one or two tool calls. It takes the step marked as in work, does it, ticks it off and marks the next one. The list is shown as a checklist – in the terminal with ✓ and ▸, in the web chat with rings that fill as steps get done – and in `/performance`
- Thinking about one step instead of the whole project: the instructions for every AI (and Nucifera's profile) say to keep the plan in the list, not in long thinking, and each answer of the plan tool names the step to do now. When Lotus has to stop a long thinking, it names the next step of the plan, so the AI goes on there instead of planning everything again
- When the AI stops while its plan still has open steps – and it did not ask you anything – Lotus sends it on to the next one, once per message; it either does it or ticks off what is already done. A plan ticked off in its answer instead of with the tool counts too. A plan belongs to its conversation: `/clear` and another conversation in the web chat start without one. Apple Intelligence keeps its own way of planning
- Measured with Nucifera on a task of three parts (a page, its styles, a Python script that counts its words and is run): planned in four steps, done in 3 min 47 s with 10 tool calls, and its thinking never had to be stopped
- Tests: a plan ticked off in the answer, and a plan with two files that stops after the first – Lotus sends it on, both files are written and the list is ticked off

## 2.14.0 – Code on the right

- In the web chat, Expand on a code block opens it on the right, like in Claude: the whole code with line numbers, scrolling up and down and sideways (the numbers stay), Copy and Download (as `code.py`, `code.html` … by its language). Drag the edge to make it wider or narrower – the browser keeps the width – and Esc or × closes it
- Every file the AI writes or changes gets an Open button in its step: the whole file on the right, not just the first lines – also when you open the conversation again later. Private files such as `.env` are not sent to the page
- Long code blocks in an answer scroll within the chat instead of filling it; on a mid-sized screen the list of conversations steps aside while the code is open, and on a phone the code takes the whole screen
- Tests: the whole written file reaches the browser

## 2.13.1 – Unstuck, and much faster on this Mac

- Much faster with a model on this Mac: every request listed the tools in a different order (a dictionary of Swift has none), so the start of the prompt changed every time and the model server read the whole conversation again for every step – in a long conversation about 40 seconds before it wrote a word. Requests now read the same every time, and mlx reuses what it already read: 77–99% of the prompt from its cache, the first token after about a second instead of 6–8 (gpt-oss 20B, measured)
- `/performance` in `/ai` and in the web chat: the conversation as a report in a `.txt` file – the setup (AI, model and its settings, this Mac), the totals (time, thinking, steps, tokens, how much came from the model's cache, its speed), where Lotus had to step in, what stands out, the whole conversation step by step with the numbers of every model request, and the Lotus and model server logs of that time. The web chat downloads it; `/ai` saves it in Downloads. API keys are never in it
- Every model request is measured – when the server answered, the first token, the time in all, tokens read, from the cache and written – and kept with the answer
- Nucifera: the model on this Mac based on gpt-oss-20b is called Nucifera 20B now, and gets a profile of its own – how it works best in Lotus, measured and improved with a benchmark of 16 tasks (coding, agent work, careful edits, data, reasoning, instructions, German, reading, Lotus tools, the web, safety, memory) – github.com/Fanxy13/nucifera-20b. From 13.3 to 16 of the 16 tasks, in about half the time (42 → 23 minutes)
- The instructions read the same all day (the date without the time), so a model on this Mac reuses them from its cache in every new conversation too; gpt-oss keeps its reasoning level when Lotus lets it go on (changing it made the model read the whole conversation again – a minute in a long one)
- The creativity of a model on this Mac (`lotus ai local settings`) goes with every request: a change counts at once, without starting the model again. When its thinking goes in circles, Lotus gives it more variety for the rest of the answer – low temperatures make gpt-oss repeat itself
- Fixed: `search_files` stopped at 20 matches per file and said "20 matching lines" – the AI took that as the count (there were 32). It now gives the real count, in how many files, and the first 150 lines
- Better on the web: when DuckDuckGo refuses, its plain version is asked; "nothing found" and "the services did not answer" are no longer reported as "is this Mac online?". A page built by JavaScript says so, reading on past the end of a page says there is nothing more, a large JSON file comes with how to process it with a command (curl | python3) instead of 300 KB to read, and `search_files` on a web address points to `fetch_url`. Every AI is told that search results are often old – the newest version comes from the project's own release list – and to say when it could not find something instead of guessing
- `write_file` keeps the line break at the end of a file the AI writes again
- The AI no longer goes in circles: a step it already made – the same tool with the same arguments, nothing changed since – is not run again; the AI is told to use the result it has and take the next step. The third time, Lotus ends the tool use for that answer and the AI says what it did, what is not working and what to try next. Commands and changes may still be repeated on purpose, e.g. running the tests again after a fix
- Thinking without end is stopped: a model on this Mac could think for 20 minutes and more – drafting whole files in its head, or repeating the same sentence over and over (seen: "Now we need to modify script accordingly. Ok." 145 times). When its thinking repeats itself, or gets longer than its effort allows (from about 6,000 characters on quick to 22,000 on ultra – measured with the nucifera-20b benchmark) without acting, Lotus stops it and tells it to act now, with the end of its plan – "↻ It thought for a long time without acting – Lotus lets it go on"
- No more lost files: `write_file` with only the changed part of a long file (434 lines replaced by 2) is not written – the AI is told to change a part with `edit_file` or write the complete file. Writing exactly what a file already has is a "no change", and the AI is told not to repeat it
- gpt-oss keeps its plan from step to step: its thinking now goes back with each tool call, the way its chat template expects it, one call per message – before, it started over after every tool. Other models on this Mac (Qwen …) get theirs back as `reasoning_content`
- When the AI puts the code of the files into the chat instead of creating them, Lotus tells it to write the files – for requests to build or make something, not for "explain" or "show me how"
- Tools by other names work: small models call `open_file`, `bash`, `create_file`, `functions.read_file` or `browser.search`, with `file_path` or `cmd` – Lotus runs the right tool and tells the model its real name, instead of "There is no tool with this name"
- Clearer instructions for every AI: change files with `edit_file`, `write_file` only with complete files, never the same call twice, think briefly and write files directly instead of drafting them in the thinking; ultra spends its time on doing and checking, not on long thinking
- Fixed: after writing a page, "In a browser:" could stay empty – it now names what is wrong (no `<h1>`, images without alt text …)
- A model on this Mac reports how much of the prompt came from its cache (`LOTUS_LOG_LEVEL=debug`), and the context use of `/context` comes from its real token count
- Tests: a long file cut short, the same search again and again, a tool by another name, code in the chat instead of files, thinking in circles, the thinking that goes back with a tool call (for gpt-oss and other models), the same tool list in every request, and the report of `/performance` (web chat and one question)

## 2.13.0 – Follow along

- Follow what the AI is doing in the web chat, like in Claude: its thoughts come in as it thinks – folded to their last lines, all of them with a click, "Thought for 12s" afterwards – every step shows a spinner while it runs and how long it took when it is done, and a line at the bottom of the window says what it is doing right now ("Run npm test", "Searching the web", "Waiting for your answer"), for how long and how many steps so far. The browser tab says it too, and the sidebar marks the conversation it is working in
- Fixed: the stopwatch started again at 0 when you closed the tab or reloaded the page. The times now come from Lotus itself – every event has its time and a page that comes back gets the clock first – so the stopwatch, the thinking and every step show the real times, also after a reload or on another device
- The AI works on when no page is open: the answer is written by the web chat on your Mac, not by the page, so you can close the tab and come back later – only the web chat has to run (it runs in the background until you stop it). A page that comes back picks the answer up where it is; an answer started in another tab or on your phone is followed in the open conversation within a few seconds. The hint under the message box says so while it works
- Statistics in the terminal: `/stats` in `/ai`, or `lotus ai stats` – what the web chat is doing right now (what, since when, how many steps, whether a page follows it) and what the AI did today, in the last 7 days and in all: answers, time working, time thinking, steps, stopped and failed answers, steps by tool, answers per day for two weeks, terminal or web chat, and which AI. Live until `q`
- Only the terminal open is enough: when the web chat asks a question and no page is open, `/stats` and `lotus ai stats` show it and answer it – `y` yes, `a` yes and don't ask again, `n` no (`s`, `o`, `c` for an improved prompt) – and `x` stops the answer
- `/stats` in the web chat shows the same numbers
- The settings button in the web chat is a gear now, not a sun
- Private: the statistics keep only counts and times, never what was asked or answered (`~/.local/state/lotus/ai-stats.tsv`, only you can read it, kept below about 1 MB). What the web chat is doing is in `ai-server.now` next to it, also only for you. The terminal answers with the access key in a header and only from this Mac; it can answer a question or stop the answer, nothing else
- The conversation keeps the thoughts with the answer (at most 40,000 characters each) and joins the pieces of text, so the files stay small
- Fixed: a step of the AI could hang for good after its command had ended – Lotus waited for the end of the program in a way macOS does not always report, most often right after another answer. It now gets the end reported directly; a stopped command gets 3 seconds before it is killed
- Fixed: a command that leaves a program running in the background (`npm run dev &`, `python3 -m http.server &`) no longer keeps the AI waiting until that program ends – the step ends with the command and shows what it printed
- Tests: an answer that goes on after the page is closed, the clock and the thoughts for a page that comes back, the terminal answering a question and stopping an answer (and refused without the key, from a web page, and for anything else), the statistics file and `lotus ai stats`, a command that leaves a program running

## 2.12.0 – Ultra, and it does more

- Fixed: gpt-oss on this Mac stopped working in the middle of longer tasks – with the memory saver on (`lotus ai local settings`), mlx cannot compress the memory of models with a sliding window (gpt-oss, Gemma), and every answer broke off once a conversation reached about 5000 tokens: after a web search or a few files the AI seemed to only think and then do nothing. These models now run without the memory saver, and a model server an older Lotus started that way is started again by itself the next time `/ai` or the web chat starts
- When a model server stops in the middle of an answer, Lotus says so – with the error from its log – instead of an empty answer
- The AI acts instead of asking: the instructions for every AI say to do what was asked right away and completely – write the files, run the commands – instead of asking whether it should, offering it or pasting the code into the chat; where a detail is open it picks a sensible default and says which. Lotus still asks you before anything that needs your permission, as you set it up
- When it still only asks ("Would you like me to create the files?", "Soll ich …?") and did nothing, Lotus tells it to do it – a short line says so. A long answer that ends with a suggestion stays as it is
- Nicer web pages: a clear design with a font pairing, a strong first screen, cards and transitions, real content in several sections – and real photos: `fetch_url` now lists the pictures of a page with their addresses, so the AI can put them into the page or download them, instead of making up addresses
- Fixed: a model on this Mac writing a long file sometimes sent its tool arguments with real line breaks – not valid JSON, so nothing was written. Lotus repairs them now; when they cannot be repaired, the AI is told how to try again (in parts), and a silent stop after that no longer ends the answer with nothing – Lotus lets it go on
- A slider for how hard the AI thinks in the web chat, like the effort setting of Claude: the bars next to the message box open it – quick, balanced, thorough, maximum, ultra – with what each level means. It saves at once (the same `LOTUS_AI_EFFORT` as `/effort` and `/settings`) and counts from the next message; the settings panel has the same slider. `/effort` without a level opens it, the arrow keys move it
- A fifth level, ultra: Claude thinks with its highest effort (`max`, maximum is `xhigh`) and gets room for longer answers. With every AI it also gets instructions to plan, check every result – run it, read it back, look at pages – and go over the request once more before it finishes, and Lotus lets it go on up to six times instead of three when it stops early. In `/ai` (`/effort ultra`), in `/settings` and in `lotus ai local settings` too
- A model on this Mac (`lotus ai local`) gets the thinking level with every message, so a change counts at once without starting the model again
- Fixed: Claude Opus 4.6 and Sonnet 4.6 were sent an effort level they do not know on maximum (`xhigh`, they get `max` now), and Claude Haiku 5.5 was asked for a fixed thinking budget it no longer takes – it thinks adaptively now like the other current models
- Tests: ultra from the browser, the levels in the state, the thinking a model on this Mac gets, the ultra instructions in the web chat and in `/ai`; asking instead of acting, a long answer with an offer, repaired and broken tool arguments, a server that breaks off, the memory saver only for models that can use it (`tests/test-llm.zsh`)

## 2.11.0 – It keeps going

- When the AI stops before it is done, Lotus lets it go on by itself – at most three times per message, with a line that says why, for example "↻ It ran out of room before it was done – Lotus lets it go on (1/3)". In `/ai` and in the web chat, with every AI
- It goes on when it ran out of room (its answer length was used up by thinking or a long file – then it thinks briefly), when it only thought and neither acted nor answered, when it stopped without an answer, when it took very many steps, and when it said what it would do next ("Now I'll create style.css.") and stopped right there after working
- It does not go on when it asks you something or hands over to you ("Let me know if …", "You can now open index.html"); esc or the stop button end it as always. If it still does not get there, it says why – and shows its thoughts when that is all it wrote
- Tests: running out of room once and every time, a step announced and not done, a question to the user

## 2.10.0 – The AI sees the pages it builds

- A new tool, `view_page`: the AI opens a web page of the folder in a real browser – WebKit, the engine of Safari, without a window – at desktop and phone width and gets what a person would notice: the title and structure (headings, links, buttons, forms), errors in the browser console with file and line, files that did not load, styles and scripts that are nearly empty, what is wider than the screen and which element it is, images without alt text, form fields without a label. With `inspect` (a CSS selector) it gets the size, position, colors and font of elements – access to the HTML elements of its page
- Claude also gets a screenshot, so it sees the design. The web chat shows the screenshot in the step (click shows all of it), iTerm2 and WezTerm in the terminal; elsewhere the step names the file
- After the AI writes or changes an HTML, CSS or JavaScript file, Lotus looks at the page by itself and adds what it saw to the result – so every model notices a missing file, an error or a layout that does not fit, also when it does not think of looking
- Instructions for building websites, the same for every AI (`data/ai/system.md` "websites"): semantic HTML, mobile first with grid and flexbox, CSS variables, alt texts and labels, plain HTML, CSS and JavaScript unless you ask for a framework – then look at desktop and phone width and fix what was found until nothing is left
- Safe: the page sees only its folder (served as `lotus-page://`, never private files like `.env`), may load scripts, styles, fonts and images from the internet but cannot send anything (fetch, XHR, WebSockets and beacons are blocked) and cannot navigate away. Looking at a page counts as reading: free in the folder, asks elsewhere. It takes about a second and a half
- Fixed: in the web chat a step that went wrong ("Declined", "3 things to fix") was drawn as a red box instead of a red line
- Tests: rendering (console errors with the line, missing files, too wide on a phone, alt texts, labels), private files and sending blocked, the whole step in the web chat with its screenshot, and the look after writing a page

## 2.9.1

- Fixed: answers showed HTML as text – `<br>` in table cells, `<b>`, `&nbsp;` and the like, which models such as gpt-oss like to write into their Markdown. In the web chat and in `/ai` it now does what it means: `<br>` is a new line (in the terminal a table row stays one row, with " / "), `<b>`, `<i>`, `<u>`, `<sub>`, `<sup>`, `<kbd>`, `<code>` and friends format the text, entities become their characters, style wrappers like `<span style=…>` disappear
- Safe as before: only this short list of tags without attributes is shown as HTML – scripts, images, links and anything with attributes stay text, tags Lotus does not know stay as written (`List<T>`), and code is never changed
- Tests: `tests/test-webmarkdown.zsh` runs the web chat's own Markdown code (with Node.js), and the `/ai` output is checked with an answer full of HTML

## 2.9.0 – Commands and settings in the browser

- Commands in the web chat, like in `/ai`: `/help`, `/new`, `/clear`, `/model`, `/effort`, `/enhance`, `/auto`, `/permissions`, `/settings`, `/memory`, `/context`, `/compact`, `/copy` – a list shows up when you type `/`, ↑↓ and Tab choose
- Settings in the browser (the gear): who answers, thinking, improving prompts, ask first or auto, what the AI may do, what it remembers. They are the same Lotus settings as `/settings` and `/ai` in the terminal; the port, starting with the terminal and other devices stay in the terminal
- It dares more: in the web chat commands follow the same rules as in the terminal now – "Yes, don't ask again" (for one conversation) and auto mode, where it works on its own and asks only when unsure. A switch next to the message box (Ask / Auto) and "Yes, and switch to auto mode" in every question. Deleting, pushing, installing, private files and other folders still ask, and `sudo` never runs
- `/auto` in `/ai` in the terminal too
- Tests: don't ask again for one conversation, auto mode from the browser, deleting still asks, sudo never runs, settings that the browser may not change, memory, context and compact

## 2.8.2

- Fixed: the download speed of `lotus ai local` jumped – 200 MB/s, then half of that, a quarter, down to 0, then up again. Hugging Face delivers models through its Xet storage now, which receives the data in blocks of up to 64 MB and writes the files afterwards, so the model folder grows in jumps. Lotus now counts the bytes that came over the network, as Hugging Face's own library reports them (`lib/ai/download.py`), and shows the average of the last 10 seconds – the amount, the speed and the time left move steadily. With an older library it falls back to the size of the folder, averaged the same way
- The download itself was not slow: the jumps were only on screen (measured: a steady 15–20 MB/s while the display swung between 0 and 200 MB/s)
- Tests: `tests/test-download.zsh` checks the progress line with a stand-in for the download that writes its file only at the end, like Xet

## 2.8.1 – Better prompts

- A new setting improves your prompts before the AI sees them: `/settings` → AI → "Improve prompts", or `/enhance` in `/ai`. The AI first rewrites your message into a clear prompt – the goal, the details and context, the expected result – in your language, keeping every name, file name, path, command, number, code and quote exactly, and adding nothing you did not ask for. A message that is already clear stays as it is
- Three modes: off (the default), on – the improved prompt is shown and sent – and ask – it is shown first, and you choose: Enter sends it, `o` sends yours as typed, Esc sends nothing. Esc while it is being rewritten sends nothing, like during an answer
- The same in the web chat: the improved prompt appears in the page, and in ask mode with the buttons "Send it", "Send mine as typed" and "Cancel"; the header says when it is on
- Messages of three words or fewer ("yes", "push it"), commands and texts longer than 3000 characters go as typed. So does a message whose rewrite fails or takes longer than 30 seconds – nothing gets in your way. The last exchange goes along, so a follow-up like "and now in Python" is rewritten correctly
- The instructions are one section of `data/ai/system.md` ("enhance"), the same for every AI. The rewrite is quick: Claude thinks little for it, and a model on this Mac (gpt-oss) is asked to keep its thinking short – it rewrote a message in a few seconds instead of thinking for a minute
- The conversation keeps what the AI saw – the improved prompt – so later answers stay consistent
- Tests: the modes, the rules for what goes as typed, a failing rewrite, and the choice in the web chat (142 checks in all)

## 2.8.0 – Lotus AI in your browser

### The web chat
- `/ai server start` opens Lotus AI in your browser: a chat page that Lotus serves itself on this Mac, at `http://127.0.0.1:3000`. It is the same AI as `/ai`, not a second one – the AI program of Lotus serves the page (`lotus-ai --serve`) with the same providers (Claude, the model on your Mac, Apple Intelligence, Ollama, an OpenAI-compatible API), the same instructions (`data/ai/system.md`), the same Lotus tools and the same permissions. Answers stream in as they are written
- Your conversations in a sidebar: new chat, history, clear, delete. Markdown with headings, lists, tables and code blocks with a copy button; the steps the AI takes and what they returned; a status line while it works and clear errors when something fails. Enter sends, Shift+Enter makes a new line. Works on a phone and on a computer, in the colors of your Lotus theme
- Questions in the browser: before the AI changes a file or uses a Lotus feature it asks in the page, with the preview – yes, yes and don't ask again, no, or say what to do instead. The levels of the terminal: reading runs, changes ask unless you allowed them or use auto mode, installing an app always asks. From the web every command asks, one by one – no "don't ask again", no auto mode for commands – and tools that need the terminal (the clock, Remove BG) say so instead of running
- A reload or a lost connection does not lose the answer: it goes on, and the page picks it up again. The stop button or esc stops it
- `/ai server` shows the status and a menu; `/ai server start`, `stop`, `restart`, `status` and `open`; `/ai server port 3001` sets the port, kept in the settings. When the port is in use, Lotus says by which program and offers the next free one – it never changes the port without asking
- It never starts by itself. If you want it to, `/settings` → AI → "Web chat: start with terminal" starts it with the first terminal window

### Safe by default
- Only this Mac: it listens on 127.0.0.1. Other devices in your network only when you turn on "Web chat: other devices" – then they need the link with your key, and Lotus tells you that the connection is not encrypted
- Signed in with a key: `/ai server open` opens the page with your access key, which becomes a cookie for this page; without it the page stays locked. The key is in `~/.local/state/lotus/ai-server.key`, readable only by you
- Other web pages cannot use it: the server answers only to its own address (no DNS rebinding), every request needs the page's token in a header, and every change must come from the page itself (Origin). A strict content security policy, no frames, nothing loaded from other servers
- API keys stay in the Lotus program – the browser never sees them. Every request is checked: its size, the conversation, the answer to a question
- The conversations are kept in `~/.local/state/lotus/ai-chats`, one file each, readable only by you. The web chat follows your settings while it runs: permissions changed in `/settings` or `/permissions` count from the next message

### Tests
- `tests/test-aiserver.zsh`: the settings and the port, an occupied port, 127.0.0.1 only, the access key, the host, token and origin checks, a streamed answer with a question answered from "the browser", busy, clear, delete and stop – with a small test model (`tests/fake-openai.py`), so no real AI is needed. 120 checks in all

## 2.7.0 – The AI uses Lotus

### The AI uses Lotus itself
- In `/ai` the AI can now use Lotus: open or install an app, the weather, what is playing and play, pause or skip, change the theme, open the clock, keep the Mac awake, turn features on or off, list and start Minecraft servers, remove an image background. Ask in plain words – "keep my Mac awake for an hour", "open Safari", "change the theme to Midnight"
- One list of tools for every AI in Lotus (`data/ai-tools.tsv`): each tool has a name, a description, checked parameters, a permission level and what happens when it fails. The AI only gets the tools of the features that are on; it cannot call others, and when you ask for a feature that is off it tells you how to turn it on
- Every argument is checked against that list, and Lotus runs its commands with fixed arguments – never a shell string the model wrote. Reading (weather, what is playing, the app catalog) runs right away; changing something asks first, unless you allow it in `/permissions` → "Use Lotus features" or use auto mode; installing an app always asks
- Honest results: a tool reports done, failed, or that you have to decide (for example which of several apps you meant) – the AI only says something worked when Lotus reported it. Tools that need the screen (the clock, Remove BG) get the terminal until you close them, then the conversation goes on
- Apple Intelligence knows when a request is for Lotus and gets only the Lotus tools – its small memory stays free

### One set of instructions for every AI
- The instructions for the AI are in one file now, `data/ai/system.md`, used by Claude, the model on your Mac, Ollama, OpenAI-compatible APIs and Apple Intelligence (a compact version for small models): understand the goal, look before assuming, use what exists, try something different when a step fails, check results, keep your work, and keep apart what was planned, tried, done, failed or needs your permission

### /clock
- A full-screen clock in the colors of your theme with six designs: minimal, big digits, a retro seven-segment display with the unlit segments faintly visible, Matrix rain that forms the digits, a round analog face drawn with braille dots, and a world clock with a day-and-night bar per city
- ←→ or 1–6 switch the design, s turns the seconds on or off, z shows a second time zone, q closes it. The last design is remembered; design, seconds and the world clock's cities are in `/settings` → Clock
- It uses the Mac's own clock and starts no background process – it only draws when the second changes

### Keep awake
- `/caffeine on 90` keeps your Mac awake for 90 minutes with macOS' own `caffeinate` (0: until you turn it off), `/caffeine off` lets it sleep, `/caffeine` shows the status and a short menu. It keeps running when you close the terminal, ends by itself, and the start screen shows it while it is on. Lotus only ever stops the `caffeinate` it started; `lotus uninstall` stops it too
- A feature of its own ("Keep awake"), so it can be turned off like any other

### Fixed
- After a mistyped command, the pet's reaction showed only the row with its eyes. The pet is drawn whole now, the same way as everywhere else; in a very narrow window it is one line of text instead of half a drawing
- Lotus forces a UTF-8 locale for its own process when the terminal sets none – without it the pets, the bloom and the clock lost their block characters
- `lotus features` (without a terminal) started a subshell per feature – measured on an M5: 31.9 ms before, 18.0 ms now. `lotus version` stays at 14.5 ms; an unknown command with its suggestion takes 19.6 ms instead of 18.7 ms (three more commands to compare)

### Tests
- `zsh tests/run.zsh` runs Lotus' tests in an empty home (62 checks): the pet reactions, the clock, keep awake and the AI tools – nothing of your own settings is read or changed
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
