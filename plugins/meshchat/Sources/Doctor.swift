// MeshChat – `lotus meshchat doctor`, and what the chat checks before it starts.
//
// Bluetooth permission on macOS belongs to an app, and MeshChat is a command-line program: macOS asks about the
// app that started it – the terminal (Terminal, iTerm2, …). That app must declare Bluetooth use in its Info.plist
// (NSBluetoothAlwaysUsageDescription); if it does not, macOS ends any program it starts that touches Bluetooth.
// So the doctor finds that app among the parent processes, reads its Info.plist, and tries Bluetooth in a process
// of its own – if macOS ends that one, the doctor is still there to say why.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct TerminalApp {
    let name: String
    let path: String
    let declaresBluetooth: Bool?        // nil: its Info.plist could not be read (an app in your home folder)
}

enum Doctor {
    // The app macOS attributes this process to: the outermost .app among its parents
    static func terminalApp() -> TerminalApp? {
        #if os(macOS)
        var pid = getppid()
        var steps = 0
        while pid > 1 && steps < 40 {
            steps += 1
            if let path = executablePath(pid), let range = path.range(of: ".app/") {
                let app = String(path[..<range.lowerBound]) + ".app"
                return describe(app)
            }
            guard let next = parent(of: pid), next != pid else { break }
            pid = next
        }
        #endif
        return nil
    }

    static func describe(_ app: String) -> TerminalApp {
        let fallback = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
        guard let data = FileManager.default.contents(atPath: app + "/Contents/Info.plist"),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return TerminalApp(name: fallback, path: app, declaresBluetooth: nil)
        }
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? fallback
        let declared = (plist["NSBluetoothAlwaysUsageDescription"] as? String).map { !$0.isEmpty } ?? false
        return TerminalApp(name: Sanitize.nickname(name).isEmpty ? fallback : Sanitize.nickname(name), path: app, declaresBluetooth: declared)
    }

    #if os(macOS)
    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
    #endif

    // ── Bluetooth, tried in a process of its own ──────────────

    struct Probe {
        var values: [String: String] = [:]
        var killedBySignal: Int32?
        var timedOut = false
    }

    static func probeBluetooth(timeout: TimeInterval = 8) -> Probe {
        var result = Probe()
        guard let exe = Bundle.main.executablePath ?? CommandLine.arguments.first else { return result }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["probe-bluetooth"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return result }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning {
            p.terminate()
            result.timedOut = true
        }
        p.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            result.values[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        if p.terminationReason == .uncaughtSignal && !result.timedOut { result.killedBySignal = p.terminationStatus }
        return result
    }

    // ── The report ────────────────────────────────────────────

    private static func row(_ key: String, _ value: String) {
        print("    " + Theme.dim(key.padding(toLength: 13, withPad: " ", startingAt: 0)) + value)
    }

    private static func more(_ text: String) { print("    " + String(repeating: " ", count: 13) + Theme.dim(text)) }

    // → 0 when the chat should work, 1 when something has to be done first
    static func run(store: Store) -> Int32 {
        var problems = 0
        print("")
        print("  " + Theme.bold(Theme.accent("lotus")) + Theme.dim(" / ") + Theme.bold("MeshChat") + Theme.dim("  doctor"))
        print("")
        #if canImport(CoreBluetooth)
        let app = terminalApp()
        if let app = app {
            row("Terminal", "\(app.name) – \(app.path)")
            switch app.declaresBluetooth {
            case true?:
                more("declares Bluetooth use – macOS asks this app for the permission")
            case false?:
                problems += 1
                more("does not declare Bluetooth use: macOS would end MeshChat when it starts Bluetooth.")
                more("Use MeshChat in Terminal (Applications › Utilities) or a terminal app that declares it.")
            case nil:
                more("its Info.plist cannot be read from here – the Bluetooth check below tells more")
            }
        } else {
            row("Terminal", "not found among the parent processes (ssh, tmux or a launch agent?)")
            more("Bluetooth then needs the permission of whatever started it – a terminal window works best")
        }
        let probe = probeBluetooth()
        let auth = probe.values["authorization-after"] ?? probe.values["authorization"] ?? "unknown"
        if let sig = probe.killedBySignal {
            problems += 1
            row("Bluetooth", Theme.red("macOS ended the Bluetooth check (signal \(sig))"))
            more("That happens when the app that started MeshChat does not declare Bluetooth use.")
            more("Run MeshChat in Terminal, or check System Settings › Privacy & Security › Bluetooth.")
        } else if probe.timedOut && probe.values.isEmpty {
            problems += 1
            row("Bluetooth", Theme.yellow("no answer within 8 seconds"))
            more("Is macOS asking whether \(app?.name ?? "your terminal") may use Bluetooth? Choose Allow and try again.")
        } else {
            let central = probe.values["central"] ?? "unknown", peripheral = probe.values["peripheral"] ?? "unknown"
            switch auth {
            case "allowed": row("Permission", Theme.green("allowed") + " for \(app?.name ?? "this terminal")")
            case "denied":
                problems += 1
                row("Permission", Theme.red("denied") + " for \(app?.name ?? "this terminal")")
                more("Allow it: System Settings › Privacy & Security › Bluetooth – turn on \(app?.name ?? "your terminal"), then restart it.")
            case "restricted":
                problems += 1
                row("Permission", Theme.red("restricted") + " – a profile of your organisation does not allow Bluetooth")
            case "not-determined":
                row("Permission", Theme.yellow("not asked yet") + " – macOS asks when the chat starts (or now, in a dialog)")
            default:
                row("Permission", auth)
            }
            switch central {
            case "on": row("Bluetooth", Theme.green("on"))
            case "off":
                problems += 1
                row("Bluetooth", Theme.red("off") + " – turn it on in Control Center or System Settings › Bluetooth")
            case "not available":
                problems += 1
                row("Bluetooth", Theme.red("this Mac has no Bluetooth Low Energy (or it is turned off by the hardware)"))
            case "not allowed":
                problems += 1
                row("Bluetooth", Theme.red("not allowed") + " – see Permission")
            default:
                row("Bluetooth", central + (central == "starting" ? " – macOS may still be asking for the permission" : ""))
            }
            if central == "on" {
                row("Advertising", peripheral == "on" ? "possible – other Macs can find this one" : Theme.yellow(peripheral) + " – this Mac can still find and reach others")
            }
        }
        #else
        problems += 1
        row("Bluetooth", Theme.red("needs macOS – this build has no CoreBluetooth"))
        #endif
        let (rooms, roomProblems) = store.rooms()
        row("Rooms", "\(rooms.count) saved · \(store.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        for p in roomProblems { more(p) }
        row("Settings", "name \(store.nickname ?? "not set yet") · hops \(store.hops) · links \(store.maxLinks) · relay for other rooms \(store.relay ? "on" : "off")")
        let events = store.recentLog(300)
        let failures = events.filter { $0.contains("could not") || $0.contains("failed") || $0.contains("timed out") || $0.contains("no answer") }
        let links = events.filter { $0.contains(" ready (") }
        if events.isEmpty {
            row("Links", "no chat yet on this Mac")
        } else {
            row("Links", "\(links.count) made, \(failures.count) failed recently (\(events.count) events in events.log)")
            for f in failures.suffix(5) { more(String(f.prefix(110))) }
        }
        print("")
        if problems == 0 {
            print("  " + Theme.green("✓") + " Ready – " + Theme.key("lotus meshchat"))
        } else {
            print("  " + Theme.red("✗") + " \(problems == 1 ? "One thing" : "\(problems) things") to fix first – see above")
        }
        print("")
        return problems == 0 ? 0 : 1
    }
}
