//
//  IntegrationsDebugLog.swift
//  Perch
//
//  Developer diagnostic for the proactive "Connect this to Perch?" offer. Appends
//  one line per context change the monitor sees (frontmost app + URL + which
//  catalog service it matched) and per gating decision in the offer coordinator,
//  to `integrations-debug.log` in the support directory — so "why didn't the
//  pop-up appear?" is answerable from the log instead of guesswork.
//
//  Logs only the app bundle id + URL host + decision — no page contents. OFF by
//  default; opt in for local debugging by setting the `PERCH_DEBUG_LOGS` env var.
//

import Foundation

enum IntegrationsDebugLog {

    private static let logFileURL: URL = PerchSupportPaths.file("integrations-debug.log")

    /// OFF by default; set `PERCH_DEBUG_LOGS` to enable for local debugging.
    private static let isEnabled =
        ProcessInfo.processInfo.environment["PERCH_DEBUG_LOGS"] != nil

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
