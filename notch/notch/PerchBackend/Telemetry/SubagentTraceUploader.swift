//
//  SubagentTraceUploader.swift
//  notch
//
//  Watches the Python sidecar's on-disk traces and ships completed autonomous
//  runs to the Worker gateway. The sidecar itself is unchanged — keeping all
//  network egress (and the install token) in Swift. A Swift port of the polling
//  semantics in scripts/watch-traces.py.
//
//  Per completed run it uploads:
//    • the RunTrace JSON  → /v1/traces/subagent  (with the parsed audit log attached)
//    • each step's JPEG   → /v1/traces/frame
//  then writes a per-run marker under `support/trace-uploads/` so it is never
//  re-uploaded. A run is "complete enough" to ship only when BOTH `finishedAt`
//  and `terminalKind` are set (stamped by the sidecar's RunTrace.finish).
//

import Foundation

final class SubagentTraceUploader {
    static let shared = SubagentTraceUploader()

    private let workerBaseURL = AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
        ?? "https://your-worker-name.your-subdomain.workers.dev"

    private let tracesDirectory = PerchSupportPaths.directory("subagent-traces")
    private let auditLogsDirectory = PerchSupportPaths.directory("subagent-logs")
    private let uploadMarkersDirectory = PerchSupportPaths.directory("trace-uploads")

    private let pollInterval: Duration = .seconds(2)

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    private let startLock = NSLock()
    private var hasStarted = false

    private init() {}

    /// Begins the polling loop. Idempotent — safe to call once at launch.
    func start() {
        startLock.lock()
        let shouldStart = !hasStarted
        hasStarted = true
        startLock.unlock()
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                if let self, TelemetryConsent.isUploadAllowed() {
                    await self.scanOnce()
                }
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
            }
        }
    }

    // MARK: - Scan

    private func scanOnce() async {
        let fileManager = FileManager.default
        guard let traceFiles = try? fileManager.contentsOfDirectory(
            at: tracesDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for traceFileURL in traceFiles where traceFileURL.pathExtension == "json" {
            let runId = traceFileURL.deletingPathExtension().lastPathComponent
            if hasUploadMarker(for: runId) { continue }

            // Parse best-effort; an unreadable file is mid-rewrite — try next poll.
            guard let data = try? Data(contentsOf: traceFileURL),
                  let traceDocument = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Completion gate: both stamped only when the run actually lands.
            guard traceDocument["finishedAt"] is String,
                  traceDocument["terminalKind"] is String else {
                continue
            }

            if await uploadRun(runId: runId, traceDocument: traceDocument) {
                writeUploadMarker(for: runId)
            }
        }
    }

    // MARK: - Upload one run

    /// Uploads the run trace, then every frame. Returns true only when ALL parts
    /// succeed, so a partial failure leaves no marker and is retried next poll.
    private func uploadRun(runId: String, traceDocument: [String: Any]) async -> Bool {
        var payload = traceDocument
        payload["audit"] = loadAuditLog(for: runId)

        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              await postSubagentTrace(body) else {
            return false
        }

        for frame in frameFiles(for: runId) {
            guard let frameData = try? Data(contentsOf: frame.url) else { continue }
            if !(await postFrame(runId: runId, stepIndex: frame.stepIndex, jpeg: frameData)) {
                return false
            }
        }
        return true
    }

    private func postSubagentTrace(_ body: Data) async -> Bool {
        guard let url = URL(string: "\(workerBaseURL)/v1/traces/subagent") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyInstallToken(to: &request)
        request.httpBody = body
        return await isSuccess(request)
    }

    private func postFrame(runId: String, stepIndex: Int, jpeg: Data) async -> Bool {
        // Build via URLComponents so runId is always percent-encoded — robust even
        // if a future sidecar id contains URL-significant characters.
        guard var components = URLComponents(string: "\(workerBaseURL)/v1/traces/frame") else {
            return false
        }
        components.queryItems = [
            URLQueryItem(name: "runId", value: runId),
            URLQueryItem(name: "step", value: String(stepIndex)),
        ]
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        applyInstallToken(to: &request)
        request.httpBody = jpeg
        return await isSuccess(request)
    }

    private func applyInstallToken(to request: inout URLRequest) {
        if let installToken = PerchInstallIdentity.currentInstallToken() {
            request.setValue(installToken, forHTTPHeaderField: "X-Perch-Install-Token")
        }
    }

    private func isSuccess(_ request: URLRequest) async -> Bool {
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - On-disk helpers

    /// Parses `subagent-logs/<runId>.jsonl` into an array of objects. Returns an
    /// empty array when there is no audit log (some runs have none).
    private func loadAuditLog(for runId: String) -> [[String: Any]] {
        let auditURL = auditLogsDirectory.appendingPathComponent("\(runId).jsonl")
        guard let text = try? String(contentsOf: auditURL, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let lineData = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    /// The step JPEGs for a run, paired with their step index, sorted ascending.
    private func frameFiles(for runId: String) -> [(url: URL, stepIndex: Int)] {
        let framesDirectory = tracesDirectory.appendingPathComponent("\(runId).frames", isDirectory: true)
        guard let frameURLs = try? FileManager.default.contentsOfDirectory(
            at: framesDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return frameURLs
            .filter { $0.pathExtension == "jpg" }
            .compactMap { url in
                // Filenames look like "step_3.jpg".
                let stem = url.deletingPathExtension().lastPathComponent
                guard let underscoreIndex = stem.lastIndex(of: "_"),
                      let stepIndex = Int(stem[stem.index(after: underscoreIndex)...]) else {
                    return nil
                }
                return (url: url, stepIndex: stepIndex)
            }
            .sorted { $0.stepIndex < $1.stepIndex }
    }

    private func hasUploadMarker(for runId: String) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(for: runId).path)
    }

    private func writeUploadMarker(for runId: String) {
        let marker = ["uploadedAt": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: marker) else { return }
        try? data.write(to: markerURL(for: runId), options: .atomic)
    }

    private func markerURL(for runId: String) -> URL {
        uploadMarkersDirectory.appendingPathComponent("\(runId).json")
    }
}
