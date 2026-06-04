import Combine
import Foundation

@MainActor
final class MessageComposerModel: ObservableObject {
    @Published var draft: String = ""
    @Published var caretUTF16Offset: Int = 0
    @Published var isPickerPresented: Bool = false
    @Published var searchQuery: String = ""
    @Published var selectedCategory: EmojiCategory = .smileysAndPeople

    var filteredEmojis: [Emoji] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EmojiCatalog.emojis(in: selectedCategory)
        }

        return EmojiCatalog.search(searchQuery)
    }

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        !trimmedDraft.isEmpty
    }

    func togglePicker() {
        isPickerPresented.toggle()
    }

    func presentPicker() {
        isPickerPresented = true
    }

    func dismissPicker() {
        isPickerPresented = false
    }

    func insert(emoji: String) {
        let result = DraftEditor.insert(emoji, into: draft, at: caretUTF16Offset)
        draft = result.text
        caretUTF16Offset = result.caret
        dismissPicker()
    }

    func reset() {
        draft = ""
        caretUTF16Offset = 0
    }
}
