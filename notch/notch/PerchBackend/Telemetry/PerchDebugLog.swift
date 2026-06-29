import Foundation

/// Records a run-less, session-level diagnostic (app startup, permission
/// changes) as one line in the master index.
///
/// `print()` output from a GUI app launched through LaunchServices (the normal
/// double-click / `open` path) is discarded by macOS — it never reaches a
/// terminal or the unified logging system. This routes the same diagnostics to
/// disk instead.
///
/// Per-turn detail (every input, plan, action, and spoken utterance) lives in
/// per-run documents written by `PerchRunLog`; this free function backs the
/// handful of call sites that fire OUTSIDE of any single run, appending a
/// `| session |` line to the master index at `<repo>/logs/perch-debug.log`.
func perchDebugLog(_ message: String) {
    PerchRunLog.logSessionMarker(message)
}
