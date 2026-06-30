import Foundation

/// Launches and owns the Python browser subagent sidecar process.
///
/// The sidecar is a child `Process` running `run.sh --socket <path>`. The Swift
/// app is the sole owner: it starts the process on first use, waits for the unix
/// socket file to appear, and terminates the process on quit. The sidecar path
/// and socket path are read from Info.plist (with sensible defaults) so the demo
/// machine and CI can point at different checkouts without code changes.
final class BrowserSubagentProcessSupervisor {

    enum SupervisorError: Error {
        case sidecarPathMissing
        case runScriptMissing(String)
        case socketNeverAppeared
        case launchFailed(String)
    }

    /// Info.plist key holding the absolute path to the `browser-subagent/` directory.
    private static let sidecarPathInfoKey = "BrowserSubagentPath"
    /// Info.plist key holding the unix socket path the sidecar should bind.
    private static let socketPathInfoKey = "BrowserSubagentSocketPath"

    // The IPC socket lives under <repo>/support/ipc — Perch keeps all on-disk
    // state in the repo, never in ~/Library/Application Support. The repo path is
    // short enough that the socket path stays well under the macOS sun_path limit.
    private static let defaultSocketPath = PerchSupportPaths.directory("ipc")
        .appendingPathComponent("subagent.sock").path

    private static let socketAppearanceTimeoutSeconds = 8.0
    private static let socketPollIntervalSeconds = 0.1

    /// File the sidecar's stdout + stderr are redirected to. Without this the
    /// child process' output is discarded, so a launch failure (e.g. macOS
    /// denying exec of `run.sh` under a protected folder, or a Python traceback)
    /// is invisible to the app — it only ever observes `socketNeverAppeared`.
    /// Capturing here makes those failures diagnosable after the fact.
    private static let sidecarLogPath = PerchSupportPaths.file("sidecar.log").path

    private var sidecarProcess: Process?

    /// The unix socket path the sidecar binds (read once from Info.plist).
    let socketPath: String

    init() {
        let configuredSocketPath = AppBundleConfiguration.stringValue(forKey: Self.socketPathInfoKey)
            .map { NSString(string: $0).expandingTildeInPath }
        // Honor an explicit Info.plist override ONLY when it does not point into
        // ~/Library/Application Support — Perch keeps all state in <repo>/support,
        // so a stale Application-Support socket path falls through to the default.
        if let configuredSocketPath,
           !configuredSocketPath.contains("Library/Application Support") {
            self.socketPath = configuredSocketPath
        } else {
            self.socketPath = Self.defaultSocketPath
        }
    }

    /// Whether the sidecar process is currently running.
    var isRunning: Bool {
        sidecarProcess?.isRunning ?? false
    }

    /// Ensures the sidecar is running and its socket exists, then returns the
    /// socket path. Idempotent — calling again while running is a no-op.
    @discardableResult
    func ensureRunning() async throws -> String {
        if isRunning, FileManager.default.fileExists(atPath: socketPath) {
            return socketPath
        }

        // Prefer an explicit Info.plist override; otherwise derive the sidecar
        // directory from the resolved repo root (`<repo>/browser-subagent`). The
        // derivation keeps machine-specific absolute paths out of the committed
        // bundle, so any clone works without editing Info.plist.
        let sidecarDirectory: String
        if let configuredSidecarDirectory = AppBundleConfiguration.stringValue(forKey: Self.sidecarPathInfoKey) {
            sidecarDirectory = configuredSidecarDirectory
        } else if let repoRootURL = PerchSupportPaths.repoRootURL {
            sidecarDirectory = repoRootURL.appendingPathComponent("browser-subagent", isDirectory: true).path
        } else {
            throw SupervisorError.sidecarPathMissing
        }

        let runScriptPath = (sidecarDirectory as NSString).appendingPathComponent("run.sh")
        guard FileManager.default.fileExists(atPath: runScriptPath) else {
            throw SupervisorError.runScriptMissing(runScriptPath)
        }

        // A leftover socket file from a sidecar that has since died would make
        // waitForSocketFile() return immediately (the file still exists) before
        // the freshly launched sidecar has actually bound — and the subsequent
        // connect() would then race against that stale path. Remove it first so
        // we only ever observe the genuinely new sidecar's socket. The sidecar
        // also unlinks stale sockets on its side, so this is safe to do blindly.
        try? FileManager.default.removeItem(atPath: socketPath)

        try launchSidecar(sidecarDirectory: sidecarDirectory)
        try await waitForSocketFile()
        return socketPath
    }

    /// Terminates the sidecar process (called on app quit).
    func terminate() {
        sidecarProcess?.terminate()
        sidecarProcess = nil
    }

    // MARK: - Private

    private func launchSidecar(sidecarDirectory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        // A login shell (-lc) picks up the user's Python toolchain from their
        // shell profile, matching how the app launches other helper scripts.
        let quotedDirectory = Self.shellQuote(sidecarDirectory)
        let quotedSocketPath = Self.shellQuote(socketPath)
        let command = "cd \(quotedDirectory) && ./run.sh --socket \(quotedSocketPath)"
        process.arguments = ["-lc", command]

        // Redirect the sidecar's stdout + stderr to a log file so launch
        // failures (exec denied, Python traceback, missing venv) are recoverable
        // instead of vanishing into a discarded pipe. Append, so successive runs
        // accumulate rather than clobber the previous failure.
        if let logHandle = Self.sidecarLogFileHandle() {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
        } catch {
            throw SupervisorError.launchFailed(error.localizedDescription)
        }
        sidecarProcess = process
    }

    private func waitForSocketFile() async throws {
        let deadline = Date().addingTimeInterval(Self.socketAppearanceTimeoutSeconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.socketPollIntervalSeconds * 1_000_000_000))
        }
        throw SupervisorError.socketNeverAppeared
    }

    /// Single-quotes a string for safe interpolation into a shell command.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens (creating if needed) the sidecar log file for appending and returns
    /// a handle positioned at the end. Writes a timestamped launch marker so the
    /// output of each spawn attempt is delimited in the log. Returns nil if the
    /// file cannot be opened, in which case the launch proceeds without capture.
    private static func sidecarLogFileHandle() -> FileHandle? {
        let fileManager = FileManager.default
        let logDirectory = (sidecarLogPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: sidecarLogPath) {
            fileManager.createFile(atPath: sidecarLogPath, contents: nil)
        }

        guard let fileHandle = FileHandle(forWritingAtPath: sidecarLogPath) else {
            return nil
        }
        _ = try? fileHandle.seekToEnd()

        let marker = "\n===== sidecar launch \(ISO8601DateFormatter().string(from: Date())) =====\n"
        if let markerData = marker.data(using: .utf8) {
            try? fileHandle.write(contentsOf: markerData)
        }
        return fileHandle
    }
}
