//
//  NotchTextInputController.swift
//  notch
//
//  Backing state for the notch text-input composer — the typed counterpart to
//  push-to-talk. The user opens it by pressing Control twice; it shows a text
//  field (with image attachments) inside a taller version of the listening bar,
//  wrapped in the same blue tracing-line glow as the voice agent.
//
//  This is a small shared store so three different owners can agree on one piece
//  of state without tight coupling:
//    • CompanionManager toggles it from the Control-double-tap shortcut.
//    • ContentView observes `isActive` to render the composer and the glow.
//    • The AppDelegate observes the posted notifications to grant/relinquish the
//      notch window's keyboard focus (see NotchSkyLightWindow.acceptsKeyInput).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One image the user attached to a typed message. Image-only for now: the model
/// receives these on the vision path alongside (or instead of) the screen capture.
struct NotchTextInputAttachment: Identifiable, Equatable {
    let id = UUID()
    /// Display name shown under the thumbnail (e.g. the original file name).
    let fileName: String
    /// A small preview rendered in the composer's thumbnail row.
    let thumbnail: NSImage
    /// JPEG-encoded bytes handed to Claude's vision call. Pre-encoded once here so
    /// the send path never has to touch image conversion.
    let jpegData: Data

    static func == (lhs: NotchTextInputAttachment, rhs: NotchTextInputAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class NotchTextInputController: ObservableObject {
    static let shared = NotchTextInputController()

    /// True while the composer is on screen. Drives the notch surface + glow.
    @Published private(set) var isActive: Bool = false

    /// The in-progress message text, bound to the composer's text field.
    @Published var draftText: String = ""

    /// Image attachments staged for the next send, in the order they were added.
    @Published private(set) var attachments: [NotchTextInputAttachment] = []

    /// The composer's current rendered content height, reported by the composer view
    /// as its bubbles/attachments/input grow. The AppDelegate resizes the notch
    /// window to match so the notch grows to fit the chat thread. 0 when closed.
    @Published var measuredComposerContentHeight: CGFloat = 0

    /// Cap so a runaway paste/drop can't stage an unbounded number of images.
    private let maximumAttachmentCount = 6

    private init() {}

    /// True when there is something worth sending (text or at least one image).
    var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    // MARK: - Activation

    /// Control-double-tap behavior: open the composer if closed, dismiss if open.
    func toggle() {
        isActive ? dismiss() : activate()
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        // Ask the AppDelegate to let the notch window become key so the field can
        // receive keystrokes (the window refuses key status otherwise).
        NotificationCenter.default.post(name: .perchShowTextInput, object: nil)
    }

    /// Clear the draft + attachments after a send WITHOUT closing the composer, so
    /// the persistent chat thread stays open for follow-ups. Deliberately does not
    /// flip `isActive` or post `.perchTextInputDidDismiss`, so the notch window keeps
    /// its keyboard focus (`acceptsKeyInput`) between messages.
    func clearDraftAfterSend() {
        draftText = ""
        attachments = []
    }

    /// Close the composer and clear the draft. Safe to call when already closed.
    func dismiss() {
        guard isActive else { return }
        isActive = false
        draftText = ""
        attachments = []
        measuredComposerContentHeight = 0
        NotificationCenter.default.post(name: .perchTextInputDidDismiss, object: nil)
    }

    // MARK: - Attachments

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Stage an image from a file on disk (used by the "+" picker and file drops).
    /// Silently ignores anything that isn't a decodable image.
    func addImageAttachment(fromFileURL fileURL: URL) {
        guard let image = NSImage(contentsOf: fileURL) else { return }
        addImageAttachment(image, fileName: fileURL.lastPathComponent)
    }

    /// Stage an image already in memory (used by paste and image drops).
    func addImageAttachment(_ image: NSImage, fileName: String) {
        guard attachments.count < maximumAttachmentCount else { return }
        guard let jpegData = Self.jpegData(from: image) else { return }
        let thumbnail = Self.thumbnail(from: image)
        attachments.append(
            NotchTextInputAttachment(fileName: fileName, thumbnail: thumbnail, jpegData: jpegData)
        )
    }

    // MARK: - Image encoding helpers

    /// Encode an NSImage to JPEG bytes for the vision call. Returns nil if the
    /// image has no usable bitmap representation.
    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Downscale to a small square-ish preview so the thumbnail row stays light.
    private static func thumbnail(from image: NSImage) -> NSImage {
        let maximumThumbnailEdge: CGFloat = 96
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return image }

        let scale = min(
            maximumThumbnailEdge / originalSize.width,
            maximumThumbnailEdge / originalSize.height,
            1.0
        )
        let targetSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}
