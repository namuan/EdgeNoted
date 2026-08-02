import Testing
@testable import EdgeNoted

@Suite("Item Model Tests")
struct ItemTests {
    @Test("Item initializes with correct default state")
    func itemDefaults() {
        let item = Item(name: "Test")
        #expect(item.isComplete == false)
    }

    @Test("Throws on invalid input", arguments: ["", "   "])
    func invalidNames(name: String) {
        #expect(throws: Item.ValidationError.self) {
            try Item.validate(name: name)
        }
    }
}
