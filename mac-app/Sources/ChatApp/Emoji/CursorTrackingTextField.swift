import AppKit
import SwiftUI

struct CursorTrackingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var caretUTF16Offset: Int
    var onSubmit: () -> Void

    init(
        _ placeholder: String,
        text: Binding<String>,
        caretUTF16Offset: Binding<Int>,
        onSubmit: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        _caretUTF16Offset = caretUTF16Offset
        self.onSubmit = onSubmit
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textField = textField
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.update(text: $text, caretUTF16Offset: $caretUTF16Offset, onSubmit: onSubmit)

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard let editor = nsView.currentEditor() as? NSTextView else {
            return
        }

        // Track caret movement via notifications. The field editor's delegate must
        // remain the NSTextField itself: replacing it silences controlTextDidChange,
        // which leaves the text binding stale and wipes typed characters on the
        // next representable update.
        context.coordinator.observeSelectionChanges(of: editor)
        let clampedCaret = min(max(caretUTF16Offset, 0), nsView.stringValue.utf16.count)
        if editor.selectedRange().location != clampedCaret || editor.selectedRange().length != 0 {
            editor.setSelectedRange(NSRange(location: clampedCaret, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, caretUTF16Offset: $caretUTF16Offset, onSubmit: onSubmit)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var textField: NSTextField?
        private var text: Binding<String>
        private var caretUTF16Offset: Binding<Int>
        private var onSubmit: () -> Void
        private weak var observedTextView: NSTextView?
        private nonisolated(unsafe) var selectionObserver: NSObjectProtocol?

        init(text: Binding<String>, caretUTF16Offset: Binding<Int>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.caretUTF16Offset = caretUTF16Offset
            self.onSubmit = onSubmit
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        func update(text: Binding<String>, caretUTF16Offset: Binding<Int>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.caretUTF16Offset = caretUTF16Offset
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            observeSelectionChanges(of: currentTextView(from: notification))
            updateCaret(from: notification)
        }

        func observeSelectionChanges(of textView: NSTextView?) {
            guard let textView, textView !== observedTextView else {
                return
            }

            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
            observedTextView = textView
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleSelectionChange()
                }
            }
        }

        private func handleSelectionChange() {
            // The field editor is shared window-wide; only track the caret while
            // it is editing this representable's text field.
            guard let textView = observedTextView,
                  textField?.currentEditor() === textView else {
                return
            }
            updateCaret(from: textView)
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField, text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
            updateCaret(from: notification)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                updateCaret(from: textView)
                onSubmit()
                return true
            }

            return false
        }

        private func updateCaret(from notification: Notification) {
            updateCaret(from: currentTextView(from: notification))
        }

        private func updateCaret(from textView: NSTextView?) {
            guard let textView else {
                return
            }

            let location = textView.selectedRange().location
            if caretUTF16Offset.wrappedValue != location {
                caretUTF16Offset.wrappedValue = location
            }
        }

        private func currentTextView(from notification: Notification) -> NSTextView? {
            (notification.userInfo?["NSFieldEditor"] as? NSTextView) ??
                (notification.object as? NSTextField)?.currentEditor() as? NSTextView
        }
    }
}
