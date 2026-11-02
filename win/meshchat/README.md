# MeshChat for Windows

The same chat as `lotus meshchat` on a Mac, for Windows 10 (version 2004) and Windows 11: one chat with everyone
around you over **Bluetooth Low Energy** – no internet, no Wi-Fi, no server, no account. Windows computers and Macs are
in the same chat: every computer with MeshChat shows every message and passes it on, as far as there are computers to
pass it on. One program, `meshchat.exe`, with everything inside – nothing to install.

```
meshchat                 the chat – in cmd, PowerShell or Windows Terminal, or with a double click
meshchat demo            try it first: two simulated people, no Bluetooth
meshchat doctor          what Windows says about Bluetooth, and who is heard nearby
meshchat help            everything else: history, nick, set links, relay, selftest
```

**It is public.** There are no rooms and nothing is encrypted: whoever is nearby with MeshChat – or with a Bluetooth
scanner – can read what you write. Messages are signed (Ed25519), so no one can write in your name or change what you
wrote. All about the protocol, its limits and privacy: [lib/meshchat/README.md](../../lib/meshchat/README.md).

## Get it

Every change builds `meshchat-windows-x64.exe` and `meshchat-windows-arm64.exe` (Snapdragon and other ARM computers):
the workflow *MeshChat for Windows* keeps them with each run (Actions › the run › Artifacts), and a release of Lotus
carries them. Put the file anywhere, rename it to `meshchat.exe` if you like, and run it. Windows SmartScreen may ask
about a program it does not know yet: *More info › Run anyway*.

Build it yourself with the .NET 8 SDK – on Windows, or anywhere else:

```
dotnet publish win/meshchat/MeshChat -c Release -r win-x64
```

→ `win/meshchat/MeshChat/bin/Release/net8.0-windows10.0.19041.0/win-x64/publish/meshchat.exe`

## What it needs

| | |
|---|---|
| Windows | 10 version 2004 (build 19041) or newer, 11 – x64 or ARM64 |
| Bluetooth | Bluetooth Low Energy (4.0 or newer) – almost every laptop since 2015; a USB adapter on a desktop |
| The others | Macs with Lotus (`lotus meshchat`) and Windows computers with `meshchat.exe` – MeshChat 2, protocol 2 |
| A terminal | Windows Terminal (Windows 11's own) or the classic console – both show it |

Windows asks no question about Bluetooth for a program like this one. What can stand in the way: Bluetooth being off
(Settings › Bluetooth & devices), *Let apps control device radios* being off (Settings › Privacy & security › Radios),
or a policy of your organisation. `meshchat doctor` names whichever it is.

## How it works on Windows

The same service as on a Mac – the same UUIDs, the same frames, the same packets, byte for byte:

- **Finding and reaching others (central):** it scans for the MeshChat service, connects, subscribes to the frames the
  other computer notifies and writes its own without response. A Mac's advertised name (`mc` + 8 hex digits) tells it
  who connects first.
- **Being found (peripheral):** where the Bluetooth adapter can (`meshchat doctor`: *Be found*), it offers the same
  service and advertises it. Windows decides what goes into that advertisement and cannot add the name – so the others
  connect to a Windows computer at once instead of taking turns; should both connect at the same moment, the second
  link is closed, as between two Macs.
- **Signal strength:** Windows cannot read the signal of a device it is connected to; it comes from the advertisements
  it keeps hearing – `/where` works the same.
- **What it keeps:** `%LOCALAPPDATA%\lotus\data\meshchat` – `identity` (this computer's key comes from it), `settings`,
  `history.jsonl` and `events.log` (links and errors, never keys or messages); the same files as on a Mac.

## Tests

- **The protocol:** `meshchat selftest` – the same scenarios as the Mac's tests, on a simulated radio: packets and their
  limits, published test vectors (SHA-256, HKDF, Ed25519), multi-hop, a chain of 19 computers for the hop limit,
  duplicates, fragments, forged and broken packets, floods, out of range and back, the screen at eight sizes. They run
  anywhere .NET runs: `dotnet run --project win/meshchat/MeshChat.Tests`.
- **The same bytes as the Mac:** [`lib/meshchat/Tests/vectors.txt`](../../lib/meshchat/Tests/vectors.txt) holds what fixed
  inputs must give – a key, a HELLO, the three kinds of messages signed, their frames. This program made it and checks it;
  the Mac's tests check it with CryptoKit; and in the CI the Mac writes packets it signed for this program to check
  (`meshchat-tests --verify-foreign`). Both directions, on every change.
- **The program on Windows:** the workflow builds it for x64 and ARM64 and runs `version`, `help` and `selftest` on a
  Windows computer.

**Not yet tried between real computers.** The Bluetooth part is built and checked against Windows' own interfaces on
every change, but no CI computer has Bluetooth. To test it:

1. A Mac with Lotus (`lotus meshchat`) and a Windows computer with `meshchat.exe`, Bluetooth on, a metre apart.
   `meshchat doctor` on Windows first: *Nearby* should name the Mac once its chat is open.
2. Within ~15 seconds both show "… is here – a neighbour". Write on both – each message appears once on the other.
3. A second Windows computer or Mac out of the first one's range, near the other: messages arrive relayed (⇢1).
4. Close the chat on one (ctrl-c): the other says it left.

Report what you find – the events of the links are in `events.log`, and `meshchat doctor` sums them up.

## Files

| | |
|---|---|
| `MeshChat.Core/` | everything that is not the radio, plain .NET: the protocol (`Wire.cs`, `Bytes.cs`, `Fragments.cs`), the signatures (`Crypto.cs`), the mesh (`Mesh.cs`), `Store.cs`, the simulated radio and the demo (`Sim.cs`, `Demo.cs`), the chat's screen (`ChatApp.cs`, `ChatView.cs`, `Terminal.cs`), the commands (`Cli.cs`), and the tests (`SelfTest/`) |
| `MeshChat/` | `meshchat.exe`: Windows' Bluetooth (`BleTransport.cs`), the doctor, the console |
| `MeshChat.Tests/` | the tests where there is no Bluetooth – Linux, macOS, the CI |

Each file of `MeshChat.Core` says which file of `lib/meshchat/Sources` it follows: a change to the protocol is made in
both, and the test vectors make sure they still agree.
