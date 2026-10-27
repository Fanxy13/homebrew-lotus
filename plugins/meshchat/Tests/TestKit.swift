// MeshChat tests – a small runner without XCTest (the Command Line Tools do not always have it). Built with the
// plugin's sources by `lotus meshchat selftest`; prints ✓/✗ per check like Lotus' own tests, exit 1 on a failure.
// The mesh tests run on a simulated radio (SimTransport.swift): they test the protocol, not Bluetooth.

import Foundation

final class TestRun {
    static var passed = 0
    static var failed = 0
    static var current = ""
    static var failures: [String] = []
}

func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
    if ok {
        TestRun.passed += 1
    } else {
        TestRun.failed += 1
        let place = "\(("\(file)" as NSString).lastPathComponent):\(line)"
        TestRun.failures.append("\(TestRun.current): \(what) (\(place))")
        print("    ✗ \(what)  [\(place)]")
    }
}

func checkEqual<T: Equatable>(_ got: T, _ want: T, _ what: String, file: StaticString = #file, line: UInt = #line) {
    check(got == want, "\(what) – got \(got), want \(want)", file: file, line: line)
}

func checkThrows<T>(_ what: String, file: StaticString = #file, line: UInt = #line, _ body: () throws -> T) {
    do {
        _ = try body()
        check(false, "\(what) – it did not fail", file: file, line: line)
    } catch {
        check(true, what, file: file, line: line)
    }
}

func checkNoThrow<T>(_ what: String, file: StaticString = #file, line: UInt = #line, _ body: () throws -> T) -> T? {
    do {
        return try body()
    } catch {
        check(false, "\(what) – \(error)", file: file, line: line)
        return nil
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    TestRun.current = name
    let before = TestRun.failed
    do {
        try body()
    } catch {
        TestRun.failed += 1
        TestRun.failures.append("\(name): \(error)")
        print("    ✗ stopped by an error: \(error)")
    }
    print("  \(TestRun.failed == before ? "✓" : "✗") \(name)")
}

func hex(_ s: String) -> Data { Hex.decode(s.filter { !$0.isWhitespace && $0 != ":" })! }

// The same "random" bytes on every run (SplitMix64), so a test that uses them is never flaky
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@main
struct TestMain {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)     // each line out at once: a crash never hides where it happened
        print("MeshChat protocol tests (crypto: \(CryptoBackend.name))")
        codecTests()
        cryptoTests()
        inviteTests()
        fragmentTests()
        dedupTests()
        meshTests()
        storeTests()
        print("")
        print("\(TestRun.passed) passed, \(TestRun.failed) failed")
        exit(TestRun.failed == 0 ? 0 : 1)
    }
}
