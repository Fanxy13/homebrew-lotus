// MeshChat – the terminal: Lotus' colors, raw keys, the window's size, and the terminal given back as it was
// whatever ends the chat – /quit, Ctrl-C, a closed window (SIGHUP), kill (SIGTERM) – and around Ctrl-Z.

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// The theme's colors as Lotus gives them to plugins (LOTUS_COLOR_KEY=38;5;150 …); only digits and ;
enum Theme {
    private static let env = ProcessInfo.processInfo.environment
    static var enabled = isatty(STDOUT_FILENO) == 1 && env["NO_COLOR"] == nil

    private static func sgr(_ name: String, _ fallback: String) -> String {
        let v = env[name] ?? ""
        let ok = !v.isEmpty && v.count < 40 && v.allSatisfy { $0.isNumber || $0 == ";" }
        return ok ? v : fallback
    }

    static let keyCode = sgr("LOTUS_COLOR_KEY", "38;5;150")
    static let accentCode = sgr("LOTUS_COLOR_ACCENT", "38;5;218")
    static let dimCode = sgr("LOTUS_COLOR_DIM", "38;5;245")
    static let logoCode = sgr("LOTUS_COLOR_LOGO", "38;5;218")

    static func paint(_ code: String, _ s: String) -> String { enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    static func key(_ s: String) -> String { paint(keyCode, s) }
    static func accent(_ s: String) -> String { paint(accentCode, s) }
    static func dim(_ s: String) -> String { paint(dimCode, s) }
    static func bold(_ s: String) -> String { paint("1", s) }
    static func red(_ s: String) -> String { paint("38;5;203", s) }
    static func green(_ s: String) -> String { paint("38;5;114", s) }
    static func yellow(_ s: String) -> String { paint("38;5;179", s) }

    // A color per person, from their fingerprint – the same for them on every Mac
    static let people = ["38;5;117", "38;5;180", "38;5;151", "38;5;218", "38;5;222", "38;5;147", "38;5;174", "38;5;116"]
    static func person(_ fingerprint: String, _ s: String) -> String {
        let n = fingerprint.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return paint(people[n % people.count], s)
    }
}

enum Term {
    static var isTTY: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    static func size() -> (rows: Int, cols: Int) {
        var ws = winsize()
        #if os(Linux)
        let request = UInt(TIOCGWINSZ)
        #else
        let request: UInt = 0x4008_7468        // TIOCGWINSZ
        #endif
        if ioctl(STDOUT_FILENO, request, &ws) == 0 && ws.ws_row > 0 && ws.ws_col > 0 {
            return (Int(ws.ws_row), Int(ws.ws_col))
        }
        let env = ProcessInfo.processInfo.environment
        return (Int(env["LINES"] ?? "") ?? 24, Int(env["COLUMNS"] ?? "") ?? 80)
    }

    // Everything, even when the terminal is slow
    static func write(_ s: String) {
        var bytes = Array(s.utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeMutableBytes { Glue.write(STDOUT_FILENO, $0.baseAddress! + off, $0.count - off) }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            off += n
        }
    }
}

// The C functions of the same name, where Swift methods would hide them
enum Glue {
    static func write(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.write(fd, p, n)
        #else
        return Glibc.write(fd, p, n)
        #endif
    }
}

// The chat's screen: raw keys, the alternate screen, bracketed paste. One instance; the signal handlers use the
// saved settings directly.
private var savedTermios = termios()
private var rawActive = false
private let leaveSequence = Array("\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l".utf8)

private func restoreNow() {
    guard rawActive else { return }
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
    leaveSequence.withUnsafeBytes { _ = Glue.write(STDOUT_FILENO, $0.baseAddress!, $0.count) }
    rawActive = false
}

enum Screen {
    static func enter() {
        guard !rawActive, isatty(STDIN_FILENO) == 1 else { return }
        _ = leaveSequence.count         // made now, not first in a signal handler
        tcgetattr(STDIN_FILENO, &savedTermios)
        var t = savedTermios
        t.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        t.c_iflag &= ~tcflag_t(IXON | ICRNL)
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
        rawActive = true
        Term.write("\u{1B}[?1049h\u{1B}[?2004h\u{1B}[H\u{1B}[2J")
        installHandlers()
    }

    static func leave() { restoreNow() }

    // Ctrl-Z: the terminal back to the shell and the whole job stopped (lotus and its plugin wait for the chat,
    // so stopping only the chat would leave the shell without its prompt) – raw again after fg
    static func suspend(redraw: () -> Void) {
        restoreNow()
        kill(0, SIGTSTP)
        enter()
        redraw()
    }

    private static var installed = false

    private static func installHandlers() {
        guard !installed else { return }
        installed = true
        atexit { restoreNow() }
        // only async-signal-safe calls in here: tcsetattr, write, _exit
        for sig in [SIGTERM, SIGHUP, SIGQUIT, SIGINT] {
            signal(sig) { s in
                restoreNow()
                _exit(128 + s)
            }
        }
    }
}

// ── Keys ──────────────────────────────────────────────────────

enum Key: Equatable {
    case char(Character)
    case paste(String)
    case enter, backspace, delete, tab, esc
    case left, right, up, down, home, end, pageUp, pageDown, wordLeft, wordRight, wordBackspace
    case ctrlA, ctrlC, ctrlD, ctrlE, ctrlK, ctrlL, ctrlU, ctrlW, ctrlZ
    case unknown
    case eof
}

// Reads stdin on a thread of its own and hands each key to `handler` on the main queue
final class KeyReader {
    private var pending: [UInt8] = []
    private let handler: (Key) -> Void

    init(handler: @escaping (Key) -> Void) { self.handler = handler }

    func start() {
        let t = Thread { [self] in self.loop() }
        t.stackSize = 1 << 20
        t.start()
    }

    private func readByte(timeoutMs: Int32 = -1) -> UInt8? {
        if !pending.isEmpty { return pending.removeFirst() }
        if timeoutMs >= 0 {
            var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            if poll(&fds, 1, timeoutMs) <= 0 { return nil }
        }
        var buf = [UInt8](repeating: 0, count: 512)
        var n = 0
        repeat { n = read(STDIN_FILENO, &buf, 512) } while n < 0 && errno == EINTR
        if n <= 0 { return nil }
        pending.append(contentsOf: buf[0..<n])
        return pending.removeFirst()
    }

    private func loop() {
        while true {
            guard let b = readByte() else {
                DispatchQueue.main.async { self.handler(.eof) }
                return
            }
            let key = decode(b)
            DispatchQueue.main.async { self.handler(key) }
        }
    }

    private func decode(_ b: UInt8) -> Key {
        switch b {
        case 1: return .ctrlA
        case 3: return .ctrlC
        case 4: return .ctrlD
        case 5: return .ctrlE
        case 9: return .tab
        case 10, 13: return .enter
        case 11: return .ctrlK
        case 12: return .ctrlL
        case 21: return .ctrlU
        case 23: return .ctrlW
        case 26: return .ctrlZ
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
                if c >= 0x40 && c <= 0x7E { return csi(params, Character(UnicodeScalar(c))) }
                params.append(Character(UnicodeScalar(c)))
                if params.count > 16 { return .unknown }
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
        case "~":
            switch params {
            case "3": return .delete
            case "1", "7": return .home
            case "4", "8": return .end
            case "5": return .pageUp
            case "6": return .pageDown
            case "200": return .paste(readPaste())
            default: return .unknown
            }
        default: return .unknown
        }
    }

    private func readPaste() -> String {
        var bytes: [UInt8] = []
        let end = Array("\u{1B}[201~".utf8)
        while let b = readByte(timeoutMs: 2000) {
            bytes.append(b)
            if bytes.count >= end.count, Array(bytes.suffix(end.count)) == end {
                bytes.removeLast(end.count)
                break
            }
            if bytes.count > 64 * 1024 { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// ── Widths ────────────────────────────────────────────────────

// Cells a character takes in the terminal: wide CJK and emoji take two, combining marks none
func cellWidth(_ ch: Character) -> Int {
    guard let scalar = ch.unicodeScalars.first else { return 0 }
    let v = scalar.value
    if v == 0 || (v >= 0x300 && v <= 0x36F) || v == 0x200D || (v >= 0xFE00 && v <= 0xFE0F) { return 0 }
    if v < 0x1100 { return 1 }
    if (v >= 0x1100 && v <= 0x115F) || (v >= 0x2E80 && v <= 0xA4CF) || (v >= 0xAC00 && v <= 0xD7A3)
        || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0xFE30 && v <= 0xFE4F) || (v >= 0xFF00 && v <= 0xFF60)
        || (v >= 0xFFE0 && v <= 0xFFE6) || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x20000 && v <= 0x3FFFD) {
        return 2
    }
    return 1
}

func cellWidth(_ s: String) -> Int { s.reduce(0) { $0 + cellWidth($1) } }

// Width of a string with color codes in it
func visibleWidth(_ s: String) -> Int {
    var w = 0
    var inEscape = false
    for ch in s {
        if inEscape {
            if let a = ch.asciiValue, a >= 0x40, a <= 0x7E, ch != "[" { inEscape = false }
            continue
        }
        if ch == "\u{1B}" { inEscape = true; continue }
        w += cellWidth(ch)
    }
    return w
}

// A plain string cut to so many cells, with … when it was longer
func clip(_ s: String, _ cells: Int) -> String {
    guard cells > 0 else { return "" }
    if cellWidth(s) <= cells { return s }
    var out = ""
    var w = 0
    for ch in s {
        let cw = cellWidth(ch)
        if w + cw > cells - 1 { break }
        out.append(ch)
        w += cw
    }
    return out + "…"
}

// A string with color codes cut to so many cells; the codes stay, and the color is reset at the end
func fit(_ s: String, _ cells: Int) -> String {
    guard visibleWidth(s) > cells else { return s }
    var out = ""
    var w = 0
    var inEscape = false
    for ch in s {
        if inEscape {
            out.append(ch)
            if let a = ch.asciiValue, a >= 0x40, a <= 0x7E, ch != "[" { inEscape = false }
            continue
        }
        if ch == "\u{1B}" {
            inEscape = true
            out.append(ch)
            continue
        }
        let cw = cellWidth(ch)
        if w + cw > cells { break }
        out.append(ch)
        w += cw
    }
    return out + "\u{1B}[0m"
}

// Plain text in lines of at most `width` cells, broken at spaces where it can
func wrap(_ s: String, _ width: Int) -> [String] {
    let width = max(2, width)
    var lines: [String] = []
    var line = ""
    var lineW = 0
    for word in s.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
        let ww = cellWidth(word)
        if lineW > 0 && lineW + 1 + ww > width {
            lines.append(line)
            line = ""
            lineW = 0
        }
        if ww > width {
            // a word longer than the line: cut it
            for ch in word {
                let cw = cellWidth(ch)
                if lineW + cw > width {
                    lines.append(line)
                    line = ""
                    lineW = 0
                }
                line.append(ch)
                lineW += cw
            }
            continue
        }
        if lineW > 0 {
            line += " "
            lineW += 1
        }
        line += word
        lineW += ww
    }
    lines.append(line)
    return lines
}
