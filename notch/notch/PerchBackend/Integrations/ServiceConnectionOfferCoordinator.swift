//
//  ServiceConnectionOfferCoordinator.swift
//  Perch
//
//  The policy brain behind the proactive "Connect [Service] to Perch?" notch
//  offer. The ServiceContextMonitor feeds it the catalog entry matching the
//  user's current window every tick; this coordinator decides whether that turns
//  into an offer, and owns the connect lifecycle once the user says yes.
//
//  It is the single owner of all "should we nag?" rules:
//   • dwell debounce — the user must settle on a service for a beat (kills offers
//     during rapid tab-flipping),
//   • already connected / enabled — never offer a service that's already wired up,
//   • snoozed — respect a recent "Not now" for its cooldown,
//   • session don't-nag — at most one offer per service per app run,
//   • one-at-a-time — never stack on another notch surface or a live offer,
//   • availability — don't offer a Composio connect that can't run (disabled / no key).
//
//  CompanionManager holds one of these; the notch offer surface observes
//  `currentOffer` (to show/hide) and `connectState` (to morph through
//  Connecting… → Connected in place). Deliberately AppKit-free; the actual
//  spawn / permission side effects live behind the injected `ServiceConnecting`.
//

import Combine
import Foundation

/// The display content of one connect offer, decoupled from the catalog entry so
/// the surface previews with canned copy.
struct ServiceConnectionOffer: Equatable {
    let displayName: String
    let toolkitSlug: String
    let kind: ServiceKind
    let capabilityHint: String?
    let appIconBundleIdentifierForTile: String?

    init(from entry: ServiceCatalogEntry) {
        self.displayName = entry.displayName
        self.toolkitSlug = entry.toolkitSlug
        self.kind = entry.kind
        self.capabilityHint = entry.capabilityHint
        self.appIconBundleIdentifierForTile = entry.appIconBundleIdentifierForTile
    }

    init(
        displayName: String,
        toolkitSlug: String,
        kind: ServiceKind,
        capabilityHint: String?,
        appIconBundleIdentifierForTile: String?
    ) {
        self.displayName = displayName
        self.toolkitSlug = toolkitSlug
        self.kind = kind
        self.capabilityHint = capabilityHint
        self.appIconBundleIdentifierForTile = appIconBundleIdentifierForTile
    }
}

/// The connect lifecycle after the user accepts an offer. Drives the surface's
/// in-place morph; the offer itself stays shown until the lifecycle clears.
enum ServiceConnectState: Equatable {
    case idle
    case connecting
    case connected
    case failed
}

/// Runs the actual connect side effect (Composio OAuth spawn / native enable +
/// permission nudge) and reports the outcome. Abstracted so the coordinator is
/// testable without spawning processes.
@MainActor
protocol ServiceConnecting: AnyObject {
    /// Begin connecting `offer`; call `onOutcome(true)` on success, `false` on
    /// failure/timeout. Always called on the main actor.
    func connect(_ offer: ServiceConnectionOffer, onOutcome: @escaping (Bool) -> Void)
}

@MainActor
final class ServiceConnectionOfferCoordinator: ObservableObject {

    /// The offer currently shown (awaiting an answer, or mid-connect). The notch
    /// surface renders this; clearing it hides the surface.
    @Published private(set) var currentOffer: ServiceConnectionOffer?

    /// The connect lifecycle for `currentOffer`. The surface morphs on this.
    @Published private(set) var connectState: ServiceConnectState = .idle

    /// How many consecutive ticks on the same service before it's offered —
    /// the dwell debounce that kills offers during rapid tab-flipping.
    static let requiredDwellTicks = 2

    /// How long the "Connected ✓" / "Couldn't connect" confirmation lingers
    /// before the surface auto-dismisses.
    private static let connectedLinger: TimeInterval = 2.0
    private static let failedLinger: TimeInterval = 3.0

    private let manifestReader: ComposioManifestReader
    private let snoozedStore: SnoozedServicesStore
    private let enabledStore: EnabledIntegrationsStore
    private let connector: ServiceConnecting

    /// Set by the panel manager: true while a higher-priority notch surface is
    /// open, so a low-urgency connect offer never stomps it.
    var isHigherPrioritySurfaceVisible: () -> Bool = { false }

    // Dwell-debounce state.
    private var pendingCandidateSlug: String?
    private var consecutiveTickCount = 0

    /// Slugs offered this app run — at most one offer per service per session,
    /// regardless of revisits (a deferred offer doesn't re-fire either).
    private var slugsOfferedThisSession: Set<String> = []

    /// Set while the CURRENT offer is an agent-driven blocking request (a running
    /// task needs the toolkit) rather than a proactive nag. Called with `true` once
    /// connected, `false` on connect failure or dismiss — so the agent can proceed
    /// or fall back. `nil` for ordinary proactive offers.
    private var agentRequestResolution: ((Bool) -> Void)?

    /// True while the current offer is an agent-driven blocking request (a running
    /// task needs the toolkit), not a proactive nag. The panel manager reads this to
    /// PIN the popup open — an agent request must stay until the user presses a
    /// button (Connect / Not now), never dismissing on an incidental click-outside.
    var currentOfferIsAgentRequest: Bool { agentRequestResolution != nil }

    init(
        manifestReader: ComposioManifestReader,
        snoozedStore: SnoozedServicesStore,
        enabledStore: EnabledIntegrationsStore,
        connector: ServiceConnecting
    ) {
        self.manifestReader = manifestReader
        self.snoozedStore = snoozedStore
        self.enabledStore = enabledStore
        self.connector = connector
    }

    // MARK: - Context ticks (from the monitor)

    /// Called every monitor tick with the service the current window matches
    /// (or nil). Advances the dwell counter and emits an offer once the user has
    /// settled on an offerable service.
    func handleContextTick(matchedService: ServiceCatalogEntry?) {
        guard let matchedService else {
            // No known service in view — reset the dwell counter. A live offer
            // is left alone (it stays until answered, like the workflow offer).
            pendingCandidateSlug = nil
            consecutiveTickCount = 0
            return
        }

        if matchedService.toolkitSlug == pendingCandidateSlug {
            consecutiveTickCount += 1
        } else {
            pendingCandidateSlug = matchedService.toolkitSlug
            consecutiveTickCount = 1
        }

        if consecutiveTickCount >= Self.requiredDwellTicks {
            emitOfferIfAllowed(for: matchedService)
        }
    }

    /// All the don't-nag gates, in cheap-first order. Emits the offer only when
    /// every gate passes.
    private func emitOfferIfAllowed(for entry: ServiceCatalogEntry) {
        let slug = entry.toolkitSlug
        // Never stack on a live offer or an in-flight connect.
        guard currentOffer == nil, connectState == .idle else { return }
        // At most once per service per session.
        guard !slugsOfferedThisSession.contains(slug) else {
            IntegrationsDebugLog.log("gate \(slug): already offered this session — skip")
            return
        }
        // Respect a recent "Not now".
        guard !snoozedStore.isSnoozed(slug) else {
            IntegrationsDebugLog.log("gate \(slug): snoozed — skip")
            return
        }

        switch entry.kind {
        case .composio:
            // Don't offer a connect that can't run, or one already connected.
            let manifestState = manifestReader.currentState()
            guard manifestState.composioAvailable else {
                IntegrationsDebugLog.log(
                    "gate \(slug): Composio unavailable (present=\(manifestState.manifestPresent) "
                        + "enabled=\(manifestState.composioEnabled)) — skip")
                return
            }
            guard !manifestState.connectedToolkitSlugs.contains(slug.lowercased()) else {
                IntegrationsDebugLog.log("gate \(slug): already connected — skip")
                return
            }
        case .native:
            guard !enabledStore.isEnabled(slug) else {
                IntegrationsDebugLog.log("gate \(slug): already enabled — skip")
                return
            }
        }

        // Don't stomp a higher-priority surface; stay pending and retry next tick.
        guard !isHigherPrioritySurfaceVisible() else {
            IntegrationsDebugLog.log("gate \(slug): higher-priority surface up — defer")
            return
        }

        IntegrationsDebugLog.log("OFFER FIRED — \(slug) (\(entry.displayName))")
        slugsOfferedThisSession.insert(slug)
        currentOffer = ServiceConnectionOffer(from: entry)
        connectState = .idle
    }

    // MARK: - Agent-driven blocking request

    /// Show a BLOCKING connect prompt requested by a running agent: the task needs
    /// `entry`'s toolkit connected to proceed. Unlike a proactive offer this bypasses
    /// the don't-nag gates (dwell / snooze / session) — the agent is acting on the
    /// user's explicit task. Calls `onResolved(true)` once connected, `false` if the
    /// connect fails or the user dismisses (the caller then falls back to the web
    /// lane). Reuses the same surface + connect machinery.
    func presentAgentConnectionRequest(
        for entry: ServiceCatalogEntry,
        onResolved: @escaping (Bool) -> Void
    ) {
        // Already connected (e.g. a sibling request just linked it) — resolve now.
        if entry.kind == .composio,
           manifestReader.currentState().connectedToolkitSlugs
               .contains(entry.toolkitSlug.lowercased()) {
            onResolved(true)
            return
        }
        // Don't stack on a non-idle connect or another agent request — resolve false so
        // the caller never hangs (the task falls back to the web lane). Requiring .idle
        // (not just "not .connecting") also covers the .connected/.failed linger window,
        // so an agent request can't overwrite a still-visible confirmation offer
        // mid-animation; once the linger clears to .idle the next request proceeds.
        guard connectState == .idle, agentRequestResolution == nil else {
            onResolved(false)
            return
        }
        agentRequestResolution = onResolved
        // Task-oriented copy: this is "finish what you asked", not a generic nag.
        currentOffer = ServiceConnectionOffer(
            displayName: entry.displayName,
            toolkitSlug: entry.toolkitSlug,
            kind: entry.kind,
            capabilityHint: "so Perch can finish your task",
            appIconBundleIdentifierForTile: entry.appIconBundleIdentifierForTile
        )
        connectState = .idle
    }

    /// Fires (and clears) the agent-request continuation, if the current offer is
    /// agent-driven. No-op for proactive offers.
    private func resolveAgentRequestIfNeeded(_ didSucceed: Bool) {
        guard let resolution = agentRequestResolution else { return }
        agentRequestResolution = nil
        resolution(didSucceed)
    }

    // MARK: - User responses to the offer

    /// "Yes" — begin connecting; the surface stays up and morphs to Connecting….
    func acceptCurrentOffer() {
        guard let offer = currentOffer, connectState == .idle else { return }
        connectState = .connecting
        connector.connect(offer) { [weak self] didSucceed in
            self?.handleConnectOutcome(for: offer, didSucceed: didSucceed)
        }
    }

    /// "Not now" — snooze this service for its cooldown, then hide. For an
    /// agent-driven request there is no snooze: the user declined, so resolve the
    /// gate `false` and let the task fall back to the web lane.
    func dismissCurrentOffer() {
        guard let offer = currentOffer, connectState == .idle else { return }
        if agentRequestResolution != nil {
            currentOffer = nil
            resolveAgentRequestIfNeeded(false)
            return
        }
        snoozedStore.recordSnoozed(offer.toolkitSlug)
        currentOffer = nil
    }

    /// Incidental hide (click-outside) — no snooze, but the session don't-nag
    /// already prevents a re-offer this run. Never fires mid-connect.
    ///
    /// An agent-driven request is a blocking gate the task depends on, so it must
    /// PERSIST until the user presses a button (Connect / Not now) — incidental
    /// click-outside hides are ignored for it. Only proactive nags defer here.
    func deferCurrentOffer() {
        guard connectState == .idle else { return }
        if agentRequestResolution != nil { return }
        currentOffer = nil
    }

    // MARK: - Connect outcome

    private func handleConnectOutcome(for offer: ServiceConnectionOffer, didSucceed: Bool) {
        // The offer may have been cleared out from under us — ignore a late callback.
        guard currentOffer == offer, connectState == .connecting else { return }

        if didSucceed {
            // Native enablement is recorded via the shared rule (Composio connectivity
            // is reflected in the manifest the reader re-reads on the next gate).
            enabledStore.recordEnabledIfNative(kind: offer.kind, toolkitSlug: offer.toolkitSlug)
            connectState = .connected
            clearAfterLinger(Self.connectedLinger)
        } else {
            connectState = .failed
            clearAfterLinger(Self.failedLinger)
        }
        // Resume the agent immediately on outcome (the popup still lingers visually).
        resolveAgentRequestIfNeeded(didSucceed)
    }

    /// Hide the surface after the confirmation has lingered, unless a fresh offer
    /// has since replaced this one.
    private func clearAfterLinger(_ seconds: TimeInterval) {
        let lingeringOffer = currentOffer
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.currentOffer == lingeringOffer else { return }
            self.currentOffer = nil
            self.connectState = .idle
        }
    }
}
