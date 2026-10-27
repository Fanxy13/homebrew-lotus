// MeshChat tests – the chat's screen: the line you write in, text wrapped to the window (wide characters too), and
// whole frames that fit the terminal at every size, from 20 × 6 to 200 × 50.

import Foundation

// The rows of a frame: what is written after each "go to row r" – escape codes count no width
private func rows(of frame: String) -> [Int: String] {
    var out: [Int: String] = [:]
    let parts = frame.components(separatedBy: "\u{1B}[")
    var current: Int?
    for part in parts {
        if let semi = part.firstIndex(of: ";"), let h = part.firstIndex(of: "H"), semi < h,
           let r = Int(part[..<semi]), part[part.index(after: semi)..<h] == "1" {
            current = r
            out[r] = String(part[part.index(after: h)...])
        } else if let r = current {
            out[r, default: ""] += "\u{1B}[" + part
        }
    }
    return out
}

func viewTests() {
    test("the line you write in: editing, words, history, limits") {
        var e = LineEditor()
        e.insert("hello wörld")
        checkEqual(e.text, "hello wörld", "typed")
        e.left(); e.left()
        e.backspace()
        checkEqual(e.text, "hello wöld", "backspace before the cursor")
        e.home()
        e.delete()
        checkEqual(e.text, "ello wöld", "delete at the start")
        e.end()
        e.deleteWordBack()
        checkEqual(e.text, "ello ", "a word back")
        e.insert("there")
        e.wordLeft()
        e.killToEnd()
        checkEqual(e.text, "ello ", "ctrl-k")
        e.insert("a\u{1B}[31mb\u{7}c\nd\te")
        checkEqual(e.text, "ello a[31mbc d e", "no escape or bell from a paste; line breaks and tabs are spaces")
        checkEqual(e.commit(), "ello a[31mbc d e", "enter gives the line")
        check(e.isEmpty, "and empties it")
        e.insert("second")
        _ = e.commit()
        e.insert("draft")
        e.older()
        checkEqual(e.text, "second", "↑ the last line")
        e.older()
        checkEqual(e.text, "ello a[31mbc d e", "↑ the one before")
        e.newer(); e.newer()
        checkEqual(e.text, "draft", "↓ back to what was being written")
        var long = LineEditor()
        long.insert(String(repeating: "ä", count: 600))
        checkEqual(long.bytes, 1000, "at most 1000 bytes (500 × ä)")
        long.killToStart()
        check(long.isEmpty, "ctrl-u")
    }

    test("text wrapped and cut to the window, wide characters counted twice") {
        checkEqual(wrap("aaa bbb ccc", 7), ["aaa bbb", "ccc"], "at spaces")
        checkEqual(wrap("abcdefghij", 4), ["abcd", "efgh", "ij"], "a word longer than the line is cut")
        checkEqual(wrap("漢字漢字漢字", 4), ["漢字", "漢字", "漢字"], "CJK takes two cells each")
        checkEqual(cellWidth("🌸a"), 3, "an emoji is two cells")
        checkEqual(cellWidth("é"), 1, "an accent is one")
        checkEqual(clip("abcdef", 4), "abc…", "cut with …")
        checkEqual(clip("ab", 4), "ab", "short enough: as it is")
        checkEqual(visibleWidth("\u{1B}[38;5;150mab\u{1B}[0m"), 2, "colors take no room")
    }

    test("every frame fits the window, whatever its size") {
        var s = ChatViewState()
        s.nickname = "A rather long nickname!!"
        s.fingerprint = "k3f9"
        s.snapshot.radio = .on
        s.snapshot.links = 2
        s.snapshot.stats.relayed = 12
        let key = Data(repeating: 1, count: 32)
        s.snapshot.participants = (0..<9).map {
            Participant(key: key, fingerprint: "f\($0)xx", nickname: "Person number \($0) 漢字", session: Data(count: 8),
                        lastSeen: 0, hops: $0 % 3, links: 1, direct: $0 % 3 == 0, left: false, away: $0 == 4,
                        signal: $0 == 0 ? Distance.rssi(metres: 3) : nil)
        }
        let texts = ["Hi", String(repeating: "long words in a long message ", count: 20), "漢字と絵文字 🌸🌸🌸 " + String(repeating: "あ", count: 80),
                     String(repeating: "x", count: 300)]
        for (i, t) in texts.enumerated() {
            s.add(.message(ChatMessage(id: UInt64(i), nickname: i % 2 == 0 ? "Bob" : "A very long nickname!!", fingerprint: "ab\(i)c",
                                       text: t, sent: 1_700_000_000 + Double(i), received: 1_700_000_500, hops: i, mine: i == 3)),
                  order: 1_700_000_000 + Double(i))
        }
        s.add(.notice(Notice(level: .warning, text: String(repeating: "a notice that wraps ", count: 12))), order: 1_700_000_100)
        s.editor.insert(String(repeating: "typing 漢字 ", count: 30))
        var failures: [String] = []
        for (r, c) in [(24, 80), (50, 200), (10, 40), (6, 20), (8, 30), (30, 100), (12, 33), (40, 61)] {
            let frame = ChatRender.frame(s, rows: r, cols: c)
            let drawn = rows(of: frame)
            if drawn.keys.max() ?? 0 > r { failures.append("\(c)×\(r): a row below the window") }
            if drawn.count != r { failures.append("\(c)×\(r): \(drawn.count) rows drawn") }
            for (n, text) in drawn where visibleWidth(text) > c {
                failures.append("\(c)×\(r): row \(n) is \(visibleWidth(text)) wide")
            }
        }
        check(failures.isEmpty, "no row wider than the window, all rows drawn \(failures.prefix(3))")
        let rule = ChatRender.peopleRule(s, width: 200).replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        check(rule.contains("● 3m"), "a neighbour's distance in the line of who is here (\(rule.prefix(60)))")
        check(ChatRender.header(s, width: 120).contains("everyone nearby") && ChatRender.header(s, width: 120).contains("public"),
              "the header says who reads it: everyone nearby – it is public")
        s.demo = true
        s.nickname = "Ada"
        s.fingerprint = "k3f9"
        let demo80 = ChatRender.header(s, width: 80)
        check(demo80.contains("DEMO – simulated") && demo80.contains("everyone nearby"), "at 80 columns the demo says it is simulated, and who reads it")
        s.demo = false
        s.snapshot.participants = []
        s.snapshot.radio = .unauthorized
        s.terminalApp = "Terminal"
        let lonely = ChatRender.frame(s, rows: 30, cols: 120)
        check(lonely.contains("Terminal may not use Bluetooth"), "no one here: what to do, with the app to allow")
        check(lonely.contains("Bluetooth not allowed"), "and the status says it")
        s.snapshot.radio = .on
        check(ChatRender.frame(s, rows: 30, cols: 140).contains("there are no rooms"), "and that the others only need to open MeshChat")
    }
}
