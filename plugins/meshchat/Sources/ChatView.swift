// MeshChat – what the chat looks like: the room and you on top, what is said with its time, who is here and how
// the mesh is doing below, and the line you write in. Drawn whole into the terminal's alternate screen, so the
// terminal is as it was when the chat ends.
//
//   lotus / MeshChat  Bike trip  #k7q2m9ab                                   you: Ada·k3f9
//   ─────────────────────────────────────────────────────────────────────────────────────
//   14:02  Bob    Hi everyone
//   14:03  Carol  Hello from the other end of the field ⇢1
//   14:03  Ada    Meet at the bridge?
//   ── here: Bob ● · Carol ⇢1 ───────────────────────────────────────────────────────────
//   ● Bluetooth on · 1 link · 4 relayed                                /help · ctrl-c quits
//   › _

import Foundation

struct LineEditor {
    private(set) var chars: [Character] = []
    private(set) var cursor = 0
    private var history: [String] = []
    private var browsing: Int?
    private var draft: [Character] = []

    var text: String { String(chars) }
    var isEmpty: Bool { chars.isEmpty }
    var bytes: Int { text.utf8.count }

    // Typed or pasted text: one line, nothing that could change the terminal, at most 1000 bytes
    mutating func insert(_ s: String) {
        for ch in s {
            if ch.unicodeScalars.contains(where: { Sanitize.isUnsafe($0) && !$0.properties.isWhitespace }) { continue }
            let c: Character = ch.unicodeScalars.contains(where: { $0.properties.isWhitespace }) ? " " : ch
            guard bytes + String(c).utf8.count <= Proto.maxTextBytes else { return }
            chars.insert(c, at: cursor)
            cursor += 1
        }
    }

    mutating func backspace() {
        guard cursor > 0 else { return }
        chars.remove(at: cursor - 1)
        cursor -= 1
    }

    mutating func delete() {
        guard cursor < chars.count else { return }
        chars.remove(at: cursor)
    }

    mutating func left() { cursor = max(0, cursor - 1) }
    mutating func right() { cursor = min(chars.count, cursor + 1) }
    mutating func home() { cursor = 0 }
    mutating func end() { cursor = chars.count }

    mutating func clear() {
        chars.removeAll()
        cursor = 0
        browsing = nil
    }

    mutating func killToEnd() { chars.removeSubrange(cursor...) }

    mutating func killToStart() {
        chars.removeSubrange(..<cursor)
        cursor = 0
    }

    mutating func wordLeft() {
        while cursor > 0 && chars[cursor - 1] == " " { cursor -= 1 }
        while cursor > 0 && chars[cursor - 1] != " " { cursor -= 1 }
    }

    mutating func wordRight() {
        while cursor < chars.count && chars[cursor] == " " { cursor += 1 }
        while cursor < chars.count && chars[cursor] != " " { cursor += 1 }
    }

    mutating func deleteWordBack() {
        let end = cursor
        wordLeft()
        chars.removeSubrange(cursor..<end)
    }

    // Enter: the line, kept for ↑
    mutating func commit() -> String {
        let t = text
        if !t.trimmingCharacters(in: .whitespaces).isEmpty && history.last != t { history.append(t) }
        if history.count > 100 { history.removeFirst() }
        clear()
        return t
    }

    mutating func older() {
        guard !history.isEmpty else { return }
        if browsing == nil {
            draft = chars
            browsing = history.count
        }
        guard let b = browsing, b > 0 else { return }
        browsing = b - 1
        chars = Array(history[b - 1])
        cursor = chars.count
    }

    mutating func newer() {
        guard let b = browsing else { return }
        if b + 1 >= history.count {
            browsing = nil
            chars = draft
        } else {
            browsing = b + 1
            chars = Array(history[b + 1])
        }
        cursor = chars.count
    }
}

enum ViewItem: Equatable {
    case message(ChatMessage)
    case notice(Notice)
    case divider(String)
}

struct ViewLine: Equatable {
    var item: ViewItem
    var order: TimeInterval         // where it goes: a message by when it was written (never after it arrived)
}

// Everything the screen shows, as plain values – ChatApp fills it, render() draws it
struct ChatViewState {
    var lines: [ViewLine] = []
    var roomName = ""
    var roomID = ""
    var nickname = ""
    var fingerprint = ""
    var demo = false
    var terminalApp = ""            // the app macOS asks about Bluetooth
    var snapshot = MeshSnapshot()
    var pending: Set<UInt64> = []   // messages of ours that no other Mac has yet
    var editor = LineEditor()
    var scroll = 0                  // rows scrolled up from the newest
    var confirmLeave = false
    var hops = Proto.defaultHops

    // A line in its place, by time; the oldest go when there are too many
    mutating func add(_ item: ViewItem, order: TimeInterval) {
        var i = lines.count
        while i > 0 && lines[i - 1].order > order { i -= 1 }
        lines.insert(ViewLine(item: item, order: order), at: i)
        if lines.count > 1500 { lines.removeFirst(lines.count - 1500) }
    }

    var othersHere: [Participant] { snapshot.participants.filter { !$0.left } }
}

enum ChatRender {
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ t: TimeInterval) -> String { clock.string(from: Date(timeIntervalSince1970: t)) }

    // All rows of the message area, oldest first
    static func messageRows(_ s: ChatViewState, width: Int) -> [String] {
        let names = s.lines.compactMap { line -> String? in
            if case .message(let m) = line.item { return m.nickname }
            return nil
        }
        // " 14:02  " + the name + "  " + the text; narrow windows give the name less room
        let nameWidth = min(12, max(4, width / 5), max(4, names.map { cellWidth($0) }.max() ?? 4))
        let indent = 8 + nameWidth + 2
        let textWidth = max(4, width - indent - 1)
        var rows: [String] = []
        for line in s.lines {
            switch line.item {
            case .message(let m):
                // after the text, dim: the relays it took, a late arrival, or that nobody has it yet
                var extra = ""
                if m.hops > 0 { extra += " ⇢\(m.hops)" }
                if m.received - m.sent > 90 && !m.mine { extra += " (arrived \(time(m.received)))" }
                if m.mine && s.pending.contains(m.id) { extra += " · waiting for someone nearby" }
                var chunks = wrap(m.text, textWidth)
                if !extra.isEmpty {
                    let last = chunks.removeLast()
                    if cellWidth(last) + cellWidth(extra) <= textWidth {
                        chunks.append(last + Theme.dim(extra))
                    } else {
                        chunks.append(last)
                        chunks.append(Theme.dim(String(extra.dropFirst())))
                    }
                }
                let name = clip(m.nickname, nameWidth)
                let pad = String(repeating: " ", count: max(0, nameWidth - cellWidth(name)))
                let who = m.mine ? Theme.bold(Theme.accent(name)) : Theme.person(m.fingerprint, name)
                for (i, text) in chunks.enumerated() {
                    if i == 0 {
                        rows.append(" " + Theme.dim(time(m.sent)) + "  " + who + pad + "  " + text)
                    } else {
                        rows.append(String(repeating: " ", count: indent) + text)
                    }
                }
            case .notice(let n):
                let paint: (String) -> String = n.level == .error ? Theme.red : n.level == .warning ? Theme.yellow : Theme.dim
                let chunks = wrap(n.text, max(2, width - 10))
                for (i, chunk) in chunks.enumerated() {
                    rows.append(i == 0 ? " " + Theme.dim(time(line.order)) + "  " + paint("· " + chunk) : String(repeating: " ", count: 10) + paint(chunk))
                }
            case .divider(let text):
                let label = " \(text) "
                let side = max(2, (width - 2 - cellWidth(label)) / 2)
                rows.append(" " + Theme.dim(String(repeating: "─", count: side) + label + String(repeating: "─", count: side)))
            }
        }
        return rows
    }

    // What to do when nobody is there yet
    static func lonelyRows(_ s: ChatViewState) -> [String] {
        if s.demo { return [] }
        var rows = ["", "   " + Theme.bold("No one else is here yet.")]
        switch s.snapshot.radio {
        case .on:
            rows += [
                "   · On the other Macs: " + Theme.key("lotus meshchat join <room code>") + Theme.dim("  – the code: /invite"),
                "   · Bluetooth on there too, within about 10 m – walls and bodies shorten that",
                "   · Others in this room pass messages on: one Mac in between reaches further",
                "   · Not working? Close the chat (ctrl-c) and run " + Theme.key("lotus meshchat doctor"),
            ]
        case .off:
            rows.append("   · Bluetooth is off – turn it on in Control Center or System Settings › Bluetooth")
        case .unauthorized:
            rows.append("   · \(s.terminalApp.isEmpty ? "Your terminal" : s.terminalApp) may not use Bluetooth – allow it in System Settings › Privacy & Security › Bluetooth")
        case .starting:
            rows.append("   · Starting Bluetooth – if macOS asks whether \(s.terminalApp.isEmpty ? "your terminal" : s.terminalApp) may use Bluetooth, choose Allow")
        case .unsupported:
            rows.append("   · This Mac has no Bluetooth Low Energy")
        case .resetting:
            rows.append("   · Bluetooth is restarting …")
        }
        return rows.map { Theme.dim($0) }
    }

    static func header(_ s: ChatViewState, width: Int) -> String {
        let room = Theme.bold(clip(s.roomName.isEmpty ? "#\(s.roomID)" : s.roomName, max(8, width / 3)))
        let title = " " + Theme.bold(Theme.accent("lotus")) + Theme.dim(" / ") + Theme.bold("MeshChat") + "  " + room
        let id = s.roomName.isEmpty ? "" : Theme.dim("  #\(s.roomID)")
        // the most that fits: everything · without the ID · DEMO short · without "you:" · just the title
        let candidates: [(String, String)] = [
            (title + id + (s.demo ? "  " + Theme.yellow("DEMO – simulated, no Bluetooth") : ""), Theme.dim("you: ") + Theme.accent(s.nickname) + Theme.dim("·\(s.fingerprint)") + " "),
            (title + (s.demo ? "  " + Theme.yellow("DEMO") : ""), Theme.dim("you: ") + Theme.accent(s.nickname) + Theme.dim("·\(s.fingerprint)") + " "),
            (title + (s.demo ? "  " + Theme.yellow("DEMO") : ""), Theme.accent(s.nickname) + " "),
            (title + (s.demo ? "  " + Theme.yellow("DEMO") : ""), ""),
        ]
        for (left, right) in candidates {
            let gap = width - visibleWidth(left) - visibleWidth(right)
            if gap >= 1 { return left + String(repeating: " ", count: gap) + right }
        }
        return title
    }

    static func peopleRule(_ s: ChatViewState, width: Int) -> String {
        let people = s.othersHere
        var text = ""
        if people.isEmpty {
            text = Theme.dim(" no one else here yet ")
        } else {
            var parts: [String] = []
            var used = 10
            for (i, p) in people.enumerated() {
                let mark = p.away ? Theme.dim(" ○") : p.direct ? Theme.green(" ●") : Theme.dim(" ⇢\(p.hops)")
                let part = Theme.person(p.fingerprint, clip(p.nickname, 16)) + mark
                let w = visibleWidth(part) + 3
                if used + w > width - 16 {
                    parts.append(Theme.dim("+\(people.count - i) more · /who"))
                    break
                }
                parts.append(part)
                used += w
            }
            text = Theme.dim(" here: ") + parts.joined(separator: Theme.dim(" · ")) + " "
        }
        let fill = max(0, width - 3 - visibleWidth(text))
        return Theme.dim(" ──") + text + Theme.dim(String(repeating: "─", count: fill))
    }

    static func status(_ s: ChatViewState, width: Int) -> String {
        let snap = s.snapshot
        var left: String
        switch snap.radio {
        case .on: left = Theme.green(" ●") + " Bluetooth on"
        case .off: left = Theme.red(" ●") + " Bluetooth is off – turn it on in Control Center"
        case .unauthorized: left = Theme.red(" ●") + " Bluetooth not allowed – System Settings › Privacy & Security › Bluetooth"
        case .unsupported: left = Theme.red(" ●") + " No Bluetooth LE on this Mac"
        case .starting: left = Theme.yellow(" ●") + " Starting Bluetooth …"
        case .resetting: left = Theme.yellow(" ●") + " Bluetooth is restarting …"
        }
        if s.demo { left = Theme.yellow(" ●") + " Simulated" }
        if snap.radio == .on || s.demo {
            left += Theme.dim(" · \(snap.links) link\(snap.links == 1 ? "" : "s")")
            if snap.connecting > 0 { left += Theme.dim(" · connecting") }
            else if snap.scanning && snap.links == 0 { left += Theme.dim(" · looking for Macs nearby") }
            if snap.stats.relayed > 0 { left += Theme.dim(" · \(snap.stats.relayed) relayed") }
        }
        let right = Theme.dim(s.scroll > 0 ? "↓ PgDn · /help " : "/help · ctrl-c quits ")
        let gap = width - visibleWidth(left) - visibleWidth(right)
        return gap >= 1 ? left + String(repeating: " ", count: gap) + right : left
    }

    // The input line and where the cursor goes in it
    static func input(_ s: ChatViewState, width: Int) -> (String, Int) {
        if s.confirmLeave {
            let name = clip(s.roomName.isEmpty ? "#" + s.roomID : s.roomName, 24)
            let q = " Leave \"\(name)\" and delete its code and history from this Mac? y/n "
            return (Theme.yellow(clip(q, width - 1)), min(width, cellWidth(clip(q, width - 1)) + 1))
        }
        let prompt = " › "
        let room = max(4, width - 4 - (s.editor.bytes > 800 ? 6 : 0))
        let chars = s.editor.chars
        // the part of the line around the cursor that fits
        var start = 0
        while cellWidth(String(chars[start..<s.editor.cursor])) > room - 1 { start += 1 }
        var shown = ""
        var w = 0
        for ch in chars[start...] {
            let cw = cellWidth(ch)
            if w + cw > room { break }
            shown.append(ch)
            w += cw
        }
        var line = Theme.accent(prompt) + shown
        if s.editor.bytes > 800 { line += Theme.dim(" \(Proto.maxTextBytes - s.editor.bytes)") }
        let column = cellWidth(prompt) + cellWidth(String(chars[start..<s.editor.cursor])) + 1
        return (line, column)
    }

    // The whole screen: rows × cols
    static func frame(_ s: ChatViewState, rows: Int, cols: Int) -> String {
        var out = "\u{1B}[?2026h\u{1B}[?25l"
        // every row cut to the window: a row too wide would wrap and push the screen out of place
        func put(_ r: Int, _ text: String) { out += "\u{1B}[\(r);1H" + fit(text, cols) + "\u{1B}[0m\u{1B}[K" }
        let tiny = rows < 8 || cols < 30
        let top = tiny ? 1 : 3
        let bottom = tiny ? rows - 1 : rows - 3
        if !tiny {
            put(1, header(s, width: cols))
            put(2, Theme.dim(" " + String(repeating: "─", count: max(0, cols - 2))))
        }
        let height = max(1, bottom - top + 1)
        var content = messageRows(s, width: cols)
        if s.othersHere.isEmpty { content += lonelyRows(s) }
        let scroll = min(s.scroll, max(0, content.count - height))
        let end = content.count - scroll
        let visible = Array(content[max(0, end - height)..<max(0, end)])
        for i in 0..<height {
            put(top + i, i < visible.count ? visible[i] : "")
        }
        if !tiny {
            put(rows - 2, peopleRule(s, width: cols))
            put(rows - 1, status(s, width: cols))
        }
        let (line, column) = input(s, width: cols)
        put(rows, line)
        out += "\u{1B}[\(rows);\(min(cols, column))H\u{1B}[?25h\u{1B}[?2026l"
        return out
    }
}
