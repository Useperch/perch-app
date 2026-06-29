//
//  EnabledIntegrationsStore.swift
//  leanring-buddy
//
//  Persists which NATIVE integrations the user has turned on, as JSON at
//  <repo>/support/enabled-integrations.json. Native apps (Word, Excel, Numbers)
//  need no OAuth — Perch already actuates them via AppleScript — so "connecting"
//  one means recording that the user wants Perch to work with it. This store is
//  the source of truth for "already enabled?", the native equivalent of the
//  Composio manifest's `connected_toolkits`: once a native service is enabled it
//  is no longer offered.
//
//  (Composio services are NOT tracked here — their connected state lives in the
//  Composio manifest, read by ComposioManifestReader.)
//
//  Deliberately plain (not @MainActor / ObservableObject) and file-URL injected
//  so it round-trips in a standalone harness.
//

import Foundation

final class EnabledIntegrationsStore {

    /// Local identity keys (e.g. "native.microsoft_word") of enabled integrations.
    private(set) var enabledSlugs: Set<String>

    private let storageFileURL: URL

    init(storageFileURL: URL) {
        self.storageFileURL = storageFileURL
        self.enabledSlugs = Self.load(from: storageFileURL)
    }

    /// The app's real enabled-integrations file.
    static func standard() -> EnabledIntegrationsStore {
        return EnabledIntegrationsStore(
            storageFileURL: PerchSupportPaths.file("enabled-integrations.json")
        )
    }

    func isEnabled(_ toolkitSlug: String) -> Bool {
        enabledSlugs.contains(toolkitSlug)
    }

    /// Mark a native integration enabled and write through. No-op if already enabled.
    func recordEnabled(_ toolkitSlug: String) {
        guard !enabledSlugs.contains(toolkitSlug) else { return }
        enabledSlugs.insert(toolkitSlug)
        persist()
    }

    /// Record native enablement after a successful connect — the ONE place this rule
    /// lives, shared by both connect paths (the "+" dropdown in ActiveIntegrationsStore
    /// and the proactive/agent offer in ServiceConnectionOfferCoordinator). Composio
    /// connectivity is reflected through the manifest instead, so only native services
    /// are recorded here.
    func recordEnabledIfNative(kind: ServiceKind, toolkitSlug: String) {
        guard kind == .native else { return }
        recordEnabled(toolkitSlug)
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let directoryURL = storageFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            // Sorted so the on-disk file is stable/diffable across writes.
            let encoded = try JSONEncoder().encode(enabledSlugs.sorted())
            try encoded.write(to: storageFileURL, options: .atomic)
        } catch {
            print("⚠️ EnabledIntegrationsStore: failed to persist enabled integrations: \(error)")
        }
    }

    private static func load(from fileURL: URL) -> Set<String> {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return Set(try JSONDecoder().decode([String].self, from: storedData))
        } catch {
            print("⚠️ EnabledIntegrationsStore: failed to decode enabled integrations: \(error)")
            return []
        }
    }
}
