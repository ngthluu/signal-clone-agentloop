import XCTest
@testable import ChatApp

@MainActor
final class MessageComposerModelTests: XCTestCase {
    func testPickerPresentationMethodsUpdateState() {
        let model = MessageComposerModel()

        model.presentPicker()
        XCTAssertTrue(model.isPickerPresented)

        model.dismissPicker()
        XCTAssertFalse(model.isPickerPresented)

        model.togglePicker()
        XCTAssertTrue(model.isPickerPresented)

        model.togglePicker()
        XCTAssertFalse(model.isPickerPresented)
    }

    func testInsertEmojiAtCaretAdvancesCaretAndDismissesPicker() {
        let model = MessageComposerModel()
        model.draft = "hello"
        model.caretUTF16Offset = 2
        model.isPickerPresented = true

        model.insert(emoji: "🎉")

        XCTAssertEqual(model.draft, "he🎉llo")
        XCTAssertEqual(model.caretUTF16Offset, "he🎉".utf16.count)
        XCTAssertFalse(model.isPickerPresented)
    }

    func testSequentialInsertsPreserveOrder() {
        let model = MessageComposerModel()

        model.insert(emoji: "😀")
        model.insert(emoji: "🚀")

        XCTAssertEqual(model.draft, "😀🚀")
        XCTAssertEqual(model.caretUTF16Offset, "😀🚀".utf16.count)
    }

    func testFilteredEmojisUsesSearchWhenQueryIsNonEmpty() {
        let model = MessageComposerModel()
        model.selectedCategory = .flags
        model.searchQuery = "heart"

        XCTAssertEqual(model.filteredEmojis, EmojiCatalog.search("heart"))
    }

    func testFilteredEmojisUsesSelectedCategoryWhenQueryIsEmpty() {
        let model = MessageComposerModel()
        model.selectedCategory = .foodAndDrink
        model.searchQuery = "   \n"

        XCTAssertEqual(model.filteredEmojis, EmojiCatalog.emojis(in: .foodAndDrink))
    }

    func testResetClearsDraftAndCaret() {
        let model = MessageComposerModel()
        model.draft = "hello😀"
        model.caretUTF16Offset = model.draft.utf16.count

        model.reset()

        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(model.caretUTF16Offset, 0)
    }

    func testCanSendUsesTrimmedDraftRule() {
        let model = MessageComposerModel()

        XCTAssertFalse(model.canSend)

        model.draft = " \n\t "
        XCTAssertFalse(model.canSend)

        model.insert(emoji: "😀")
        XCTAssertTrue(model.canSend)
    }
}
