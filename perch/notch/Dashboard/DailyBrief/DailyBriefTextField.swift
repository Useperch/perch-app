//
//  DailyBriefTextField.swift
//  notch
//
//  A full-capability inline text editor for the brief's editable list rows. It wraps a
//  native AppKit `NSTextField` (so all the normal editing — backspace, selection, arrow
//  keys, undo, copy/paste, word-wrap — just works) and intercepts only two keys to get the
//  Notion behavior: Return starts a new row, and Backspace on an EMPTY row deletes it.
//
//  SwiftUI's own `TextField` + `.onKeyPress` was unreliable for this (it interfered with
//  ordinary backspace), so the editing surface is AppKit and only the two list-structure
//  keys are special-cased via the field-editor command path.
//

import AppKit
import SwiftUI

struct DailyBriefTextField: NSViewRepresentable {
    /// This row's identity (used to drive programmatic focus from the parent).
    let itemID: String
    @Binding var text: String
    /// Which row currently owns the keyboard; kept in sync both ways.
    @Binding var focusedItemID: String?
    let font: NSFont
    let textColor: NSColor
    /// Wrap width — the list columns are fixed, so a constant keeps long items on two lines.
    let wrapWidth: CGFloat

    /// Return pressed: start a new row below this one.
    let onReturn: () -> Void
    /// Backspace pressed while this row is empty: delete it and move focus up.
    let onBackspaceWhenEmpty: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: "")
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.font = font
        textField.textColor = textColor
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.cell?.usesSingleLineMode = false
        textField.maximumNumberOfLines = 0
        textField.preferredMaxLayoutWidth = wrapWidth
        textField.stringValue = text
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.font = font
        textField.textColor = textColor
        textField.preferredMaxLayoutWidth = wrapWidth

        // Programmatic focus: when the parent points focus at this row and it isn't already
        // being edited, make it first responder (async to avoid layout reentrancy).
        if focusedItemID == itemID, textField.currentEditor() == nil {
            DispatchQueue.main.async {
                textField.window?.makeFirstResponder(textField)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DailyBriefTextField

        init(parent: DailyBriefTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            // Keep SwiftUI's focus state in sync when the user clicks into a field.
            if parent.focusedItemID != parent.itemID {
                parent.focusedItemID = parent.itemID
            }
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true   // consumed — don't insert a literal newline
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                // Only special-case Backspace when the row is empty; otherwise let the field
                // delete a character normally (full native editing).
                if textView.string.isEmpty {
                    parent.onBackspaceWhenEmpty()
                    return true
                }
                return false
            }
            return false
        }
    }
}
