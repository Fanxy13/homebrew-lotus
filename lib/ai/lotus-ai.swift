// lotus-ai – Apple Intelligence (on-device Foundation Models) for the terminal.
// Built once on demand by lib/cmd/ai.zsh:  xcrun swiftc -O -parse-as-library
//
//   lotus-ai --check            prints "available" or "unavailable: <reason>"
//   lotus-ai "question"          streams one answer
//   lotus-ai -                   reads the prompt from stdin
//   lotus-ai --chat              conversation until an empty line, "exit" or Ctrl-D
// Instructions can be set with the LOTUS_AI_INSTRUCTIONS environment variable.

import Foundation
import FoundationModels

@main
struct LotusAI {
    static let defaultInstructions = """
        You are Lotus, a helpful assistant inside the macOS terminal. \
        Answer clearly and concisely in plain text. Do not use Markdown headings or tables.
        """

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let model = SystemLanguageModel.default

        if args.first == "--check" {
            switch model.availability {
            case .available: print("available")
            case .unavailable(let reason): print("unavailable: \(reason)")
            }
            return
        }
        guard case .available = model.availability else {
            FileHandle.standardError.write(Data("Apple Intelligence is not available on this Mac.\n".utf8))
            exit(2)
        }

        let instructions = ProcessInfo.processInfo.environment["LOTUS_AI_INSTRUCTIONS"] ?? defaultInstructions
        let session = LanguageModelSession(instructions: instructions)

        if args.first == "--chat" {
            while true {
                FileHandle.standardOutput.write(Data("\n\u{1B}[1myou ›\u{1B}[0m ".utf8))
                guard let line = readLine(), !line.trimmingCharacters(in: .whitespaces).isEmpty,
                      line != "exit", line != "quit" else { break }
                print("")
                await stream(session, line)
            }
            return
        }

        var prompt = args.joined(separator: " ")
        if prompt == "-" || prompt.isEmpty {
            prompt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { exit(1) }
        let ok = await stream(session, prompt)
        exit(ok ? 0 : 1)
    }

    // Prints the answer while it is being written
    @discardableResult
    static func stream(_ session: LanguageModelSession, _ prompt: String) async -> Bool {
        var printed = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                let text = snapshot.content
                if text.hasPrefix(printed) {
                    FileHandle.standardOutput.write(Data(text.dropFirst(printed.count).utf8))
                } else {
                    FileHandle.standardOutput.write(Data(text.utf8))
                }
                printed = text
            }
            print("")
            return true
        } catch let error as LanguageModelSession.GenerationError {
            let reason: String
            switch error {
            case .guardrailViolation:
                reason = "Apple's safety filter blocked this request. Try different words."
            case .exceededContextWindowSize:
                reason = "The text is too long for the on-device model. Try a shorter text."
            default:
                reason = error.localizedDescription
            }
            FileHandle.standardError.write(Data("\n  \(reason)\n".utf8))
            return false
        } catch {
            FileHandle.standardError.write(Data("\n  Apple Intelligence could not answer: \(error.localizedDescription)\n".utf8))
            return false
        }
    }
}
