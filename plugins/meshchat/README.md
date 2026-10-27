# MeshChat

A group chat in the terminal with the Macs around you – over **Bluetooth Low Energy**, without internet, Wi-Fi,
accounts or a server. Messages hop from Mac to Mac: two Macs that are too far apart for each other still chat
through the ones in between. A plugin for [Lotus](../../README.md).

```
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat
lotus meshchat create "Bike trip"      # a room, and the code to give to the others
lotus meshchat join MC1-…              # on the other Macs
lotus meshchat                         # or /meshchat in a Lotus shell: the chat
```

```
 lotus / MeshChat  Bike trip  #k7q2m9ab                                          you: Ada·k3f9
 ─────────────────────────────────────────────────────────────────────────────────────────────
 14:02  · Bob is here – a neighbour.
 14:02  · Carol is here – 1 relay away.
 14:02  Bob    Hi everyone
 14:03  Carol  Hello from the other end of the field ⇢1
 14:03  Ada    Meet at the bridge?
 ── here: Bob ● · Carol ⇢1 ───────────────────────────────────────────────────────────────────
 ● Bluetooth on · 1 link · 4 relayed                                     /help · ctrl-c quits
 › _
```

Try it first without a second Mac: `lotus meshchat demo` – the same chat with two simulated people, one of them a
relay away (nothing goes over Bluetooth there, and the screen says so).

**What it is not:** MeshChat talks to other Macs running MeshChat with the same protocol – not to iPhones,
Android phones, Bluetooth devices or other messengers.

## Contents

[What it does](#what-it-does) · [What it needs](#what-it-needs) · [Install and remove](#install-and-remove) ·
[Permissions](#permissions) · [Using it](#using-it) · [How it works](#how-it-works) ·
[Privacy and security](#privacy-and-security) · [Tests](#tests) · [Testing with real Macs](#testing-with-real-macs) ·
[Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Files](#files)

## What it does

- **Rooms with a code.** `create` makes a room and shows its code (`MC1-WADXN-SAV1H-SC5NC-TQF58-M5ZE6-RHMY`);
  whoever has the code can join. The code is made from 128 random bits and has a check, so a typo is caught.
- **Finds the others by itself.** Every Mac advertises and scans; MeshChat connects to the ones in range.
- **A mesh.** Every Mac passes on what it receives to its other neighbours – up to 5 relays (`set hops`, at most 7).
  Duplicates are dropped, so each message shows once however many paths it takes.
- **Encrypted for the room, signed by its sender.** Only Macs with the room's code can read the room, and a
  message cannot be changed on the way or written in someone else's name ([details](#privacy-and-security)).
- **Who is here, and how:** a neighbour (● a direct Bluetooth link), further away (⇢2: two relays), or not heard
  for a while (○). People come and go with a line in the chat.
- **Comes and goes gracefully.** A Mac that moves out of range and back is linked again and gets what it missed in
  the last 14 minutes (up to 32 messages) – each once.
- **History** of every room on your Mac, in the plugin's data folder only.
- **Doctor** for what can go wrong: the terminal's Bluetooth permission, Bluetooth off, the build, failed links.

## What it needs

| | |
|---|---|
| macOS | 11 (Big Sur) or newer – as Lotus |
| Bluetooth | Bluetooth Low Energy: every Mac that runs macOS 11 has it |
| To build it once | Apple's Command Line Tools: `xcode-select --install` (Lotus' `/ai` needs them too) |
| The others | Macs with Lotus and this plugin, a version with the same protocol (1) |
| A terminal app | that may use Bluetooth – Terminal can; [why that matters](#permissions) |

Nothing else: no Homebrew packages, no Swift packages. MeshChat uses what macOS brings – CoreBluetooth for the
radio and CryptoKit for the cryptography.

## Install and remove

```
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat
```

Lotus shows what the plugin may do (**limited – only its own folder**, no internet) and asks. The first
`lotus meshchat` builds the chat from its Swift sources – about a minute, once; again only after an update. The
program is kept in the plugin's data folder, like Lotus keeps its own AI terminal.

```
lotus plugin update meshchat          # the newest version (installed from git)
lotus plugin uninstall meshchat       # the plugin with its data: rooms, codes, history and the build
```

## Permissions

**Lotus: limited access, no internet.** MeshChat runs in Lotus' plugin sandbox: it reads only its own folder,
writes only its data folder (`~/.local/share/lotus/plugins/meshchat`) and may not use the network (`network = no`).
Bluetooth is not the network: CoreBluetooth talks to macOS' Bluetooth service (bluetoothd) over XPC, which the
sandbox does not block. The automated tests on a Mac run the build and a Bluetooth check inside this sandbox, and
CoreBluetooth answers there exactly as outside it (on that CI Mac: "no Bluetooth LE" – it has none). Full access is
not needed – and was not given. (A chat between real Macs inside the sandbox is part of the
[test with real Macs](#testing-with-real-macs); see [Known limitations](#known-limitations).)

**macOS: Bluetooth permission for your terminal app.** macOS gives the Bluetooth permission to apps, and MeshChat
is a program in your terminal: macOS asks about the app it runs in. The first time, it asks
*“Terminal” would like to use Bluetooth* – choose **Allow**. You can change it any time in
**System Settings › Privacy & Security › Bluetooth**. Note what this means: the permission is your terminal app's,
so other command-line programs you start in it may use Bluetooth too. That is how macOS treats all command-line
Bluetooth tools; MeshChat asks for nothing beyond it.

A terminal app has to *declare* that it may use Bluetooth (`NSBluetoothAlwaysUsageDescription` in its
Info.plist). If it does not, macOS does not ask – it ends the program that tries. Before it starts Bluetooth,
MeshChat looks up which app it runs in and reads its Info.plist; if the app does not declare Bluetooth use,
MeshChat says so instead of being ended (`--force` tries anyway). `lotus meshchat doctor` shows all of it. Should
macOS end MeshChat anyway, the terminal is put back as it was and the doctor is named.

MeshChat's own program also carries an Info.plist with that declaration (linked into it when it is built). macOS
uses it only when it asks about MeshChat itself, which is not the case when you start it from a terminal.

**No helper app, nothing in the background.** A separate app bundle would get a Bluetooth permission of its own
(instead of the terminal's), but it would have to be launched apart from the terminal and talk to the chat through
some channel, and it would keep running unless stopped. MeshChat avoids all of that: the chat is one program in
your terminal window, Bluetooth runs only while it is open, and closing it – `/quit`, ctrl-c, closing the window –
ends everything; macOS stops advertising and scanning with the process.

## Using it

```
lotus meshchat                        the chat in your last room – the first time: create one, join one, or the demo
lotus meshchat create [name]          a new room; shows the code
lotus meshchat join <code>            join with a code (case, dashes and spaces do not matter; O and I are read as 0 and 1)
lotus meshchat rooms                  your rooms · open <room> · invite [room] · leave [room] · history [room]
lotus meshchat nick <name>            your name in the chat (asked the first time)
lotus meshchat set hops 1–7           how many relays your messages may take (5)
lotus meshchat set links 1–8          Bluetooth links at most (8)
lotus meshchat set relay on|off       also pass on other rooms' messages – unread (off)
lotus meshchat relay                  a Mac that only passes messages on, unread, to extend the range
lotus meshchat doctor                 permissions, Bluetooth, the build, failed links
lotus meshchat demo                   the chat with two simulated people
lotus meshchat selftest               the protocol tests on this Mac
```

In the chat:

| | |
|---|---|
| `/who` | who is here: ● neighbour, ⇢2 two relays away, ○ not heard for a while – with their fingerprint |
| `/invite` | the room code, to give to others |
| `/nick <name>` · `/room` · `/status` | your name · the room and your fingerprint · Bluetooth and the mesh |
| `/rooms` · `/open <room>` · `/join <code>` · `/create <name>` | other rooms, without leaving the chat |
| `/leave` | leave the room: its code and history are deleted from this Mac (asks first) |
| `/quit`, ctrl-c, ctrl-d | close the chat – the room stays; others see that you left |
| ↑ ↓ · PgUp PgDn · Tab · `//text` | your last lines · scroll · complete a command · send a line starting with / |

Ctrl-Z suspends the chat (`fg` brings it back). One chat at a time on a Mac.

## How it works

```
 ┌── your Mac ─────────────────────────────────────────────┐
 │ meshchat.zsh   builds Sources/*.swift once, runs it     │  Lotus plugin sandbox:
 │ ChatApp        screen, keys, commands, history          │  its own folder, its data folder, no network
 │ MeshNode       links · handshake · flooding · rooms     │──── one queue; the radio calls it there
 │ RoomCrypto     ChaCha20-Poly1305 · Ed25519 (CryptoKit)  │
 │ BLETransport   CoreBluetooth: central + peripheral      │  (SimTransport in tests and the demo)
 └──────────────┬──────────────────────────────────────────┘
                │ GATT: frames ≤ 512 bytes
        other Macs with MeshChat (each one central and peripheral)
```

### Bluetooth

Every Mac is both a **peripheral** and a **central**:

- As a peripheral it publishes one GATT service, `31FF69C7-51D3-4241-AD2F-A4ADB116CD77`, with two
  characteristics: **RX** `6292E318-…-3A6EF318B275` (write without response – others write frames to it) and
  **TX** `A4F81D3A-…-98BD9B97B79C` (notify – it sends frames to the Macs subscribed to it). It advertises only the
  service UUID and a name `mc` + 8 hex digits – a random token, new at every start. No names, no messages, no room
  codes, nothing of the room in advertisements.
- As a central it scans for that service, connects, subscribes to TX and writes to RX.

One connection is one **link**, whichever Mac made it. When two Macs see each other, the one with the smaller
token connects; the other waits 8 seconds before it tries itself (in case it is seen but cannot see). Should both
connect at once, the link whose central has the smaller session is kept and the other closed – both Macs decide
alike. A peripheral cannot end a connection in CoreBluetooth; when it closes a link, it ignores it, and the other
Mac closes it when it goes silent.

**Connections are managed, not retried forever:** a connection attempt has 15 seconds, the handshake 10; a Mac
that does not answer (or never completes the handshake) is tried again after 2, 4, 8 … 60 seconds, after 8 failures
in a row only every 5 minutes, and only while it is still heard advertising – a Mac not heard for 2 minutes is
forgotten. A link that worked and broke is tried again after 2 seconds. A link silent
for 45 seconds is closed (quiet links are pinged every 15). At most 8 links (`set links`); when full, the Mac stops
advertising and scanning.

**Scanning costs battery,** so it runs in bursts: nearly always while there is no link (restarted every 27 seconds
so Macs already seen are reported again), 10 seconds of every 30 once linked, never when full.

### Link frames

Every GATT write or notification is one frame: `[link version 1][kind]` and then

| Kind | | |
|---|---|---|
| HELLO | `[lowest][highest protocol version][8 session][2 largest packet][flags][software]` | first thing on a link |
| DATA | `[2 sequence][index][count][a part of a packet]` | a mesh packet, cut to the link's size |
| PING / PONG | – | a quiet link still there? |
| BYE | `[reason]` | leaving · incompatible · a second link · full |

A frame holds at most what the link allows (`maximumWriteValueLength`, `maximumUpdateValueLength`: 20–512
bytes). Packets are cut into up to 255 parts and put back together in any order, each part once; at most 8
packets may be half done per link, for 15 seconds, and none grows over 2048 bytes. Frames wait in a queue per link
while it is busy (the flow control of writes without response and of notifications).

### Mesh packets and routing

```
[version 1][type 1][flags][ttl][hops][8 message ID][8 room tag][8 time, ms][12 nonce][ciphertext][16 tag]
```

Routing is **managed flooding** – no routing tables, nothing to set up:

1. A new message goes to every neighbour, with `ttl` = your hop setting (5) and `hops` = 0.
2. A Mac that receives a packet looks at its ID: seen in the last 30 minutes (up to 4096 IDs) → dropped. That
   stops loops and the copies that arrive over a second path.
3. Otherwise it opens it with the room key and checks the sender's signature and the time: older than 15 minutes
   or more than 10 minutes in the future → refused (with a word about the clocks). A packet that fails is dropped,
   **never passed on**, and its ID is not remembered – a forged copy cannot keep the real message out.
4. It shows the message and passes the packet to all its *other* neighbours with `ttl − 1` and `hops + 1`.
   `ttl` 0 is not passed on; `ttl + hops` can never be more than 7.
5. A neighbour that connects gets the room's last 32 packets from the last 14 minutes (so they are still fresh
   when they arrive). A Mac that was out of range for a moment catches up, and the duplicate check keeps everyone
   else from seeing them twice.

Each link takes at most 40 packets (and 300 frames) at once and 15 (150) a second; a flood beyond that is dropped.
A Mac in another room does not pass your room's packets on – it cannot check them. A relay
(`lotus meshchat relay`, or `set relay on`) does pass on other rooms' packets, unread and also rate-limited, to
extend the range.

**Limits of this routing:** every Mac in the room carries every message (fine for a chat of a few dozen people,
not for thousands); there are no delivery receipts; a message reaches only who is in reach within its hops while
it is fresh; and links are made to any MeshChat Mac, so many Macs of *other* rooms nearby can take up link slots.

### Inside a packet

```
[kind: chat 1 · presence 2 · bye 3][flags][32 sender's public key][8 session][nickname] …kind… [64 signature]
```

Presence ("I am here", every 30 seconds and when a Mac joins: "who is here?") carries the room's name, so whoever
joins with only the code learns it from the others.

### Versions

Every layer says its version, so a newer MeshChat is recognized instead of misread: link frames, the protocol
range in HELLO (a Mac with no version in common is told so and shown as "a newer/older MeshChat nearby"), packets,
room codes (`MC1-`; an `MC2-` code asks you to update), and the files in the data folder (rooms have a format;
one written by a newer MeshChat is used but never rewritten, a damaged one is left alone and named).

## Privacy and security

**What is protected.** Everything said in a room – messages, names, the room's name – is encrypted with
ChaCha20-Poly1305 under a key derived from the room code (HKDF-SHA256), and authenticated: a changed bit, a changed
header field or another room's key and it is refused. Every message is signed (Ed25519) with the sender's key for
that room, so no one can write in someone else's name or change what they wrote. All of it is Apple's CryptoKit;
nothing cryptographic is self-made. Room codes come from the system's cryptographic random generator.

**Who can read a room: everyone with its code.** Each of them can read everything said in the room while they are
in it – and the last 15 minutes before, which the others pass on. Give the code only to whom it is for. Leaving a
room (or uninstalling) deletes it from *your* Mac; it does not take anything back from the others, and it does not
lock anyone out – for that, make a new room.

**Names are not identities.** Anyone in the room can choose any name. The four letters after a name (`Ada·k3f9`)
come from that person's key in this room and cannot be faked – check them in `/who` when two have the same name.
Your key is different in every room, so rooms cannot be linked to the same person by it.

**What anyone nearby can see** (with a Bluetooth scanner, or by connecting): that MeshChat runs on a Mac (the
service), its token, its Bluetooth address – and the Mac's own name, which macOS shows to Bluetooth devices that
connect, as for any Bluetooth use – and on a link: when and how much is sent, message IDs, times, hop counts and an
8-byte room tag, which tells which packets belong to the same room. Not what is said, not who says it, not the
room's name or code. Links are not encrypted by Bluetooth itself (Macs would have to pair); the room's encryption
is what protects the content.

**What this is not.** Not end-to-end encryption between two people: the room shares one key. There is no forward
secrecy – whoever has the code (or gets it later) can read packets recorded before. Codes are not rotated. Bluetooth
can be jammed, and a member can flood the room (rate limits bound what reaches each Mac).

**On your Mac.** Room codes and history are kept in plain files in the plugin's data folder, readable only by your
user (folders 0700, files 0600) – FileVault protects them when the Mac is off. Codes, keys and messages are never
written to the log (`events.log` has links and errors only). No internet – Lotus' sandbox enforces it – no
analytics, no accounts, no server. The AI of Lotus has no tools for MeshChat, so it never reads your chats.

## Tests

**Automated – the protocol on a simulated radio.** `lotus meshchat selftest` builds `Tests/*.swift` with the
plugin's sources and runs them (no XCTest needed). They cover:

- frames, packets and what is inside: round trips, and refusal of cut, oversized, wrong-version, wrong-hop and
  random packets (2000 random ones without a crash)
- cryptography against published vectors (SHA-256, HKDF RFC 5869, ChaCha20-Poly1305 RFC 8439, Ed25519 RFC 8032);
  wrong keys, changed bits, changed header fields and signatures in someone else's name are refused
- room codes: format, typos, swapped letters, wrong length, newer versions, how people type them
- fragments: every link size from 20 to 512 bytes, any order, twice, interleaved, limits against a hostile
  neighbour; duplicate IDs remembered for 30 minutes
- the mesh, with the real `MeshNode` on `SimTransport`: two Macs, **A reaching C through B when A and C cannot hear
  each other**, each message once in a dense mesh, the hop limit on a chain of 8, old/future/replayed messages,
  forged packets that are neither shown nor relayed nor able to block the real one, floods, other rooms and relay
  mode, **out of range and back with catch-up and no duplicates**, two Macs connecting at once, other protocol
  versions, who is here/away/gone, Bluetooth off and on, long messages over 20-byte frames, doubled and lost frames,
  link limits, a restarted Mac
- storage: settings next to a pack's, the identity, rooms of an older, the current and a newer format, damaged
  files, history with damaged lines, trimming, permissions, one chat at a time
- the chat's screen: the line editor (words, history, pastes with control characters, the 1000-byte limit),
  wrapping with wide characters, and whole frames that fit the window at eight sizes from 20 × 6 to 200 × 50

**Automated – the plugin in Lotus.** `zsh tests/run.zsh meshchat` (Lotus' own tests, on a Mac): installs it as
limited, builds it **inside the plugin sandbox**, runs the selftest with CryptoKit, makes and joins rooms, checks
the files and their permissions, drives the chat in a terminal (the demo: types a message, `/who`, ctrl-c) and
checks the terminal is given back, the doctor, leaving, uninstalling. The workflow
[`.github/workflows/meshchat.yml`](../../.github/workflows/meshchat.yml) runs all of it on a Mac on every change,
and builds with every warning shown – a CoreBluetooth delegate method with a wrong signature would compile and
silently never be called, so the build fails on "nearly matches" warnings.

**What the automated tests do not show:** that Bluetooth works between real Macs. The simulated radio behaves
like CoreBluetooth where the mesh relies on it, but it is not CoreBluetooth, and CI Macs have no usable Bluetooth.
The real radio (`BLETransport.swift`) is compiled on every change, not exercised. Test it with the steps below.

## Testing with real Macs

Three Macs (A, B, C) with Lotus, the plugin and Bluetooth on; MeshChat in Terminal on each. Run
`lotus meshchat doctor` on each first – it should end with **✓ Ready**.

1. **A creates a room:** `lotus meshchat create "Mesh test"`. Note the code; the chat opens.
2. **B joins:** `lotus meshchat join <code>`. Within ~15 seconds both show "… is here – a neighbour", ● in the
   list, and `/who` says "a direct Bluetooth link". Write on both – each message appears on the other once.
3. **C connects through B – and not to A.** Either place C out of A's range with B between them (Bluetooth reaches
   about 10 m indoors, much less through walls and people; try separate rooms or 30 m outdoors), or force the
   topology in one room: start B, then A with `lotus meshchat --links 1` and wait until A shows B, then C with
   `lotus meshchat --links 1` – A and C each take one link, and A's is already taken by B. In A's `/who`, C must show
   **⇢1** (one relay away), not ●.
4. **A writes; C receives it through B,** marked ⇢1. C answers; A receives it ⇢1. B shows both, and B's `/status`
   counts them as relayed.
5. **No duplicates:** write a few messages on each Mac; every message appears exactly once on every Mac (`/status`
   shows "copies dropped" counting up when there are several paths).
6. **Disconnect and reconnect:** turn Bluetooth off on B (Control Center) for ~20 seconds. A and C show that the
   link ended and – with only B between them – lose each other after a while (○, "not heard for a while"). While B
   is off, write something on A. Turn Bluetooth on again on B: B links again within ~30 seconds, B receives A's
   message once (catch-up), C too, and the chat goes on. Nothing crashes; quit with ctrl-c, start again – the
   history is there, nothing twice.

Also worth trying: ctrl-c and ctrl-z in the chat (the terminal must look as before), a long message (fragmented),
`lotus meshchat relay` on B in step 3 instead of the chat, and `/leave`.

## Troubleshooting

| What you see | What to do |
|---|---|
| "… does not declare Bluetooth use" | Your terminal app cannot get the permission. Run MeshChat in Terminal (Applications › Utilities). `--force` tries anyway – macOS may then end it. |
| "MeshChat was ended by signal 6/9" right after the start | macOS ended it over the Bluetooth permission. `lotus meshchat doctor`; use Terminal. |
| "Bluetooth not allowed" | System Settings › Privacy & Security › Bluetooth → turn on your terminal app, restart the terminal. |
| "Bluetooth is off" | Control Center or System Settings › Bluetooth. MeshChat goes on by itself when it is on. |
| "No one else is here yet" | The others need MeshChat open in the **same room** (same code), Bluetooth on, within reach. `lotus meshchat doctor` on each Mac; the "Links" line shows failed connections. |
| "A Mac nearby runs a newer/older MeshChat" | `lotus plugin update meshchat` on the older one. |
| "Ignored a message … the clocks differ" | Set the date and time automatically on both Macs. |
| "MeshChat could not be built" | `xcode-select --install`; `lotus meshchat doctor` shows the compiler's first errors; the whole log is in the data folder (`build.log`). |
| "MeshChat is open already in another window" | One chat per Mac – close the other one. |
| Someone has the same name as you | Compare the four letters after the dot in `/who`. |

## Known limitations

- **Macs only**, and only with MeshChat – no iPhone, Android or other Bluetooth chat apps.
- **Not tested on Bluetooth hardware by its author.** The protocol, the mesh, the encryption, the chat and the
  build in Lotus' sandbox are tested automatically (above); the CoreBluetooth radio compiles on every change but
  was not run between real Macs. Please run the [test with three Macs](#testing-with-real-macs) and report what you
  find.
- The Bluetooth permission is the terminal app's (see [Permissions](#permissions)); terminal apps that do not
  declare Bluetooth use cannot run it.
- The chat runs while it is open: no messages arrive when it is closed or the Mac sleeps. Missed messages come only
  from neighbours that still have them – the last 32, from the last 14 minutes.
- One room per chat window, one chat per Mac. At most 8 Bluetooth links; Bluetooth's range indoors is short.
- No delivery receipts, no private messages, no files – text up to 1000 bytes per message.
- Clocks that differ by more than 10 minutes make messages look old or early, and they are refused.
- No forward secrecy, no key rotation, metadata visible nearby ([Privacy and security](#privacy-and-security)).

## Files

| | |
|---|---|
| `plugin.conf` | the plugin: `lotus meshchat`, limited access, no network |
| `meshchat.zsh` | builds the Swift program once (in the data folder), runs it, `doctor` and `selftest` |
| `Info.plist` | linked into the program: its Bluetooth usage description |
| `Sources/Wire.swift` · `Bytes.swift` | the protocol on the wire, strict decoding, texts made safe for the terminal |
| `Sources/Room.swift` · `Seal.swift` · `CryptoKitBackend.swift` | room codes and keys · sealing and opening packets · CryptoKit |
| `Sources/Mesh.swift` · `Fragments.swift` · `Dedup.swift` | the mesh: links, routing, presence · fragments · duplicates |
| `Sources/Transport.swift` · `BLETransport.swift` · `SimTransport.swift` | the radio · CoreBluetooth · simulated (tests, demo) |
| `Sources/ChatApp.swift` · `ChatView.swift` · `Terminal.swift` | the chat, its screen, the terminal |
| `Sources/Store.swift` · `Doctor.swift` · `Demo.swift` · `App.swift` | data folder · doctor · demo · the command |
| `Tests/*.swift` | the protocol tests (`lotus meshchat selftest`) |

In the data folder (`~/.local/share/lotus/plugins/meshchat`): `settings`, `identity`, `rooms/<id>/room.json` and
`history.jsonl`, `events.log`, and `bin/` with the built program.
