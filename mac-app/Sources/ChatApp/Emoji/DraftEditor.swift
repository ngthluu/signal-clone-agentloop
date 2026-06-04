import Foundation

enum DraftEditor {
    static func insert(_ insertion: String, into text: String, at caretUTF16Offset: Int) -> (text: String, caret: Int) {
        let clampedOffset = min(max(caretUTF16Offset, 0), text.utf16.count)
        let insertionIndex = characterBoundary(in: text, atOrBeforeUTF16Offset: clampedOffset)
        let prefixUTF16Count = text[..<insertionIndex].utf16.count

        var newText = text
        newText.insert(contentsOf: insertion, at: insertionIndex)

        let newCaret = prefixUTF16Count + insertion.utf16.count
        return (newText, min(max(newCaret, 0), newText.utf16.count))
    }

    private static func characterBoundary(in text: String, atOrBeforeUTF16Offset offset: Int) -> String.Index {
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: offset)
        let proposedIndex = utf16Index.samePosition(in: text)

        if let proposedIndex, text.indices.contains(proposedIndex) || proposedIndex == text.endIndex {
            return proposedIndex
        }

        var boundary = text.startIndex
        for index in text.indices {
            let utf16Offset = text[..<index].utf16.count
            guard utf16Offset <= offset else {
                break
            }
            boundary = index
        }

        if text.utf16.count <= offset {
            return text.endIndex
        }

        return boundary
    }
}
