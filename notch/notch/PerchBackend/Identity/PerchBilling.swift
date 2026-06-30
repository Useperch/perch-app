//
//  PerchBilling.swift
//  notch
//
//  Starts an upgrade. The app asks the Worker to create a Stripe Checkout session
//  for THIS install (the install id becomes the checkout's client_reference_id),
//  then opens the hosted checkout URL in the browser. After the user pays, the
//  Stripe webhook flips this install's account to pro; the app picks that up via
//  PerchInstallIdentity.refreshEntitlement().
//
//  Initiating upgrade from the app (not the website) is what lets the payment be
//  attributed back to this Mac — so "enter your email at checkout" auto-applies
//  here, with no password and no verification email.
//

import AppKit
import Foundation

enum PerchBilling {
    private static let workerBaseURL = AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
        ?? "https://your-worker-name.your-subdomain.workers.dev"

    /// Creates a checkout session and opens it in the browser. Returns false if the
    /// session couldn't be created (e.g. billing not yet configured on the Worker).
    @MainActor
    static func startUpgradeCheckout() async -> Bool {
        guard let url = URL(string: "\(workerBaseURL)/billing/checkout") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        if let installToken = PerchInstallIdentity.currentInstallToken() {
            request.setValue(installToken, forHTTPHeaderField: "X-Perch-Install-Token")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let checkoutURLString = json["url"] as? String,
                  let checkoutURL = URL(string: checkoutURLString) else {
                return false
            }
            NSWorkspace.shared.open(checkoutURL)
            // After checkout the webhook updates the account asynchronously, so
            // poll the entitlement a few times to reflect the upgrade without a
            // restart. Cheap GETs; stops early once pro is seen.
            scheduleEntitlementRefresh()
            return true
        } catch {
            perchDebugLog("billing: checkout error \(error.localizedDescription)")
            return false
        }
    }

    /// Polls the entitlement for a short window after checkout so the app reflects
    /// the upgrade as soon as the webhook lands.
    @MainActor
    private static func scheduleEntitlementRefresh() {
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 6_000_000_000) // 6s
                await PerchInstallIdentity.shared.refreshEntitlement()
                if PerchInstallIdentity.shared.entitlement.isPro { break }
            }
        }
    }
}
