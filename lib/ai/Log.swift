// Lotus log: the same file and format as lib/log.zsh (tab separated, one line per entry).
// Only what happened is written – tool names and paths, never file contents, prompts or keys.
import Foundation

enum Log {
    private static let ranks = ["off": 0, "error": 1, "warn": 2, "info": 3, "debug": 4, "trace": 5]
    private static let env = ProcessInfo.processInfo.environment
    private static let path = env["LOTUS_LOG"] ?? ""
    private static let maxRank: Int = {
        var r = ranks[env["LOTUS_LOG_LEVEL"] ?? "info"] ?? 3
        if env["LOTUS_VERBOSE"] == "1" { r = max(r, 4) }
        return r
    }()
    private static let lock = NSLock()

    static func write(_ level: String, _ message: String, component: String = "ai") {
        guard !path.isEmpty, (ranks[level.lowercased()] ?? 3) <= maxRank else { return }
        var m = message.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: " ")
        let home = NSHomeDirectory()
        if home.count > 1 { m = m.replacingOccurrences(of: home, with: "~") }
        if let re = try? NSRegularExpression(pattern: "(sk-(?:ant-|proj-)?)[A-Za-z0-9_-]{12,}") {
            m = re.stringByReplacingMatches(in: m, range: NSRange(m.startIndex..., in: m), withTemplate: "$1•••")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = "\(f.string(from: Date()))\t\(level.uppercased())\t\(component)\t\(m)\n"
        lock.lock(); defer { lock.unlock() }
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        _ = line.withCString { Darwin.write(fd, $0, strlen($0)) }
        close(fd)
    }
}
