// Lotus AI – the rules for a model with little room: Apple Intelligence (Apple.swift). Its window is fixed by Apple – 4096
// tokens for the instructions, the tool definitions, the conversation, what the tools return and the answer together – so
// Lotus spends it carefully: a request gets only the tools it needs, described briefly; the conversation gets the room
// that is left, the newest first; a task is carried from one session to the next by a short log of what was done; and a
// text that goes in circles is cut. Plain functions without the model, so the tests check them on every system:
// lotus-ai --small-check (tests/test-smallmodel.zsh).

import Foundation

enum SmallModel {
    // What a request needs – Apple.swift sorts each message into one of these first
    enum Kind: String { case chat, look, change, web, lotus }

    // Apple's on-device model: everything shares 4096 tokens
    static let window = 4096

    // Tokens of a text, roughly: about three characters each – fewer for accented letters, code and other scripts
    static func tokens(_ text: String) -> Int { (text.utf8.count + 2) / 3 }

    // ── The tools a request gets ──────────────────────────────

    // Each definition takes room in the window, and fewer choices make fewer wrong calls
    static func toolNames(_ kind: Kind, request: String, lotus: [String]) -> [String] {
        switch kind {
        case .chat: return []
        case .look: return ["list_directory", "read_file", "search_files"]
        case .change: return ["list_directory", "read_file", "write_file", "edit_file", "run_command"] + (aboutPages(request) ? ["view_page"] : [])
        case .web: return ["web_search", "fetch_url"]
        case .lotus: return lotus
        }
    }

    // The request is about a web page: view_page can look at it
    static func aboutPages(_ text: String) -> Bool {
        text.range(of: #"\.html?\b|\.css\b|\b(html|css|web ?pages?|web ?sites?|homepage|landing ?page|webseiten?|internetseiten?|site web|page web|sitio web|página web)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    // What the tools do, said briefly – the long descriptions (Tools.swift) are for models with room
    static let brief: [String: String] = [
        "list_directory": "List the files and folders in a folder.",
        "read_file": "Read a text file. Read a file before you change it.",
        "write_file": "Create a file, or replace a whole file. content is the complete file – never a part or a placeholder.",
        "edit_file": "Change part of a file: old_text exactly as it is in the file (once), new_text instead of it.",
        "search_files": "Find the lines that contain a text in the files of a folder, like grep.",
        "run_command": "Run a zsh command in the working folder and get its output. No sudo, nothing interactive.",
        "web_search": "Search the web. Gives titles, addresses and short snippets.",
        "fetch_url": "Read a web page as text. start reads on in a long page.",
        "view_page": "Open an HTML file in a browser: it reports errors, files that did not load and what is too wide.",
        "remember": "Keep one short fact about the user for later conversations.",
    ]
    static let briefParams: [String: String] = [
        "path": "Path, relative to the working folder.",
        "content": "The complete content of the file.",
        "old_text": "The exact text to replace.",
        "new_text": "The text instead of it.",
        "pattern": "The text to find.",
        "command": "The command line.",
        "query": "What to search for.",
        "url": "The address of the page.",
        "offset": "First line to read (optional).",
        "limit": "How many lines to read (optional).",
        "start": "Character to start at (optional).",
        "view": "desktop or phone (optional).",
        "inspect": "A CSS selector to get details of (optional).",
        "fact": "The fact, in one sentence.",
    ]

    // A tool for the small model: its description and those of its arguments made short
    static func shortened(_ spec: ToolSpec) -> ToolSpec {
        let params = spec.params.map { p in
            ToolParam(name: p.name, description: briefParams[p.name] ?? clip(p.description, 90), required: p.required, isInt: p.isInt,
                      enumValues: p.enumValues, minimum: p.minimum, maximum: p.maximum, isPath: p.isPath)
        }
        return ToolSpec(name: spec.name, description: brief[spec.name] ?? clip(spec.description, 180), params: params, lotus: spec.lotus)
    }

    // Tokens the definitions of these tools take: names, descriptions, arguments and the schema around them
    static func toolTokens(_ specs: [ToolSpec]) -> Int {
        specs.reduce(0) { sum, s in
            sum + 30 + tokens(s.name + " " + s.description) + s.params.reduce(0) { $0 + 12 + tokens($1.name + " " + $1.description) }
        }
    }

    // ── How much of the conversation fits ─────────────────────

    // Characters of the conversation that fit beside the instructions and the tools (both in tokens), keeping room for
    // the request, what the tools return and the answer
    static func historyRoom(instructions: Int, tools: Int, work: Bool) -> Int {
        let reserve = work ? 1900 : 1100
        let left = window - instructions - tools - reserve
        return min(12_000, max(1_200, left * 3))
    }

    // The newest turns that fit into room characters, oldest first. A long one is cut, so that one long answer does not
    // push out everything before it; the list starts with the user.
    static func recent(_ turns: [Turn], room: Int) -> [Turn] {
        let longest = max(600, room / 2)
        var picked: [Turn] = []
        var total = 0
        for t in turns.reversed() {
            var text = t.text
            if text.count > longest { text = String(text.prefix(longest - 6)) + " […]" }
            if total + text.count > room { break }
            total += text.count
            picked.insert(Turn(role: t.role, text: text), at: 0)
        }
        while picked.first?.role == "assistant" { picked.removeFirst() }
        return picked
    }

    // ── A task across sessions ────────────────────────────────

    // A line of the work log for a tool call: what it did, and the start of what it returned
    static func logLine(_ tool: String, _ args: [String: Any], _ output: String, error: Bool) -> String {
        let what = ToolRunner.brief(args)
        let said = output.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let room = ToolRunner.lookOnly.contains(tool) ? 220 : 120
        return "- \(tool)\(what.isEmpty ? "" : " " + clip(what, 80))\(error ? " – failed" : ""): \(clip(said, room))"
    }

    // The newest lines of a work log that fit into max characters, oldest first
    static func logText(_ lines: [String], max: Int) -> String {
        var picked: [String] = []
        var total = 0
        for l in lines.reversed() {
            if total + l.count + 1 > max { break }
            total += l.count + 1
            picked.insert(l, at: 0)
        }
        let left = lines.count - picked.count
        return (left > 0 ? "(\(left) earlier entr\(left == 1 ? "y" : "ies") left out)\n" : "") + picked.joined(separator: "\n")
    }

    // The request as a fresh session is told it – with the exchange before it, which a short follow-up needs
    static func request(_ text: String, earlier: String) -> String {
        (earlier.isEmpty ? "" : "Earlier in the conversation: \(clip(earlier, 520))\n\n") + "The user's request: \(clip(text, 900))"
    }

    // A session for one step of a plan is told the request, the plan, what is done – and this step
    static func stepPrompt(request: String, steps: [String], index: Int, log: [String], answerIn: String, earlier: String = "") -> String {
        let plan = steps.enumerated().map { i, s in "\(i + 1). \(s)" + (i < index ? " (done)" : i == index ? " ← now" : "") }.joined(separator: "\n")
        let done = log.isEmpty ? "" : "\n\nDone so far:\n" + logText(log, max: 1500)
        return Self.request(request, earlier: earlier) + "\n\nThe plan:\n\(plan)\(done)\n\n"
            + "Now do step \(index + 1) – \(steps[index]) – with the tools, and only this step. Use what is done so far instead of "
            + "doing it again. Then say in one short sentence what you did. \(answerIn)"
    }

    // A step that changed nothing although it should: told so, once
    static func stepAgain(request: String, step: String, log: [String], answerIn: String) -> String {
        "The user's request: \(clip(request, 900))\n\n" + (log.isEmpty ? "" : "Done so far:\n" + logText(log, max: 1200) + "\n\n")
            + "This step is not done yet – nothing was created, changed or run: \(step)\nDo it now: call write_file, edit_file or "
            + "run_command. Then say in one short sentence what you did. \(answerIn)"
    }

    // A fresh session going on with a task: the request, what is done, why it goes on
    static func continuePrompt(request: String, log: [String], why: String, answerIn: String, earlier: String = "") -> String {
        Self.request(request, earlier: earlier) + "\n\n" + (log.isEmpty ? "" : "Done so far:\n" + logText(log, max: 1500) + "\n\n")
            + why + " Go on where it stopped and finish the request. Do not do again what is done, and do not repeat what was said. "
            + answerIn
    }

    // The end of a task done step by step: what was done, for the user
    static func summaryPrompt(request: String, log: [String], answerIn: String) -> String {
        "The user asked: \(clip(request, 600))\n\nThis is what was done:\n\(logText(log, max: 1800))\n\n"
            + "Tell the user in one to three short sentences what was done and where to find it. Mention only what the log shows; "
            + "if something failed, say so. \(answerIn)"
    }

    // A step that changes something – a file written, a command run – rather than one that only looks
    static func changes(_ step: String) -> Bool {
        let t = step.lowercased()
        let looks = #"^\W*(look|read|list|check|verify|view|open|inspect|review|find|search|explore|understand|schau|lies|les|prüf|kontrollier|öffne|such|finde|sieh|regarde|lis|vérifi|cherche|examine|mira|lee|revisa|comprueba|busca)"#
        if t.range(of: looks, options: .regularExpression) != nil { return false }
        let acts = #"\b(create|write|add|make|build|change|edit|update|fix|rename|delete|remove|move|copy|install|run|execute|insert|replace|set up|generate|style|implement|save|erstell\w*|schreib\w*|füg\w*|änder\w*|bearbeit\w*|aktualisier\w*|korrigier\w*|lösch\w*|entfern\w*|verschieb\w*|kopier\w*|installier\w*|führ\w*|ersetz\w*|bau\w*|speicher\w*|leg\w*|crée\w*|cré\w*|écri\w*|ajout\w*|modifi\w*|supprim\w*|renomm\w*|install\w*|exécut\w*|crea\w*|escrib\w*|añad\w*|modific\w*|elimin\w*|borr\w*|renombr\w*|instal\w*|ejecut\w*|guard\w*)\b"#
        return t.range(of: acts, options: .regularExpression) != nil
    }

    // ── Going in circles ──────────────────────────────────────

    // A text whose last words came three times already, the same each time (six times in a code block): where to cut it –
    // after the first time, at the end of a line or sentence when one is near – or nil. A refrain with other words in
    // between is no circle.
    static func circles(_ text: String) -> String.Index? {
        guard text.count >= 200 else { return nil }
        let tail = String(text.suffix(60))
        guard Set(tail.filter { !$0.isWhitespace }).count >= 8 else { return nil }      // a rule of dashes is no circle
        let inCode = text.components(separatedBy: "```").count % 2 == 0
        let needed = inCode ? 6 : 3
        var hits: [Range<String.Index>] = []
        var from = text.startIndex
        while hits.count < needed, from < text.endIndex, let r = text.range(of: tail, range: from..<text.endIndex) {
            hits.append(r)
            from = text.index(after: r.lowerBound)
        }
        guard hits.count >= needed else { return nil }
        // a circle says the same between the times
        let a = text[hits[0].lowerBound..<hits[1].lowerBound], b = text[hits[1].lowerBound..<hits[2].lowerBound]
        guard a == b else { return nil }
        let first = hits[0].upperBound
        let kept = text[..<first]
        for mark in ["\n", ". ", "! ", "? "] {
            if let r = kept.range(of: mark, options: .backwards), text.distance(from: r.upperBound, to: first) < 240 { return r.upperBound }
        }
        return first
    }

    // ── For the tests ─────────────────────────────────────────

    // lotus-ai --small-check <what> …: the rules above, for tests/test-smallmodel.zsh
    static func check(_ args: [String]) -> Int32 {
        let rest = Array(args.dropFirst())
        let input = { String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
        switch args.first ?? "" {
        case "tools":
            // tools <kind> <request …>: the tools that request gets
            guard let kind = rest.first.flatMap(Kind.init(rawValue:)) else { return 2 }
            print(toolNames(kind, request: rest.dropFirst().joined(separator: " "), lotus: ["weather", "music"]).joined(separator: " "))
        case "circles":
            // the text on stdin: "no", or where it is cut and what is kept
            let text = input()
            if let cut = circles(text) {
                print("cut at \(text.distance(from: text.startIndex, to: cut))")
                print(String(text[..<cut]), terminator: "")
            } else {
                print("no")
            }
        case "room":
            // room <instruction tokens> <tool tokens> work|chat: characters of the conversation that fit
            guard rest.count == 3, let i = Int(rest[0]), let t = Int(rest[1]) else { return 2 }
            print(historyRoom(instructions: i, tools: t, work: rest[2] == "work"))
        case "changes":
            // changes <step …>: whether the step changes something or only looks
            print(changes(rest.joined(separator: " ")) ? "changes" : "looks")
        case "brief":
            // the definitions a change of a web page gets, briefly – and what they take compared with all of them, long
            let names = toolNames(.change, request: "index.html", lotus: [])
            let short = ToolCatalog.builtin.filter { names.contains($0.name) }.map(shortened)
            for s in short { print("\(s.name): \(s.description)") }
            print("tokens \(toolTokens(short)) instead of \(toolTokens(ToolCatalog.builtin.filter { $0.name != "plan" }))")
        case "recent":
            // recent <room>: the turns on stdin ("user: …" / "assistant: …", one per line) that fit
            guard let room = rest.first.flatMap({ Int($0) }) else { return 2 }
            let turns = input().components(separatedBy: "\n").compactMap { line -> Turn? in
                guard let colon = line.range(of: ":") else { return nil }
                return Turn(role: String(line[..<colon.lowerBound]), text: String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
            for t in recent(turns, room: room) { print("\(t.role): \(t.text)") }
        case "log":
            // log <max>: the lines on stdin as the work log a session gets
            guard let max = rest.first.flatMap({ Int($0) }) else { return 2 }
            print(logText(input().split(separator: "\n").map(String.init), max: max))
        default:
            FileHandle.standardError.write(Data("Usage: lotus-ai --small-check tools|circles|room|changes|brief|recent|log …\n".utf8))
            return 2
        }
        return 0
    }
}
