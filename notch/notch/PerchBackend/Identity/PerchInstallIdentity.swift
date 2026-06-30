//
//  PerchInstallIdentity.swift
//  notch
//
//  Stable per-install identity for multi-user Perch. On first run this mints a
//  random UUID and persists it to `<repo>/support/install-identity.json` (durable
//  state belongs in support/, never UserDefaults). The install can optionally be
//  linked to an email captured at onboarding.
//
//  Identity is exchanged with the Cloudflare Worker via /register, which returns:
//    • installToken     — the opaque bearer the app sends on every Worker call
//                         (X-Perch-Install-Token). Stored only as a hash server-side,
//                         so each register mints a NEW token; the install id is stable.
//    • serverTracingEnabled — the owner's remote kill switch for trace collection.
//
//  Network code on any actor reads the current token through the thread-safe
//  `currentInstallToken()` accessor — the same nonisolated pattern that
//  `PerchCapabilityToggles.isEyesEnabledNow()` uses.
//

import Combine
import Foundation

@MainActor
final class PerchInstallIdentity: ObservableObject {
    static let shared = PerchInstallIdentity()

    /// The stable per-install UUID, minted once and persisted.
    @Published private(set) var installId: String
    /// The email linked at onboarding, if any.
    @Published private(set) var email: String?
    /// The owner's server-side kill switch from the last /register response.
    /// When false, trace collection is disabled for this install regardless of
    /// the local opt-in toggle. Mirrored to a cross-actor cache for the uploaders.
    @Published private(set) var serverTracingEnabled: Bool {
        didSet { Self.cacheServerTracingEnabled(serverTracingEnabled) }
    }
    /// Whether we currently hold an install token (have registered at least once).
    @Published private(set) var isRegistered: Bool

    /// The bearer token. Setting it mirrors the value into the cross-actor cache.
    private var installToken: String? {
        didSet { Self.cacheInstallToken(installToken) }
    }

    private init() {
        let persisted = Self.loadOrMintIdentity()
        installId = persisted.installId
        email = persisted.email
        serverTracingEnabled = persisted.tracingEnabled
        installToken = persisted.installToken
        isRegistered = persisted.installToken != nil
        Self.cacheInstallToken(persisted.installToken)
        Self.cacheServerTracingEnabled(persisted.tracingEnabled)
    }

    // MARK: - Cross-actor token accessor

    private static let tokenLock = NSLock()
    nonisolated(unsafe) private static var cachedInstallToken: String?

    /// The current install token, readable from any actor (network request
    /// builders run off the main actor). nil before the first successful register.
    nonisolated static func currentInstallToken() -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return cachedInstallToken
    }

    private static func cacheInstallToken(_ token: String?) {
        tokenLock.lock()
        cachedInstallToken = token
        tokenLock.unlock()
    }

    private static let serverTracingLock = NSLock()
    nonisolated(unsafe) private static var cachedServerTracingEnabled = true

    /// The owner's server-side tracing kill switch, readable from any actor (the
    /// uploaders run off the main actor). Defaults true until the first register.
    nonisolated static func isServerTracingEnabled() -> Bool {
        serverTracingLock.lock()
        defer { serverTracingLock.unlock() }
        return cachedServerTracingEnabled
    }

    private static func cacheServerTracingEnabled(_ enabled: Bool) {
        serverTracingLock.lock()
        cachedServerTracingEnabled = enabled
        serverTracingLock.unlock()
    }

    // MARK: - Registration

    /// Registers (or re-registers) this install with the Worker, refreshing the
    /// install token and the server tracing kill switch. Best-effort: a network
    /// failure leaves the prior token and state untouched. Pass `emailToLink` to
    /// associate the onboarding email with this install.
    func register(emailToLink: String? = nil) async {
        guard let registerURL = URL(string: "\(Self.workerBaseURL)/register") else { return }

        var requestBody: [String: Any] = [
            "installId": installId,
            "appVersion": Self.appVersion,
            "osVersion": Self.osVersion,
        ]
        if let emailToLink, !emailToLink.isEmpty {
            requestBody["email"] = emailToLink
        }

        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await Self.registrationSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let issuedToken = json["installToken"] as? String else {
                perchDebugLog("install-identity: register failed (no token in response)")
                return
            }

            installToken = issuedToken
            isRegistered = true
            if let tracingEnabled = json["tracingEnabled"] as? Bool {
                serverTracingEnabled = tracingEnabled
            }
            if let emailToLink, !emailToLink.isEmpty {
                email = emailToLink
            }
            persist()
            perchDebugLog("install-identity: registered install \(installId.prefix(8))")
        } catch {
            perchDebugLog("install-identity: register error \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private struct PersistedIdentity: Codable {
        let installId: String
        var installToken: String?
        var email: String?
        var tracingEnabled: Bool
    }

    private static let identityFileURL = PerchSupportPaths.file("install-identity.json")

    /// A long-lived URLSession for the registration handshake. Disk caches are
    /// disabled so no bearer token is cached on disk.
    private static let registrationSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    private static func loadOrMintIdentity() -> PersistedIdentity {
        if let data = try? Data(contentsOf: identityFileURL),
           let decoded = try? JSONDecoder().decode(PersistedIdentity.self, from: data) {
            return decoded
        }
        // First run: mint a fresh id. tracingEnabled defaults true (the server's
        // default); the actual value is confirmed on the first /register.
        let minted = PersistedIdentity(
            installId: UUID().uuidString.lowercased(),
            installToken: nil,
            email: nil,
            tracingEnabled: true
        )
        Self.write(minted)
        return minted
    }

    private func persist() {
        Self.write(PersistedIdentity(
            installId: installId,
            installToken: installToken,
            email: email,
            tracingEnabled: serverTracingEnabled
        ))
    }

    private static func write(_ identity: PersistedIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        try? data.write(to: identityFileURL, options: .atomic)
    }

    // MARK: - Environment

    private static let workerBaseURL = AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
        ?? "https://your-worker-name.your-subdomain.workers.dev"

    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
}
