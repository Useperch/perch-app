//
//  TypedChatMessage.swift
//  notch
//
//  A single bubble in the typed-chat thread shown inside the notch composer.
//
//  This is a UI-only projection of a typed conversation — deliberately separate
//  from `CompanionManager.conversationHistory` (the model's rolling short-term
//  memory, which is shared with voice, capped at 10 exchanges, and stores the
//  point-tag-stripped spoken text). This type instead carries exactly what the
//  bubble thread needs to draw: a role, the display text, whether it's still
//  streaming, and any image thumbnails the user attached.
//

import AppKit

/// Who authored a bubble in the typed-chat thread.
enum TypedChatRole {
    case user
    case assistant
}

/// One message bubble in the typed-chat thread.
struct TypedChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: TypedChatRole
    /// The bubble's display text. Mutable because an assistant bubble is filled in
    /// token-by-token as the reply streams in.
    var text: String
    /// True while an assistant reply is still streaming into this bubble. Drives the
    /// "thinking" dots (when text is empty) and the trailing shimmer (while filling).
    var isStreaming: Bool
    /// Display-only previews of the images the user attached to this message. Empty
    /// for assistant bubbles. The vision bytes travel a separate path; the UI only
    /// ever needs the thumbnails.
    let attachmentThumbnails: [NSImage]

    init(
        id: UUID = UUID(),
        role: TypedChatRole,
        text: String,
        isStreaming: Bool = false,
        attachmentThumbnails: [NSImage] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.attachmentThumbnails = attachmentThumbnails
    }
}
