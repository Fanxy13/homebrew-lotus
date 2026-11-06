// MeshChat tests – the chat's screen: the line you write in, text wrapped to the window (wide characters too), whole
// frames that fit the terminal at every size, from 20 × 6 to 200 × 50, and the lines between the days.

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

    test("the days: a line before each – Today, Yesterday, 3 days ago, 1 week ago – in the language of Lotus") {
        let de: [(Int, String)] = [(-1, "Heute"), (0, "Heute"), (1, "Gestern"), (2, "vor 2 Tagen"), (6, "vor 6 Tagen"),
                                   (7, "vor 1 Woche"), (13, "vor 1 Woche"), (14, "vor 2 Wochen"), (29, "vor 4 Wochen"),
                                   (30, "vor 1 Monat"), (60, "vor 2 Monaten"), (364, "vor 11 Monaten"), (365, "vor 1 Jahr"),
                                   (800, "vor 2 Jahren")]
        checkEqual(de.map { Days.label(daysAgo: $0.0, language: "de") }, de.map { $0.1 }, "in German, from today to years ago")
        let en: [(Int, String)] = [(0, "Today"), (1, "Yesterday"), (3, "3 days ago"), (7, "1 week ago"), (21, "3 weeks ago"),
                                   (45, "1 month ago"), (100, "3 months ago"), (400, "1 year ago"), (1000, "2 years ago")]
        checkEqual(en.map { Days.label(daysAgo: $0.0, language: "en") }, en.map { $0.1 }, "in English")
        checkEqual([Days.label(daysAgo: 1, language: "fr"), Days.label(daysAgo: 8, language: "fr"), Days.label(daysAgo: 3, language: "es")],
                   ["Hier", "il y a 1 semaine", "hace 3 días"], "in French and Spanish")
        checkEqual(Days.label(daysAgo: 1, language: "it"), "Yesterday", "a language without words of its own: English")
        checkEqual([Days.pick("de"), Days.pick("de_CH"), Days.pick("FR-ch"), Days.pick("it"), Days.pick("d"), Days.pick(nil)],
                   ["de", "de", "fr", nil, nil, nil], "the language as LOTUS_LANG says it")

        // midnight in this Mac's time zone divides the days
        let midnight = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let noon = midnight + 12 * 3600
        checkEqual(Days.index(noon) - Days.index(midnight + 60), 0, "a minute after midnight is today")
        checkEqual(Days.index(noon) - Days.index(midnight - 60), 1, "a minute before it is yesterday")

        // the rows: a line before each day – 8 and 9 days ago are both 1 week ago – and the history's own line kept
        var s = ChatViewState()
        s.language = "de"
        for (i, ago) in [9, 8, 2, 1, 1].enumerated() {
            let t = noon - Double(ago) * 86400 + Double(i)
            s.add(.message(ChatMessage(id: UInt64(i), nickname: "Bob", fingerprint: "ab1c", text: "message \(i)", sent: t, received: t,
                                       hops: 0, mine: false)), order: t)
        }
        s.add(.divider("earlier messages above"), order: noon - 86400 + 10)
        s.add(.message(ChatMessage(id: 9, nickname: "Ada", fingerprint: "k3f9", text: "and now", sent: noon, received: noon, hops: 0, mine: true)),
              order: noon)
        s.add(.notice(Notice(level: .info, text: "Bob is here")), order: noon + 1)
        func plain(_ now: TimeInterval) -> [String] {
            ChatRender.messageRows(s, width: 60, now: now).map {
                $0.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            }
        }
        func rules(_ now: TimeInterval) -> [String] {
            plain(now).filter { $0.contains("───") }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ─")) }
        }
        checkEqual(rules(noon + 60), ["vor 1 Woche", "vor 2 Tagen", "Gestern", "earlier messages above", "Heute"], "a line before each day, in German")
        let shown = plain(noon + 60)
        check(shown.first?.contains(" vor 1 Woche ") ?? false, "the first row says the day of the oldest message")
        if let i = shown.firstIndex(where: { $0.contains(" Heute ") }), i + 1 < shown.count {
            check(shown[i + 1].contains("and now"), "today's message right under it (\(shown[i + 1]))")
        } else {
            check(false, "a line that says Heute")
        }
        check(shown.allSatisfy { visibleWidth($0) <= 60 }, "every line fits the window")
        checkEqual(rules(noon + 86400), ["vor 1 Woche", "vor 3 Tagen", "vor 2 Tagen", "earlier messages above", "Gestern"],
                   "the next day: what was today is yesterday")
        s.language = "en"
        checkEqual(rules(noon + 60), ["1 week ago", "2 days ago", "Yesterday", "earlier messages above", "Today"], "in English")
        s.lines.removeAll()
        checkEqual(rules(noon), [], "nothing said: no line")
        s.add(.notice(Notice(level: .info, text: "This is a demo")), order: noon)
        checkEqual(rules(noon), ["Today"], "a chat of today: one line on top")
        // a damaged history: a time far in the future or none at all is shown somewhere, never a crash
        for (i, t) in [1e30, -1e30, .nan, .infinity].enumerated() {
            s.add(.message(ChatMessage(id: UInt64(20 + i), nickname: "Bob", fingerprint: "ab1c", text: "odd", sent: t, received: t, hops: 0, mine: false)),
                  order: t)
        }
        check(plain(noon).filter { $0.contains("odd") }.count == 4, "times from a damaged history: shown, not a crash")
    }
}
