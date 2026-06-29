//
//  ActiveIntegrationsStrip.swift
//  notch
//
//  The dark rounded strip of connected-integration chips followed by the "+"
//  searchable picker of connectable services. Shared between notch surfaces;
//  both render `ActiveIntegrationsStrip(store:)` against
//  `CompanionManager.activeIntegrationsStore`.
//

import AppKit
import SwiftUI

// MARK: - Active Integrations Strip

/// The dark rounded strip of connected-integration chips followed by the "+"
/// picker of connectable services. Observes the store so it re-renders when a
/// connect completes (a new chip appears) or a connect is in flight.
struct ActiveIntegrationsStrip: View {
    @ObservedObject var store: ActiveIntegrationsStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(store.connectedIntegrations, id: \.toolkitSlug) { entry in
                IntegrationChip(entry: entry, isConnecting: store.isConnecting(entry))
            }

            ForEach(pendingConnectingEntries, id: \.toolkitSlug) { entry in
                IntegrationChip(entry: entry, isConnecting: true)
            }

            AddIntegrationPickerPopover(store: store)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Colors.notchSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Colors.notchBorder, lineWidth: 0.5)
        )
        .onAppear { store.refresh() }
    }

    private var pendingConnectingEntries: [ServiceCatalogEntry] {
        let connectedSlugs = Set(store.connectedIntegrations.map { $0.toolkitSlug })
        return store.connectableIntegrations.filter {
            store.isConnecting($0) && !connectedSlugs.contains($0.toolkitSlug)
        }
    }
}

// MARK: - Integration Chip

private struct IntegrationChip: View {
    let entry: ServiceCatalogEntry
    let isConnecting: Bool

    var body: some View {
        IntegrationIcon(entry: entry)
            .frame(width: 16, height: 16)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DS.Colors.notchChipFill)
            )
            .overlay {
                if isConnecting {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .help(entry.displayName)
    }
}

// MARK: - Integration Icon

private struct IntegrationIcon: View {
    let entry: ServiceCatalogEntry

    @StateObject private var logoLoader = IntegrationLogoLoader()

    var body: some View {
        Group {
            if entry.toolkitSlug == "figma" {
                FigmaLogoMark()
            } else if let resolvedAppIcon = resolvedAppIcon {
                NotchAppIconTile(appIcon: resolvedAppIcon, tileSize: 16)
            } else if let loadedLogo = logoLoader.image {
                Image(nsImage: loadedLogo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                monogram
            }
        }
        .task(id: entry.toolkitSlug) {
            guard entry.toolkitSlug != "figma", resolvedAppIcon == nil else { return }
            await logoLoader.load(Self.logoURL(for: entry))
        }
    }

    private var resolvedAppIcon: NSImage? {
        guard let bundleIdentifier = entry.appIconBundleIdentifierForTile else { return nil }
        return NotchAppIconResolver.icon(forBundleIdentifier: bundleIdentifier)
    }

    private var monogram: some View {
        Text(String(entry.displayName.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(DS.Colors.textSecondary)
    }

    static func logoURL(for entry: ServiceCatalogEntry) -> URL? {
        if let overrideURLString = brandLogoOverrideURLStrings[entry.toolkitSlug] {
            return URL(string: overrideURLString)
        }
        return faviconURL(forHost: entry.matchHosts.first)
    }

    static let brandLogoOverrideURLStrings: [String: String] = [
        "gmail":
            "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7e/Gmail_icon_%282020%29.svg/120px-Gmail_icon_%282020%29.svg.png",
        "googlecalendar":
            "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Google_Calendar_icon_%282020%29.svg/120px-Google_Calendar_icon_%282020%29.svg.png",
        "googledrive":
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/12/Google_Drive_icon_%282020%29.svg/120px-Google_Drive_icon_%282020%29.svg.png",
    ]

    static func faviconURL(forHost host: String?) -> URL? {
        guard let host, !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }
}

@MainActor
private final class IntegrationLogoLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private static var cache: [String: NSImage] = [:]

    func load(_ url: URL?) async {
        guard let url else { return }
        let cacheKey = url.absoluteString
        if let cachedImage = Self.cache[cacheKey] {
            image = cachedImage
            return
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("notch/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let loadedImage = NSImage(data: data) else { return }
            Self.cache[cacheKey] = loadedImage
            image = loadedImage
        } catch {
            // Leave nil — the chip shows its monogram fallback.
        }
    }
}

// MARK: - Add Integration Picker

private struct AddIntegrationPickerPopover: View {
    @ObservedObject var store: ActiveIntegrationsStore
    @State private var isPopoverPresented = false
    @State private var integrationSearchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredConnectableIntegrations: [ServiceCatalogEntry] {
        let trimmedSearchText = integrationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let connectable = store.connectableIntegrations
        guard !trimmedSearchText.isEmpty else { return connectable }
        return connectable.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(trimmedSearchText)
                || entry.toolkitSlug.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    var body: some View {
        Button(action: { isPopoverPresented.toggle() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DS.Colors.notchChipFill)
                )
        }
        .buttonStyle(.plain)
        .help("Add integration")
        .pointerCursor()
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            pickerContent
                .onAppear {
                    integrationSearchText = ""
                    isSearchFieldFocused = true
                }
        }
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                TextField("Search integrations…", text: $integrationSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFieldFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.Colors.notchSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Colors.notchBorder, lineWidth: 0.5)
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !store.composioAvailable && store.connectableIntegrations.isEmpty {
                        pickerEmptyRow("Composio not configured")
                    } else if store.connectableIntegrations.isEmpty {
                        pickerEmptyRow("Everything's connected")
                    } else if filteredConnectableIntegrations.isEmpty {
                        pickerEmptyRow("No matches")
                    } else {
                        ForEach(filteredConnectableIntegrations, id: \.toolkitSlug) { entry in
                            pickerRow(for: entry)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .frame(width: 240)
    }

    private func pickerEmptyRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(DS.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func pickerRow(for entry: ServiceCatalogEntry) -> some View {
        Button(action: {
            store.connect(entry)
            isPopoverPresented = false
        }) {
            HStack(spacing: 8) {
                IntegrationIcon(entry: entry)
                    .frame(width: 16, height: 16)

                Text(entry.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if store.isConnecting(entry) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor(isEnabled: !store.isConnecting(entry))
        .disabled(store.isConnecting(entry))
    }
}

// MARK: - App Icon Helpers

private enum NotchAppIconResolver {
    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

private struct NotchAppIconTile: View {
    let appIcon: NSImage
    var tileSize: CGFloat = 16

    var body: some View {
        Image(nsImage: appIcon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: tileSize, height: tileSize)
    }
}

// MARK: - Figma Logo Mark

struct FigmaLogoMark: View {
    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 2
            let cornerRadius = unit / 2

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(Color(hex: "#F24E1E"))
                    Circle()
                        .fill(Color(hex: "#FF7262"))
                }
                .frame(height: unit * 2 / 3)

                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(Color(hex: "#A259FF"))
                    Circle()
                        .fill(Color(hex: "#1ABCFE"))
                }
                .frame(height: unit * 2 / 3)

                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: cornerRadius,
                        topTrailingRadius: 0
                    )
                    .fill(Color(hex: "#0ACF83"))
                    Color.clear
                }
                .frame(height: unit * 2 / 3)
            }
        }
    }
}