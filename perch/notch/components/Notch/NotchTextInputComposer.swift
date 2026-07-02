//
//  NotchTextInputComposer.swift
//  notch
//
//  The typed-input surface shown inside the notch when the user presses Control
//  twice. It matches the voice listening bar's width but grows taller, with the
//  text field anchored at the bottom and an image-attachment row above it. The
//  blue tracing-line glow around the notch is drawn separately by
//  `NotchVoiceOutline` (overlaid in `ContentView`), exactly as for voice.
//
//  Sends through `CompanionManager.sendTypedMessage(_:attachments:)`, the same
//  pipeline a spoken request uses — so a typed message with images behaves just
//  like a voice turn that needed to see the screen.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchTextInputComposer: View {
    @EnvironmentObject var vm: ViewModel
    @EnvironmentObject var companionManager: CompanionManager
    @ObservedObject var controller = NotchTextInputController.shared

    @FocusState private var isTextFieldFocused: Bool
    @State private var isDropTargeted: Bool = false

    /// The composer always uses the canonical voice blue for its accents (send
    /// button, caret, drop highlight) — NOT the system accent color and NOT the
    /// album-tinted aura — so it matches the voice surface's blue identity.
    private static let voiceBlue = VoiceAuraPalette.blue.glow

    /// Same width as the voice listening bar so the surface lines up with the
    /// notch exactly the way "Listening…" does — just taller.
    private var composerWidth: CGFloat {
        vm.closedNotchSize.width
            + 2 * VoiceLiveActivity.earWidth
            + 2 * VoiceLiveActivity.earGap
    }

    /// Empty space at the very top so the text field and attachments sit BELOW the
    /// physical notch (the black camera housing) rather than behind it.
    private var topNotchClearance: CGFloat {
        vm.effectiveClosedNotchHeight + 8
    }

    /// Constant gap between the input row and the bottom edge of the notch, kept the
    /// same no matter how tall the chat thread grows.
    private let bottomGap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Clear the physical notch at the top of the surface.
            Color.clear.frame(height: topNotchClearance)

            // The persistent chat thread grows the surface upward as the
            // conversation fills in; empty threads take no space.
            if !companionManager.typedChatMessages.isEmpty {
                NotchChatTranscriptView()
            }

            if !controller.attachments.isEmpty {
                attachmentThumbnailRow
            }

            inputRow
        }
        .padding(.horizontal, 16)
        // Fixed breathing room between the input row and the bottom edge of the
        // notch, kept constant however tall the thread grows.
        .padding(.bottom, bottomGap)
        .frame(width: composerWidth)
        // Report the composer's rendered height so the AppDelegate can size the
        // notch window to fit exactly this content.
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ComposerContentHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
        .onPreferenceChange(ComposerContentHeightPreferenceKey.self) { measuredHeight in
            controller.measuredComposerContentHeight = measuredHeight
        }
        .overlay {
            // A subtle highlight while an image is being dragged over the composer.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Self.voiceBlue.opacity(0.6), lineWidth: 1.5)
                    .padding(6)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            controller.ingest(providers: providers)
            return true
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            controller.ingest(providers: providers)
        }
        // Escape closes the composer without sending.
        .onExitCommand {
            controller.dismiss()
        }
        .onAppear {
            // Focus the field as soon as the surface appears. The notch window is
            // made key by the AppDelegate in response to the same trigger, so the
            // field can actually take keystrokes by the time this runs.
            focusTextFieldSoon()
        }
    }

    // MARK: - Input row (text field + attach + send), anchored at the bottom

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 10) {
            attachButton

            TextField("Ask anything", text: $controller.draftText)
                .textFieldStyle(.plain)
                // Match the notch's voice status text (system, 14, medium) so the
                // composer reads as part of the same surface.
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .tint(Self.voiceBlue)
                .lineLimit(1)
                .focused($isTextFieldFocused)
                // Return sends the message.
                .onSubmit(submit)

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var attachButton: some View {
        Button(action: { controller.requestTray() }) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .pointingHandCursorOnHover()
        .help("Add context")
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(controller.canSend ? Self.voiceBlue : Color.white.opacity(0.25))
        }
        .buttonStyle(.plain)
        .disabled(!controller.canSend)
        .pointingHandCursorOnHover()
        .help("Send")
    }

    // MARK: - Attachment thumbnails

    private var attachmentThumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.attachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 60)
    }

    private func attachmentThumbnail(_ attachment: NotchTextInputAttachment) -> some View {
        Image(nsImage: attachment.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    controller.removeAttachment(id: attachment.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .pointingHandCursorOnHover()
                .offset(x: 5, y: -5)
            }
            .help(attachment.fileName)
    }

    // MARK: - Actions

    private func submit() {
        guard controller.canSend else { return }
        let text = controller.draftText
        let attachments = controller.attachments
        companionManager.sendTypedMessage(text, attachments: attachments)
        // Keep the composer open as a persistent chat thread: clear the draft but
        // stay active and keyboard-focused so the user can read the reply and type
        // a follow-up. Escape / double-Control still fully dismiss.
        controller.clearDraftAfterSend()
        focusTextFieldSoon()
    }

    /// Assert focus now and again on the next runloop tick — the window may only
    /// just have become key, in which case an immediate focus request is dropped.
    private func focusTextFieldSoon() {
        isTextFieldFocused = true
        DispatchQueue.main.async { isTextFieldFocused = true }
    }
}

/// Carries the composer's rendered content height up to `onPreferenceChange`, which
/// forwards it to the controller so the AppDelegate can size the notch window to fit.
private struct ComposerContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shows the pointer (link) cursor while hovering an interactive control, per the
/// project rule that every clickable element communicates clickability on hover.
private struct PointingHandCursorOnHover: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func pointingHandCursorOnHover() -> some View {
        modifier(PointingHandCursorOnHover())
    }
}
