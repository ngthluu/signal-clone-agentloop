import AppKit
import SwiftUI
import XCTest
@testable import ChatApp

@MainActor
final class CursorTrackingTextFieldTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() {
        window?.close()
        window = nil
        super.tearDown()
    }

    func testTypingUpdatesBindingAndPreservesTypedCharacters() throws {
        var text = ""
        var caret = 0
        let view = CursorTrackingTextField(
            "Message",
            text: Binding(get: { text }, set: { text = $0 }),
            caretUTF16Offset: Binding(get: { caret }, set: { caret = $0 }),
            onSubmit: {}
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 60)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        spinRunLoop()

        let field = try XCTUnwrap(findTextField(in: hosting), "hosted CursorTrackingTextField should materialize an NSTextField")
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        // Type two characters the way the field editor delivers real keystrokes.
        editor.insertText("h", replacementRange: editor.selectedRange())
        spinRunLoop()
        editor.insertText("i", replacementRange: editor.selectedRange())
        spinRunLoop()

        XCTAssertEqual(text, "hi", "every keystroke must reach the text binding")
        XCTAssertEqual(field.stringValue, "hi", "typed characters must not be wiped by representable updates")
        XCTAssertTrue(
            editor.delegate === field,
            "the field editor's delegate must remain the NSTextField; replacing it breaks controlTextDidChange delivery"
        )
        XCTAssertEqual(caret, 2)
    }

    private func spinRunLoop(for interval: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField {
            return field
        }
        for subview in view.subviews {
            if let field = findTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
