//
//  IntegrationsDebugLog.swift
//  leanring-buddy
//
//  TEMPORARY demo-time diagnostic for the proactive "Connect this to Perch?"
//  offer. Appends one line per context change the monitor sees (frontmost app +
//  URL + which catalog service it matched) and per gating decision in the offer
//  coordinator, to <repo>/support/integrations-debug.log — so "why didn't the
//  pop-up appear?" is answerable from the log instead of guesswork.
//
//  Logs only the app bundle id + URL host + decision — no page contents.
//  Remove this file and its call sites once the trigger is confirmed working.
//

import Foundation

enum IntegrationsDebugLog {

    private static let logFileURL: URL = PerchSupportPaths.file("integrations-debug.log")

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
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
