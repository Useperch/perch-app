//
//  AppSkillLibrary.swift
//  Perch
//
//  Per-app "skills" for the desktop automation agent. When the agent is operating
//  inside a specific Mac app, it can load a read-only markdown skill keyed by that
//  app's bundle identifier (e.g. "com.microsoft.Excel") and inject it into the
//  decider's system prompt — making Perch an expert in that app.
//
//  Skills are READ-ONLY markdown (no self-rewriting — see CLAUDE.md). A skill is
//  resolved in two places, the first hit winning so a runtime override beats the
//  shipped file:
//    1. <repo>/support/app-skills/<bundle-id>.md  — gitignored, hot-editable override.
//    2. <repo>/skills/desktop/<bundle-id>.md      — committed, version-controlled.
//
//  When no file exists for the frontmost app the loader returns nil and the prompt
//  is unchanged, so apps without a skill behave exactly as before.
//

import Foundation

@MainActor
enum AppSkillLibrary {

    /// Cache keyed by bundle identifier so each app's skill is read from disk once
    /// per session, not on every decider turn. The value is itself optional: a
    /// cached `nil` records "we already looked and there is no skill for this app".
    private static var skillMarkdownByBundleIdentifier: [String: String?] = [:]

    /// The markdown skill for the given app, or nil when the bundle id is unknown or
    /// no skill file exists. "Check if there is a markdown file before starting."
    static func skillMarkdown(forBundleIdentifier bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }

        if let cachedResult = skillMarkdownByBundleIdentifier[bundleIdentifier] {
            return cachedResult
        }

        let loadedMarkdown = loadSkillMarkdownFromDisk(forBundleIdentifier: bundleIdentifier)
        skillMarkdownByBundleIdentifier[bundleIdentifier] = loadedMarkdown
        return loadedMarkdown
    }

    /// Reads `<bundle-id>.md` from the override directory first, then the committed
    /// `skills/desktop/` directory in the repo root. Returns the first that exists.
    private static func loadSkillMarkdownFromDisk(forBundleIdentifier bundleIdentifier: String) -> String? {
        let skillFileName = "\(bundleIdentifier).md"

        let overrideSkillURL = PerchSupportPaths
            .directory("app-skills")
            .appendingPathComponent(skillFileName)
        if let overrideMarkdown = try? String(contentsOf: overrideSkillURL, encoding: .utf8),
           !overrideMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return overrideMarkdown
        }

        if let repoRootURL = PerchSupportPaths.repoRootURL {
            let packagedSkillURL = repoRootURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("desktop", isDirectory: true)
                .appendingPathComponent(skillFileName)
            if let packagedMarkdown = try? String(contentsOf: packagedSkillURL, encoding: .utf8),
               !packagedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return packagedMarkdown
            }
        }

        return nil
    }
}
