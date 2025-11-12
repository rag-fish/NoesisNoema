//
//  SafeTextInput.swift
//  NoesisNoema
//
//  IME-safe text input wrapper for macOS to avoid NSXPCDecoder warnings
//

import SwiftUI

#if os(macOS)
import AppKit

struct SafeTextInput: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var isEnabled: Bool
    @EnvironmentObject var appSettings: AppSettings

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesAdaptiveColorMappingForDarkAppearance = false

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled

        // Discard marked text and reset input context when disabled or when IME is explicitly disabled
        if !isEnabled || appSettings.disableMacOSIME {
            if textView.hasMarkedText() {
                textView.unmarkText()
            }
            textView.inputContext?.discardMarkedText()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SafeTextInput
        weak var scrollView: NSScrollView?

        init(_ parent: SafeTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !NSEvent.modifierFlags.contains(.shift) {
                    DispatchQueue.main.async {
                        self.parent.onSubmit()
                    }
                    return true
                }
            }
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // When IME is disabled, ensure input context discards marked text on selection change
            if parent.appSettings.disableMacOSIME {
                if textView.hasMarkedText() {
                    textView.unmarkText()
                }
                textView.inputContext?.discardMarkedText()
            }
        }
    }
}

#else

struct SafeTextInput: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var isEnabled: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .onSubmit(onSubmit)
            .disabled(!isEnabled)
    }
}

#endif
