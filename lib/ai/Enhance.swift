// Lotus AI – better prompts (LOTUS_AI_ENHANCE, /enhance): before the AI sees a message, the same AI rewrites
// it into a clear prompt – the goal, the details, the expected result – with the instructions of
// data/ai/system.md ("## enhance"), the same for every provider. For /ai and the web chat alike.
//   off  messages go as typed (the default)
//   on   the improved prompt is shown and sent
//   ask  it is shown first: send it, send the original, or nothing
// The conversation keeps what the model saw (the improved prompt), so later turns stay consistent.

import Foundation

enum Enhance {
    static let modes = ["off", "on", "ask"]
    static let timeout: UInt64 = 30          // seconds; slower than that, the message goes as typed
    static let longest = 3000                // characters; longer messages go as typed

    // Why a message goes as typed, or nil when it is worth improving
    static func skip(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("/") { return "a command" }
        if t.split(whereSeparator: { $0.isWhitespace }).count <= 3 { return "3 words or fewer" }
        if t.count > longest { return "longer than \(longest) characters" }
        return nil
    }

    // What the rewriter gets: the last exchange (so a follow-up stays right) and the request
    static func request(_ text: String, after turns: [Turn]) -> String {
        var out = ""
        if let u = turns.last(where: { $0.role == "user" }), let a = turns.last(where: { $0.role == "assistant" }) {
            out = "Earlier in the conversation (context only, do not repeat it):\nUser: \(u.text.prefix(400))\n"
                + "Assistant: \(ChannelSplit.answer(a.text).prefix(400))\n\n"
        }
        return out + "The request to improve:\n" + text
    }

    // The improved prompt without a preface or quotes; nil when it is not useful (empty, unchanged,
    // or so long that the model answered the request instead of rewriting it)
    static func clean(_ reply: String, original: String) -> String? {
        var s = ChannelSplit.answer(reply).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") && s.hasSuffix("```") && s.count > 6 {
            s = String(s.dropFirst(3).dropLast(3))
            if let nl = s.firstIndex(of: "\n"), !s[..<nl].contains(" ") { s = String(s[s.index(after: nl)...]) }   // a language name
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for label in ["Improved request:", "Improved prompt:", "Improved:", "Prompt:"] where s.lowercased().hasPrefix(label.lowercased()) {
            s = String(s.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("„", "“"), ("«", "»"), ("'", "'")] where s.count > 2 && s.hasPrefix(open) && s.hasSuffix(close) {
            let inner = s.dropFirst(open.count).dropLast(close.count)
            if !inner.contains(open) { s = String(inner).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let was = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 2, s.count <= max(1200, was.count * 5), words(s) != words(was) else { return nil }
        return s
    }

    // Only letters and digits, in lower case: a rewrite that changed nothing but case, spaces or
    // punctuation is no better
    static func words(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    // Wrapped to the window, at most `rows` rows – for showing it in the terminal
    static func rows(_ text: String, width: Int, rows: Int) -> (lines: [String], more: Bool) {
        var out: [String] = []
        for para in text.components(separatedBy: "\n") {
            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                if !line.isEmpty && cellWidth(line) + 1 + cellWidth(w) > width {
                    out.append(line)
                    line = w
                } else {
                    line += line.isEmpty ? w : " " + w
                }
            }
            out.append(line)
        }
        return (out.prefix(rows).map { clip($0, width) }, out.count > rows)
    }

    // Set by the timer when the rewrite takes too long (so it is not taken for the user's esc)
    final class Late: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
}
