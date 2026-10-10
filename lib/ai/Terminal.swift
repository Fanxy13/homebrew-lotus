// Lotus AI – terminal basics: colors, output, raw keyboard input, spinner.

import Foundation
import Darwin

// Colors come from the Lotus theme (SGR parameters such as "38;2;248;184;208"), set by lib/cmd/ai.zsh
enum Style {
    private static let env = ProcessInfo.processInfo.environment
    private static func sgr(_ name: String, _ fallback: String) -> String {
        let value = env[name] ?? ""
        return "\u{1B}[" + (value.isEmpty ? fallback : value) + "m"
    }
    static let logo = sgr("LOTUS_AI_C_LOGO", "38;5;218")
    static let key = sgr("LOTUS_AI_C_KEY", "38;5;150")
    static let accent = sgr("LOTUS_AI_C_ACCENT", "38;5;218")
    static let border = sgr("LOTUS_AI_C_BORDER", "38;5;242")
    static let dim = sgr("LOTUS_AI_C_DIM", "38;5;245")
    static let code = sgr("LOTUS_AI_C_MUSIC", "38;5;180")
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let boldOff = "\u{1B}[22m"
    static let italic = "\u{1B}[3m"
    static let red = "\u{1B}[38;5;203m"
    static let green = "\u{1B}[38;5;114m"
}

// The user's pet (lib/cmd/pets.zsh, set by lib/cmd/ai.zsh): it sits in the welcome box and it is
// the spinner while the AI works. Only plain ASCII and block pixels (▀ … ▟) get through.
struct Pet {
    let name: String
    let art: [String]
    let blinkArt: [String]      // same height as art (art itself when the pet has no such drawing)
    let wagArt: [String]
    let mini: String            // just the face in one line, for windows with no room for the whole pet
    let miniBlink: String
    let color: String

    var width: Int { (art + blinkArt + wagArt).map { cellWidth($0) }.max() ?? 0 }

    static let current: Pet? = {
        let e = ProcessInfo.processInfo.environment
        func clean(_ s: String) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.filter { ($0.value >= 0x20 && $0.value < 0x7F) || ($0.value >= 0x2580 && $0.value <= 0x259F) }))
        }
        func drawing(_ key: String) -> [String] {
            (e[key] ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { String(clean(String($0)).prefix(24)) }
        }
        let name = clean(e["LOTUS_AI_PET_NAME"] ?? "")
        let art = drawing("LOTUS_AI_PET_ART")
        guard !name.isEmpty, art.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), art.count <= 8 else { return nil }
        // A frame only counts when it is as high as the idle drawing, so the pet never changes height
        func variant(_ key: String) -> [String] {
            let f = drawing(key)
            return f.count == art.count && f.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ? f : art
        }
        let color = e["LOTUS_AI_PET_COLOR"] ?? ""
        let valid = color.allSatisfy { $0.isNumber || $0 == ";" }
        return Pet(name: String(name.prefix(16)), art: art,
                   blinkArt: variant("LOTUS_AI_PET_ART_BLINK"), wagArt: variant("LOTUS_AI_PET_ART_WAG"),
                   mini: String(clean(e["LOTUS_AI_PET_MINI"] ?? "").prefix(12)),
                   miniBlink: String(clean(e["LOTUS_AI_PET_MINI_BLINK"] ?? "").prefix(12)),
                   color: "\u{1B}[" + (valid && !color.isEmpty ? color : "38;5;218") + "m")
    }()
}

// All output goes through one lock so the spinner never cuts into other text
final class Out: @unchecked Sendable {
    static let shared = Out()
    private let lock = NSLock()

    func write(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

func emit(_ text: String) {
    Spinner.shared.stop()
    Out.shared.write(text)
}

enum Term {
    static var isTTY: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    static var width: Int {
        var size = winsize()
        // TIOCGWINSZ on Darwin
        let ok = withUnsafeMutablePointer(to: &size) { ioctl(STDOUT_FILENO, UInt(0x4008_7468), $0) }
        return ok == 0 && size.ws_col > 0 ? Int(size.ws_col) : 80
    }

    static var height: Int {
        var size = winsize()
        let ok = withUnsafeMutablePointer(to: &size) { ioctl(STDOUT_FILENO, UInt(0x4008_7468), $0) }
        return ok == 0 && size.ws_row > 0 ? Int(size.ws_row) : 24
    }
}

// Display width of a character in the terminal (wide CJK and pictographs take two cells)
func cellWidth(_ ch: Character) -> Int {
    guard let scalar = ch.unicodeScalars.first else { return 0 }
    let v = scalar.value
    if v == 0 || (v >= 0x300 && v <= 0x36F) || v == 0x200B || (v >= 0xFE00 && v <= 0xFE0F) { return 0 }
    if v < 0x1100 { return 1 }
    if (v >= 0x1100 && v <= 0x115F) || (v >= 0x2E80 && v <= 0xA4CF) || (v >= 0xAC00 && v <= 0xD7A3)
        || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0xFE30 && v <= 0xFE4F) || (v >= 0xFF00 && v <= 0xFF60)
        || (v >= 0xFFE0 && v <= 0xFFE6) || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x20000 && v <= 0x3FFFD) {
        return 2
    }
    return 1
}

func cellWidth(_ s: String) -> Int { s.reduce(0) { $0 + cellWidth($1) } }

// Visible width of a string that may contain color codes
func visibleWidth(_ s: String) -> Int {
    var width = 0
    var inEscape = false
    for ch in s {
        if inEscape {
            if let a = ch.asciiValue, a >= 0x40, a <= 0x7E, ch != "[" { inEscape = false }
            continue
        }
        if ch == "\u{1B}" { inEscape = true; continue }
        width += cellWidth(ch)
    }
    return width
}

// Cuts a plain string to a number of cells
func clip(_ s: String, _ cells: Int) -> String {
    if cellWidth(s) <= cells { return s }
    var out = ""
    var w = 0
    for ch in s {
        let cw = cellWidth(ch)
        if w + cw > max(0, cells - 1) { break }
        out.append(ch)
        w += cw
    }
    return out + "…"
}

// ── Handing the terminal to another program ──────────────────
// For Lotus tools that draw on the whole screen (the clock, Remove BG): the AI stops reading keys,
// gives the terminal back its normal mode, runs the program and waits, then takes the terminal again.
// Ctrl-C belongs to that program meanwhile; the AI only catches it so it does not end too.

extension Term {
    static func handOff(_ exe: String, _ args: [String], cwd: URL) -> Int32 {
        Spinner.shared.stop()
        KeyReader.pause()
        RawMode.disable()
        signal(SIGINT) { _ in }            // caught (not ignored), so the program still gets its own Ctrl-C
        defer {
            signal(SIGINT, SIG_DFL)
            RawMode.enable()
            KeyReader.resume()
        }
        // posix_spawn, not Process: Process starts the program in a process group of its own, and a
        // program outside the terminal's foreground group is stopped (SIGTTIN/SIGTTOU) the moment it
        // touches the terminal. In our own group it is in the foreground, like a program started by the shell.
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("LOTUS_AI_") { env.removeValue(forKey: k) }
        let argv: [UnsafeMutablePointer<CChar>?] = ([exe] + args).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addchdir_np(&actions, cwd.path)
        defer { posix_spawn_file_actions_destroy(&actions) }
        var pid: pid_t = 0
        guard posix_spawn(&pid, exe, &actions, nil, argv, envp) == 0 else { return 127 }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        // exited normally → its exit status; ended by a signal → 128 + the signal, like the shell says it
        if status & 0x7f == 0 { return (status >> 8) & 0xff }
        return 128 + (status & 0x7f)
    }
}

// ── Raw mode ──────────────────────────────────────────────────

var savedTermios = termios()
var rawModeActive = false

enum RawMode {
    static func enable() {
        guard !rawModeActive, isatty(STDIN_FILENO) == 1 else { return }
        tcgetattr(STDIN_FILENO, &savedTermios)
        var t = savedTermios
        t.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        t.c_iflag &= ~tcflag_t(IXON | ICRNL)
        // OPOST stays on, so "\n" still returns to the start of the line
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
        rawModeActive = true
        Out.shared.write("\u{1B}[?2004h")          // bracketed paste
        installSignalHandlers()
    }

    static func disable() {
        guard rawModeActive else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
        rawModeActive = false
        Out.shared.write("\u{1B}[?2004l\u{1B}[?25h")
    }

    private static func installSignalHandlers() {
        for sig in [SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig) { _ in
                if rawModeActive { tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios) }
                let reset = "\u{1B}[?2004l\u{1B}[?25h\n"
                _ = reset.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
                _exit(1)
            }
        }
    }
}

// ── Keys ──────────────────────────────────────────────────────

enum Key: Equatable {
    case char(Character)
    case paste(String)
    case enter, newline, backspace, delete, tab, backtab, esc
    case left, right, up, down, home, end, wordLeft, wordRight, wordBackspace
    case ctrlA, ctrlC, ctrlD, ctrlE, ctrlK, ctrlL, ctrlU, ctrlW, ctrlO
    case cancelled, unknown
}

final class KeyQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Key] = []
    private var waiter: CheckedContinuation<Key, Never>?

    func push(_ key: Key) {
        lock.lock()
        if let w = waiter {
            waiter = nil
            lock.unlock()
            w.resume(returning: key)
        } else {
            buffer.append(key)
            lock.unlock()
        }
    }

    // Next key; a cancelled task gets .cancelled
    func next() async -> Key {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Key, Never>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    c.resume(returning: .cancelled)
                } else if !buffer.isEmpty {
                    let k = buffer.removeFirst()
                    lock.unlock()
                    c.resume(returning: k)
                } else {
                    waiter = c
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume(returning: .cancelled)
        }
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }
}

// Reads stdin on its own thread and turns bytes into keys
final class KeyReader: @unchecked Sendable {
    let queue: KeyQueue
    private var pending: [UInt8] = []

    // While another program has the terminal (Term.handOff) the reader takes no keys
    private static let pauseLock = NSLock()
    nonisolated(unsafe) private static var paused = false
    nonisolated(unsafe) private static var resting = true
    static func pause() {
        pauseLock.lock(); paused = true; pauseLock.unlock()
        for _ in 0..<40 {
            pauseLock.lock(); let r = resting; pauseLock.unlock()
            if r { return }
            usleep(10_000)
        }
    }
    static func resume() { pauseLock.lock(); paused = false; pauseLock.unlock() }
    private static func isPaused() -> Bool {
        pauseLock.lock(); defer { pauseLock.unlock() }
        resting = paused
        return paused
    }

    init(queue: KeyQueue) { self.queue = queue }

    func start() {
        let thread = Thread { [self] in loop() }
        thread.stackSize = 1 << 20
        thread.start()
    }

    private func readByte(timeoutMs: Int32 = -1) -> UInt8? {
        if !pending.isEmpty { return pending.removeFirst() }
        if timeoutMs >= 0 {
            var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            if poll(&fds, 1, timeoutMs) <= 0 { return nil }
        }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(STDIN_FILENO, &buf, 256)
        if n <= 0 { return nil }
        pending.append(contentsOf: buf[0..<n])
        return pending.removeFirst()
    }

    private func loop() {
        while true {
            if KeyReader.isPaused() { usleep(20_000); continue }
            if pending.isEmpty {
                // wait a little at a time, so a pause takes effect before the next key
                var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                let r = poll(&fds, 1, 100)
                if r == 0 { continue }
                if r < 0 {
                    if errno == EINTR { continue }
                    queue.push(.ctrlD)
                    return
                }
                if KeyReader.isPaused() { continue }     // the other program gets this key
            }
            guard let b = readByte() else {
                queue.push(.ctrlD)
                return
            }
            queue.push(decode(b))
        }
    }

    private func decode(_ b: UInt8) -> Key {
        switch b {
        case 1: return .ctrlA
        case 3: return .ctrlC
        case 4: return .ctrlD
        case 5: return .ctrlE
        case 9: return .tab
        case 10: return .newline
        case 11: return .ctrlK
        case 12: return .ctrlL
        case 13: return .enter
        case 15: return .ctrlO
        case 21: return .ctrlU
        case 23: return .ctrlW
        case 127, 8: return .backspace
        case 27: return escape()
        case 0..<32: return .unknown
        default: return utf8(b)
        }
    }

    private func utf8(_ first: UInt8) -> Key {
        var bytes = [first]
        let count = first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : first >= 0xC0 ? 2 : 1
        while bytes.count < count, let b = readByte(timeoutMs: 50) { bytes.append(b) }
        if let s = String(bytes: bytes, encoding: .utf8), let ch = s.first { return .char(ch) }
        return .unknown
    }

    private func escape() -> Key {
        guard let b = readByte(timeoutMs: 40) else { return .esc }
        switch b {
        case UInt8(ascii: "["):
            var params = ""
            while let c = readByte(timeoutMs: 40) {
                if c >= 0x40 && c <= 0x7E {
                    return csi(params, Character(UnicodeScalar(c)))
                }
                params.append(Character(UnicodeScalar(c)))
            }
            return .esc
        case UInt8(ascii: "O"):
            switch readByte(timeoutMs: 40) {
            case UInt8(ascii: "A"): return .up
            case UInt8(ascii: "B"): return .down
            case UInt8(ascii: "C"): return .right
            case UInt8(ascii: "D"): return .left
            case UInt8(ascii: "H"): return .home
            case UInt8(ascii: "F"): return .end
            default: return .unknown
            }
        case 13, 10: return .newline                 // Option+Enter
        case 127, 8: return .wordBackspace
        case UInt8(ascii: "b"): return .wordLeft
        case UInt8(ascii: "f"): return .wordRight
        case 27: return .esc
        default: return .unknown
        }
    }

    private func csi(_ params: String, _ final: Character) -> Key {
        switch final {
        case "A": return .up
        case "B": return .down
        case "C": return params.contains(";3") || params.contains(";5") ? .wordRight : .right
        case "D": return params.contains(";3") || params.contains(";5") ? .wordLeft : .left
        case "H": return .home
        case "F": return .end
        case "Z": return .backtab                    // shift-tab
        case "~":
            switch params {
            case "3": return .delete
            case "1", "7": return .home
            case "4", "8": return .end
            case "200": return .paste(readPaste())
            default: return .unknown
            }
        default: return .unknown
        }
    }

    private func readPaste() -> String {
        var bytes: [UInt8] = []
        let end: [UInt8] = Array("\u{1B}[201~".utf8)
        while let b = readByte(timeoutMs: 2000) {
            bytes.append(b)
            if bytes.count >= end.count, Array(bytes.suffix(end.count)) == end {
                bytes.removeLast(end.count)
                break
            }
        }
        let text = String(decoding: bytes, as: UTF8.self)
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// ── Spinner ───────────────────────────────────────────────────

final class Spinner: @unchecked Sendable {
    static let shared = Spinner()
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var label = ""
    private var started = Date()
    private var frame = 0
    private let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
    // With a pet and room: the whole pet, blinking and wagging now and then (0 idle, 1 blink, 2 wag)
    private static let petPlan: [Int] = {
        var plan: [Int] = []
        for (pose, count) in [(0, 16), (1, 1), (0, 6), (1, 2), (0, 6), (2, 3), (0, 2), (2, 3), (0, 2)] {
            plan += Array(repeating: pose, count: count)
        }
        return plan
    }()
    // Too little room for that: just its face in one line
    private let petFrames: [String]? = {
        guard let p = Pet.current, !p.mini.isEmpty else { return nil }
        let shut = p.miniBlink.isEmpty ? p.mini : p.miniBlink
        return Array(repeating: p.mini, count: 16) + [shut] + Array(repeating: p.mini, count: 6) + [shut, shut]
    }()
    private var rowsDrawn = 1       // rows the spinner takes on screen; the cursor rests on the first one
    var hint = "esc to stop"

    func start(_ text: String) {
        guard Term.isTTY else { return }
        lock.lock()
        label = text
        if timer == nil {
            started = Date()
            let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
            t.schedule(deadline: .now(), repeating: .milliseconds(110))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            lock.unlock()
            Out.shared.write("\u{1B}[?25l")
            t.resume()
        } else {
            lock.unlock()
        }
    }

    func setLabel(_ text: String) {
        lock.lock()
        label = text
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        guard timer != nil else { lock.unlock(); return }
        frame += 1
        let secs = Int(Date().timeIntervalSince(started))
        let status = "\(Style.logo)\(label)…\(Style.reset) \(Style.dim)(\(secs)s · \(hint))\(Style.reset)"
        if let p = Pet.current, p.art.count > 1, Term.height >= p.art.count + 4, Term.width > p.width + 4 + visibleWidth(status) {
            drawPet(p, status)
        } else {
            let glyph: String
            if let pet = petFrames, let p = Pet.current { glyph = p.color + pet[frame % pet.count] }
            else { glyph = Style.logo + frames[frame % frames.count] }
            let clear = rowsDrawn > 1 ? "\r\u{1B}[J" : ""      // the window got too small for the whole pet
            rowsDrawn = 1
            Out.shared.write("\(clear)\r\u{1B}[2K\(glyph)\(Style.reset) \(status)")
        }
        lock.unlock()
    }

    // The whole pet with the status beside its face. The cursor goes back to the first row after
    // every picture, so the next picture (or stop) starts there
    private func drawPet(_ p: Pet, _ status: String) {
        let pose = Spinner.petPlan[frame % Spinner.petPlan.count]
        let art = pose == 1 ? p.blinkArt : pose == 2 ? p.wagArt : p.art
        let faceRow = (art.count - 1) / 2
        var out = rowsDrawn > art.count ? "\r\u{1B}[J" : ""
        for (i, line) in art.enumerated() {
            let pad = String(repeating: " ", count: max(0, p.width - cellWidth(line)))
            out += "\r\u{1B}[2K\(p.color)\(line)\(Style.reset)\(pad)"
            if i == faceRow { out += "   \(status)" }
            if i < art.count - 1 { out += "\n" } else { out += "\u{1B}[\(art.count - 1)A\r" }
        }
        rowsDrawn = art.count
        Out.shared.write(out)
    }

    func stop() {
        lock.lock()
        guard let t = timer else { lock.unlock(); return }
        timer = nil
        t.cancel()
        Out.shared.write((rowsDrawn > 1 ? "\r\u{1B}[J" : "\r\u{1B}[2K") + "\u{1B}[?25h")
        rowsDrawn = 1
        lock.unlock()
    }
}

// ── Watchdog ──────────────────────────────────────────────────
// Runs work that may stop making progress (the on-device model sometimes stalls).
// Returns as soon as the work is done, stalls, or the calling task is cancelled.

enum Watchdog {
    struct Stalled: Error {}

    final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var last = Date()
        private var busy = 0
        func tick() { lock.lock(); last = Date(); lock.unlock() }
        func begin() { lock.lock(); busy += 1; lock.unlock() }
        func end() { lock.lock(); busy -= 1; last = Date(); lock.unlock() }
        func reset() { lock.lock(); last = Date(); busy = 0; lock.unlock() }
        var idle: TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return busy > 0 ? 0 : Date().timeIntervalSince(last)
        }
    }

    private final class Once<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<T, Error>?
        init(_ c: CheckedContinuation<T, Error>) { cont = c }
        var done: Bool { lock.lock(); defer { lock.unlock() }; return cont == nil }
        func finish(_ r: Result<T, Error>) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(with: r)
        }
    }

    private final class Control<T>: @unchecked Sendable {
        let lock = NSLock()
        var work: Task<Void, Never>?
        var once: Once<T>?
        var cancelled = false
    }

    static func run<T>(idle: TimeInterval, shared: Progress? = nil, _ op: @escaping @Sendable (Progress) async throws -> T) async throws -> T {
        let progress = shared ?? Progress()
        progress.reset()
        let ctl = Control<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
                let once = Once(c)
                ctl.lock.lock()
                ctl.once = once
                if ctl.cancelled {
                    ctl.lock.unlock()
                    once.finish(.failure(CancellationError()))
                    return
                }
                let work = Task {
                    do { once.finish(.success(try await op(progress))) } catch { once.finish(.failure(error)) }
                }
                ctl.work = work
                ctl.lock.unlock()
                Task {
                    while !once.done {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if progress.idle > idle {
                            work.cancel()
                            once.finish(.failure(Stalled()))
                        }
                    }
                }
            }
        } onCancel: {
            ctl.lock.lock()
            ctl.cancelled = true
            let w = ctl.work, o = ctl.once
            ctl.lock.unlock()
            w?.cancel()
            o?.finish(.failure(CancellationError()))
        }
    }
}
