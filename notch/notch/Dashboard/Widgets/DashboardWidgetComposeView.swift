//
//  DashboardWidgetComposeView.swift
//  leanring-buddy
//
//  The body shown by a freshly-added widget (source `.draft`) before it knows what to
//  show: a card with a textbox inside it. The user describes what they want ("most
//  important tech news on X") right in the card; on submit the widget interprets the
//  description and transforms into a live data-driven widget in place. A small close
//  control discards the draft.
//

import AppKit
import SwiftUI

struct DashboardWidgetComposeView: View {
    /// Called with the trimmed description when the user submits a non-empty spec.
    var onSubmit: (String) -> Void
    /// Called when the user discards the draft (the close control).
    var onDiscard: () -> Void

    @State private var specText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        DashboardWidgetCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                TextField("e.g. most important tech news on X", text: $specText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DashboardTheme.Fonts.serif(size: 17, weight: .regular))
                    .foregroundColor(DashboardTheme.Colors.textPrimary)
                    .lineLimit(2...5)
                    .focused($isFieldFocused)
                    .onSubmit(submit)

                Spacer(minLength: 0)

                HStack {
                    Text("Perch finds the source.")
                        .font(DashboardTheme.Fonts.sans(size: 12))
                        .foregroundColor(DashboardTheme.Colors.textTertiary)
                    Spacer()
                    addButton
                }
            }
        }
        .onAppear { isFieldFocused = true }
    }

    // MARK: Header (icon + title + discard)

    private var header: some View {
        HStack(spacing: 9) {
            DashboardWidgetHeader(systemIconName: "plus.circle", title: "New widget")
            Spacer(minLength: 8)
            DiscardButton(onDiscard: onDiscard)
        }
    }

    private var addButton: some View {
        Button(action: submit) {
            Text("Add")
                .font(DashboardTheme.Fonts.sans(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(trimmedSpec.isEmpty
                                   ? DashboardTheme.Colors.addButton.opacity(0.4)
                                   : DashboardTheme.Colors.addButton)
                )
        }
        .buttonStyle(.plain)
        .disabled(trimmedSpec.isEmpty)
        .onHover { hovering in
            if hovering && !trimmedSpec.isEmpty { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var trimmedSpec: String {
        specText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let spec = trimmedSpec
        guard !spec.isEmpty else { return }
        onSubmit(spec)
    }
}

// MARK: - Discard control

/// A small "×" that removes the draft widget. Pointer cursor on hover like every
/// interactive element.
private struct DiscardButton: View {
    let onDiscard: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onDiscard) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DashboardTheme.Colors.textTertiary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(isHovering ? 0.06 : 0.0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
