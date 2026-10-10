// Lotus AI – drawing: streamed Markdown, tool steps, the input box and menus.

import Foundation

// ── Streamed Markdown ─────────────────────────────────────────
// Turns text that arrives in small pieces into wrapped, colored terminal output.
// Handles code fences, headings, bullets, `inline code` and **bold**.

final class MarkdownStream {
    private let firstPrefix: String
    private let prefix: String
    private let baseStyle: String
    private let maxLines: Int
    private var started = false
    private var col = 0
    private var lines = 0
    private var truncated = false

    private var atLineStart = true
    private var head = ""
    private var lineKind: LineKind = .undecided
    private var fullLine = ""          // headings and fence lines are collected whole
    private var inFence = false
    private var inCode = false
    private var bold = false
    private var pendingStar = false
    private var word = ""
    private var wordWidth = 0
    private var html = ""              // "<…" or "&…" that may still become an HTML tag or entity
    private var htmlCode = false       // inside <code>…</code>: only its end tag counts
    private var tableLine = false      // a Markdown table row: a <br> in it must not break the row

    private enum LineKind { case undecided, text, heading, fence }

    init(bullet: String, style: String = "", maxLines: Int = .max) {
        self.firstPrefix = bullet
        self.prefix = "  "
        self.baseStyle = style
        self.maxLines = maxLines
    }

    private var width: Int { max(30, min(Term.width, 120) - 2) }

    private func out(_ s: String) {
        guard !truncated else { return }
        emit(s)
    }

    private func startLine() {
        if !started {
            started = true
            out(firstPrefix + baseStyle)
        } else {
            out(prefix + baseStyle)
        }
        col = 2
    }

    private func newline() {
        flushWord()
        if col == 0 { startLine() }
        out(Style.reset + "\n")
        col = 0
        lines += 1
        inCode = false
        bold = false
        htmlCode = false
        tableLine = false
        if lines >= maxLines && !truncated {
            truncated = true
        }
    }

    func feed(_ text: String) {
        for ch in text { feed(ch) }
    }

    private func feed(_ ch: Character) {
        if inFence { fenceChar(ch); return }
        if atLineStart {
            if lineKind == .heading || lineKind == .fence {
                if ch == "\n" { finishCollected() } else { fullLine.append(ch) }
                return
            }
            if ch == "\n" {
                let pending = head
                head = ""
                atLineStart = false
                lineKind = .text
                for c in pending { inline(c) }
                inline("\n")
                return
            }
            head.append(ch)
            let trimmed = head.drop(while: { $0 == " " })
            if trimmed.isEmpty { return }
            if trimmed.hasPrefix("```") {
                lineKind = .fence
                fullLine = head
                head = ""
                return
            }
            if trimmed.first == "`" && trimmed.count < 3 { return }
            if trimmed.first == "#" {
                if trimmed.count < 2 { return }
                if trimmed.allSatisfy({ $0 == "#" }) && trimmed.count < 6 { return }
                if trimmed.drop(while: { $0 == "#" }).first == " " {
                    lineKind = .heading
                    fullLine = head
                    head = ""
                    return
                }
            }
            if trimmed.first == "-" || trimmed.first == "*" {
                if trimmed.count < 2 { return }
                if trimmed.dropFirst().first == " " {
                    let indent = String(head.prefix(while: { $0 == " " }))
                    head = ""
                    atLineStart = false
                    lineKind = .text
                    if col == 0 { startLine() }
                    out(indent + Style.logo + "•" + Style.reset + baseStyle + " ")
                    col += cellWidth(indent) + 2
                    return
                }
            }
            let pending = head
            head = ""
            atLineStart = false
            lineKind = .text
            tableLine = pending.drop(while: { $0 == " " }).first == "|"
            for c in pending { inline(c) }
            return
        }
        inline(ch)
    }

    private func finishCollected() {
        let line = fullLine
        fullLine = ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if lineKind == .fence {
            let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            if col == 0 { startLine() }
            out(Style.border + "╭─" + (lang.isEmpty ? "" : " " + Style.dim + lang) + Style.reset + "\n")
            col = 0
            lines += 1
            inFence = true
        } else {
            let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            if col == 0 { startLine() }
            out(Style.bold + Style.accent + HTMLText.plain(stripMarks(text)) + Style.reset + "\n")
            col = 0
            lines += 1
        }
        lineKind = .undecided
        atLineStart = true
    }

    private func stripMarks(_ s: String) -> String { s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }

    private func fenceChar(_ ch: Character) {
        if ch != "\n" { fullLine.append(ch); return }
        let line = fullLine
        fullLine = ""
        if col == 0 { startLine() }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            out(Style.border + "╰─" + Style.reset + "\n")
            inFence = false
        } else {
            out(Style.border + "│ " + Style.reset + Style.code + line + Style.reset + "\n")
        }
        col = 0
        lines += 1
        if lines >= maxLines { truncated = true }
    }

    // HTML that models write into Markdown (<br>, <b>, &nbsp; …) does what it means instead of showing up as
    // text – never in code. Tags Lotus does not know stay as written (List<T>).
    private func inline(_ ch: Character) {
        if !html.isEmpty {
            html.append(ch)
            switch HTMLText.read(html) {
            case .more:
                return
            case .text:
                let s = html
                html = ""
                put(s.first!)                       // not HTML – what follows may start something new
                for c in s.dropFirst() { inline(c) }
            case .tag(let name, let closing):
                let s = html
                html = ""
                if htmlCode && !(closing && HTMLText.codeTags.contains(name)) {
                    for c in s { put(c) }           // inside <code>: tags are code
                } else {
                    tag(name, closing)
                }
            case .char(let c):
                html = ""
                put(c)
            }
            return
        }
        if (ch == "<" || ch == "&") && (!inCode || htmlCode) {
            html = String(ch)
            return
        }
        put(ch)
    }

    private func tag(_ name: String, _ closing: Bool) {
        if pendingStar { pendingStar = false; word.append("*"); wordWidth += 1 }
        switch name {
        case "br":
            if tableLine { put(" "); put("/"); put(" ") } else { put("\n") }
        case "p", "div", "hr":
            if closing || name == "hr" { put("\n") }
        case "b", "strong":
            bold = !closing
            word += bold ? Style.bold : Style.boldOff + baseStyle
        case "i", "em", "cite", "var":
            word += closing ? "\u{1B}[23m" : Style.italic
        case "u", "ins":
            word += closing ? "\u{1B}[24m" : "\u{1B}[4m"
        case "s", "del", "strike":
            word += closing ? "\u{1B}[29m" : "\u{1B}[9m"
        case _ where HTMLText.codeTags.contains(name):
            inCode = !closing
            htmlCode = !closing
            word += inCode ? Style.code : Style.reset + baseStyle + (bold ? Style.bold : "")
        default:
            break                                   // sub, sup, mark, span, font …: only the text stays
        }
    }

    private func put(_ ch: Character) {
        if pendingStar {
            pendingStar = false
            if ch == "*" {
                bold.toggle()
                word += bold ? Style.bold : Style.boldOff + baseStyle
                return
            }
            word.append("*")
            wordWidth += 1
        }
        switch ch {
        case "\n":
            newline()
            atLineStart = true
            lineKind = .undecided
        case "`":
            inCode.toggle()
            word += inCode ? Style.code : Style.reset + baseStyle + (bold ? Style.bold : "")
        case "*" where !inCode:
            pendingStar = true
        case " ":
            flushWord()
            if col == 0 { startLine() }
            if col < width { out(" "); col += 1 }
        default:
            word.append(ch)
            wordWidth += cellWidth(ch)
        }
    }

    private func flushWord() {
        guard !word.isEmpty else { return }
        if col == 0 { startLine() }
        if col + wordWidth > width && col > 2 && wordWidth < width - 2 {
            out(Style.reset + "\n")
            lines += 1
            if lines >= maxLines { truncated = true }
            startLine()
            if bold { out(Style.bold) }
            if inCode { out(Style.code) }
        }
        out(word)
        col += wordWidth
        word = ""
        wordWidth = 0
    }

    // Ends the block; returns true when lines were left out
    @discardableResult
    func finish() -> Bool {
        if pendingStar { pendingStar = false; word.append("*"); wordWidth += 1 }
        if inFence {
            if !fullLine.isEmpty { fenceChar("\n") }
            if inFence {
                if col == 0 { startLine() }
                out(Style.border + "╰─" + Style.reset + "\n")
                inFence = false
                col = 0
            }
        } else if lineKind == .heading || lineKind == .fence {
            finishCollected()
        } else if !head.isEmpty {
            let pending = head
            head = ""
            for c in pending { inline(c) }
        }
        if !html.isEmpty {                          // the answer ended in the middle: it was text
            let s = html
            html = ""
            for c in s { put(c) }
        }
        flushWord()
        if col > 0 { out(Style.reset + "\n"); col = 0 }
        let wasTruncated = truncated
        truncated = false
        if wasTruncated { emit("  \(Style.dim)…\(Style.reset)\n") }
        return wasTruncated
    }

    var hasOutput: Bool { started }
}

// ── HTML in Markdown ──────────────────────────────────────────
// Models write <br> into table cells, <b>, <sup>, &nbsp; … The terminal shows what they mean; the web chat
// (lib/ai/web/app.js) does the same with the same list. Unknown tags stay as written.

enum HTMLText {
    enum Result: Equatable { case more, text, tag(String, Bool), char(Character) }

    static let tags: Set<String> = ["br", "b", "strong", "i", "em", "u", "s", "del", "strike", "ins", "sub", "sup", "mark", "small",
                                    "kbd", "code", "q", "abbr", "cite", "var", "samp", "tt", "span", "font", "p", "div", "hr"]
    static let codeTags: Set<String> = ["code", "kbd", "samp", "tt"]
    static let wrappers: Set<String> = ["span", "font"]       // these may carry attributes: they are dropped whole
    static let entities: [String: Character] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "mdash": "—", "ndash": "–", "hellip": "…",
        "copy": "©", "reg": "®", "trade": "™", "times": "×", "divide": "÷", "rarr": "→", "larr": "←", "uarr": "↑", "darr": "↓",
        "harr": "↔", "deg": "°", "euro": "€", "pound": "£", "yen": "¥", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "plusmn": "±", "le": "≤", "ge": "≥", "ne": "≠", "check": "✓",
    ]

    // What "<…" or "&…" is so far: maybe more to come, plain text, a known tag or an entity's character
    static func read(_ s: String) -> Result {
        guard let first = s.first else { return .text }
        let body = s.dropFirst()
        if first == "<" {
            if s.count > 120 || body.contains("\n") || body.contains("<") { return .text }
            var inner = Substring(body)
            if inner.hasSuffix(">") {
                inner = inner.dropLast()
                let closing = inner.hasPrefix("/")
                if closing { inner = inner.dropFirst() }
                let name = inner.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
                let rest = inner.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                guard tags.contains(name) else { return .text }
                if !(rest.isEmpty || rest == "/") && !wrappers.contains(name) { return .text }
                return .tag(name, closing)
            }
            if inner.hasPrefix("/") { inner = inner.dropFirst() }
            if inner.isEmpty { return .more }
            let name = inner.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) })
            if name.isEmpty { return .text }                              // "< 3", "<-"
            if name.count == inner.count { return name.count <= 6 ? .more : .text }
            let after = inner.dropFirst(name.count)
            if after.allSatisfy({ $0 == " " || $0 == "/" }) && after.count <= 2 { return .more }    // "<br /"
            if wrappers.contains(name.lowercased()) && after.first == " " { return .more }          // <span style=…
            return .text
        }
        guard first == "&" else { return .text }
        if s.hasSuffix(";") && s.count > 2 {
            let name = String(body.dropLast())
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                guard let v = value, v >= 0x20, !(0x7F...0x9F).contains(v), let u = Unicode.Scalar(v) else { return .text }
                return .char(Character(u))
            }
            return entities[name].map { .char($0) } ?? .text
        }
        if body.count > 8 { return .text }
        let ok = body.enumerated().allSatisfy { i, c in c.isASCII && (c.isLetter || c.isNumber || (i == 0 && c == "#")) }
        return ok ? .more : .text
    }

    // A whole line at once (headings): line breaks become spaces, known tags go, entities become characters
    static func plain(_ s: String) -> String {
        guard s.contains("<") || s.contains("&") else { return s }
        var out = ""
        var pending = ""
        for ch in s {
            if !pending.isEmpty {
                pending.append(ch)
                switch read(pending) {
                case .more: continue
                case .text: out += pending; pending = ""
                case .tag(let name, _): out += name == "br" ? " " : ""; pending = ""
                case .char(let c): out.append(c); pending = ""
                }
            } else if ch == "<" || ch == "&" {
                pending = String(ch)
            } else {
                out.append(ch)
            }
        }
        return out + pending
    }
}

// ── What the assistant is doing, as blocks ────────────────────

final class Renderer: @unchecked Sendable {
    static let shared = Renderer()
    private let lock = NSLock()
    private var text: MarkdownStream?
    private var thinking: MarkdownStream?
    private var thinkingStarted: Date?
    var quiet = false            // plain mode: no bullets, no colors
    // The web chat (Server.swift): every block becomes an event for the browser instead of terminal output
    var sink: ((String, [String: Any]) -> Void)?
    private var webText = false  // a text block is open in the web chat

    func textDelta(_ s: String) {
        guard !s.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if let sink = sink {
            webCloseThinking(sink)
            webText = true
            sink("text", ["text": s])
            return
        }
        closeThinking()
        if quiet { emit(s); return }
        if text == nil { text = MarkdownStream(bullet: Style.logo + "● " + Style.reset) }
        text?.feed(s)
    }

    // Thinking stays out of the way: the spinner (the pet's face) says "Thinking", afterwards one
    // short line says for how long – only the answer is shown
    func thinkingDelta(_ s: String) {
        guard !s.isEmpty, !quiet else { return }
        lock.lock(); defer { lock.unlock() }
        if let sink = sink {
            if thinkingStarted == nil { thinkingStarted = Date(); sink("thinking", [:]) }
            return
        }
        if thinkingStarted == nil {
            closeText()
            thinkingStarted = Date()
            Spinner.shared.start("Thinking")
        }
    }

    private func closeText() {
        if let t = text {
            t.finish()
            text = nil
            emit("\n")
        }
    }

    private func closeThinking() {
        if let started = thinkingStarted {
            thinking = nil
            thinkingStarted = nil
            let secs = Int(Date().timeIntervalSince(started))
            emit("\(Style.dim)✻ thought for \(max(1, secs))s\(Style.reset)\n")
        }
    }

    private func webCloseThinking(_ sink: (String, [String: Any]) -> Void) {
        guard let started = thinkingStarted else { return }
        thinkingStarted = nil
        sink("thought", ["secs": max(1, Int(Date().timeIntervalSince(started)))])
    }

    // Closes whatever is open, e.g. before a tool step or at the end of the answer
    func endBlock() {
        lock.lock(); defer { lock.unlock() }
        if let sink = sink {
            webCloseThinking(sink)
            if webText { webText = false; sink("end", [:]) }
            return
        }
        closeThinking()
        if quiet {
            if text != nil { text = nil }
            return
        }
        closeText()
    }

    func toolHeader(_ name: String, _ detail: String) {
        endBlock()
        if let sink = sink { sink("tool", ["name": name, "detail": String(detail.prefix(2000))]); return }
        let room = max(10, Term.width - cellWidth(name) - 6)
        let args = detail.isEmpty ? "" : "\(Style.dim)(\(Style.reset)\(clip(detail, room))\(Style.dim))\(Style.reset)"
        emit("\(Style.key)●\(Style.reset) \(Style.bold)\(name)\(Style.reset)\(args)\n")
    }

    func toolResult(_ summary: String, error: Bool = false) {
        if let sink = sink { sink("result", ["text": String(summary.prefix(2000)), "error": error]); return }
        let color = error ? Style.red : Style.dim
        emit("  \(Style.dim)⎿\(Style.reset)  \(color)\(clip(summary, max(20, Term.width - 6)))\(Style.reset)\n\n")
    }

    // Indented preview lines below a tool step
    func toolLines(_ lines: [String], color: String = Style.dim, limit: Int = 8) {
        if let sink = sink {
            // the browser has room for more of a preview; a long one scrolls
            let n = max(limit, 40)
            let kind = color == Style.green ? "add" : color == Style.red ? "del" : color == Style.accent ? "note" : "dim"
            sink("lines", ["lines": lines.prefix(n).map { String($0.replacingOccurrences(of: "\t", with: "    ").prefix(400)) },
                           "more": max(0, lines.count - n), "color": kind])
            return
        }
        let width = max(20, Term.width - 7)
        for line in lines.prefix(limit) {
            emit("     \(color)\(clip(line.replacingOccurrences(of: "\t", with: "  "), width))\(Style.reset)\n")
        }
        if lines.count > limit {
            emit("     \(Style.dim)… \(lines.count - limit) more lines\(Style.reset)\n")
        }
    }

    // The improved prompt before it is sent (/enhance): dimmed, the first lines
    func improvedPrompt(_ text: String, asking: Bool = false) {
        endBlock()
        if let sink = sink { sink("improved", ["text": text]); return }
        guard !quiet else { return }
        let (lines, more) = Enhance.rows(text, width: max(20, min(Term.width, 120) - 4), rows: 6)
        var out = "\(Style.dim)✻ Improved prompt\(asking ? " – send it?" : "")\(Style.reset)\n"
        for l in lines { out += "  \(Style.dim)\(l)\(Style.reset)\n" }
        if more { out += "  \(Style.dim)…\(Style.reset)\n" }
        emit(out + (asking ? "" : "\n"))
    }

    func info(_ s: String) {
        endBlock()
        if let sink = sink {
            let text = ToolRunner.plain(s).trimmingCharacters(in: CharacterSet(charactersIn: " \n⎿✻"))
            if !text.isEmpty { sink("info", ["text": text]) }
            return
        }
        emit("  \(Style.dim)\(s)\(Style.reset)\n")
    }

    func error(_ title: String, _ detail: String = "") {
        Log.write("ERROR", detail.isEmpty ? title : "\(title) – \(detail)")
        endBlock()
        if let sink = sink { sink("error", ["title": title, "detail": detail]); return }
        emit("\(Style.red)●\(Style.reset) \(Style.bold)\(title)\(Style.reset)\n")
        if !detail.isEmpty {
            for line in detail.split(separator: "\n", omittingEmptySubsequences: false) {
                emit("  \(Style.dim)\(line)\(Style.reset)\n")
            }
        }
        emit("\n")
    }
}

// ── Frames ────────────────────────────────────────────────────

func frame(_ rows: [String], width: Int, color: String = Style.border) -> String {
    let inner = width - 4
    var out = color + "╭" + String(repeating: "─", count: width - 2) + "╮" + Style.reset + "\n"
    for row in rows {
        let pad = max(0, inner - visibleWidth(row))
        out += color + "│" + Style.reset + " " + row + String(repeating: " ", count: pad) + " " + color + "│" + Style.reset + "\n"
    }
    out += color + "╰" + String(repeating: "─", count: width - 2) + "╯" + Style.reset + "\n"
    return out
}

// ── Input box ─────────────────────────────────────────────────

struct SlashCommand {
    let name: String
    let help: String
}

final class InputBox {
    private let keys: KeyQueue
    private var text: [Character] = []
    private var cursor = 0
    private var history: [String]
    private var historyIndex: Int?
    private var draft: [Character] = []
    private var drawnRows = 0        // rows from the top of the box to the cursor
    private var exitArmed = false
    private let historyFile: URL?
    let commands: [SlashCommand]
    var status: () -> String = { "" }
    var autoMode: () -> Bool = { false }
    var onBacktab: (() -> Void)?

    init(keys: KeyQueue, commands: [SlashCommand], historyFile: URL?) {
        self.keys = keys
        self.commands = commands
        self.historyFile = historyFile
        if let f = historyFile, let data = try? String(contentsOf: f, encoding: .utf8) {
            history = data.split(separator: "\u{1E}").map(String.init).filter { !$0.isEmpty }
        } else {
            history = []
        }
    }

    private func remember(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if history.last != line { history.append(line) }
        if history.count > 200 { history.removeFirst(history.count - 200) }
        if let f = historyFile {
            try? history.joined(separator: "\u{1E}").write(to: f, atomically: true, encoding: .utf8)
            chmod(f.path, 0o600)
        }
    }

    private var suggestions: [SlashCommand] {
        let s = String(text)
        guard s.hasPrefix("/"), !s.contains(" "), !s.contains("\n") else { return [] }
        return commands.filter { $0.name.hasPrefix(s.lowercased()) }
    }

    // Wraps the text into rows; returns rows and the cursor's row/column
    private func layout(_ inner: Int) -> (rows: [String], row: Int, col: Int) {
        var rows: [String] = [""]
        var widths = [0]
        var cRow = 0, cCol = 0
        for (i, ch) in text.enumerated() {
            if i == cursor { cRow = rows.count - 1; cCol = widths[widths.count - 1] }
            if ch == "\n" {
                rows.append(""); widths.append(0)
                continue
            }
            let w = cellWidth(ch)
            if widths[widths.count - 1] + w > inner {
                rows.append(""); widths.append(0)
                if i == cursor { cRow = rows.count - 1; cCol = 0 }
            }
            rows[rows.count - 1].append(ch)
            widths[widths.count - 1] += w
        }
        if cursor == text.count {
            cRow = rows.count - 1
            cCol = widths[widths.count - 1]
            if cCol >= inner { rows.append(""); widths.append(0); cRow += 1; cCol = 0 }
        }
        return (rows, cRow, cCol)
    }

    private func render() {
        let width = max(24, Term.width - 1)
        let inner = width - 8
        var (rows, cRow, cCol) = layout(inner)
        // Keep tall input inside the window
        let maxRows = max(3, Term.height - 8)
        var first = 0
        if rows.count > maxRows {
            first = min(max(0, cRow - maxRows + 1), rows.count - maxRows)
            rows = Array(rows[first..<(first + maxRows)])
            cRow -= first
        }
        var out = ""
        if drawnRows > 0 { out += "\u{1B}[\(drawnRows)A" }
        out += "\r\u{1B}[J"
        out += Style.border + "╭" + String(repeating: "─", count: width - 2) + "╮" + Style.reset + "\n"
        for (i, row) in rows.enumerated() {
            let lead = (i == 0 && first == 0) ? Style.logo + ">" + Style.reset + " " : "  "
            let pad = max(0, inner - cellWidth(row))
            out += Style.border + "│" + Style.reset + " " + lead + row + String(repeating: " ", count: pad + 2) + " " + Style.border + "│" + Style.reset + "\n"
        }
        out += Style.border + "╰" + String(repeating: "─", count: width - 2) + "╯" + Style.reset
        // Footer: command suggestions or hints and status
        var footer: [String] = []
        let sugg = suggestions
        if !sugg.isEmpty {
            for c in sugg.prefix(8) {
                footer.append("  " + Style.logo + c.name.padding(toLength: 12, withPad: " ", startingAt: 0) + Style.reset + Style.dim + c.help + Style.reset)
            }
        } else {
            let auto = !exitArmed && autoMode()
            let left = exitArmed ? "Press Ctrl-C again to quit"
                : auto ? "⏵⏵ auto – asks only when unsure · ⇧⇥ off"
                : onBacktab != nil && width >= 96 ? "/ for commands · ⌥⏎ new line · ⇧⇥ auto · ctrl-d quits"
                : "/ for commands · ⌥⏎ new line · ctrl-d quits"
            let right = status()
            let gap = max(2, width - cellWidth(left) - cellWidth(right) - 2)
            let shown = auto ? Style.accent + left + Style.dim : left
            footer.append("  " + Style.dim + shown + String(repeating: " ", count: gap) + right + Style.reset)
        }
        for f in footer { out += "\n" + f }
        // Move back to the cursor
        let totalBelow = (rows.count - cRow) + footer.count
        out += "\u{1B}[\(totalBelow)A\r\u{1B}[\(4 + cCol)C"
        drawnRows = 1 + cRow
        Out.shared.write(out)
    }

    private func clearBox() {
        var out = ""
        if drawnRows > 0 { out += "\u{1B}[\(drawnRows)A" }
        out += "\r\u{1B}[J"
        Out.shared.write(out)
        drawnRows = 0
    }

    private func insert(_ s: String) {
        for ch in s where ch != "\r" {
            text.insert(ch, at: cursor)
            cursor += 1
        }
    }

    private func wordStart(from i: Int) -> Int {
        var j = i
        while j > 0 && text[j - 1] == " " { j -= 1 }
        while j > 0 && text[j - 1] != " " && text[j - 1] != "\n" { j -= 1 }
        return j
    }

    private func wordEnd(from i: Int) -> Int {
        var j = i
        while j < text.count && text[j] == " " { j += 1 }
        while j < text.count && text[j] != " " && text[j] != "\n" { j += 1 }
        return j
    }

    // Reads one message. nil means the user wants to leave.
    func read() async -> String? {
        text = []
        cursor = 0
        historyIndex = nil
        drawnRows = 0
        render()
        while true {
            let key = await keys.next()
            if key != .ctrlC { exitArmed = false }
            switch key {
            case .cancelled:
                clearBox()
                return nil
            case .char(let ch):
                insert(String(ch))
            case .paste(let s):
                insert(s)
            case .enter:
                if cursor > 0 && text[cursor - 1] == "\\" {
                    text[cursor - 1] = "\n"
                } else if !suggestions.isEmpty && suggestions.first?.name != String(text) && !String(text).contains(" ") {
                    text = Array(suggestions[0].name)
                    cursor = text.count
                    fallthrough
                } else {
                    let line = String(text)
                    clearBox()
                    echo(line)
                    remember(line)
                    return line
                }
            case .newline:
                if key == .newline { insert("\n") }
            case .backtab:
                onBacktab?()
            case .tab:
                if let s = suggestions.first {
                    text = Array(s.name + " ")
                    cursor = text.count
                }
            case .backspace:
                if cursor > 0 { text.remove(at: cursor - 1); cursor -= 1 }
            case .delete:
                if cursor < text.count { text.remove(at: cursor) }
            case .wordBackspace, .ctrlW:
                let s = wordStart(from: cursor)
                text.removeSubrange(s..<cursor)
                cursor = s
            case .left:
                cursor = max(0, cursor - 1)
            case .right:
                cursor = min(text.count, cursor + 1)
            case .wordLeft:
                cursor = wordStart(from: cursor)
            case .wordRight:
                cursor = wordEnd(from: cursor)
            case .home, .ctrlA:
                cursor = (text[..<cursor].lastIndex(of: "\n").map { $0 + 1 }) ?? 0
            case .end, .ctrlE:
                cursor = (text[cursor...].firstIndex(of: "\n")) ?? text.count
            case .ctrlK:
                let e = (text[cursor...].firstIndex(of: "\n")) ?? text.count
                text.removeSubrange(cursor..<e)
            case .ctrlU:
                let s = (text[..<cursor].lastIndex(of: "\n").map { $0 + 1 }) ?? 0
                text.removeSubrange(s..<cursor)
                cursor = s
            case .up:
                if !text[..<cursor].contains("\n"), !history.isEmpty {
                    if historyIndex == nil { draft = text; historyIndex = history.count }
                    if let i = historyIndex, i > 0 {
                        historyIndex = i - 1
                        text = Array(history[i - 1])
                        cursor = text.count
                    }
                }
            case .down:
                if !text[cursor...].contains("\n"), let i = historyIndex {
                    if i + 1 < history.count {
                        historyIndex = i + 1
                        text = Array(history[i + 1])
                    } else {
                        historyIndex = nil
                        text = draft
                    }
                    cursor = text.count
                }
            case .ctrlL:
                Out.shared.write("\u{1B}[2J\u{1B}[H")
                drawnRows = 0
            case .ctrlC:
                if !text.isEmpty {
                    text = []; cursor = 0
                } else if exitArmed {
                    clearBox()
                    return nil
                } else {
                    exitArmed = true
                }
            case .ctrlD:
                if text.isEmpty { clearBox(); return nil }
                if cursor < text.count { text.remove(at: cursor) }
            case .esc:
                if !text.isEmpty && String(text).hasPrefix("/") { text = []; cursor = 0 }
            default:
                break
            }
            render()
        }
    }

    // The message stays on screen above the answer
    private func echo(_ line: String) {
        let width = max(20, Term.width - 4)
        var out = ""
        for (i, part) in line.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lead = i == 0 ? Style.logo + ">" + Style.reset + " " : "  "
            out += lead + Style.dim + clip(String(part), width) + Style.reset + "\n"
        }
        Out.shared.write(out + "\n")
    }
}

// ── Menu ──────────────────────────────────────────────────────

// A small list to pick from with the arrow keys. Returns the index or nil.
func menu(_ title: String, _ items: [String], selected: Int = 0, keys: KeyQueue) async -> Int? {
    guard !items.isEmpty else { return nil }
    var sel = min(max(0, selected), items.count - 1)
    var drawn = 0
    func draw() {
        var out = drawn > 0 ? "\u{1B}[\(drawn)A\r\u{1B}[J" : ""
        out += "  \(Style.bold)\(title)\(Style.reset)\n"
        for (i, item) in items.enumerated() {
            out += i == sel ? "  \(Style.logo)› \(item)\(Style.reset)\n" : "    \(item)\n"
        }
        out += "  \(Style.dim)↑↓ choose · enter select · esc cancel\(Style.reset)\n"
        drawn = items.count + 2
        Out.shared.write(out)
    }
    Out.shared.write("\u{1B}[?25l")
    defer { Out.shared.write("\u{1B}[?25h") }
    draw()
    while true {
        switch await keys.next() {
        case .up: sel = (sel - 1 + items.count) % items.count
        case .down, .tab: sel = (sel + 1) % items.count
        case .enter:
            Out.shared.write("\u{1B}[\(drawn)A\r\u{1B}[J")
            return sel
        case .esc, .ctrlC, .cancelled, .char("q"):
            Out.shared.write("\u{1B}[\(drawn)A\r\u{1B}[J")
            return nil
        case .char(let c):
            if let n = c.wholeNumberValue, n >= 1, n <= items.count { sel = n - 1 }
        default: break
        }
        draw()
    }
}
