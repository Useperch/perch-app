//
//  PerchRunLog.swift
//  leanring-buddy
//
//  Per-run trace documents written into a `logs/` folder INSIDE the repo (never
//  into ~/Library/Application Support). Each companion turn (one voice or typed
//  interaction) gets its own markdown document containing the full ordered trace
//  of that run — every input, plan/decision, action, and spoken utterance —
//  plus the full AppleScript the agent executed inline.
//
//  The existing flat `perch-debug.log` is repurposed here as the MASTER INDEX:
//  one summary line per run (timestamp, input kind, input, the run-doc filename
//  for further tracing) plus session-level markers.
//
//  This is a dev-time diagnostic. The running app finds the repo from its own
//  bundle location (the local build lives at <repo>/build/manual/Perch.app); if
//  no repo can be resolved (e.g. the installed copy), logging is a silent no-op.
//

import Foundation

/// Scannable category tag prefixed onto every trace line so a run document — and
/// the whole `logs/` folder — can be grepped by kind of event.
enum PerchDebugCategory: String {
    case input  = "INPUT"   // what the user said / typed
    case plan   = "PLAN"    // context sent to Claude, Claude's reply, intent-gate decision
    case action = "ACTION"  // pointing, background-task lifecycle, desktop actions, AppleScript
    case speak  = "SPEAK"   // what Perch spoke aloud (verbatim)
    case error  = "ERROR"
    case state  = "STATE"   // permissions, overlay, subagent state transitions
}

/// Writes per-run trace documents and the master index. All file IO is
/// best-effort and never throws — a logging failure must never affect app or
/// agent behavior.
enum PerchRunLog {

    /// Opaque handle to one run's document. A value type so it can be passed
    /// across async boundaries and handed to `BrowserSubagentManager` — the
    /// act-lane agent may finish AFTER a later turn has started, and its late
    /// AppleScript / completion must still land in the originating run's doc.
    struct RunDocument {
        let id: String
        let fileName: String
        let fileURL: URL
        let startedAt: Date
        let inputSummary: String
    }

    // MARK: - Configuration

    /// Set by test/eval harnesses so fixture runs don't write trace docs.
    private static let isDisabledByEnvironment =
        ProcessInfo.processInfo.environment["CLICKY_RUN_LOG_DISABLED"] != nil

    /// `<repo>/logs/`, created on first use. Nil when no repo could be resolved
    /// (we deliberately never fall back to Application Support). The relocated
    /// support state (traces, profile, etc.) lives under `<repo>/support/` —
    /// see `PerchSupportPaths`.
    private static let logsDirectoryURL: URL? = {
        guard let repoRootURL = PerchSupportPaths.repoRootURL else { return nil }
        let logsURL = repoRootURL.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        return logsURL
    }()

    /// The master index — the repurposed `perch-debug.log`, one line per run.
    private static let masterIndexURL: URL? = logsDirectoryURL?
        .appendingPathComponent("perch-debug.log")

    // MARK: - Formatters

    /// Filesystem-safe UTC timestamp for run-doc filenames (no colons).
    private static let runFileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// ISO8601 for the run-doc header and master-index lines.
    private static let isoTimestampFormatter = ISO8601DateFormatter()

    /// Short wall-clock prefix on each trace line within a run document.
    private static let lineTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Public API

    /// Opens a new run document for one companion turn, writes its header, and
    /// appends a one-line summary to the master index. Returns nil when logging
    /// is disabled or no repo could be resolved.
    static func beginRun(inputKind: String, input: String) -> RunDocument? {
        guard !isDisabledByEnvironment, let logsDirectoryURL else { return nil }

        let startedAt = Date()
        let shortId = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        let fileName = "\(runFileTimestampFormatter.string(from: startedAt))__\(shortId).md"
        let fileURL = logsDirectoryURL.appendingPathComponent(fileName)
        let inputSummary = singleLineSummary(of: input)

        let header = """
        # Perch run \(shortId)

        - **Started:** \(isoTimestampFormatter.string(from: startedAt))
        - **Input kind:** \(inputKind)
        - **Input:** \(input)

        ---

        """
        write(header + "\n", to: fileURL, append: false)

        let run = RunDocument(
            id: shortId,
            fileName: fileName,
            fileURL: fileURL,
            startedAt: startedAt,
            inputSummary: inputSummary
        )
        appendMasterIndexLine(for: run, inputKind: inputKind)
        return run
    }

    /// Appends a single tagged trace line to a run document.
    static func append(_ run: RunDocument?, _ category: PerchDebugCategory, _ message: String) {
        guard !isDisabledByEnvironment, let run else { return }
        let line = "`\(lineTimestampFormatter.string(from: Date()))` **[\(category.rawValue)]** \(message)\n\n"
        write(line, to: run.fileURL, append: true)
    }

    /// Appends a tagged line followed by a fenced block — used for verbatim
    /// payloads (the full context sent to Claude, Claude's full reply) that are
    /// too large to read well on a single line.
    static func appendBlock(
        _ run: RunDocument?,
        _ category: PerchDebugCategory,
        _ title: String,
        body: String,
        language: String = ""
    ) {
        guard !isDisabledByEnvironment, let run else { return }
        let block = """
        `\(lineTimestampFormatter.string(from: Date()))` **[\(category.rawValue)]** \(title)

        ```\(language)
        \(body)
        ```

        """
        write(block, to: run.fileURL, append: true)
    }

    /// Appends the full AppleScript a run's agent executed, with its result —
    /// "everything the agent did", inline in the run document.
    static func appendAppleScript(_ run: RunDocument?, source: String, result: String?) {
        guard !isDisabledByEnvironment, let run else { return }
        var block = """
        `\(lineTimestampFormatter.string(from: Date()))` **[\(PerchDebugCategory.action.rawValue)]** AppleScript executed

        ```applescript
        \(source)
        ```

        """
        if let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block += "_Result:_ \(singleLineSummary(of: result))\n\n"
        }
        write(block, to: run.fileURL, append: true)
    }

    /// Reads the browser subagent's own trace JSON and inlines any AppleScript
    /// it executed in its own process (the Python "system" family, run via
    /// `osascript`) into the run document. The Swift-side desktop AppleScript is
    /// captured directly at the action callback; this covers the rest.
    static func appendAppleScriptFromSubagentTrace(_ run: RunDocument?, subagentId: String) {
        guard !isDisabledByEnvironment, let run, !subagentId.isEmpty else { return }
        let traceURL = PerchSupportPaths.directory("subagent-traces")
            .appendingPathComponent("\(subagentId).json")

        guard let traceData = try? Data(contentsOf: traceURL),
              let traceJSON = try? JSONSerialization.jsonObject(with: traceData) as? [String: Any],
              let steps = traceJSON["steps"] as? [[String: Any]] else { return }

        for step in steps {
            guard let appleScriptEntries = step["appleScripts"] as? [[String: Any]] else { continue }
            for entry in appleScriptEntries {
                guard let source = entry["source"] as? String, !source.isEmpty else { continue }
                appendAppleScript(run, source: source, result: entry["result"] as? String)
            }
        }
    }

    /// Appends a run-less marker line (startup, permission changes) to the
    /// master index. Backs the legacy `perchDebugLog(_:)` free function.
    static func logSessionMarker(_ message: String) {
        guard !isDisabledByEnvironment, let masterIndexURL else { return }
        let line = "\(isoTimestampFormatter.string(from: Date())) | session | \(singleLineSummary(of: message))\n"
        write(line, to: masterIndexURL, append: true)
    }

    // MARK: - Internals

    private static func appendMasterIndexLine(for run: RunDocument, inputKind: String) {
        guard let masterIndexURL else { return }
        let line = "\(isoTimestampFormatter.string(from: run.startedAt)) | \(inputKind) | \"\(run.inputSummary)\" | \(run.fileName)\n"
        write(line, to: masterIndexURL, append: true)
    }

    /// Collapses whitespace/newlines and truncates so a value fits on one line
    /// in the master index or a result note.
    private static func singleLineSummary(of text: String, limit: Int = 140) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    private static let writeLock = NSLock()

    private static func write(_ string: String, to url: URL, append: Bool) {
        guard let data = string.data(using: .utf8) else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        if append, let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }
}
