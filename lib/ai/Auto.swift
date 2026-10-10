import Foundation

// ── Auto mode ─────────────────────────────────────────────────
// In auto mode the AI works on its own: it reads, creates and changes files in this folder and runs
// commands without asking – and asks only when Lotus is unsure. Before a command runs, this check reads
// it the way the shell would and lets it through only when it is sure: the command looks at things,
// builds or tests, or changes files in this folder. Deleting, pushing, installing, sending data, other
// folders, private files and programs it does not know get a question, with the reason.

struct AutoCheck {
    let inside: (String) -> Bool        // the path is in this folder
    let isPrivate: (String) -> Bool     // keys, .env, …
    var readOutside = false             // looking at files elsewhere is allowed (/permissions)
    var write = true                    // changing files in this folder is allowed
    private var loopVars: Set<String> = []     // for f in *.txt: $f stands for files in this folder

    init(inside: @escaping (String) -> Bool, isPrivate: @escaping (String) -> Bool, readOutside: Bool = false, write: Bool = true) {
        self.inside = inside
        self.isPrivate = isPrivate
        self.readOutside = readOutside
        self.write = write
    }

    struct Word { var text: String; var expands: Bool }
    enum Token { case word(Word), op(String) }

    // nil: sure – it runs without a question. Otherwise why Lotus asks ("it deletes files").
    func unsure(_ command: String, depth: Int = 0) -> String? {
        guard depth < 3 else { return "it runs commands inside commands" }
        let (tokens, problem) = AutoCheck.tokens(command)
        if let p = problem { return p }
        // the commands of the line, and whether another command's output flows into each one
        var segments: [(tokens: [Token], piped: Bool)] = []
        var segment: [Token] = []
        var piped = false
        for t in tokens + [.op("\n")] {
            if case .op(let o) = t, AutoCheck.separators.contains(o) {
                if o == "&" { return "it keeps running in the background" }
                if !segment.isEmpty { segments.append((segment, piped)) }
                segment = []
                piped = o == "|"
            } else {
                segment.append(t)
            }
        }
        var me = self
        for (seg, _) in segments {
            let ws = seg.compactMap { t -> Word? in if case .word(let w) = t { return w } else { return nil } }
            if ws.count >= 3, ws[0].text == "for", ws[2].text == "in",
               ws.dropFirst(3).allSatisfy({ !$0.expands && inside($0.text) && !isPrivate($0.text) }) {
                me.loopVars.insert(ws[1].text)
            }
        }
        for (seg, piped) in segments {
            if let r = me.judge(seg, depth, piped: piped) { return r }
        }
        return nil
    }

    // ── Reading the command like the shell ──

    static let separators: Set<String> = [";", "&&", "||", "|", "&", "(", ")", "\n"]
    static let inner = "it runs commands Lotus cannot see ($(…) or `…`)"

    // Words (quotes removed, $… marked) and operators. Here-documents are skipped: they are text.
    static func tokens(_ s: String) -> ([Token], String?) {
        var out: [Token] = []
        var cur = "", has = false, expands = false
        var pending: [(end: String, strip: Bool)] = []   // here-documents waiting for the next line
        var wantEnd: Bool?                               // the next word ends a here-document
        let c = Array(s)
        var i = 0
        func at(_ k: Int) -> Character? { k < c.count ? c[k] : nil }
        func flush() {
            guard has else { return }
            if let strip = wantEnd { pending.append((cur, strip)); wantEnd = nil }
            out.append(.word(Word(text: cur, expands: expands)))
            cur = ""; has = false; expands = false
        }
        while i < c.count {
            let ch = c[i]
            switch ch {
            case "\\":
                if let n = at(i + 1), n != "\n" { cur.append(n); has = true }
                i += 2
            case "'":
                guard let j = c[(i + 1)...].firstIndex(of: "'") else { return (out, "its quotes do not close") }
                cur += String(c[(i + 1)..<j]); has = true; i = j + 1
            case "\"":
                var j = i + 1
                while j < c.count && c[j] != "\"" {
                    if c[j] == "\\", let n = at(j + 1) { cur.append(n); j += 2; continue }
                    if c[j] == "`" { return (out, inner) }
                    if c[j] == "$" {
                        if at(j + 1) == "(" && at(j + 2) != "(" { return (out, inner) }
                        expands = true
                    }
                    cur.append(c[j]); j += 1
                }
                guard j < c.count else { return (out, "its quotes do not close") }
                has = true; i = j + 1
            case "`":
                return (out, inner)
            case "$":
                if at(i + 1) == "(" {
                    // $((6*7)) is arithmetic; $(…) runs a command
                    guard at(i + 2) == "(", let close = String(c[i...]).range(of: "))") else { return (out, inner) }
                    let body = String(c[i...])[..<close.upperBound]
                    if body.dropFirst(3).contains("$(") || body.contains("`") { return (out, inner) }
                    cur += body; has = true; expands = true; i += body.count
                } else {
                    expands = true; cur.append(ch); has = true; i += 1
                }
            case " ", "\t":
                flush(); i += 1
            case "#" where !has:
                while i < c.count && c[i] != "\n" { i += 1 }
            case "\n":
                flush(); out.append(.op("\n")); i += 1
                for doc in pending {
                    while i < c.count {
                        var e = i
                        while e < c.count && c[e] != "\n" { e += 1 }
                        var line = String(c[i..<e])
                        if doc.strip { line = String(line.drop(while: { $0 == "\t" })) }
                        i = e + 1
                        if line == doc.end { break }
                    }
                }
                pending = []
            case ";":
                flush(); out.append(.op(";")); i += at(i + 1) == ";" ? 2 : 1
            case "&":
                flush()
                if at(i + 1) == "&" { out.append(.op("&&")); i += 2 }
                else if at(i + 1) == ">" { let add = at(i + 2) == ">"; out.append(.op(add ? "&>>" : "&>")); i += add ? 3 : 2 }
                else { out.append(.op("&")); i += at(i + 1) == "|" || at(i + 1) == "!" ? 2 : 1 }
            case "|":
                flush()
                if at(i + 1) == "|" { out.append(.op("||")); i += 2 }
                else { out.append(.op("|")); i += at(i + 1) == "&" ? 2 : 1 }
            case "(", ")":
                if ch == "(" && cur == "=" { return (out, inner) }     // zsh =(…)
                flush(); out.append(.op(String(ch))); i += 1
            case "<", ">":
                // a file descriptor right before it (2>) belongs to the operator
                if has && !expands && cur.allSatisfy(\.isNumber) { cur = ""; has = false }
                flush()
                if at(i + 1) == "(" { return (out, inner) }            // <(…) >(…)
                if at(i + 1) == "&" {
                    // 2>&1 goes to another output; ">& file" is a file
                    if let n = at(i + 2), n.isNumber || n == "-" {
                        i += 2
                        while let n = at(i), n.isNumber || n == "-" { i += 1 }
                    } else {
                        out.append(.op(ch == ">" ? "&>" : "<")); i += 2
                    }
                } else if ch == ">" {
                    if at(i + 1) == ">" { out.append(.op(">>")); i += 2 }
                    else { out.append(.op(">")); i += at(i + 1) == "|" || at(i + 1) == "!" ? 2 : 1 }
                } else if at(i + 1) == "<" {
                    if at(i + 2) == "<" { out.append(.op("<<<")); i += 3 }
                    else { let strip = at(i + 2) == "-"; out.append(.op("<<")); wantEnd = strip; i += strip ? 3 : 2 }
                } else if at(i + 1) == ">" {
                    return (out, "it has a redirection Lotus cannot follow")
                } else {
                    out.append(.op("<")); i += 1
                }
            default:
                cur.append(ch); has = true; i += 1
            }
        }
        flush()
        return (out, nil)
    }

    // ── One command of a line ──

    private func judge(_ seg: [Token], _ depth: Int, piped: Bool) -> String? {
        var words: [Word] = []
        var fed = piped             // something flows into the command (a pipe, <, a here-document)
        var k = 0
        while k < seg.count {
            switch seg[k] {
            case .word(let w):
                words.append(w); k += 1
            case .op(let o):
                guard k + 1 < seg.count, case .word(let w) = seg[k + 1] else { return "it has a redirection Lotus cannot follow" }
                k += 2
                switch o {
                case ">", ">>", "&>", "&>>":
                    if ["/dev/null", "/dev/stdout", "/dev/stderr"].contains(w.text) { continue }
                    if let r = changes(w) { return r }
                case "<":
                    fed = true
                    if let r = looks(w) { return r }
                default:
                    fed = true      // here-documents and here-strings are text
                }
            }
        }
        return program(words[...], depth, fed: fed)
    }

    private static let keywords: Set<String> = ["if", "then", "else", "elif", "fi", "do", "done", "while", "until", "esac", "!", "{", "}", "time", "builtin", "noglob", "nocorrect"]
    private static let systemBins: Set<String> = ["/bin", "/usr/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]

    private func program(_ all: ArraySlice<Word>, _ depth: Int, fed: Bool) -> String? {
        var ws = all
        while let f = ws.first {
            let t = f.text
            if f.expands && !t.contains("=") { return "it runs a program Lotus cannot check ($…)" }
            if AutoCheck.keywords.contains(t) { ws = ws.dropFirst(); continue }
            if ["for", "select", "case", "[[", "]]"].contains(t) { return nil }   // a loop's list, a case, a test: no program
            if let eq = t.firstIndex(of: "="), eq != t.startIndex,
               t[..<eq].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                let name = String(t[..<eq])
                if ["PATH", "BASH_ENV", "ENV", "ZDOTDIR", "IFS", "PROMPT_COMMAND"].contains(name) || name.hasPrefix("DYLD_") || name.hasPrefix("LD_")
                    || name.hasPrefix("GIT_SSH") || name == "GIT_EXEC_PATH" {
                    return "it changes where programs come from (\(name))"
                }
                ws = ws.dropFirst(); continue
            }
            if t == "command" {
                if ws.dropFirst().first?.text.hasPrefix("-") == true { return nil }   // command -v
                ws = ws.dropFirst(); continue
            }
            if t == "nice" {
                ws = ws.dropFirst()
                while let n = ws.first, n.text.hasPrefix("-") || n.text.allSatisfy(\.isNumber) { ws = ws.dropFirst() }
                continue
            }
            if t == "timeout" || t == "gtimeout" {
                ws = ws.dropFirst()
                if ws.first?.text.first?.isNumber == true { ws = ws.dropFirst() }
                continue
            }
            break
        }
        guard let first = ws.first else { return nil }
        var name = first.text
        let args = Array(ws.dropFirst())
        if name.contains("/") {
            if first.expands == false && inside(name) && !isPrivate(name) { return projectProgram(name, args) }
            let dir = (name as NSString).deletingLastPathComponent
            guard AutoCheck.systemBins.contains(dir) else { return "it runs a program outside this folder" }
            name = (name as NSString).lastPathComponent
        }
        return judge(program: name, args, depth, fed: fed)
    }

    // ── Paths ──

    // $f of "for f in *.txt" stands for a file in this folder
    private func plain(_ w: Word) -> Word {
        guard w.expands, !loopVars.isEmpty else { return w }
        var t = w.text
        for v in loopVars {
            t = t.replacingOccurrences(of: #"\$\{?"# + NSRegularExpression.escapedPattern(for: v) + #"\}?(?![A-Za-z0-9_])"#, with: "x", options: .regularExpression)
        }
        return t.contains("$") ? w : Word(text: t, expands: false)
    }

    private func changes(_ word: Word) -> String? {
        let w = plain(word)
        if !write { return "it changes files, and that is switched off in /permissions" }
        if w.expands { return "it writes to a place Lotus cannot check ($…)" }
        if isPrivate(w.text) { return "it touches private files" }
        if !inside(w.text) { return "it changes files outside this folder" }
        return nil
    }

    private func looks(_ word: Word) -> String? {
        let w = plain(word)
        if w.expands { return "it uses names Lotus cannot check ($…)" }
        if isPrivate(w.text) { return "it touches private files" }
        if !readOutside && !inside(w.text) { return "it looks at files outside this folder" }
        return nil
    }

    private static func isOption(_ w: Word) -> Bool { w.text.hasPrefix("-") && w.text != "-" }
    private static func operands(_ args: [Word]) -> [Word] { args.filter { !isOption($0) && $0.text != "-" } }

    // The value of --file=/x style options, when it looks like a path
    private func optionValues(_ args: [Word]) -> String? {
        for a in args where AutoCheck.isOption(a) {
            guard let eq = a.text.firstIndex(of: "=") else { continue }
            let v = Word(text: String(a.text[a.text.index(after: eq)...]), expands: a.expands)
            if v.text.hasPrefix("/") || v.text.hasPrefix("~") || v.text.hasPrefix("..") || v.expands, let r = looks(v) { return r }
        }
        return nil
    }

    private func looksAll(_ args: [Word]) -> String? {
        for a in AutoCheck.operands(args) { if let r = looks(a) { return r } }
        return optionValues(args)
    }

    private func changesAll(_ args: [Word]) -> String? {
        for a in AutoCheck.operands(args) { if let r = changes(a) { return r } }
        return optionValues(args)
    }

    private func has(_ args: [Word], _ flags: Set<String>) -> Bool {
        args.contains { a in flags.contains(a.text) || flags.contains(where: { $0.hasPrefix("--") && a.text.hasPrefix($0 + "=") }) }
    }

    // ./build.sh, .venv/bin/pytest, node_modules/.bin/jest: the folder's own programs
    private func projectProgram(_ name: String, _ args: [Word]) -> String? {
        let base = (name as NSString).lastPathComponent.lowercased()
        let words = ["deploy", "publish", "release", "push", "install", "uninstall", "clean", "reset", "delete", "remove", "nuke", "wipe"]
        if let w = words.first(where: { base.contains($0) }) { return "it runs this folder's \"\(w)\" script" }
        return looksAll(args)
    }

    // ── Programs ──

    private static let noFiles: Set<String> = [
        "echo", "printf", "pwd", "whoami", "id", "groups", "date", "cal", "uname", "sw_vers", "hostname", "true", "false",
        "seq", "jot", "sleep", "nproc", "arch", "locale", "uptime", "which", "whereis", "type", "whence", "where", "test", "[",
        "expr", "bc", "dc", "tput", "clear", "man", "whatis", "apropos", "basename", "dirname",
        "unset", "cd", "pushd", "popd", "shift", "return", "exit", "wait", "read", ":", "vm_stat",
        "iostat", "ps", "pgrep", "top", "lsof", "netstat", "ping", "dig", "nslookup", "host", "whois", "traceroute",
        "system_profiler", "ioreg", "getconf", "ulimit", "tty", "stty", "fc", "hash", "rehash",
    ]
    private static let readers: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "ag", "ack", "file", "stat", "du", "df", "tree",
        "sort", "uniq", "cut", "tr", "diff", "cmp", "comm", "jq", "yq", "xxd", "hexdump", "od", "strings", "md5", "shasum",
        "sha1sum", "sha256sum", "md5sum", "cksum", "otool", "nm", "lipo", "size", "mdls", "mdfind", "column", "fold", "nl",
        "paste", "rev", "tac", "expand", "unexpand", "iconv", "base64", "less", "more", "bat", "realpath", "readlink",
        "look", "fmt", "pr", "zipinfo", "zcat", "gzcat", "bzcat", "xzcat", "diff3", "sdiff", "wc", "afinfo", "sips",
    ]
    private static let interpreters: Set<String> = ["python", "python3", "node", "ruby", "perl", "php", "bash", "sh", "zsh", "dash", "deno", "bun", "lua", "Rscript", "swift"]
    private static let builders: Set<String> = [
        "make", "gmake", "ninja", "cmake", "meson", "swiftc", "clang", "clang++", "gcc", "g++", "cc", "c++", "rustc", "javac",
        "java", "kotlinc", "tsc", "pytest", "py.test", "tox", "nox", "mypy", "ruff", "black", "isort", "flake8", "pylint",
        "eslint", "prettier", "jest", "vitest", "mocha", "gradle", "mvn", "rake", "xcodebuild", "swiftlint", "swiftformat",
        "shellcheck", "go", "cargo", "dotnet", "flutter", "dart", "zig", "ghc", "stack", "mix", "elixir", "erl", "rustfmt",
        "gofmt", "clang-format", "markdownlint", "hugo", "jekyll", "ld",
    ]

    private func judge(program p: String, _ args: [Word], _ depth: Int, fed: Bool = false) -> String? {
        let name = p.range(of: #"^(python|pip)[0-9.]*$"#, options: .regularExpression) != nil
            ? (p.hasPrefix("pip") ? "pip" : "python3") : p
        if AutoCheck.noFiles.contains(name) {
            if name == "cd" || name == "pushd" || name == "popd" {
                // cd alone goes home, cd - and popd go back – then the paths after it mean other files
                guard name != "popd", let dir = AutoCheck.operands(args).first, dir.text != "-" else { return "it works in another folder" }
                if let r = looks(dir) { return r == "it looks at files outside this folder" ? "it works in another folder" : r }
            }
            return nil
        }
        if AutoCheck.readers.contains(name) { return looksAll(args) }
        switch name {
        case "sudo", "doas", "su":
            return "it needs administrator rights"
        case "rm", "rmdir", "unlink", "trash", "srm", "shred":
            return "it deletes files"
        case "mkdir", "touch", "mv", "chmod":
            let ops = name == "chmod" ? Array(AutoCheck.operands(args).dropFirst()) : AutoCheck.operands(args)
            if has(args, ["-R"]) { return "it changes a whole folder tree" }
            for a in ops { if let r = changes(a) { return r } }
            return nil
        case "cp", "ln", "ditto", "install":
            let ops = AutoCheck.operands(args)
            guard let target = ops.last else { return nil }
            for a in ops.dropLast() { if let r = looks(a) { return r } }
            return changes(target)
        case "sed", "gsed":
            if args.contains(where: { $0.text == "-i" || $0.text.hasPrefix("-i") || $0.text == "--in-place" }) {
                return changesAll(Array(AutoCheck.operands(args).dropFirst(has(args, ["-e", "-f"]) ? 0 : 1)))
            }
            return looksAll(Array(AutoCheck.operands(args).dropFirst()))
        case "awk", "gawk", "nawk":
            let ops = AutoCheck.operands(args)
            if let prog = ops.first, prog.text.contains("system(") || prog.text.contains("|") || prog.text.range(of: #">\s*""#, options: .regularExpression) != nil {
                return "it runs commands or writes files from awk"
            }
            return looksAll(Array(ops.dropFirst()))
        case "find", "fd":
            if has(args, ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprintf", "-fls", "-x", "-X", "--exec", "--exec-batch"]) {
                return "it runs commands or deletes from find"
            }
            for a in args.prefix(while: { !$0.text.hasPrefix("-") }) { if let r = looks(a) { return r } }
            return nil
        case "xargs":
            guard let prog = args.first(where: { !$0.text.hasPrefix("-") }) else { return nil }
            return AutoCheck.readers.contains(prog.text) || AutoCheck.noFiles.contains(prog.text) ? nil : "it runs \(prog.text) on names Lotus cannot see"
        case "tar", "zip", "unzip", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "7z", "7zz":
            var ops = AutoCheck.operands(args)
            if name == "tar", let mode = ops.first, mode.text.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil, !args.contains(where: { $0.text.hasPrefix("-") && $0.text.count > 1 && !$0.text.hasPrefix("--") }) {
                ops.removeFirst()        // tar xzf archive.tgz
            }
            for a in ops { if let r = changes(a) { return r } }
            return optionValues(args)
        case "env", "printenv", "set":
            return args.isEmpty || name == "printenv" ? "it shows your environment, which may hold keys" : (name == "env" ? envCommand(args, depth) : nil)
        case "export", "local", "typeset", "declare", "readonly":
            if AutoCheck.operands(args).isEmpty { return "it shows your environment, which may hold keys" }
            return program(ArraySlice(args.filter { $0.text.contains("=") } + [Word(text: "true", expands: false)]), depth, fed: false)
        case "tee":
            return changesAll(args)
        case "pbpaste":
            return "it reads your clipboard"
        case "eval", "exec", "source", ".", "alias", "trap", "function", "autoload", "zmodload", "nohup", "disown", "watch":
            return "it runs code Lotus cannot see"
        case "curl", "wget", "http", "xh":
            return internet(name, args)
        case "ssh", "scp", "sftp", "rsync", "ftp", "nc", "ncat", "telnet", "socat", "mosh":
            return "it connects to another computer"
        case "git":
            return git(args)
        case "brew":
            let sub = AutoCheck.operands(args).first?.text ?? ""
            let read: Set<String> = ["list", "ls", "info", "search", "outdated", "deps", "uses", "config", "doctor", "--prefix", "--cellar",
                                     "--repo", "--version", "leaves", "desc", "cat", "log", "missing", "commands", "tap-info", ""]
            return read.contains(sub) || args.first?.text == "--prefix" ? nil : "it changes the software on this Mac (brew \(sub))"
        case "npm", "pnpm", "yarn", "bun":
            return packages(name, args, depth)
        case "npx", "pnpx", "bunx":
            return "it downloads and runs a package"
        case "pip", "pipx", "uv", "poetry", "conda", "gem", "bundle", "composer", "cpan", "cpanm":
            let sub = AutoCheck.operands(args).first?.text ?? ""
            if ["list", "show", "freeze", "check", "outdated", "search", "--version", "help", "env", "info", "tree", "lock", "version"].contains(sub) { return nil }
            if sub == "run" || sub == "exec" { return unsure(AutoCheck.rest(args, after: sub), depth: depth + 1) }
            return "it installs or changes packages (\(name) \(sub))"
        case "defaults":
            let sub = AutoCheck.operands(args).first?.text ?? ""
            return ["read", "read-type", "domains", "find", "help"].contains(sub) ? nil : "it changes settings of this Mac"
        case "plutil":
            return has(args, ["-p", "-lint", "-help", "-type"]) ? looksAll(args) : changesAll(args)
        case "codesign":
            return has(args, ["-v", "--verify", "-d", "--display", "-dv", "-dvv", "-dvvv"]) ? looksAll(args) : "it signs programs"
        case "diskutil":
            return ["list", "info"].contains(AutoCheck.operands(args).first?.text ?? "") ? nil : "it changes disks"
        case "xcode-select":
            return has(args, ["-p", "--print-path", "-v", "--version"]) ? nil : "it changes the developer tools"
        case "sysctl":
            return args.contains { $0.text == "-w" || $0.text.contains("=") } ? "it changes system settings" : nil
        case "xattr":
            return has(args, ["-d", "-c", "-w", "-r"]) ? changesAll(args) : looksAll(args)
        case "ifconfig":
            return AutoCheck.operands(args).count > 1 ? "it changes the network" : nil
        case "xcrun":
            let sub = AutoCheck.operands(args).first?.text ?? ""
            if ["swift", "swiftc", "clang", "clang++", "xctest", "lipo", "otool", "nm", "size", "strip", "actool", "ibtool", "metal", "metallib"].contains(sub) || has(args, ["--show-sdk-path", "--find", "--show-sdk-version", "-f"]) { return nil }
            if sub == "simctl" { return ["list", "help"].contains(AutoCheck.operands(args).dropFirst().first?.text ?? "") ? nil : "it changes simulators" }
            return "Lotus does not know xcrun \(sub)"
        case "open":
            let ops = AutoCheck.operands(args)
            if args.count == ops.count, !ops.isEmpty, ops.allSatisfy({ $0.text.hasPrefix("http://") || $0.text.hasPrefix("https://") || looks($0) == nil }) { return nil }
            return "it opens something on your screen"
        case "osascript", "shortcuts", "automator":
            return "it controls other apps"
        case "kill", "pkill", "killall":
            return "it stops programs"
        default:
            break
        }
        if AutoCheck.interpreters.contains(name) { return interpreter(name, args, depth, fed: fed) }
        if AutoCheck.builders.contains(name) { return builder(name, args) }
        return "Lotus does not know \(name)"
    }

    private static func rest(_ args: [Word], after sub: String) -> String {
        guard let i = args.firstIndex(where: { $0.text == sub }) else { return "" }
        return args[(i + 1)...].map { quote($0.text) }.joined(separator: " ")
    }

    private static func quote(_ s: String) -> String {
        s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:,+@%".contains($0) }) && !s.isEmpty ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func envCommand(_ args: [Word], _ depth: Int) -> String? {
        let rest = args.drop(while: { $0.text.hasPrefix("-") || $0.text.contains("=") })
        guard !rest.isEmpty else { return "it shows your environment, which may hold keys" }
        return unsure(rest.map { AutoCheck.quote($0.text) }.joined(separator: " "), depth: depth + 1)
    }

    // python3 script.py, node -e "…", bash -c "…"
    private func interpreter(_ name: String, _ args: [Word], _ depth: Int, fed: Bool) -> String? {
        if ["bash", "sh", "zsh", "dash"].contains(name), let i = args.firstIndex(where: { $0.text == "-c" }), i + 1 < args.count {
            return unsure(args[i + 1].text, depth: depth + 1)
        }
        if name == "python3", let i = args.firstIndex(where: { $0.text == "-m" }), i + 1 < args.count {
            let module = args[i + 1].text
            let fine: Set<String> = ["pytest", "unittest", "json.tool", "py_compile", "compileall", "doctest", "timeit", "mypy", "black", "ruff", "flake8", "pylint", "isort", "venv", "tabnanny", "calendar", "this"]
            if module == "pip" { return judge(program: "pip", Array(args[(i + 2)...]), depth) }
            return fine.contains(module) ? looksAll(Array(args[(i + 2)...])) : "it runs the Python module \(module)"
        }
        let inline: Set<String> = ["-c", "-e", "--eval", "-p", "--print", "-r", "-E"]
        if let i = args.firstIndex(where: { inline.contains($0.text) || (name == "perl" || name == "ruby") && $0.text.hasPrefix("-") && $0.text.contains("e") }) {
            guard i + 1 < args.count else { return nil }
            let code = args[i + 1].text
            let smells = ["import os", "subprocess", "shutil", "os.", "sys.", "open(", "Path(", "write", "unlink", "remove", "rename",
                          "rmtree", "socket", "urllib", "requests", "http", "eval(", "exec(", "__import__", "child_process", "require(",
                          "fs.", "process.", "File.", "Dir.", "system(", "`", "IO.", "Net::", "fetch(", "Deno.", "Bun.", "unlink(",
                          "-i", "glob", "chmod", "kill"]
            if let s = smells.first(where: { code.contains($0) }) { return "it runs code that may change things (\(s))" }
            // perl -pi -e '…' file changes the files after the code
            let files = Array(args[(i + 2)...])
            let inPlace = (name == "perl" || name == "ruby") && args.contains { $0.text.hasPrefix("-") && !$0.text.hasPrefix("--") && $0.text.contains("i") }
            return inPlace ? changesAll(files) : looksAll(files)
        }
        // no script: the code comes from what flows in (curl … | python3, a here-document) – or there is none
        guard let script = AutoCheck.operands(args).first else { return fed ? "it runs code Lotus cannot see (it flows in)" : nil }
        if isPrivate(script.text) { return "it touches private files" }
        if script.expands || !inside(script.text) { return "it runs a script outside this folder" }
        return projectProgram(script.text, Array(AutoCheck.operands(args).dropFirst()))
    }

    private func builder(_ name: String, _ args: [Word]) -> String? {
        let ops = AutoCheck.operands(args).map(\.text)
        let sub = ops.first ?? ""
        switch name {
        case "make", "gmake", "ninja", "cmake", "meson":
            if ops.contains(where: { ["install", "uninstall", "deploy", "publish", "release", "--install"].contains($0) }) || has(args, ["--install"]) {
                return "it installs or publishes something"
            }
        case "cargo":
            if ["install", "uninstall", "publish", "login", "logout", "owner", "yank"].contains(sub) { return "it installs or publishes (cargo \(sub))" }
        case "go":
            if ["install", "env"].contains(sub) && (sub == "install" || has(args, ["-w", "-u"])) { return "it installs or changes Go settings" }
        case "dotnet":
            if ["tool", "nuget", "workload"].contains(sub) { return "it installs or publishes (dotnet \(sub))" }
        case "flutter", "dart":
            if ops.contains("publish") || ["upgrade", "downgrade", "channel", "config"].contains(sub) { return "it changes Flutter or publishes" }
        case "mvn", "gradle":
            if ops.contains(where: { ["deploy", "publish", "release:perform", "install"].contains($0) }) { return "it installs or publishes something" }
        case "xcodebuild":
            if has(args, ["-exportArchive", "-runFirstLaunch", "-license", "-downloadPlatform", "-downloadAllPlatforms"]) { return "it changes Xcode or exports an app" }
        default:
            break
        }
        // the output of a compiler or formatter goes where it is told; make -C and friends work elsewhere
        for (i, a) in args.enumerated() where i + 1 < args.count {
            if ["-o", "--output", "--out-dir", "--outDir", "--target-dir"].contains(a.text), let r = changes(args[i + 1]) { return r }
            if ["-C", "--directory", "-f", "--file", "--makefile", "--manifest-path", "--package-path", "-project", "-workspace", "--project", "--cwd"].contains(a.text),
               let r = looks(args[i + 1]) { return r == "it looks at files outside this folder" ? "it works in another folder" : r }
        }
        return optionValues(args)
    }

    private func packages(_ name: String, _ args: [Word], _ depth: Int) -> String? {
        if has(args, ["-g", "--global", "--location=global"]) { return "it installs for the whole Mac" }
        let ops = AutoCheck.operands(args).map(\.text)
        let sub = ops.first ?? ""
        switch sub {
        case "", "test", "t", "tst", "run", "run-script", "start", "build", "ci", "ls", "list", "outdated", "view", "info", "why",
             "explain", "help", "--version", "-v", "dev", "lint", "check", "format", "typecheck", "preview", "serve", "pack", "dedupe":
            return nil
        case "install", "i", "add", "isntall", "in":
            return ops.count > 1 ? "it installs new packages (\(ops.dropFirst().prefix(3).joined(separator: " ")))" : nil
        case "audit":
            return ops.contains("fix") ? "it changes packages (audit fix)" : nil
        case "exec", "dlx", "x":
            return "it downloads and runs a package"
        default:
            // yarn and bun run scripts by their name (yarn test, bun dev)
            if (name == "yarn" || name == "bun") && !["publish", "remove", "rm", "uninstall", "upgrade", "up", "link", "unlink", "login", "logout", "global", "create", "init", "patch", "pm"].contains(sub) { return nil }
            return "it changes or publishes packages (\(name) \(sub))"
        }
    }

    private func internet(_ name: String, _ args: [Word]) -> String? {
        let sends: Set<String> = ["-d", "--data", "--data-raw", "--data-binary", "--data-urlencode", "-F", "--form", "--form-string",
                                  "-T", "--upload-file", "--json", "-u", "--user", "--post-data", "--post-file", "--body-data", "--body-file",
                                  "-K", "--config", "-b", "--cookie"]
        if has(args, sends) { return "it sends data to the internet" }
        for (i, a) in args.enumerated() {
            if (a.text == "-X" || a.text == "--request" || a.text == "--method") && i + 1 < args.count, args[i + 1].text.uppercased() != "GET" {
                return "it sends data to the internet (\(args[i + 1].text.uppercased()))"
            }
            if a.text.hasPrefix("-X") && a.text.count > 2 && a.text.dropFirst(2).uppercased() != "GET" { return "it sends data to the internet" }
            if a.text.lowercased().hasPrefix("file:") { return "it reads files through a file:// address" }
            if ["-o", "--output", "-O", "--output-document", "-P", "--directory-prefix"].contains(a.text), i + 1 < args.count,
               !(name == "curl" && a.text == "-O") {
                if let r = changes(args[i + 1]) { return r }
            }
        }
        return nil
    }

    private func git(_ args: [Word]) -> String? {
        var rest = args[...]
        // git -C dir, --no-pager, -c key=value
        while let f = rest.first, f.text.hasPrefix("-") {
            if f.text == "-c" || f.text.hasPrefix("--config") || f.text == "--exec-path" { return "it changes how git runs (\(f.text))" }
            for opt in ["--git-dir=", "--work-tree=", "--namespace="] where f.text.hasPrefix(opt) {
                if let r = looks(Word(text: String(f.text.dropFirst(opt.count)), expands: f.expands)) { return r }
            }
            if f.text == "-C" || f.text == "--git-dir" || f.text == "--work-tree" {
                rest = rest.dropFirst()
                if let dir = rest.first, let r = looks(dir) { return r }
            }
            rest = rest.dropFirst()
        }
        guard let subWord = rest.first else { return nil }
        let sub = subWord.text
        let more = Array(rest.dropFirst())
        let ops = AutoCheck.operands(more).map(\.text)
        let read: Set<String> = ["status", "diff", "log", "show", "blame", "grep", "ls-files", "ls-tree", "rev-parse", "rev-list", "describe",
                                 "shortlog", "cat-file", "show-ref", "for-each-ref", "name-rev", "merge-base", "count-objects", "whatchanged",
                                 "help", "version", "--version", "fetch", "check-ignore", "var", "annotate", "difftool", "range-diff", "bisect"]
        if read.contains(sub) { return sub == "bisect" ? "it moves the working tree (bisect)" : nil }
        switch sub {
        case "add", "init", "commit", "mv", "switch", "stash", "branch", "tag", "remote", "config", "reflog", "worktree", "submodule",
             "checkout", "restore", "notes", "apply", "am", "format-patch", "archive", "gc", "maintenance":
            break
        case "push":
            return "it sends commits to a remote (git push)"
        case "pull":
            return "it brings in changes from a remote (git pull)"
        default:
            return "it changes the history or throws away work (git \(sub))"
        }
        switch sub {
        case "commit":
            return has(more, ["--amend", "--fixup", "--squash"]) ? "it rewrites the last commit" : nil
        case "add", "init", "format-patch":
            return looksAll(more)
        case "mv":
            return changesAll(more)
        case "switch":
            return has(more, ["--discard-changes", "-f", "--force"]) ? "it throws away changes" : nil
        case "checkout":
            return has(more, ["-b", "-B"]) && !has(more, ["-f", "--force"]) && !more.contains(where: { $0.text == "--" || $0.text == "." })
                ? nil : "it may throw away changes (git checkout)"
        case "restore":
            return has(more, ["--staged", "-S"]) && !has(more, ["--worktree", "-W"]) ? nil : "it throws away changes (git restore)"
        case "stash":
            return ["drop", "clear"].contains(ops.first ?? "") ? "it deletes saved changes" : nil
        case "branch":
            return has(more, ["-d", "-D", "--delete", "-m", "-M", "--move", "-f", "--force", "-c", "-C", "--copy", "-u", "--set-upstream-to", "--unset-upstream"])
                ? "it deletes or renames branches" : nil
        case "tag":
            return has(more, ["-d", "--delete", "-f", "--force"]) ? "it deletes or moves tags" : nil
        case "remote":
            return ops.isEmpty || ["show", "get-url"].contains(ops.first!) ? nil : "it changes the remotes"
        case "config":
            return has(more, ["--get", "--get-all", "--list", "-l", "--get-regexp", "--show-origin", "--show-scope"]) ? nil : "it changes git settings"
        case "reflog", "worktree", "submodule", "notes":
            return ops.isEmpty || ["list", "show", "status"].contains(ops.first!) ? nil : "it changes the repository (git \(sub) \(ops.first!))"
        case "apply", "am":
            return has(more, ["--check", "--stat", "--numstat", "--summary"]) ? nil : "it applies a patch"
        case "archive":
            for (i, a) in more.enumerated() where (a.text == "-o" || a.text == "--output") && i + 1 < more.count { return changes(more[i + 1]) }
            return nil
        default:
            return "it cleans up the repository (git \(sub))"
        }
    }
}
