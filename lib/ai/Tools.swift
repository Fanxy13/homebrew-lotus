// Lotus AI – the tools the AI can use on this Mac, and the questions it asks first.
// Reading inside the working folder is free; every change and every command needs a yes.

import Foundation

struct ToolParam {
    let name: String
    let description: String
    let required: Bool
    var isInt = false
}

struct ToolSpec {
    let name: String
    let description: String
    let params: [ToolParam]

    var jsonSchema: [String: Any] {
        var props: [String: Any] = [:]
        for p in params {
            props[p.name] = ["type": p.isInt ? "integer" : "string", "description": p.description]
        }
        return ["type": "object", "properties": props, "required": params.filter(\.required).map(\.name)]
    }
}

enum ToolCatalog {
    static let all: [ToolSpec] = [
        ToolSpec(name: "list_directory",
                 description: "List the files and folders in a directory. Use it to look around before reading or changing files.",
                 params: [ToolParam(name: "path", description: "Directory path, relative to the working directory. Default: the working directory.", required: false)]),
        ToolSpec(name: "read_file",
                 description: "Read a text file. Always read a file before you edit it.",
                 params: [ToolParam(name: "path", description: "File path, relative to the working directory.", required: true),
                          ToolParam(name: "offset", description: "First line to read (1-based). Optional.", required: false, isInt: true),
                          ToolParam(name: "limit", description: "Number of lines to read. Optional.", required: false, isInt: true)]),
        ToolSpec(name: "write_file",
                 description: "Create a new file or replace a whole file with new content. Missing folders are created automatically, so write demo/index.html to make the demo folder too. Write complete content, never placeholders.",
                 params: [ToolParam(name: "path", description: "File path, relative to the working directory.", required: true),
                          ToolParam(name: "content", description: "The complete file content.", required: true)]),
        ToolSpec(name: "edit_file",
                 description: "Change part of an existing file: replaces old_text, which must appear exactly once, with new_text. Read the file first. new_text replaces only old_text, not the whole file. For short files it is often simpler to write the whole file again with write_file.",
                 params: [ToolParam(name: "path", description: "File path, relative to the working directory.", required: true),
                          ToolParam(name: "old_text", description: "The exact text to replace, including enough surrounding lines to be unique.", required: true),
                          ToolParam(name: "new_text", description: "The replacement text.", required: true)]),
        ToolSpec(name: "search_files",
                 description: "Search file contents for a text or regular expression, like grep. Returns matching lines with file names and line numbers.",
                 params: [ToolParam(name: "pattern", description: "Text or extended regular expression to search for.", required: true),
                          ToolParam(name: "path", description: "Folder or file to search in. Default: the working directory.", required: false)]),
        ToolSpec(name: "run_command",
                 description: "Run a shell command (zsh) in the working directory and get its output, e.g. to run a program, tests, git or a build. The user approves each command. No sudo, no interactive programs.",
                 params: [ToolParam(name: "command", description: "The command line to run.", required: true)]),
    ]

    static let displayNames = ["list_directory": "List", "read_file": "Read", "write_file": "Write",
                                "edit_file": "Edit", "search_files": "Search", "run_command": "Run"]
}

// ── Questions to the user during an answer ────────────────────

final class Interaction: @unchecked Sendable {
    let keys: KeyQueue?
    private let lock = NSLock()
    private var keyWaiter: CheckedContinuation<Key, Never>?
    private var buffered: [Key] = []
    private var asking = 0             // > 0 while a question is on screen: keys belong to it

    init(keys: KeyQueue?) { self.keys = keys }

    var canAsk: Bool { keys != nil }

    // Called by the watcher that reads keys while the AI works; true when a question took the key
    func deliver(_ key: Key) -> Bool {
        lock.lock()
        guard asking > 0 else { lock.unlock(); return false }
        if let w = keyWaiter {
            keyWaiter = nil
            lock.unlock()
            w.resume(returning: key)
        } else {
            buffered.append(key)
            lock.unlock()
        }
        return true
    }

    private func beginAsking() { lock.lock(); asking += 1; lock.unlock() }
    private func endAsking() {
        lock.lock()
        asking -= 1
        if asking == 0 { buffered.removeAll() }
        lock.unlock()
    }

    func waitKey() async -> Key {
        guard canAsk else { return .cancelled }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Key, Never>) in
                lock.lock()
                if Task.isCancelled { lock.unlock(); c.resume(returning: .cancelled); return }
                if !buffered.isEmpty {
                    let k = buffered.removeFirst()
                    lock.unlock()
                    c.resume(returning: k)
                    return
                }
                keyWaiter = c
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let w = keyWaiter
            keyWaiter = nil
            lock.unlock()
            w?.resume(returning: .cancelled)
        }
    }

    enum Answer { case yes, always, no(String) }

    func confirm(_ question: String, allowAlways: Bool) async -> Answer {
        guard canAsk else { return .no("") }
        beginAsking()
        defer { endAsking() }
        Spinner.shared.stop()
        let always = allowAlways ? "  \(Style.key)a\(Style.reset) yes, don't ask again" : ""
        let room = max(20, Term.width - 4)
        let hint = Term.width > 84 ? "  \(Style.dim)(n lets you say what to do instead)\(Style.reset)" : ""
        Out.shared.write("  \(Style.bold)\(clip(question, room))\(Style.reset)\n  \(Style.key)y\(Style.reset) yes\(always)  \(Style.key)n\(Style.reset) no\(hint)")
        while true {
            let k = await waitKey()
            switch k {
            case .char("y"), .char("Y"), .char("j"), .char("J"):
                Out.shared.write("\r\u{1B}[2K\u{1B}[1A\r\u{1B}[2K")
                return .yes
            case .char("a") where allowAlways, .char("A") where allowAlways:
                Out.shared.write("\r\u{1B}[2K\u{1B}[1A\r\u{1B}[2K")
                return .always
            case .char("n"), .char("N"):
                Out.shared.write("\r\u{1B}[2K\u{1B}[1A\r\u{1B}[2K")
                let note = await readLine("  What should the AI do instead? (enter to skip) ")
                return .no(note)
            case .esc, .ctrlC, .cancelled:
                Out.shared.write("\r\u{1B}[2K\u{1B}[1A\r\u{1B}[2K")
                return .no("")
            default:
                continue
            }
        }
    }

    // A one-line answer typed during an answer
    func readLine(_ prompt: String) async -> String {
        beginAsking()
        defer { endAsking() }
        var text: [Character] = []
        func draw() { Out.shared.write("\r\u{1B}[2K\(Style.dim)\(prompt)\(Style.reset)\(String(text))") }
        draw()
        while true {
            switch await waitKey() {
            case .char(let c): text.append(c)
            case .paste(let s): text.append(contentsOf: s.replacingOccurrences(of: "\n", with: " "))
            case .backspace: if !text.isEmpty { text.removeLast() }
            case .enter:
                Out.shared.write("\r\u{1B}[2K")
                return String(text).trimmingCharacters(in: .whitespaces)
            case .esc, .ctrlC, .cancelled:
                Out.shared.write("\r\u{1B}[2K")
                return ""
            default: break
            }
            draw()
        }
    }
}

// Lets one tool run at a time, even when a model asks for several at once
actor AsyncLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

// ── Running tools ─────────────────────────────────────────────

struct ToolOutcome {
    var text: String
    var isError = false
}

final class ToolRunner: @unchecked Sendable {
    let cwd: URL
    let ui: Interaction
    var outputLimit: Int            // characters a tool may hand back to the model
    private var editsAllowed = false
    private var commandsAllowed = false
    private var readsAllowed = false
    private let serial = AsyncLock()
    private(set) var actions: [String] = []   // what happened in this answer, for the memory

    init(cwd: URL, ui: Interaction, outputLimit: Int) {
        self.cwd = cwd
        self.ui = ui
        self.outputLimit = outputLimit
    }

    func takeActions() -> [String] {
        let a = actions
        actions = []
        return a
    }

    func run(_ name: String, _ args: [String: Any]) async -> ToolOutcome {
        await serial.lock()
        let result = await execute(name, args)
        await serial.unlock()
        Spinner.shared.start("Thinking")
        return result
    }

    private func str(_ args: [String: Any], _ key: String) -> String? {
        if let s = args[key] as? String { return s }
        if let n = args[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private func int(_ args: [String: Any], _ key: String) -> Int? {
        if let n = args[key] as? Int { return n }
        if let n = args[key] as? NSNumber { return n.intValue }
        if let s = args[key] as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private func execute(_ name: String, _ args: [String: Any]) async -> ToolOutcome {
        Spinner.shared.stop()
        switch name {
        case "list_directory": return listDirectory(str(args, "path") ?? ".")
        case "read_file":
            guard let p = str(args, "path") else { return missing("path") }
            return await readFile(p, offset: int(args, "offset"), limit: int(args, "limit"))
        case "write_file":
            guard let p = str(args, "path") else { return missing("path") }
            guard let c = str(args, "content") else { return missing("content") }
            return await writeFile(p, c)
        case "edit_file":
            guard let p = str(args, "path") else { return missing("path") }
            guard let o = str(args, "old_text") else { return missing("old_text") }
            return await editFile(p, o, str(args, "new_text") ?? "")
        case "search_files":
            guard let p = str(args, "pattern"), !p.isEmpty else { return missing("pattern") }
            return await searchFiles(p, str(args, "path") ?? ".")
        case "run_command":
            guard let c = str(args, "command"), !c.trimmingCharacters(in: .whitespaces).isEmpty else { return missing("command") }
            return await runCommand(c)
        default:
            return ToolOutcome(text: "Unknown tool \(name). Available: \(ToolCatalog.all.map(\.name).joined(separator: ", ")).", isError: true)
        }
    }

    private func missing(_ p: String) -> ToolOutcome {
        ToolOutcome(text: "Missing parameter: \(p)", isError: true)
    }

    // ── Paths ──

    func resolve(_ raw: String) -> URL {
        var p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { p = "." }
        if p.hasPrefix("~") { p = NSString(string: p).expandingTildeInPath }
        let url = p.hasPrefix("/") ? URL(fileURLWithPath: p) : cwd.appendingPathComponent(p)
        return url.standardizedFileURL
    }

    func display(_ url: URL) -> String {
        let path = url.path
        for base in Set([cwd.path, cwd.standardizedFileURL.path, cwd.resolvingSymlinksInPath().path]) {
            for p in Set([path, url.resolvingSymlinksInPath().path]) {
                if p == base { return "." }
                if p.hasPrefix(base + "/") { return String(p.dropFirst(base.count + 1)) }
            }
        }
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    private func inside(_ url: URL) -> Bool {
        let base = cwd.resolvingSymlinksInPath().standardizedFileURL.path
        var probe = url
        // A file that does not exist yet: check its folder
        while !FileManager.default.fileExists(atPath: probe.path) && probe.path != "/" { probe.deleteLastPathComponent() }
        let real = probe.resolvingSymlinksInPath().standardizedFileURL.path
        return real == base || real.hasPrefix(base + "/") || base == "/"
    }

    private func sensitive(_ url: URL) -> Bool {
        let parts = Set(url.pathComponents)
        let names = [".ssh", ".gnupg", ".aws", "Keychains", ".netrc", ".git-credentials", ".docker", ".kube", "1Password"]
        if names.contains(where: parts.contains) { return true }
        let last = url.lastPathComponent
        return last == ".env" || last.hasPrefix(".env.") || last.hasSuffix(".pem") || last.hasSuffix(".key") || last == "id_rsa" || last == "id_ed25519"
    }

    private func mayRead(_ url: URL) async -> Bool {
        if sensitive(url) {
            return await ask("Let the AI read \(display(url))? It looks private.", allowAlways: false)
        }
        if inside(url) || readsAllowed { return true }
        let answer = await ui.confirm("Let the AI read \(display(url))? It is outside this folder.", allowAlways: true)
        switch answer {
        case .yes: return true
        case .always: readsAllowed = true; return true
        case .no: return false
        }
    }

    private var declineNote = ""

    private func ask(_ question: String, allowAlways: Bool) async -> Bool {
        switch await ui.confirm(question, allowAlways: allowAlways) {
        case .yes: return true
        case .always: return true
        case .no(let note): declineNote = note; return false
        }
    }

    private func declined(_ what: String) -> ToolOutcome {
        Renderer.shared.toolResult("Declined", error: true)
        let note = declineNote
        declineNote = ""
        actions.append("The user declined: \(what)")
        if !ui.canAsk {
            return ToolOutcome(text: "This needs the user's approval, but Lotus cannot ask in this window. Tell the user to run /ai in a terminal to allow it.", isError: true)
        }
        return ToolOutcome(text: note.isEmpty ? "The user declined this. Do not try it again; ask what they want instead." : "The user declined this and said: \(note)", isError: true)
    }

    private func limited(_ s: String) -> String {
        guard s.count > outputLimit else { return s }
        let head = s.prefix(outputLimit * 2 / 3)
        let tail = s.suffix(outputLimit / 4)
        return head + "\n[… \(s.count - head.count - tail.count) characters left out …]\n" + tail
    }

    // ── Tools ──

    private func listDirectory(_ raw: String) -> ToolOutcome {
        let url = resolve(raw)
        Renderer.shared.toolHeader("List", display(url))
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            Renderer.shared.toolResult("Not a folder", error: true)
            return ToolOutcome(text: "No such directory: \(display(url))", isError: true)
        }
        guard !sensitive(url) else {
            Renderer.shared.toolResult("Private folder – not listed", error: true)
            return ToolOutcome(text: "This folder looks private; Lotus does not list it.", isError: true)
        }
        let items = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { $0 != ".DS_Store" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var lines: [String] = []
        for name in items.prefix(400) {
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path, isDirectory: &d)
            lines.append(d.boolValue ? name + "/" : name)
        }
        if items.count > 400 { lines.append("… and \(items.count - 400) more") }
        Renderer.shared.toolResult("\(items.count) \(items.count == 1 ? "entry" : "entries")")
        return ToolOutcome(text: lines.isEmpty ? "(empty folder)" : limited(lines.joined(separator: "\n")))
    }

    private func readFile(_ raw: String, offset: Int?, limit: Int?) async -> ToolOutcome {
        let url = resolve(raw)
        Renderer.shared.toolHeader("Read", display(url))
        guard await mayRead(url) else { return declined("reading \(display(url))") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            Renderer.shared.toolResult("File not found", error: true)
            return ToolOutcome(text: "File not found: \(display(url))", isError: true)
        }
        if isDir.boolValue {
            Renderer.shared.toolResult("That is a folder", error: true)
            return ToolOutcome(text: "\(display(url)) is a directory – use list_directory.", isError: true)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size < 8_000_000, let data = FileManager.default.contents(atPath: url.path) else {
            Renderer.shared.toolResult("Too large to read", error: true)
            return ToolOutcome(text: "The file is too large to read (\(size / 1_000_000) MB).", isError: true)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            Renderer.shared.toolResult("Not a text file", error: true)
            return ToolOutcome(text: "\(display(url)) is not a text file.", isError: true)
        }
        let all = content.components(separatedBy: "\n")
        let start = max(1, offset ?? 1)
        let count = max(1, limit ?? all.count)
        let slice = all.dropFirst(start - 1).prefix(count)
        var text = slice.joined(separator: "\n")
        var note = ""
        if text.count > outputLimit {
            text = String(text.prefix(outputLimit))
            let shownLines = text.components(separatedBy: "\n").count
            note = "\n[Showing lines \(start)–\(start + shownLines - 1) of \(all.count). Read more with offset and limit.]"
        } else if start > 1 || slice.count < all.count {
            note = "\n[Lines \(start)–\(start + slice.count - 1) of \(all.count)]"
        }
        Renderer.shared.toolResult("\(all.count) \(all.count == 1 ? "line" : "lines")")
        actions.append("Read \(display(url))")
        return ToolOutcome(text: (text.isEmpty ? "(empty file)" : text) + note)
    }

    private func writeFile(_ raw: String, _ content: String) async -> ToolOutcome {
        let url = resolve(raw)
        let exists = FileManager.default.fileExists(atPath: url.path)
        var lines = content.components(separatedBy: "\n")
        if lines.count > 1 && lines.last == "" { lines.removeLast() }
        Renderer.shared.toolHeader("Write", display(url))
        if exists, let old = try? String(contentsOf: url, encoding: .utf8) {
            showDiff(old, content)
        } else {
            Renderer.shared.toolLines(lines, color: Style.green, limit: 10)
        }
        let isInside = inside(url)
        if sensitive(url) || !isInside || !editsAllowed {
            let verb = exists ? "Replace" : "Create"
            let place = isInside ? "" : " (outside this folder)"
            switch await ui.confirm("\(verb) \(display(url))\(place)?", allowAlways: isInside && !sensitive(url)) {
            case .yes: break
            case .always: editsAllowed = true
            case .no(let note): declineNote = note; return declined("writing \(display(url))")
            }
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Renderer.shared.toolResult("Could not write: \(error.localizedDescription)", error: true)
            return ToolOutcome(text: "Could not write \(display(url)): \(error.localizedDescription)", isError: true)
        }
        let what = "\(exists ? "Updated" : "Created") \(display(url)) (\(lines.count) \(lines.count == 1 ? "line" : "lines"))"
        Renderer.shared.toolResult(what)
        actions.append(what)
        return ToolOutcome(text: what)
    }

    private func editFile(_ raw: String, _ oldText: String, _ newText: String) async -> ToolOutcome {
        let url = resolve(raw)
        Renderer.shared.toolHeader("Edit", display(url))
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            Renderer.shared.toolResult("File not found", error: true)
            return ToolOutcome(text: "Cannot read \(display(url)). Use write_file to create it.", isError: true)
        }
        guard !oldText.isEmpty else { return ToolOutcome(text: "old_text is empty.", isError: true) }
        var oldText = oldText
        var count = content.components(separatedBy: oldText).count - 1
        if count == 0, let found = ToolRunner.looseMatch(oldText, in: content) {
            // Same lines with different indentation or trailing spaces
            oldText = found
            count = content.components(separatedBy: oldText).count - 1
        }
        if count == 0 {
            Renderer.shared.toolResult("Text not found in the file", error: true)
            return ToolOutcome(text: "old_text was not found in \(display(url)). Read the file again and copy the text exactly.", isError: true)
        }
        if count > 1 {
            Renderer.shared.toolResult("Text appears \(count) times", error: true)
            return ToolOutcome(text: "old_text appears \(count) times in \(display(url)). Include more surrounding lines so it is unique.", isError: true)
        }
        showDiff(oldText, newText, full: true)
        let isInside = inside(url)
        if sensitive(url) || !isInside || !editsAllowed {
            switch await ui.confirm("Change \(display(url))?", allowAlways: isInside && !sensitive(url)) {
            case .yes: break
            case .always: editsAllowed = true
            case .no(let note): declineNote = note; return declined("editing \(display(url))")
            }
        }
        let updated = content.replacingOccurrences(of: oldText, with: newText)
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Renderer.shared.toolResult("Could not save: \(error.localizedDescription)", error: true)
            return ToolOutcome(text: "Could not save \(display(url)): \(error.localizedDescription)", isError: true)
        }
        let removed = oldText.components(separatedBy: "\n").count
        let added = newText.components(separatedBy: "\n").count
        let what = "Edited \(display(url)) (−\(removed) +\(added) lines)"
        Renderer.shared.toolResult(what)
        actions.append(what)
        return ToolOutcome(text: what)
    }

    // Finds the lines of `needle` in `text` when only indentation or trailing spaces differ
    static func looseMatch(_ needle: String, in text: String) -> String? {
        let want = needle.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let wantTrimmed = Array(want.drop(while: { $0.isEmpty }).reversed().drop(while: { $0.isEmpty }).reversed())
        guard !wantTrimmed.isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n")
        let have = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        var hits: [Int] = []
        if have.count >= wantTrimmed.count {
            for i in 0...(have.count - wantTrimmed.count) where Array(have[i..<(i + wantTrimmed.count)]) == wantTrimmed {
                hits.append(i)
            }
        }
        guard hits.count == 1, let i = hits.first else { return nil }
        return lines[i..<(i + wantTrimmed.count)].joined(separator: "\n")
    }

    // Shows changed lines: red for removed, green for added
    private func showDiff(_ old: String, _ new: String, full: Bool = false) {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        var prefix = 0
        if !full {
            while prefix < min(a.count, b.count) && a[prefix] == b[prefix] { prefix += 1 }
        }
        var suffix = 0
        if !full {
            while suffix < min(a.count, b.count) - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        }
        let removed = Array(a[prefix..<(a.count - suffix)])
        let added = Array(b[prefix..<(b.count - suffix)])
        if removed.isEmpty && added.isEmpty {
            Renderer.shared.toolLines(["(no changes)"])
            return
        }
        Renderer.shared.toolLines(removed.map { "- " + $0 }, color: Style.red, limit: 6)
        Renderer.shared.toolLines(added.map { "+ " + $0 }, color: Style.green, limit: 10)
    }

    private func searchFiles(_ pattern: String, _ raw: String) async -> ToolOutcome {
        let url = resolve(raw)
        Renderer.shared.toolHeader("Search", "\"\(pattern)\" in \(display(url))")
        guard await mayRead(url) else { return declined("searching \(display(url))") }
        let args = ["-rInE", "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=.build",
                    "--exclude-dir=build", "--exclude-dir=DerivedData", "--exclude-dir=.venv", "-m", "20", "-e", pattern, url.path]
        var r = await Shell.run("/usr/bin/grep", args, cwd: cwd, timeout: 20)
        if r.status == 2 {
            // Not a valid regular expression: search for the plain text instead
            r = await Shell.run("/usr/bin/grep", args.map { $0 == "-rInE" ? "-rInF" : $0 }, cwd: cwd, timeout: 20)
        }
        var lines = r.output.split(separator: "\n").map(String.init)
        let base = cwd.standardizedFileURL.path + "/"
        lines = lines.map { $0.hasPrefix(base) ? String($0.dropFirst(base.count)) : $0 }
        if r.status > 1 {
            Renderer.shared.toolResult("Search failed", error: true)
            return ToolOutcome(text: "grep failed: \(r.output)", isError: true)
        }
        Renderer.shared.toolResult(lines.isEmpty ? "No matches" : "\(lines.count) matching lines")
        let shown = lines.prefix(150).joined(separator: "\n")
        return ToolOutcome(text: lines.isEmpty ? "No matches." : limited(shown + (lines.count > 150 ? "\n… \(lines.count - 150) more" : "")))
    }

    private static let dangerous: [String] = [
        #"\brm\s+(-[a-zA-Z]*[rf]|--recursive|--force)"#, #"\bmkfs"#, #"\bdiskutil\s+(erase|partition|zero)"#,
        #"\bdd\s"#, #">\s*/dev/"#, #"\bchmod\s+-R"#, #"\bchown\s+-R"#, #"git\s+push\s+.*(--force|-f\b)"#,
        #"git\s+(reset\s+--hard|clean\s+-[a-z]*f)"#, #"(curl|wget)[^|]*\|\s*(ba|z)?sh"#, #"\bkillall\b"#,
        #"\blaunchctl\s+(unload|remove|bootout)"#, #"\bdefaults\s+delete"#, #"\bsrm\b"#, #":\(\)\s*\{"#,
    ]

    private func runCommand(_ command: String) async -> ToolOutcome {
        Renderer.shared.toolHeader("Run", command.replacingOccurrences(of: "\n", with: " ⏎ "))
        if command.range(of: #"(^|[;&|(\s])sudo\b"#, options: .regularExpression) != nil {
            Renderer.shared.toolResult("Not run: Lotus never uses sudo", error: true)
            actions.append("Did not run (needs sudo): \(command)")
            return ToolOutcome(text: "Lotus does not run sudo commands. Show the user the command and ask them to run it themselves if they want to.", isError: true)
        }
        let risky = ToolRunner.dangerous.contains { command.range(of: $0, options: .regularExpression) != nil }
        if risky || !commandsAllowed {
            if risky { Renderer.shared.toolLines(["This command can delete or overwrite things."], color: Style.red) }
            switch await ui.confirm("Run this command?", allowAlways: !risky) {
            case .yes: break
            case .always: commandsAllowed = true
            case .no(let note): declineNote = note; return declined("running `\(command)`")
            }
        }
        Spinner.shared.start("Running")
        let started = Date()
        let r = await Shell.run("/bin/zsh", ["-c", command], cwd: cwd, timeout: 180)
        Spinner.shared.stop()
        let secs = Date().timeIntervalSince(started)
        let lines = r.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : lines
        Renderer.shared.toolLines(trimmed, limit: 10)
        let time = secs < 10 ? String(format: "%.1fs", secs) : "\(Int(secs))s"
        let state = r.timedOut ? "stopped after 3 minutes" : r.cancelled ? "stopped" : "exit \(r.status)"
        Renderer.shared.toolResult("\(state) · \(time)", error: r.status != 0 || r.timedOut)
        actions.append("Ran `\(command)` → \(state)")
        var text = "Exit status: \(r.status)\(r.timedOut ? " (timed out after 180 s)" : "")\n"
        text += r.output.isEmpty ? "(no output)" : limited(r.output)
        return ToolOutcome(text: text, isError: r.status != 0)
    }
}

// ── Running programs ──────────────────────────────────────────

enum Shell {
    struct Result {
        var status: Int32
        var output: String
        var timedOut = false
        var cancelled = false
    }

    static func run(_ exe: String, _ args: [String], cwd: URL, timeout: TimeInterval) async -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("LOTUS_AI_") { env.removeValue(forKey: k) }   // keys never reach commands
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = Collected()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { collected.append(d) }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: 127, output: "Could not start: \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        await withTaskCancellationHandler {
            while process.isRunning {
                if Date() > deadline { timedOut = true; process.terminate(); break }
                if Task.isCancelled { cancelled = true; process.terminate(); break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        } onCancel: {
            process.terminate()
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? pipe.fileHandleForReading.readToEnd() { collected.append(rest) }
        let text = String(decoding: collected.data, as: UTF8.self)
        return Result(status: process.terminationStatus, output: text, timedOut: timedOut, cancelled: cancelled || Task.isCancelled)
    }

    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var data = Data()
        func append(_ d: Data) {
            lock.lock()
            if data.count < 4_000_000 { data.append(d) }
            lock.unlock()
        }
    }
}
