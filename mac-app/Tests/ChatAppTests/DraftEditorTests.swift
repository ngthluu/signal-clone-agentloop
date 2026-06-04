import XCTest
@testable import ChatApp

final class DraftEditorTests: XCTestCase {
    func testInsertIntoEmptyDraftYieldsEmojiAndCaretAfterIt() {
        let emoji = "😀"

        let result = DraftEditor.insert(emoji, into: "", at: 0)

        XCTAssertEqual(result.text, emoji)
        XCTAssertEqual(result.caret, emoji.utf16.count)
    }

    func testInsertAtStartOfASCIIDraft() {
        let result = DraftEditor.insert("🎉", into: "hello", at: 0)

        XCTAssertEqual(result.text, "🎉hello")
        XCTAssertEqual(result.caret, "🎉".utf16.count)
    }

    func testInsertAtMiddleOfASCIIDraft() {
        let result = DraftEditor.insert("🚀", into: "hello", at: 2)

        XCTAssertEqual(result.text, "he🚀llo")
        XCTAssertEqual(result.caret, "he🚀".utf16.count)
    }

    func testInsertAtEndOfASCIIDraft() {
        let text = "hello"

        let result = DraftEditor.insert("🍕", into: text, at: text.utf16.count)

        XCTAssertEqual(result.text, "hello🍕")
        XCTAssertEqual(result.caret, "hello🍕".utf16.count)
    }

    func testCaretBelowZeroClampsToStart() {
        let result = DraftEditor.insert("😀", into: "hello", at: -5)

        XCTAssertEqual(result.text, "😀hello")
        XCTAssertEqual(result.caret, "😀".utf16.count)
    }

    func testCaretAboveLengthClampsToEnd() {
        let result = DraftEditor.insert("😀", into: "hello", at: 99)

        XCTAssertEqual(result.text, "hello😀")
        XCTAssertEqual(result.caret, "hello😀".utf16.count)
    }

    func testMultiScalarEmojiAreInsertedAsIntactGraphemes() {
        let originalText = "ab"

        for emoji in ["👍🏽", "👨‍👩‍👧", "🇯🇵"] {
            let result = DraftEditor.insert(emoji, into: originalText, at: 1)

            XCTAssertTrue(result.text.contains(emoji))
            XCTAssertEqual(Array(result.text).count, Array(originalText).count + 1)
            XCTAssertEqual(String(data: Data(result.text.utf8), encoding: .utf8), result.text)
            XCTAssertTrue((0...result.text.utf16.count).contains(result.caret))
        }
    }

    func testInsertionInsideExistingEmojiSnapsDownAndDoesNotSplitIt() {
        let originalText = "😀😄"

        let result = DraftEditor.insert("🚀", into: originalText, at: 1)

        XCTAssertEqual(result.text, "🚀😀😄")
        XCTAssertEqual(Array(result.text), ["🚀", "😀", "😄"])
        XCTAssertEqual(result.caret, "🚀".utf16.count)
    }
}
