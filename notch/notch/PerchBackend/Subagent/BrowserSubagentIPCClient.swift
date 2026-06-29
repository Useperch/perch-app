import Foundation

/// JSON-RPC-over-unix-socket client for the Python browser subagent sidecar.
///
/// Uses a raw POSIX `AF_UNIX` stream socket because the Network framework does
/// not publicly expose unix-domain endpoints. The socket is wrapped in an actor
/// so request/response bookkeeping is serialized; a dedicated background read
/// loop decodes newline-delimited JSON and either resolves a pending request
/// continuation (messages with an `id`) or surfaces a typed event.
actor BrowserSubagentIPCClient {

    enum IPCError: Error {
        case connectionFailed(String)
        case socketPathTooLong
        case notConnected
        case disconnected
        case malformedResponse
    }

    private var socketDescriptor: Int32 = -1
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    private var eventStream: AsyncStream<BrowserSubagentEvent>!
    private var eventContinuation: AsyncStream<BrowserSubagentEvent>.Continuation!

    init() {
        var capturedContinuation: AsyncStream<BrowserSubagentEvent>.Continuation!
        eventStream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        eventContinuation = capturedContinuation
    }

    /// Builds a brand-new event stream + continuation. A connection that dropped
    /// calls `finish()` on its continuation, and `AsyncStream.finish()` is
    /// terminal — the old stream can never yield again. So every fresh `connect()`
    /// must install a new stream, otherwise a reconnected sidecar's events would
    /// silently go nowhere.
    private func recreateEventStream() {
        var capturedContinuation: AsyncStream<BrowserSubagentEvent>.Continuation!
        eventStream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        eventContinuation = capturedContinuation
    }

    /// Stream of typed events emitted by the sidecar (state, frame, confirm, done, error).
    nonisolated func events() async -> AsyncStream<BrowserSubagentEvent> {
        await eventStreamHandle()
    }

    private func eventStreamHandle() -> AsyncStream<BrowserSubagentEvent> {
        eventStream
    }

    // MARK: - Connection

    func connect(socketPath: String) throws {
        // Install a fresh event stream — a previous connection may have finished
        // the old one, which is terminal and cannot be reused on reconnect.
        recreateEventStream()

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw IPCError.connectionFailed("socket() failed: \(String(cString: strerror(errno)))")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        // sun_path is a fixed C array; reject paths that would overflow it.
        let maxPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= maxPathCapacity else {
            close(descriptor)
            throw IPCError.socketPathTooLong
        }
        withUnsafeMutablePointer(to: &address.sun_path) { sunPathPointer in
            sunPathPointer.withMemoryRebound(to: CChar.self, capacity: maxPathCapacity) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Foundation.connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            close(descriptor)
            throw IPCError.connectionFailed("connect() failed: \(String(cString: strerror(errno)))")
        }

        socketDescriptor = descriptor
        startReadLoop(on: descriptor)
    }

    func disconnect() {
        if socketDescriptor >= 0 {
            close(socketDescriptor)
            socketDescriptor = -1
        }
        eventContinuation.finish()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: IPCError.disconnected)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Requests

    /// Sends a request and awaits its `result` dictionary.
    @discardableResult
    func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard socketDescriptor >= 0 else { throw IPCError.notConnected }

        let requestId = nextRequestId
        nextRequestId += 1

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params,
        ]
        let line = try Self.encodeLine(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            do {
                try writeLine(line)
            } catch {
                pendingRequests[requestId] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func writeLine(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var totalWritten = 0
            let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            while totalWritten < data.count {
                let written = write(socketDescriptor, base + totalWritten, data.count - totalWritten)
                if written <= 0 {
                    throw IPCError.disconnected
                }
                totalWritten += written
            }
        }
    }

    // MARK: - Incoming dispatch

    private func handleIncomingMessage(_ message: [String: Any]) {
        if let requestId = message["id"] as? Int {
            guard let continuation = pendingRequests.removeValue(forKey: requestId) else { return }
            if let errorObject = message["error"] as? [String: Any] {
                let errorMessage = errorObject["message"] as? String ?? "rpc error"
                continuation.resume(throwing: NSError(
                    domain: "BrowserSubagentIPC",
                    code: errorObject["code"] as? Int ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                ))
            } else {
                continuation.resume(returning: message["result"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any],
              let event = BrowserSubagentEvent.from(method: method, params: params) else { return }
        eventContinuation.yield(event)
    }

    private func handleConnectionClosed() {
        socketDescriptor = -1
        eventContinuation.finish()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: IPCError.disconnected)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Background read loop

    private nonisolated func startReadLoop(on descriptor: Int32) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var lineBuffer = Data()
            var readBuffer = [UInt8](repeating: 0, count: 65536)

            while true {
                let bytesRead = read(descriptor, &readBuffer, readBuffer.count)
                if bytesRead <= 0 {
                    Task { await self?.handleConnectionClosed() }
                    return
                }
                lineBuffer.append(contentsOf: readBuffer[0..<bytesRead])

                // Split on newline; dispatch each complete line.
                while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                    let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineIndex)
                    lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIndex)
                    guard !lineData.isEmpty,
                          let object = try? JSONSerialization.jsonObject(with: lineData),
                          let message = object as? [String: Any] else { continue }
                    Task { await self?.handleIncomingMessage(message) }
                }
            }
        }
    }

    private static func encodeLine(_ message: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: message, options: [])
        data.append(0x0A)  // trailing newline frames the message
        return data
    }
}
