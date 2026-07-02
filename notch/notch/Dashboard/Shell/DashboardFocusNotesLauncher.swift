//
//  DashboardFocusNotesLauncher.swift
//  Perch
//
//  Side effect for the Focus widget: when the user begins a focus session, open Apple
//  Notes to a fresh, dated note so they have somewhere to think out loud while the timer
//  runs. Kept out of `DashboardFocusModel` on purpose — the timer stays a pure countdown
//  brain; this integration lives at the UI boundary that decides a tap is a "begin".
//
//  Everything degrades gracefully: launching Notes is best-effort. If Automation
//  permission is denied (e.g. the standalone dashboard preview, or first run before the
//  grant) the AppleScript error is logged and swallowed — starting the timer must never
//  depend on Notes being reachable.
//

import AppKit
import Foundation

enum DashboardFocusNotesLauncher {

    /// Open the Notes app to a brand-new note headed with today's date, ready to type into.
    /// Called when a focus session *begins* (not on a resume), so each session that starts
    /// from a full timer gets its own fresh note.
    static func openNewFocusNote(now: Date = Date()) {
        let noteTitleLine = sessionTitleLine(for: now)
        let appleScriptSource = makeNewNoteScript(titleLine: noteTitleLine)

        // NSAppleScript is synchronous and can block while Notes activates; run it off the
        // main thread so tapping "Begin a session" stays instant and the timer starts now.
        Task.detached(priority: .userInitiated) {
            var executionErrorInfo: NSDictionary?
            NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&executionErrorInfo)
            if let executionErrorInfo {
                let errorMessage = (executionErrorInfo[NSAppleScript.errorMessage] as? String)
                    ?? "AppleScript error \(executionErrorInfo[NSAppleScript.errorNumber] ?? "?")"
                NSLog("[Dashboard] Could not open a new Notes note for the focus session: \(errorMessage)")
            }
        }
    }

    /// The note's first line (which Notes promotes to the note's title), e.g.
    /// "Focus session — Saturday, June 20".
    private static func sessionTitleLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return "Focus session — \(formatter.string(from: date))"
    }

    /// Build the AppleScript that activates Notes, creates a new note seeded with the title
    /// line, and brings that note forward. Notes treats the note body as HTML and promotes
    /// the first line to the title, so the title line is wrapped in `<h1>`.
    private static func makeNewNoteScript(titleLine: String) -> String {
        let escapedTitleLine = appleScriptStringLiteral(titleLine)
        return """
        tell application "Notes"
            activate
            set newFocusNote to make new note with properties {body:"<h1>" & \(escapedTitleLine) & "</h1>"}
            show newFocusNote
        end tell
        """
    }

    /// Escape a Swift string into a safe AppleScript double-quoted string literal (escaping
    /// backslashes and double quotes), so a stray quote in the title can't break the script.
    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
