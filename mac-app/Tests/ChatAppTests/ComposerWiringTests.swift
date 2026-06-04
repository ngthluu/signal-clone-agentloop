import SwiftUI
import XCTest
@testable import ChatApp

@MainActor
final class ComposerWiringTests: XCTestCase {
    func testComposerDraftIsSentThenReset() async {
        let model = MessageComposerModel()
        model.draft = "hi 😀"
        model.caretUTF16Offset = model.draft.utf16.count
        var sentText: String?
        let send: (String) async -> Void = { value in
            sentText = value
        }

        let text = model.draft
        await send(text)
        model.reset()

        XCTAssertEqual(sentText, "hi 😀")
        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(model.caretUTF16Offset, 0)
    }

    func testEmojiPickerViewCanBeConstructedWithShippedModel() {
        let model = MessageComposerModel()

        _ = EmojiPickerView(model: model)

        XCTAssertEqual(model.selectedCategory, .smileysAndPeople)
    }
}
