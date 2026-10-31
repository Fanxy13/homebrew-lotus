// Lotus AI – where macOS, Linux and Windows differ. Everything else in lib/ai/*.swift is the same on every system
// (dev/3.0/ARCHITECTURE.md, "The AI on three systems"): this file has the hardware facts, the sleep assertion, the
// clocks and the language guess, so the other files do not need #if.
//
//   Host.memoryBytes / chip / model / osName / osVersion / cores   facts for /performance and the prompts
//   Awake.begin / end / clocks / slept                             the computer stays awake while the AI answers
//   Language.name(of:)                                             the language of a request, for gpt-oss

import Foundation
#if canImport(Darwin)
import Darwin
import IOKit.pwr_mgt
import NaturalLanguage
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum Host {
    #if os(macOS)
    static let name = "macOS"            // the system, as the prompts and /performance call it
    static let machine = "Mac"           // the computer
    #elseif os(Linux)
    static let name = "Linux"
    static let machine = "computer"
    #elseif os(Windows)
    static let name = "Windows"
    static let machine = "computer"
    #else
    static let name = "this system"
    static let machine = "computer"
    #endif

    static var isMac: Bool { name == "macOS" }

    static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }
    static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    #if os(macOS)
    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }

    private static func sysctlInt(_ name: String) -> Int64 {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : 0
    }

    static var memoryBytes: Int64 { sysctlInt("hw.memsize") }
    static var model: String { sysctl("hw.model") }                      // Mac16,1
    static var chip: String { sysctl("machdep.cpu.brand_string") }       // Apple M5
    #else
    // Linux (and whatever else has /proc): the files the kernel keeps
    static var memoryBytes: Int64 {
        guard let text = try? String(contentsOfFile: "/proc/meminfo", encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n") where line.hasPrefix("MemTotal:") {
            let kb = line.split(separator: " ").compactMap { Int64($0) }.first ?? 0
            return kb * 1024
        }
        return 0
    }

    private static func firstLine(_ path: String) -> String {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").first.map(String.init) ?? ""
    }

    static var model: String {
        let n = firstLine("/sys/devices/virtual/dmi/id/product_name")
        return n.isEmpty ? firstLine("/proc/device-tree/model") : n
    }

    static var chip: String {
        guard let text = try? String(contentsOfFile: "/proc/cpuinfo", encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n") {
            for key in ["model name", "Model", "Hardware"] where line.hasPrefix(key) {
                if let i = line.firstIndex(of: ":") { return line[line.index(after: i)...].trimmingCharacters(in: .whitespaces) }
            }
        }
        return ""
    }
    #endif
}

// ── Awake while the AI works ──────────────────────────────────
// A long answer of a model on this computer must not stall because it went to sleep when nobody touched it.
// Closing the lid on battery still puts it to sleep – how long it slept is measured, so /performance does not
// count that time as thinking. macOS: an IOKit assertion · Linux: an inhibitor lock held by systemd-inhibit.
enum Awake {
    #if os(macOS)
    static func begin(_ why: String) -> Int? {
        var id = IOPMAssertionID(0)
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn), why as CFString, &id)
        return ok == kIOReturnSuccess ? Int(id) : nil
    }

    static func end(_ id: Int?) {
        if let id = id { IOPMAssertionRelease(IOPMAssertionID(id)) }
    }

    // The clock that stops while the computer sleeps, and the one that goes on
    static func clocks() -> (awake: UInt64, all: UInt64) {
        (clock_gettime_nsec_np(CLOCK_UPTIME_RAW), clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW))
    }
    #else
    private static var holders: [Int: Process] = [:]

    static func begin(_ why: String) -> Int? {
        // without systemd (or a login manager) there is nothing to ask – the AI works all the same
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["systemd-inhibit", "--what=idle:sleep", "--who=Lotus AI", "--why=\(why)", "--mode=block", "sleep", "2147483647"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let id = Int(p.processIdentifier)
        holders[id] = p
        return id
    }

    static func end(_ id: Int?) {
        guard let id = id, let p = holders.removeValue(forKey: id) else { return }
        p.terminate()
    }

    static func clocks() -> (awake: UInt64, all: UInt64) {
        func now(_ clock: clockid_t) -> UInt64 {
            var t = timespec()
            clock_gettime(clock, &t)
            return UInt64(t.tv_sec) &* 1_000_000_000 &+ UInt64(t.tv_nsec)
        }
        // CLOCK_MONOTONIC stops during a suspend, CLOCK_BOOTTIME goes on
        return (now(CLOCK_MONOTONIC), now(CLOCK_BOOTTIME))
    }
    #endif

    static func slept(since c: (awake: UInt64, all: UInt64)) -> Double {
        let now = clocks()
        let all = Double(now.all &- c.all), awake = Double(now.awake &- c.awake)
        return max(0, (all - awake) / 1e9)
    }
}

// ── The language of the request ───────────────────────────────
// gpt-oss sometimes answers in another language after many steps; Lotus names the language in its notes to it.
// macOS: Apple's NaturalLanguage. Elsewhere: the words every text of a language has – good enough to tell the
// languages people write to Lotus in, and silent when it is not sure.
enum Language {
    static func name(of text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.split(whereSeparator: { $0.isWhitespace }).count >= 4 else { return nil }
        #if canImport(NaturalLanguage)
        let r = NLLanguageRecognizer()
        r.processString(t)
        guard let lang = r.dominantLanguage, let p = r.languageHypotheses(withMaximum: 1)[lang], p > 0.6 else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue)
        #else
        return guess(t)
        #endif
    }

    static let common: [String: Set<String>] = [
        "English": ["the", "and", "is", "to", "of", "in", "it", "that", "you", "for", "with", "this", "are", "what", "how", "can", "please", "my", "me", "do"],
        "German": ["der", "die", "das", "und", "ist", "nicht", "ich", "du", "ein", "eine", "mit", "für", "auf", "zu", "den", "dem", "bitte", "wie", "was", "kannst", "mein", "mir"],
        "French": ["le", "la", "les", "et", "est", "de", "des", "un", "une", "pour", "dans", "que", "pas", "vous", "je", "mon", "avec", "sur", "comment", "peux"],
        "Spanish": ["el", "la", "los", "las", "y", "es", "de", "un", "una", "para", "que", "con", "por", "mi", "cómo", "puedes", "en", "se", "no", "lo"],
        "Italian": ["il", "lo", "la", "gli", "e", "è", "di", "un", "una", "per", "che", "con", "non", "mi", "come", "puoi", "sono", "del", "della", "in"],
        "Portuguese": ["o", "a", "os", "as", "e", "é", "de", "um", "uma", "para", "que", "com", "não", "meu", "como", "pode", "em", "do", "da", "você"],
        "Dutch": ["de", "het", "een", "en", "is", "van", "niet", "ik", "je", "met", "voor", "op", "dat", "wat", "hoe", "kun", "mijn", "te", "naar", "ook"],
    ]

    static func guess(_ text: String) -> String? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.count >= 4 else { return nil }
        var scores: [(String, Int)] = common.map { name, set in (name, words.filter { set.contains($0) }.count) }
        scores.sort { $0.1 > $1.1 }
        guard let best = scores.first, best.1 >= 2 else { return nil }
        let second = scores.count > 1 ? scores[1].1 : 0
        // clearly ahead of the next language, and a good share of the words are its own
        guard best.1 >= second + 2, Double(best.1) / Double(words.count) >= 0.2 else { return nil }
        return best.0
    }
}

// ── Sockets and files under their libc names ──────────────────
// "Darwin.write(…)" does not exist on Linux, and inside a type with its own close() or write() a plain call would be
// the method. These go to libc, whichever libc this system has; the socket constants that differ are in Sock.
enum Sock {
    #if canImport(Glibc)
    static let stream = Int32(SOCK_STREAM.rawValue)     // an enum in glibc
    #else
    static let stream = SOCK_STREAM
    #endif

    #if canImport(Darwin)
    static let noSignal: Int32 = 0                      // macOS: SO_NOSIGPIPE is set on the socket instead
    #else
    static let noSignal = Int32(MSG_NOSIGNAL)
    #endif

    static let peek = Int32(MSG_PEEK) | Int32(MSG_DONTWAIT)
}

func libcWrite(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { write(fd, p, n) }
func libcClose(_ fd: Int32) { _ = close(fd) }
func libcListen(_ fd: Int32, _ backlog: Int32) -> Int32 { listen(fd, backlog) }
func libcAccept(_ fd: Int32) -> Int32 {
    let c = accept(fd, nil, nil)
    if c >= 0 { _ = fcntl(c, F_SETFD, FD_CLOEXEC) }       // a program the AI starts must not keep a connection open
    return c
}
func libcSend(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { send(fd, p, n, Sock.noSignal) }

// ── Programs of this system ───────────────────────────────────
extension Host {
    // The first executable of that name in PATH or the usual places
    static func which(_ name: String) -> String? {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        for d in dirs where !d.isEmpty {
            let p = d + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // The shell that runs the AI's commands – Lotus lives in zsh, on a Mac and on Linux alike
    static var zsh: String {
        #if os(macOS)
        return "/bin/zsh"
        #else
        for p in ["/usr/bin/zsh", "/bin/zsh", "/usr/local/bin/zsh"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        return which("zsh") ?? "/bin/zsh"
        #endif
    }

    // Is there a graphical session (a clipboard, a browser to open)? A login over SSH has none.
    static var hasDisplay: Bool {
        #if os(macOS) || os(Windows)
        return true
        #else
        let e = ProcessInfo.processInfo.environment
        return !(e["WAYLAND_DISPLAY"] ?? "").isEmpty || !(e["DISPLAY"] ?? "").isEmpty
        #endif
    }

    // Puts text on the clipboard. false: this system has no way (no display, no clipboard program)
    static func copy(_ text: String) -> Bool {
        #if os(macOS)
        let tools: [(String, [String])] = [("/usr/bin/pbcopy", [])]
        #elseif os(Windows)
        let tools: [(String, [String])] = [("clip.exe", [])]
        #else
        guard hasDisplay else { return false }
        let wayland = !(ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] ?? "").isEmpty
        var tools: [(String, [String])] = [("xclip", ["-selection", "clipboard"]), ("xsel", ["--clipboard", "--input"])]
        if wayland { tools.insert(("wl-copy", []), at: 0) } else { tools.append(("wl-copy", [])) }
        #endif
        for (name, args) in tools {
            guard let exe = name.hasPrefix("/") ? (FileManager.default.isExecutableFile(atPath: name) ? name : nil) : which(name) else { continue }
            if feed(exe, args, Data(text.utf8)) == 0 { return true }
        }
        return false
    }

    // Opens an address in the browser (http and https only)
    @discardableResult
    static func open(_ url: String) -> Bool {
        guard url.hasPrefix("https://") || url.hasPrefix("http://") else { return false }
        #if os(macOS)
        let tools: [(String, [String])] = [("/usr/bin/open", [url])]
        #elseif os(Windows)
        let tools: [(String, [String])] = [("cmd.exe", ["/c", "start", "", url])]
        #else
        guard hasDisplay else { return false }
        let tools: [(String, [String])] = [("xdg-open", [url]), ("gio", ["open", url]), ("sensible-browser", [url])]
        #endif
        for (name, args) in tools {
            guard let exe = name.hasPrefix("/") ? name : which(name) else { continue }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            if (try? p.run()) != nil { return true }
        }
        return false
    }

    // Keeps a secret (the Claude API key) where this system keeps secrets: the Keychain on a Mac; elsewhere Lotus' own
    // secret store (the desktop keyring, or a file only you can read) – asked through Lotus itself. The value goes in
    // through stdin and is never part of a command line.
    static func saveSecret(_ item: String, _ value: String) -> Bool {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["-i"]
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let account = ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "lotus"
        pipe.fileHandleForWriting.write(Data("add-generic-password -U -s \(item) -a \(account) -w \(value)\n".utf8))
        try? pipe.fileHandleForWriting.close()
        p.waitUntilExit()
        return p.terminationStatus == 0
        #else
        guard let root = ProcessInfo.processInfo.environment["LOTUS_ROOT"], !root.isEmpty else { return false }
        let script = #"setopt extendedglob; source "$1/lib/core.zsh" && lotus_load && lotus_os_secret_set "$2" "$(cat)""#
        return feed(zsh, ["-fc", script, "lotus", root, item], Data(value.utf8)) == 0
        #endif
    }
}

#if !canImport(Darwin)
// ── Starting programs without Foundation's Process ────────────
// On Linux, Foundation reports the end of a Process only when every program that inherited its pipes has closed
// them: `server &` would keep a step waiting for as long as the server runs. So programs are started with
// posix_spawn and waited for with waitpid – only the program itself, not what it left running behind it.
struct Spawned {
    let pid: pid_t
    let output: Int32       // the read end of its stdout and stderr, or -1
    let input: Int32        // the write end of its stdin, or -1
}

// fdMap: descriptors of this program handed on under another number (from → to); logTo: where its output goes when
// it is not captured (a file; otherwise /dev/null)
func spawnProgram(_ exe: String, _ args: [String], env: [String: String]? = nil, cwd: String? = nil,
                  feedInput: Bool = false, captureOutput: Bool = false, ownGroup: Bool = false,
                  fdMap: [(from: Int32, to: Int32)] = [], logTo: String? = nil) -> Spawned? {
    var outFds: [Int32] = [-1, -1], inFds: [Int32] = [-1, -1]
    // close-on-exec: the program gets only the ends it is given below
    func cloexec(_ fds: [Int32]) { for f in fds { _ = fcntl(f, F_SETFD, FD_CLOEXEC) } }
    if captureOutput {
        guard pipe(&outFds) == 0 else { return nil }
        cloexec(outFds)
    }
    if feedInput {
        guard pipe(&inFds) == 0 else {
            if captureOutput { close(outFds[0]); close(outFds[1]) }
            return nil
        }
        cloexec(inFds)
    }
    var actions = posix_spawn_file_actions_t()
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    if feedInput { posix_spawn_file_actions_adddup2(&actions, inFds[0], 0) } else { posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) }
    if captureOutput {
        posix_spawn_file_actions_adddup2(&actions, outFds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, outFds[1], 2)
    } else if let log = logTo {
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
    } else {
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    }
    // the mapped descriptors go through numbers far from the targets first, so one cannot overwrite another
    var parked: [Int32] = []
    for m in fdMap {
        let high = fcntl(m.from, F_DUPFD_CLOEXEC, 64)
        guard high >= 0 else { continue }
        parked.append(high)
        posix_spawn_file_actions_adddup2(&actions, high, m.to)
    }
    defer { parked.forEach { close($0) } }
    if let cwd = cwd { posix_spawn_file_actions_addchdir_np(&actions, cwd) }
    var attr = posix_spawnattr_t()
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    if ownGroup {               // like Process: a process group of its own
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
    }
    let environment = env ?? ProcessInfo.processInfo.environment
    let argv: [UnsafeMutablePointer<CChar>?] = ([exe] + args).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp)
    if captureOutput { close(outFds[1]) }
    if feedInput { close(inFds[0]) }
    guard rc == 0 else {
        if captureOutput { close(outFds[0]) }
        if feedInput { close(inFds[1]) }
        return nil
    }
    return Spawned(pid: pid, output: outFds[0], input: inFds[1])
}

// An exit status as the shell reports it: the code, or 128 + the signal
func exitStatus(_ raw: Int32) -> Int32 {
    raw & 0x7f == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
}
#endif

// Runs a program, hands it some text on stdin, waits (at most 5 seconds) for it → its exit status (-1: not started)
func feed(_ exe: String, _ args: [String], _ input: Data) -> Int32 {
    #if canImport(Darwin)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardInput = pipe
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    pipe.fileHandleForWriting.write(input)
    try? pipe.fileHandleForWriting.close()
    p.waitUntilExit()
    return p.terminationStatus
    #else
    guard let s = spawnProgram(exe, args, feedInput: true) else { return -1 }
    _ = signal(SIGPIPE, SIG_IGN)
    input.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
        var sent = 0
        while sent < b.count {
            let n = write(s.input, b.baseAddress! + sent, b.count - sent)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { break }
            sent += n
        }
    }
    close(s.input)
    var status: Int32 = 0
    for _ in 0..<500 {
        let r = waitpid(s.pid, &status, WNOHANG)
        if r == s.pid { return exitStatus(status) }
        if r < 0 && errno != EINTR { return -1 }
        usleep(10_000)
    }
    kill(s.pid, SIGKILL)
    _ = waitpid(s.pid, &status, 0)
    return -1
    #endif
}
