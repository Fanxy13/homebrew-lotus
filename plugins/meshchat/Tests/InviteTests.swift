// MeshChat tests – room codes: made from secure random bytes, read back the way people type them, and every
// kind of wrong code refused with the reason.

import Foundation

func inviteTests() {
    test("room codes: format and round trip") {
        let secret = RoomSecret.generate()
        let code = InviteCode.make(secret)
        check(code.hasPrefix("MC1-"), "starts with MC1-")
        let groups = code.split(separator: "-")
        checkEqual(groups.count, 7, "MC1 and six groups")
        checkEqual(groups.dropFirst().map { $0.count }, [5, 5, 5, 5, 5, 4], "groups of five")
        check(code.allSatisfy { $0 == "-" || Base32.alphabet.contains($0) || $0 == "M" }, "only base32 letters")
        checkEqual(try InviteCode.parse(code), secret, "read back")
        var codes = Set<String>()
        for _ in 0..<200 { codes.insert(InviteCode.make(RoomSecret.generate())) }
        checkEqual(codes.count, 200, "200 new rooms, 200 different codes")
    }

    test("room codes: typed the way people type them") {
        let secret = RoomSecret.generate()
        let code = InviteCode.make(secret)
        checkEqual(try InviteCode.parse(code.lowercased()), secret, "lower case")
        checkEqual(try InviteCode.parse(code.replacingOccurrences(of: "-", with: "")), secret, "without dashes")
        checkEqual(try InviteCode.parse(code.replacingOccurrences(of: "-", with: " ")), secret, "with spaces")
        checkEqual(try InviteCode.parse("  \(code)\n"), secret, "pasted with spaces and a line break")
        checkEqual(try InviteCode.parse(String(code.dropFirst(4))), secret, "without MC1-")
        let body = Base32.encode(secret.bytes + Data(CryptoBackend.sha256(Data("MeshChat invite v1".utf8) + secret.bytes).prefix(2)))
        checkEqual(try InviteCode.parse(body), secret, "the bare 29 characters, even when they start with MC and a digit")
        let confusable = code.replacingOccurrences(of: "0", with: "O").replacingOccurrences(of: "1", with: "I")
        checkEqual(try InviteCode.parse(confusable), secret, "O for 0 and I for 1")
    }

    test("room codes: wrong ones are refused with the reason") {
        let code = InviteCode.make(RoomSecret.generate())
        func reason(_ text: String) -> InviteError? {
            do { _ = try InviteCode.parse(text); return nil } catch let e as InviteError { return e } catch { return nil }
        }
        checkEqual(reason(""), .empty, "empty")
        checkEqual(reason("  - "), .empty, "only dashes")
        checkEqual(reason("MC2-AAAAA"), .newerVersion("MC2"), "a code of a newer MeshChat")
        checkEqual(reason(code + "Q"), .wrongLength, "a character too many")
        checkEqual(reason(String(code.dropLast())), .wrongLength, "a character missing")
        checkEqual(reason(code.replacingOccurrences(of: code.last.map(String.init) ?? "", with: "U")), .badCharacter("U"), "U is not in room codes")
        checkEqual(reason("MC1-ABCDE-!!!"), .badCharacter("!"), "punctuation")
        // one character changed: the check bytes catch it
        var chars = Array(code)
        let i = 10
        chars[i] = chars[i] == "A" ? "B" : "A"
        checkEqual(reason(String(chars)), .checksum, "a typo in the middle")
        // two neighbouring letters that differ, swapped
        var swapped = Array(code)
        let dash: Character = "-"
        let at = (4..<(swapped.count - 1)).first { (j: Int) -> Bool in
            let a = swapped[j], b = swapped[j + 1]
            return a != b && a != dash && b != dash
        }
        if let j = at { swapped.swapAt(j, j + 1) }
        checkEqual(reason(String(swapped)), .checksum, "two letters swapped")
        check(InviteError.checksum.description.contains("typo"), "the reason is said in words")
    }
}
