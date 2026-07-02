//
//  WorkflowShareModels.swift
//  Perch
//
//  Pure value types for sharing a workflow playbook between Perch installs:
//  the link returned by the Worker after an upload, the playbook fetched on
//  the receiving side, and the parser for the `perch://import/<id>` URL the
//  share landing page hands to the receiving app.
//
//  Pure (Foundation only) so the CLI harness (scripts/check-workflow-share.sh)
//  can compile and exercise the real parsing logic.
//

import Foundation

/// What the Worker returns after a playbook upload: the opaque share id and
/// the https link the user pastes to someone else.
struct WorkflowShareLink: Equatable {
    let shareId: String
    let urlString: String
}

/// A playbook fetched from a share link on the receiving device.
struct IncomingSharedWorkflow: Equatable {
    let shareId: String
    let title: String
    let markdown: String
}

enum WorkflowShareImportURL {

    /// Share ids are 16 random bytes base64url-encoded by the Worker — only
    /// URL-safe base64 characters, and long enough to be unguessable.
    static let shareIdPattern = "^[A-Za-z0-9_-]{16,64}$"

    /// Parses the share id out of a `perch://import/<id>` URL (the link on
    /// the browser landing page). Returns nil for anything else so a
    /// malformed or hostile URL is simply ignored.
    static func parseWorkflowShareId(fromImportURL url: URL) -> String? {
        guard url.scheme?.lowercased() == "perch" else { return nil }
        // In `perch://import/<id>` the "import" segment parses as the host.
        guard url.host?.lowercased() == "import" else { return nil }

        let pathComponents = url.path.split(separator: "/").map(String.init)
        guard pathComponents.count == 1, let candidateShareId = pathComponents.first else {
            return nil
        }
        guard candidateShareId.range(
            of: shareIdPattern, options: .regularExpression
        ) != nil else {
            return nil
        }
        return candidateShareId
    }
}
