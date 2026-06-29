//
//  ServiceContextMonitor.swift
//  leanring-buddy
//
//  Watches what the user is currently looking at and tells the
//  ServiceConnectionOfferCoordinator which known service (if any) it matches.
//  This is the trigger behind the proactive "Connect [Service] to Perch?" offer.
//
//  It is deliberately "dumb" — like LiveEventSource, it does no offer policy
//  (that's the coordinator's job): it only polls the frontmost window's
//  identity (via AccessibilityTreeSnapshotter.focusedWindowContext), matches it
//  against the catalog, and hands the result over each tick.
//
//  Polling cadence is 0.75s on the main run loop (between the workflow clipboard
//  poller's 0.4s and a 1s ceiling — responsive on a tab switch without burning
//  CPU). The expensive catalog match runs ONLY when the context key actually
//  changes (a real app/tab switch); otherwise the cached match is re-fed so the
//  coordinator's dwell counter still advances. The context provider is injectable
//  so tests drive it without the Accessibility grant.
//

import Foundation

@MainActor
final class ServiceContextMonitor {

    private static let pollInterval: TimeInterval = 0.75

    private let catalog: ServiceCatalog
    private let currentContextProvider: () -> FocusedWindowContext
    private let onMatchedService: (ServiceCatalogEntry?) -> Void

    private var pollTimer: Timer?

    /// The last context key seen — used to skip the catalog match when the user
    /// hasn't actually switched page/app since the previous tick.
    private var lastContextKey: String?
    /// The match for `lastContextKey`, re-fed each tick so dwell still advances.
    private var cachedMatchedService: ServiceCatalogEntry?

    init(
        catalog: ServiceCatalog,
        currentContextProvider: @escaping () -> FocusedWindowContext
            = AccessibilityTreeSnapshotter.focusedWindowContext,
        onMatchedService: @escaping (ServiceCatalogEntry?) -> Void
    ) {
        self.catalog = catalog
        self.currentContextProvider = currentContextProvider
        self.onMatchedService = onMatchedService
    }

    func start() {
        guard pollTimer == nil else { return }
        IntegrationsDebugLog.log("monitor started (poll \(Self.pollInterval)s) — \(catalog.entries.count) catalog entries")
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop; hop to the main actor
            // explicitly so the isolated tick is always correct.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// One poll: resolve the current window, match it (only when the context
    /// actually changed), and feed the coordinator.
    func tick() {
        let context = currentContextProvider()
        let contextKey = ServiceCatalog.contextKey(for: context)

        if contextKey != lastContextKey {
            lastContextKey = contextKey
            cachedMatchedService = catalog.match(context)
            // One line per real context switch so "why no pop-up?" is diagnosable:
            // what app/URL was frontmost and whether it matched a catalog service.
            IntegrationsDebugLog.log(
                "context app=\(context.applicationBundleIdentifier ?? "nil") "
                    + "url=\(context.documentPathOrURL ?? "nil") "
                    + "→ matched=\(cachedMatchedService?.toolkitSlug ?? "none")"
            )
        }

        onMatchedService(cachedMatchedService)
    }
}
