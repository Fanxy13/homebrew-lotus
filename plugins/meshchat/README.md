# MeshChat

One chat in the terminal with everyone around you – over **Bluetooth Low Energy**, without internet, Wi-Fi, accounts,
rooms or a server. Every Mac with MeshChat shows every message and passes it on: two Macs that are too far apart for
each other still chat through the ones in between, as far as there are Macs to pass it on. A plugin for
[Lotus](../../README.md).

```
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat
lotus meshchat                         # or /meshchat in a Lotus shell: the chat – on every Mac, nothing else to do
```

```
 lotus / MeshChat  everyone nearby  public                                        you: Ada·k3f9
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

**It is public.** There are no rooms and nothing is encrypted: whoever is nearby with MeshChat – or with a Bluetooth
scanner – can read what you write. Messages are signed, so no one can write in your name or change what you wrote.

**What it is not:** MeshChat talks to other Macs running MeshChat 2 – not to iPhones, Android phones, Bluetooth
devices or other messengers.

## Contents

[What it does](#what-it-does) · [What it needs](#what-it-needs) · [Install and remove](#install-and-remove) ·
[Permissions](#permissions) · [Using it](#using-it) · [How it works](#how-it-works) ·
[Privacy and security](#privacy-and-security) · [Tests](#tests) · [Testing with real Macs](#testing-with-real-macs) ·
[Troubleshooting](#troubleshooting) · [Known limitations](#known-limitations) · [Files](#files)

## What it does

- **One chat with everyone nearby.** No rooms, no codes, nothing to set up: open MeshChat on each Mac and they find
  each other.
- **Finds the others by itself.** Every Mac advertises and scans; MeshChat connects to the ones in range.
- **A mesh, as far as it goes.** Every Mac passes on what it receives to its other neighbours. Every message starts
  with the most the protocol allows – 16 relays – so it reaches every Mac that is connected through others.
  Duplicates are dropped, so each message shows once however many paths it takes.
- **Signed by its sender.** A message cannot be changed on the way or written in someone else's name
  ([details](#privacy-and-security)) – but it is not secret.
- **Who is here, and how:** a neighbour (● a direct Bluetooth link), further away (⇢2: two relays), or not heard
  for a while (○). People come and go with a line in the chat.
- **Comes and goes gracefully.** A Mac that moves out of range and back is linked again and gets what it missed in
  the last 14 minutes (up to 32 messages) – each once.
- **One person cannot flood everyone:** each sender's share is 40 messages at once, then one a second; the rest is
  dropped and not passed on.
- **History** on your Mac, in the plugin's data folder only.
- **Doctor** for what can go wrong: the terminal's Bluetooth permission, Bluetooth off, the build, failed links.

## What it needs

| | |
|---|---|
| macOS | 11 (Big Sur) or newer – as Lotus |
| Bluetooth | Bluetooth Low Energy: every Mac that runs macOS 11 has it |
| To build it once | Apple's Command Line Tools: `xcode-select --install` (Lotus' `/ai` needs them too) |
| The others | Macs with Lotus and this plugin, MeshChat 2 (protocol 2) – MeshChat 1, with rooms, does not mix with it |
| A terminal app | that can ask for Bluetooth – Terminal, iTerm2, Ghostty, kitty, Visual Studio Code; [why](#permissions) |

Nothing else: no Homebrew packages, no Swift packages. MeshChat uses what macOS brings – CoreBluetooth for the
radio and CryptoKit for the signatures.

## Install and remove

```
lotus plugin install https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat
```

Lotus shows what the plugin may do (**limited – only its own folder**, no internet) and asks. The first
`lotus meshchat` builds the chat from its Swift sources – about a minute, once; again only after an update. The
program is kept in the plugin's data folder, like Lotus keeps its own AI terminal.

```
lotus plugin update meshchat          # the newest version (installed from git)
lotus plugin uninstall meshchat       # the plugin with its data: history, this Mac's identity and the build
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

Whether a terminal app *can* ask depends on the app – this was checked on macOS 14.8, 15 and 26.6 (the macOS
runners of GitHub Actions, reading each app's Info.plist and macOS' own permission log):

| Terminal app | Bluetooth for programs in it |
|---|---|
| Terminal (Apple) | **yes** – it declares no Bluetooth use, but macOS lets it ask anyway (it holds `com.apple.private.tcc.allow-prompting`). Its dialog therefore shows no reason: it is MeshChat asking. |
| iTerm2, Ghostty, kitty, Visual Studio Code | **yes** – they declare Bluetooth use (`NSBluetoothAlwaysUsageDescription`) |
| WezTerm, Warp | **no**, as far as can be told – they declare none, and macOS ends a program that starts Bluetooth in such an app (not tried here: MeshChat checks it before it starts) |

Before it starts Bluetooth, MeshChat looks up which app it runs in. With one that can ask, it goes ahead. With any
other, it first starts Bluetooth in a separate process for a second: should macOS end that one, MeshChat says which
terminal to use instead of vanishing. `lotus meshchat doctor` shows all of it. Should macOS end MeshChat anyway,
the terminal is put back as it was and the doctor is named.

MeshChat's own program also carries an Info.plist with a Bluetooth usage description (linked into it when it is
built). macOS uses it only when it asks about MeshChat itself, which is not the case when you start it from a
terminal.

**No helper app, nothing in the background.** An app of its own would get a Bluetooth permission of its own, but it
would have to be started by macOS apart from the terminal – outside Lotus' sandbox (in a test, macOS did not even
start such an app when a program in the sandbox asked) – and talk to the chat through some channel. MeshChat
avoids all of that: the chat is one program in your terminal window, Bluetooth runs only while it is open, and
closing it – `/quit`, ctrl-c, closing the window – ends everything; macOS stops advertising and scanning with the
process.

## Using it

```
lotus meshchat                        the chat (the first time: what it is, and your name)
lotus meshchat history                what was said while your chat was open (-n 50: the last 50)
lotus meshchat nick <name>            your name in the chat
lotus meshchat set links 1–8          Bluetooth links at most (8)
lotus meshchat relay                  a Mac that only passes messages on – shows nothing, keeps nothing, says nothing
lotus meshchat doctor                 permissions, Bluetooth, the build, failed links
lotus meshchat demo                   the chat with two simulated people
lotus meshchat selftest               the protocol tests on this Mac
```

In the chat:

| | |
|---|---|
| `/who` | who is here: ● neighbour, ⇢2 two relays away, ○ not heard for a while – with their fingerprint |
| `/nick <name>` · `/status` | your name · Bluetooth, the mesh, what was refused, where the history is |
| `/clear` | an empty screen (the history stays) |
| `/quit`, ctrl-c, ctrl-d | close the chat; the others see that you left |
| ↑ ↓ · PgUp PgDn · Tab · `//text` | your last lines · scroll · complete a command · send a line starting with / |

Ctrl-Z suspends the chat (`fg` brings it back). One chat at a time on a Mac.

## How it works

```
 ┌── your Mac ─────────────────────────────────────────────┐
 │ meshchat.zsh   builds Sources/*.swift once, runs it     │  Lotus plugin sandbox:
 │ ChatApp        screen, keys, commands, history          │  its own folder, its data folder, no network
 │ MeshNode       links · handshake · flooding · who's here│──── one queue; the radio calls it there
 │ Signing        Ed25519 signatures (CryptoKit)           │
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
  service UUID and a name `mc` + 8 hex digits – a random token, new at every start. No names and no messages in
  advertisements.
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
[version 2][type 1][flags][ttl][hops][8 message ID][8 time, ms][the message][64 signature]
```

Routing is **managed flooding** – no routing tables, nothing to set up:

1. A new message goes to every neighbour, with `ttl` = 16 (the most there is) and `hops` = 0.
2. A Mac that receives a packet looks at its ID: seen in the last 30 minutes (up to 4096 IDs) → dropped. That
   stops loops and the copies that arrive over a second path.
3. Otherwise it checks the sender's signature, the sender's share (40 at once, then one a second) and the time:
   older than 15 minutes or more than 10 minutes in the future → refused (with a word about the clocks). A packet
   that fails is dropped and **never passed on**; a forged one's ID is not remembered – a forged copy cannot keep
   the real message out.
4. It shows the message and passes the packet to all its *other* neighbours with `ttl − 1` and `hops + 1`.
   `ttl` 0 is not passed on; `ttl + hops` can never be more than 16. The ID check already makes every Mac send a
   message only once; `ttl` is the second line, should that ever fail.
5. A neighbour that connects gets the last 32 packets from the last 14 minutes (so they are still fresh when they
   arrive). A Mac that was out of range for a moment catches up, and the duplicate check keeps everyone else from
   seeing them twice.

Each link takes at most 40 packets (and 300 frames) at once and 15 (150) a second; a flood beyond that is dropped.
A relay (`lotus meshchat relay`) is a Mac that does all of this but says nothing itself: it does not announce
itself, so it is not in anyone's list.

**Limits of this routing:** every Mac carries every message (fine for a chat of a few dozen people, not for
thousands); there are no delivery receipts; a message reaches only who is in reach – within 16 relays – while it is
fresh.

### Inside a packet

```
[kind: chat 1 · presence 2 · bye 3][flags][32 sender's public key][8 session][nickname] …kind… [64 signature]
```

The signature (Ed25519) covers `"MeshChat v2"`, the header with `ttl` and `hops` set to 0 – the only two fields
relays change – and the whole message. Presence ("I am here", every 30 seconds and when a Mac joins: "who is
here?") carries how many links the sender has.

### Versions

Every layer says its version, so another MeshChat is recognized instead of misread: link frames, the protocol range
in HELLO (a Mac with no version in common is told so and shown as "a newer/older MeshChat nearby"), and packets.
MeshChat 1 had rooms and spoke protocol 1; MeshChat 2 speaks protocol 2 – the two do not link, and each says the
other needs an update. MeshChat 1's rooms in the data folder are left as they are; the doctor names the folder.

## Privacy and security

**Public by design.** There are no rooms and nothing is encrypted: everything you write – your name and your
messages – goes to every Mac with MeshChat nearby, and each one passes it on, up to 16 relays far. Anyone nearby
with MeshChat can read it; so can anyone with a Bluetooth scanner who connects, and anyone who records the radio.
Write only what you would say aloud in the room.

**What is protected: who wrote what.** Every message is signed (Ed25519) with its sender's key; a changed letter, a
changed time or ID, or someone else's key put in, and it is refused – not shown, not passed on. So no one can write
in your name or change what you wrote on the way. All of it is Apple's CryptoKit; nothing cryptographic is
self-made. The key comes from 32 random bytes of the system's cryptographic random generator (`identity`).

**Names are not identities.** Anyone can choose any name. The four letters after a name (`Ada·k3f9`) come from that
person's key and cannot be faked – check them in `/who` when two have the same name. Your key stays the same as
long as your `identity` file does: the others recognize you the next time – and so can anyone listening, over
days. Uninstalling (or deleting `identity` in the data folder) gives you a new one.

**What anyone nearby can see:** everything said, by whom (name and fingerprint), when, how far it came; that
MeshChat runs on a Mac (the service), its token, its Bluetooth address – and the Mac's own name, which macOS shows
to Bluetooth devices that connect, as for any Bluetooth use. Links are not encrypted by Bluetooth itself (Macs would
have to pair).

**What this is not.** Not private, not end-to-end encrypted, no private messages. Bluetooth can be jammed. Rate
limits bound what one sender – and one link – can push through, but someone with many keys and Macs can still
crowd the chat.

**On your Mac.** The history and this Mac's identity are kept in plain files in the plugin's data folder,
readable only by your user (folders 0700, files 0600) – FileVault protects them when the Mac is off. Keys and
messages are never written to the log (`events.log` has links and errors only). No internet – Lotus' sandbox
enforces it – no analytics, no accounts, no server. The AI of Lotus has no tools for MeshChat, so it never reads
your chats.

## Tests

**Automated – the protocol on a simulated radio.** `lotus meshchat selftest` builds `Tests/*.swift` with the
plugin's sources and runs them (no XCTest needed). They cover:

- frames, packets and what is inside: round trips, and refusal of cut, oversized, other-version, wrong-hop and
  random packets (2000 random ones without a crash)
- cryptography against published vectors (SHA-256, HKDF RFC 5869, Ed25519 RFC 8032); this Mac's key; changed text,
  names, keys, times, IDs, flags and signatures are refused; signatures in someone else's name too
- fragments: every link size from 20 to 512 bytes, any order, twice, interleaved, limits against a hostile
  neighbour; duplicate IDs remembered for 30 minutes
- the mesh, with the real `MeshNode` on `SimTransport`: two Macs, **A reaching C through B when A and C cannot hear
  each other**, each message once in a dense mesh, **a chain of 19 Macs: a message goes 16 relays far – and no
  further**, old/future/replayed messages, forged packets that are neither shown nor relayed nor able to block the
  real one, broken frames and floods, **one sender's share**, a relay that passes on but says nothing, **out of
  range and back with catch-up and no duplicates**, two Macs connecting at once, other protocol versions
  (MeshChat 1 among them), who is here/away/gone, Bluetooth off and on, long messages over 20-byte frames, doubled
  and lost frames, link limits, a restarted Mac
- storage: settings next to a pack's, the identity, history with damaged lines, trimming, permissions, MeshChat 1's
  rooms left alone, one chat at a time
- the chat's screen: the line editor (words, history, pastes with control characters, the 1000-byte limit),
  wrapping with wide characters, and whole frames that fit the window at eight sizes from 20 × 6 to 200 × 50

**Automated – the plugin in Lotus.** `zsh tests/run.zsh meshchat` (Lotus' own tests, on a Mac): installs it as
limited, builds it **inside the plugin sandbox**, runs the selftest with CryptoKit, checks the commands, the files
and their permissions, drives the chat in a terminal (the demo: types a message, `/who`, ctrl-c) and checks the
terminal is given back, the history, the doctor, uninstalling. The workflow
[`.github/workflows/meshchat.yml`](../../.github/workflows/meshchat.yml) runs all of it on a Mac on every change,
builds with every warning shown – a CoreBluetooth delegate method with a wrong signature would compile and
silently never be called, so the build fails on "nearly matches" warnings – and runs the doctor in a window of
Apple's Terminal, where MeshChat must recognize Terminal and go ahead (the check MeshChat 1 got wrong).

**What the automated tests do not show:** that Bluetooth works between real Macs. The simulated radio behaves
like CoreBluetooth where the mesh relies on it, but it is not CoreBluetooth, and CI Macs have no usable Bluetooth.
The real radio (`BLETransport.swift`) is compiled on every change, not exercised. Test it with the steps below.

## Testing with real Macs

Three Macs (A, B, C) with Lotus, the plugin and Bluetooth on; MeshChat in Terminal on each. Run
`lotus meshchat doctor` on each first – it should end with **✓ Ready**.

1. **A and B:** `lotus meshchat` on both (allow Bluetooth when macOS asks). Within ~15 seconds both show
   "… is here – a neighbour", ● in the list, and `/who` says "a direct Bluetooth link". Write on both – each
   message appears on the other once.
2. **C connects through B – and not to A.** Either place C out of A's range with B between them (Bluetooth reaches
   about 10 m indoors, much less through walls and people; try separate rooms or 30 m outdoors), or force the
   topology in one room: start B, then A with `lotus meshchat --links 1` and wait until A shows B, then C with
   `lotus meshchat --links 1` – A and C each take one link, and A's is already taken by B. In A's `/who`, C must show
   **⇢1** (one relay away), not ●.
3. **A writes; C receives it through B,** marked ⇢1. C answers; A receives it ⇢1. B shows both, and B's `/status`
   counts them as relayed.
4. **No duplicates:** write a few messages on each Mac; every message appears exactly once on every Mac (`/status`
   shows "copies dropped" counting up when there are several paths).
5. **Disconnect and reconnect:** turn Bluetooth off on B (Control Center) for ~20 seconds. A and C show that the
   link ended and – with only B between them – lose each other after a while (○, "not heard for a while"). While B
   is off, write something on A. Turn Bluetooth on again on B: B links again within ~30 seconds, B receives A's
   message once (catch-up), C too, and the chat goes on. Nothing crashes; quit with ctrl-c, start again – the
   history is there, nothing twice.

Also worth trying: ctrl-c and ctrl-z in the chat (the terminal must look as before), a long message (fragmented),
`lotus meshchat relay` on B in step 2 instead of the chat (A and C still reach each other; nobody sees B in `/who`),
and the same in iTerm2.

## Troubleshooting

| What you see | What to do |
|---|---|
| "macOS ended MeshChat's Bluetooth check – … cannot ask for Bluetooth" | Your terminal app cannot get the permission (WezTerm and Warp declare no Bluetooth use). Open MeshChat in Terminal, iTerm2, Ghostty, kitty or Visual Studio Code. |
| "MeshChat was ended by signal 6/9" right after the start | macOS ended it over the Bluetooth permission. `lotus meshchat doctor`; use one of the terminals above. |
| A dialog: "Terminal" would like to use Bluetooth – with no reason given | That is MeshChat asking: Apple's Terminal declares no reason of its own. Allow. |
| "Bluetooth not allowed" | System Settings › Privacy & Security › Bluetooth → turn on your terminal app, restart the terminal. |
| "Bluetooth is off" | Control Center or System Settings › Bluetooth. MeshChat goes on by itself when it is on. |
| "No one else is here yet" | The others need MeshChat 2 open, Bluetooth on, within reach. `lotus meshchat doctor` on each Mac; the "Links" line shows failed connections. |
| "A Mac nearby runs a newer/older MeshChat" | `lotus plugin update meshchat` on the older one – MeshChat 1 (rooms) and 2 do not mix. |
| "MeshChat has no rooms any more" | MeshChat 2 is one chat with everyone nearby: just `lotus meshchat`. |
| "Ignored a message … the clocks differ" | Set the date and time automatically on both Macs. |
| "… sends very many messages" | Someone is flooding; MeshChat shows their share only. Nothing to do. |
| "MeshChat could not be built" | `xcode-select --install`; `lotus meshchat doctor` shows the compiler's first errors; the whole log is in the data folder (`build.log`). |
| "MeshChat is open already in another window" | One chat per Mac – close the other one. |
| Someone has the same name as you | Compare the four letters after the dot in `/who`. |

## Known limitations

- **Public.** Everything said can be read by anyone nearby – there are no private messages and no encryption.
- **Macs only**, and only with MeshChat 2 – no iPhone, Android or other Bluetooth chat apps.
- **Not tested on Bluetooth hardware by its author.** The protocol, the mesh, the signatures, the chat and the
  build in Lotus' sandbox are tested automatically (above), and how macOS treats Terminal's Bluetooth requests was
  observed on macOS 14, 15 and 26; the CoreBluetooth radio compiles on every change but was not run between real
  Macs. Please run the [test with three Macs](#testing-with-real-macs) and report what you find.
- The Bluetooth permission is the terminal app's (see [Permissions](#permissions)); terminal apps that declare no
  Bluetooth use, like WezTerm and Warp, cannot run it. Apple's Terminal asks without giving a reason.
- The chat runs while it is open: no messages arrive when it is closed or the Mac sleeps. Missed messages come only
  from neighbours that still have them – the last 32, from the last 14 minutes.
- One chat per Mac. At most 8 Bluetooth links; Bluetooth's range indoors is short; a message goes at most 16 relays.
- Every Mac carries every message – fine for a few dozen people, not for a crowd.
- No delivery receipts, no files – text up to 1000 bytes per message.
- Clocks that differ by more than 10 minutes make messages look old or early, and they are refused.
- Your fingerprint stays the same until the identity file is deleted, so anyone listening can tell your messages
  apart over time ([Privacy and security](#privacy-and-security)).

## Files

| | |
|---|---|
| `plugin.conf` | the plugin: `lotus meshchat`, limited access, no network |
| `meshchat.zsh` | builds the Swift program once (in the data folder), runs it, `doctor` and `selftest` |
| `Info.plist` | linked into the program: its Bluetooth usage description |
| `Sources/Wire.swift` · `Bytes.swift` | the protocol on the wire, strict decoding, texts made safe for the terminal |
| `Sources/Identity.swift` · `Signing.swift` · `CryptoKitBackend.swift` | this Mac's key · signing and checking packets · CryptoKit |
| `Sources/Mesh.swift` · `Fragments.swift` · `Dedup.swift` | the mesh: links, routing, presence · fragments · duplicates |
| `Sources/Transport.swift` · `BLETransport.swift` · `SimTransport.swift` | the radio · CoreBluetooth · simulated (tests, demo) |
| `Sources/ChatApp.swift` · `ChatView.swift` · `Terminal.swift` | the chat, its screen, the terminal |
| `Sources/Store.swift` · `Doctor.swift` · `Demo.swift` · `App.swift` | data folder · doctor · demo · the command |
| `Tests/*.swift` | the protocol tests (`lotus meshchat selftest`) |

In the data folder (`~/.local/share/lotus/plugins/meshchat`): `settings`, `identity`, `history.jsonl`,
`events.log`, and `bin/` with the built program.
