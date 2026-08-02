import Testing

@testable import EdgeNoted

@Suite("Color token parsing")
struct ColorTokenParserTests {
    @Test("Parses 6-digit hex tokens")
    func parsesSixDigit() {
        let tokens = ColorTokenParser.tokens(in: "Use #FF5733 and #0A84FF here")
        #expect(tokens.count == 2)
        #expect(tokens[0].hex == "ff5733")
        #expect(tokens[1].hex == "0a84ff")
    }

    @Test("Expands 3-digit hex tokens to 6 digits")
    func parsesThreeDigit() {
        let tokens = ColorTokenParser.tokens(in: "#f00 is red")
        #expect(tokens.count == 1)
        #expect(tokens[0].hex == "ff0000")
    }

    @Test("Ignores partial or invalid hex sequences")
    func ignoresInvalid() {
        let tokens = ColorTokenParser.tokens(in: "#ff573 too short, #ff57330 too long, #gggggg invalid")
        #expect(tokens.isEmpty)
    }

    @Test("Token offsets point at the hash")
    func tokenOffsets() {
        let tokens = ColorTokenParser.tokens(in: "ab #123456 cd")
        #expect(tokens.count == 1)
        #expect(tokens[0].start == 3)
        #expect(tokens[0].length == 7)
    }

    @Test("Converts hex to color components")
    func components() throws {
        let components = try #require(ColorTokenParser.components(fromHex: "FF0000"))
        #expect(components.red == 1.0)
        #expect(components.green == 0.0)
        #expect(components.blue == 0.0)
        #expect(ColorTokenParser.components(fromHex: "nope") == nil)
    }

    @Test("Hex string round-trip from sRGB components")
    func hexStringRoundTrip() throws {
        let color = try #require(ColorTokenParser.color(fromHex: "1B7F5A"))
        let hex = ColorTokenParser.hexString(from: color)
        #expect(hex == "1B7F5A")
    }
}
