//
//  WorkflowShareClient.swift
//  Perch
//
//  HTTP client for the Worker's workflow-share routes: uploads a playbook's
//  markdown and gets back a share link, and fetches a shared playbook by id
//  on the receiving device. Every request carries the `X-Perch-Client`
//  secret header — the Worker only serves playbook content to requests that
//  have it, so a browser opening the share link sees a stub landing page,
//  never the playbook.
//
//  The share backend can differ from the chat backend (chat stays on the
//  local proxy during development while shares point at the deployed Worker),
//  so the base URL resolves from its own `WorkflowShareBaseURL` key and only
//  falls back to `WorkerBaseURL`.
//

import Foundation

struct WorkflowShareClient {

    enum WorkflowShareClientError: LocalizedError {
        case backendUnreachable
        case unauthorized
        case playbookTooLarge
        case shareNotFound
        case malformedServerResponse

        var errorDescription: String? {
            switch self {
            case .backendUnreachable:
                return "Couldn't reach the Perch backend — is it running?"
            case .unauthorized:
                return "The Perch backend rejected this app's share credentials."
            case .playbookTooLarge:
                return "This workflow is too large to share."
            case .shareNotFound:
                return "That workflow link has expired or doesn't exist."
            case .malformedServerResponse:
                return "The Perch backend sent back something unexpected."
            }
        }
    }

    private struct UploadRequestBody: Encodable {
        let title: String
        let markdown: String
    }

    private struct UploadResponseBody: Decodable {
        let id: String
        let url: String
    }

    private struct FetchResponseBody: Decodable {
        let title: String
        let markdown: String
    }

    /// Where the share routes live. Environment override → dedicated plist
    /// key → the chat Worker's base URL (same resolution pattern as
    /// CompanionManager's `workerBaseURL`).
    static func resolveShareBaseURL() -> String {
        if let environmentOverride = ProcessInfo.processInfo
            .environment["PERCH_WORKFLOW_SHARE_BASE_URL"], !environmentOverride.isEmpty {
            return environmentOverride
        }
        if let configuredShareBaseURL = AppBundleConfiguration.stringValue(
            forKey: "WorkflowShareBaseURL"
        ) {
            return configuredShareBaseURL
        }
        return AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
            ?? "http://localhost:8787"
    }

    /// The shared secret proving a request comes from a Perch app. Trivially
    /// extractable from the bundle — acceptable for this demo; the real
    /// protections are the unguessable 128-bit share ids and the Worker-side
    /// 30-day expiry.
    static func resolveClientSecret() -> String {
        if let environmentOverride = ProcessInfo.processInfo
            .environment["PERCH_WORKFLOW_SHARE_CLIENT_SECRET"], !environmentOverride.isEmpty {
            return environmentOverride
        }
        return AppBundleConfiguration.stringValue(forKey: "WorkflowShareClientSecret")
            ?? "YOUR_WORKFLOW_SHARE_SECRET"
    }

    private let shareBaseURL: String
    private let clientSecret: String
    private let urlSession: URLSession

    init(
        shareBaseURL: String = WorkflowShareClient.resolveShareBaseURL(),
        clientSecret: String = WorkflowShareClient.resolveClientSecret()
    ) {
        self.shareBaseURL = shareBaseURL
        self.clientSecret = clientSecret

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        // Fail fast on an unreachable backend instead of silently waiting —
        // waitsForConnectivity turned connection-refused into a multi-minute
        // hang for the extractor (HANDOFF.md §0.1); never repeat that here.
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: sessionConfiguration)
    }

    /// Uploads a playbook and returns the share link to hand to someone else.
    func uploadPlaybook(markdown: String, title: String) async throws -> WorkflowShareLink {
        guard let uploadURL = URL(string: "\(shareBaseURL)/workflow-share") else {
            throw WorkflowShareClientError.backendUnreachable
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientSecret, forHTTPHeaderField: "X-Perch-Client")
        request.httpBody = try JSONEncoder().encode(
            UploadRequestBody(title: title, markdown: markdown)
        )

        let (responseData, response) = try await performRequest(request)
        try throwForErrorStatus(response)

        guard let uploadResponse = try? JSONDecoder().decode(
            UploadResponseBody.self, from: responseData
        ) else {
            throw WorkflowShareClientError.malformedServerResponse
        }
        return WorkflowShareLink(shareId: uploadResponse.id, urlString: uploadResponse.url)
    }

    /// Fetches a shared playbook by id on the receiving device.
    func fetchSharedPlaybook(shareId: String) async throws -> IncomingSharedWorkflow {
        guard let fetchURL = URL(string: "\(shareBaseURL)/workflow-share/\(shareId)") else {
            throw WorkflowShareClientError.backendUnreachable
        }
        var request = URLRequest(url: fetchURL)
        request.httpMethod = "GET"
        request.setValue(clientSecret, forHTTPHeaderField: "X-Perch-Client")

        let (responseData, response) = try await performRequest(request)
        try throwForErrorStatus(response)

        guard let fetchResponse = try? JSONDecoder().decode(
            FetchResponseBody.self, from: responseData
        ) else {
            throw WorkflowShareClientError.malformedServerResponse
        }
        return IncomingSharedWorkflow(
            shareId: shareId,
            title: fetchResponse.title,
            markdown: fetchResponse.markdown
        )
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await urlSession.data(for: request)
        } catch {
            throw WorkflowShareClientError.backendUnreachable
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowShareClientError.malformedServerResponse
        }
        return (responseData, httpResponse)
    }

    private func throwForErrorStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw WorkflowShareClientError.unauthorized
        case 404:
            throw WorkflowShareClientError.shareNotFound
        case 413:
            throw WorkflowShareClientError.playbookTooLarge
        default:
            throw WorkflowShareClientError.malformedServerResponse
        }
    }
}
