import AppKit
import SwiftUI

/// A floating, non-activating panel that shows ONE browser subagent run's activity
/// natively inside Perch.
///
/// There is one of these per concurrent run, each parked over its own agent-swarm
/// triangle slot at the top-right of the notch screen. Collapsed, it is invisible —
/// the spinning triangle in the overlay is the at-a-glance "working" signal and this
/// panel is the hover/click hit-target behind it. Hovering expands the panel into a
/// live browser preview (streamed JPEG frames) with a status badge, a kill switch,
/// and in-place banners for the login gate and irreversible-action confirmations.
///
/// Modeled on `MenuBarPanelManager`'s NSPanel usage: borderless, `.floating` level,
/// joins all Spaces, never steals focus. Unlike the click-through cursor overlay,
/// this panel hit-tests its controls so the user can stop, confirm, or finish
/// logging in for THIS run.
@MainActor
final class BrowserSubagentPreviewPanel {

    private var panel: NSPanel?
    /// The run this panel previews. Held strongly so the final frame stays visible
    /// for the grace period even after the manager prunes the run from its registry.
    private let run: BrowserSubagentRun
    /// This run's vertical stack slot (0 = top), fixed for the run's life — used to
    /// park the panel over its triangle. A run keeps its slot until it finishes.
    private let slotIndex: Int
    private weak var browserSubagentManager: BrowserSubagentManager?

    private static let collapsedPanelSize = NSSize(width: 72, height: 72)
    private static let expandedPanelSize = NSSize(width: 660, height: 470)
    /// Inset from the screen's right edge — nudged in from the extreme corner.
    private static let screenEdgeInset: CGFloat = 30
    /// Inset below the menu bar so the panel doesn't hug the very top.
    private static let topEdgeInset: CGFloat = 24

    init(
        run: BrowserSubagentRun,
        slotIndex: Int,
        browserSubagentManager: BrowserSubagentManager
    ) {
        self.run = run
        self.slotIndex = slotIndex
        self.browserSubagentManager = browserSubagentManager
    }

    /// Shows the panel (creating it lazily) over this run's triangle slot. Idempotent
    /// — repeated calls while visible do NOT reset its frame, so state rebroadcasts
    /// never fight an in-progress hover expansion.
    func show() {
        if let panel, panel.isVisible { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        applyPanelFrame(isExpanded: false)
        panel.orderFrontRegardless()
    }

    /// Hides the panel without destroying it.
    func hide() {
        panel?.orderOut(nil)
    }

    /// Resizes the panel between the collapsed badge and the expanded preview.
    fileprivate func setExpanded(_ isExpanded: Bool) {
        applyPanelFrame(isExpanded: isExpanded)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: BrowserSubagentPreviewView(
                run: run,
                browserSubagentManager: browserSubagentManager,
                onExpandedChange: { [weak self] isExpanded in
                    self?.setExpanded(isExpanded)
                }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: Self.collapsedPanelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        return panel
    }

    /// Anchors the panel to the TOP-right corner of the notch screen, over THIS run's
    /// triangle slot (shifted down one slot-spacing per stacked agent). The top-right
    /// corner stays fixed across collapse/expand, so expansion grows down-and-left and
    /// the hovered slot stays inside the panel (the hover is never lost).
    private func applyPanelFrame(isExpanded: Bool) {
        guard let panel else { return }
        guard let screen = notchScreen() else { return }
        let panelSize = isExpanded ? Self.expandedPanelSize : Self.collapsedPanelSize
        // AppKit screen coordinates are bottom-up, so a lower stack slot moves the
        // panel DOWN by subtracting from y.
        let slotVerticalOffset = CGFloat(slotIndex) * AgentSwarmLayout.slotVerticalSpacing
        let origin = NSPoint(
            x: screen.frame.maxX - panelSize.width - Self.screenEdgeInset,
            y: screen.visibleFrame.maxY - Self.topEdgeInset - panelSize.height - slotVerticalOffset
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    /// The screen with the hardware notch (where the swarm renders), falling back to
    /// the main screen on non-notch displays.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
}

/// SwiftUI content for one run's preview panel. Collapsed: a transparent hit-target
/// over the run's triangle slot. Expanded (on hover, or forced while user input is
/// pending): the live browser preview with status badge, kill switch, and
/// login/confirmation banners — all scoped to this run.
private struct BrowserSubagentPreviewView: View {
    @ObservedObject var run: BrowserSubagentRun
    weak var browserSubagentManager: BrowserSubagentManager?
    /// Tells the owning NSPanel to resize between collapsed and expanded.
    let onExpandedChange: (Bool) -> Void

    @State private var isExpanded = false
    /// Pending delayed-collapse, cancelled if the mouse re-enters.
    @State private var scheduledCollapseTask: Task<Void, Never>?

    /// While this run is waiting on the user (login gate or confirmation), the panel
    /// stays expanded regardless of hover so the controls cannot disappear.
    private var userInputIsPending: Bool {
        run.pendingConfirmation != nil || run.pendingLoginGateMessage != nil
    }

    /// True only when a headless Chrome browser is actually running this task —
    /// detected by the arrival of at least one streamed frame. A desktop/system run
    /// never streams frames, so hovering must NOT expand into an empty preview.
    private var hasBrowserPreviewToShow: Bool {
        run.latestFrame != nil
    }

    var body: some View {
        ZStack {
            if isExpanded {
                expandedPreviewCard
            } else {
                // Collapsed: nothing painted. The "agent working" visual is the
                // spinning triangle in the swarm; this transparent panel sits over
                // that slot purely as the hover/click hit-target.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isMouseInside in
            handleHoverChange(isMouseInside: isMouseInside)
        }
        .onChange(of: userInputIsPending) { _, inputIsNowPending in
            if inputIsNowPending {
                applyExpansion(true)
            }
        }
        .onChange(of: run.subagentState) { _, newState in
            // A fresh run always starts collapsed.
            if newState == .spawning {
                scheduledCollapseTask?.cancel()
                applyExpansion(false)
            }
        }
        // The cursor overlay polls the mouse and flips this when the user hovers this
        // run's triangle — the reliable hover signal for a non-key floating panel.
        .onChange(of: run.isAgentIndicatorHovered) { _, isHoveringTriangle in
            handleHoverChange(isMouseInside: isHoveringTriangle)
        }
    }

    // MARK: - Expansion plumbing

    private func handleHoverChange(isMouseInside: Bool) {
        scheduledCollapseTask?.cancel()
        scheduledCollapseTask = nil

        if isMouseInside {
            // Only expand when there's a headless browser frame to show; desktop runs
            // have none, so an expansion would reveal an empty card.
            guard hasBrowserPreviewToShow else { return }
            applyExpansion(true)
            return
        }

        scheduledCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            guard !userInputIsPending else { return }
            applyExpansion(false)
        }
    }

    private func applyExpansion(_ shouldExpand: Bool) {
        guard shouldExpand != isExpanded else { return }
        if shouldExpand {
            onExpandedChange(true)
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = true
            }
        } else {
            isExpanded = false
            onExpandedChange(false)
        }
        Task { [browserSubagentManager, runIdentifier = run.id] in
            await browserSubagentManager?.setPreviewQuality(
                subagentId: runIdentifier, targetFps: shouldExpand ? 8 : 2
            )
        }
    }

    // MARK: - Expanded card

    private var expandedPreviewCard: some View {
        VStack(spacing: 0) {
            previewArea
            if let loginGateMessage = run.pendingLoginGateMessage {
                loginGateBanner(loginGateMessage)
            }
            if let confirmation = run.pendingConfirmation {
                confirmationBanner(confirmation)
            }
        }
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var previewArea: some View {
        ZStack {
            if let frame = run.latestFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(previewPlaceholderText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack {
                HStack {
                    statusBadge
                    Spacer()
                    killSwitchButton
                }
                .padding(8)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPlaceholderText: String {
        if run.pendingLoginGateMessage != nil {
            return "Sign in using the Chrome window that just opened"
        }
        return "Starting…"
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(DS.Colors.overlayCursorBlue)
                .frame(width: 7, height: 7)
            Text(run.subagentState.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
    }

    private var killSwitchButton: some View {
        Button {
            Task { [browserSubagentManager, runIdentifier = run.id] in
                await browserSubagentManager?.cancel(subagentId: runIdentifier)
            }
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(6)
                .background(Color.red.opacity(0.85))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Stop this agent")
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Banners

    private func loginGateBanner(_ loginGateMessage: String) -> some View {
        VStack(spacing: 8) {
            Text(loginGateMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            bannerActionButton(title: "Done logging in", tint: DS.Colors.overlayCursorBlue) {
                Task { [browserSubagentManager, runIdentifier = run.id] in
                    await browserSubagentManager?.completeLoginGate(subagentId: runIdentifier)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
    }

    private func confirmationBanner(_ confirmation: PendingBrowserSubagentConfirmation) -> some View {
        VStack(spacing: 8) {
            if let caption = confirmationTierCaption(confirmation.tier) {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(confirmationTierCaptionColor(confirmation.tier))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            Text(confirmation.description)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 8) {
                bannerActionButton(title: "Approve", tint: .blue) {
                    Task { [browserSubagentManager, runIdentifier = run.id] in
                        await browserSubagentManager?.respondToConfirmation(subagentId: runIdentifier, approved: true)
                    }
                }
                bannerActionButton(title: "Deny", tint: .gray) {
                    Task { [browserSubagentManager, runIdentifier = run.id] in
                        await browserSubagentManager?.respondToConfirmation(subagentId: runIdentifier, approved: false)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
    }

    /// The severity caption shown above a confirmation's description, by tier.
    private func confirmationTierCaption(_ tier: String?) -> String? {
        switch tier {
        case "destructive":
            return "This can't be undone — confirm exactly what:"
        case "external":
            return "Perch needs your OK to do this:"
        default:
            return nil
        }
    }

    /// The caption color by tier: destructive red, external amber, per DESIGN.md.
    private func confirmationTierCaptionColor(_ tier: String?) -> Color {
        switch tier {
        case "destructive":
            return DS.Colors.destructiveText
        case "external":
            return DS.Colors.warningText
        default:
            return .white.opacity(0.7)
        }
    }

    private func bannerActionButton(
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(tint.opacity(0.85))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
