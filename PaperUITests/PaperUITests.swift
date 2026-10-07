import XCTest

final class PaperUITests: XCTestCase {
    @MainActor
    func testPaletteAndTabCommands() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("l", modifierFlags: .command)
        let input = app.textFields["paper.commandPalette.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.typeKey("a", modifierFlags: .command)
        input.typeText("https://example.com\n")
        XCTAssertFalse(input.exists)

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(input.exists)
    }
}
