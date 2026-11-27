// lotus-vue – runs the Vue compiler for the Live Server (lib/live/liveserver.py, lib/live/vue.py), built once by lotus_swift_build
// (lib/core.zsh) from this file, when the first .vue file is asked for.
//
//   lotus-vue <script.js>…    loads the scripts, in this order, into JavaScriptCore – Apple's own JavaScript engine, the one in Safari
//                             (lib/live/vue/compiler-sfc.js, then lib/live/vue/sfc.js) – and then answers on stdin and stdout:
//                             one request per line in, one answer per line out. The lines are JSON and made and read by sfc.js,
//                             which knows what a request is; this program only carries them (see the top of sfc.js).
//
// It reads and writes nothing but those lines and the scripts it is told to load, and has no network: a .vue file is compiled on
// this Mac and nowhere else.

import Foundation
import JavaScriptCore

func say(_ line: String) {
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

// a text as a JSON string – "…" with its quotes and breaks escaped
func json(_ text: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
          let list = String(data: data, encoding: .utf8) else { return "\"\"" }
    return String(list.dropFirst().dropLast())
}

func die(_ message: String) -> Never {
    say("{\"fatal\": \(json(message))}")
    exit(1)
}

@main
struct Main {
    static func main() {
        let paths = Array(CommandLine.arguments.dropFirst())
        if paths.isEmpty { die("usage: lotus-vue <compiler-sfc.js> <sfc.js>") }
        guard let context = JSContext() else { die("JavaScriptCore could not start") }
        var failure = ""
        context.exceptionHandler = { _, exception in failure = exception?.toString() ?? "an error in a script" }
        for path in paths {
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { die("cannot read \(path)") }
            context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
            if !failure.isEmpty { die("\((path as NSString).lastPathComponent): \(failure)") }
        }
        guard let handle = context.objectForKeyedSubscript("lotusRequest"), handle.isObject else { die("the scripts do not define lotusRequest") }
        while let line = readLine(strippingNewline: true) {
            failure = ""
            let answer = handle.call(withArguments: [line])
            if !failure.isEmpty {                       // the script threw instead of answering: that is an answer too
                say("{\"id\": null, \"errors\": [{\"message\": \(json(failure))}]}")
            } else if let text = answer?.toString(), !text.isEmpty {
                say(text)
            } else {
                say("{\"id\": null, \"errors\": [{\"message\": \"no answer\"}]}")
            }
        }
    }
}
