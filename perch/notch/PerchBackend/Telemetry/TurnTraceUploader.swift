//
//  TurnTraceUploader.swift
//  notch
//
//  Ships finalized turn traces (StructuredTurnTrace) to the Worker gateway's
//  /v1/traces/turn route. Best-effort and never throws — telemetry must never
//  affect app behavior. Uploads that fail (offline, server down) are persisted
//  to `support/turn-trace-queue/` and retried on the next enqueue and at launch,
//  so a turn taken offline still lands once connectivity returns.
//

import Foundation

final class TurnTraceUploader {
    static let shared = TurnTraceUploader()

    private let workerBaseURL = AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
        ?? "https://your-worker-name.your-subdomain.workers.dev"

    private let queueDirectory = PerchSupportPaths.directory("turn-trace-queue")

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    private init() {}

    /// Finalize-time entry point. Serializes the trace, then uploads it (and
    /// drains any previously-queued traces). Consent is checked here so the
    /// decision is made once, off the caller's path.
    func enqueue(_ trace: StructuredTurnTrace) {
        guard TelemetryConsent.isUploadAllowed() else { return }
        let payload = Self.payload(from: trace)
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.drainQueue()
            let uploaded = await self.upload(body)
            if !uploaded {
                self.persistToQueue(body, clientRunId: trace.clientRunId)
            }
        }
    }

    /// Retries any queued traces. Called at launch (see start()) and before each
    /// new upload so a reconnect flushes the backlog.
    func start() {
        guard TelemetryConsent.isUploadAllowed() else { return }
        Task.detached(priority: .utility) { [weak self] in
            await self?.drainQueue()
        }
    }

    // MARK: - Upload

    /// POSTs one serialized turn payload. Returns true on a 2xx. A non-2xx that is
    /// NOT retryable (4xx other than 429) is treated as "done" so we don't queue a
    /// permanently-rejected payload forever.
    private func upload(_ body: Data) async -> Bool {
        guard let url = URL(string: "\(workerBaseURL)/v1/traces/turn") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let installToken = PerchInstallIdentity.currentInstallToken() {
            request.setValue(installToken, forHTTPHeaderField: "X-Perch-Install-Token")
        }
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            if (200...299).contains(httpResponse.statusCode) { return true }
            // Drop permanently-rejected payloads (bad request / unauthorized in
            // hard mode); keep retrying only transient failures (429 / 5xx).
            let isRetryable = httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode)
            return !isRetryable
        } catch {
            return false
        }
    }

    // MARK: - Offline queue

    private func persistToQueue(_ body: Data, clientRunId: String) {
        let fileName = "\(clientRunId)-\(UUID().uuidString.prefix(8)).json"
        try? body.write(to: queueDirectory.appendingPathComponent(fileName), options: .atomic)
    }

    private func drainQueue() async {
        let fileManager = FileManager.default
        guard let queuedFiles = try? fileManager.contentsOfDirectory(
            at: queueDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for fileURL in queuedFiles where fileURL.pathExtension == "json" {
            guard let body = try? Data(contentsOf: fileURL) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            if await upload(body) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Serialization

    private static let isoFormatter = ISO8601DateFormatter()

    private static func payload(from trace: StructuredTurnTrace) -> [String: Any] {
        var payload: [String: Any] = [
            "clientRunId": trace.clientRunId,
            "inputKind": trace.inputKind,
            "input": trace.input,
            "startedAt": isoFormatter.string(from: trace.startedAt),
            "endedAt": isoFormatter.string(from: trace.endedAt),
            "events": trace.events.map { event in
                [
                    "ts": event.timestampMillis,
                    "category": event.category,
                    "title": event.title,
                    "body": event.body,
                ]
            },
        ]
        if let systemPrompt = trace.systemPrompt { payload["systemPrompt"] = systemPrompt }
        if let conversationHistory = trace.conversationHistory { payload["conversationHistory"] = conversationHistory }
        if let userPrompt = trace.userPrompt { payload["userPrompt"] = userPrompt }
        if let modelResponse = trace.modelResponse { payload["modelResponse"] = modelResponse }
        if let intentGate = trace.intentGate { payload["intentGate"] = intentGate }
        if let spokenText = trace.spokenText { payload["spokenText"] = spokenText }
        if let error = trace.error { payload["error"] = error }
        return payload
    }
}
