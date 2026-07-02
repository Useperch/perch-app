//
//  PerchSupportPaths.swift
//  Perch
//
//  The single source of truth for where Perch keeps its on-disk state.
//
//  Everything lives INSIDE the repo under `<repo>/support/` — Perch must never
//  write to ~/Library/Application Support (see CLAUDE.md). The running dev build
//  finds the repo from its own bundle location (the local build lives at
//  <repo>/build/manual/Perch.app). If no repo can be resolved (e.g. a stray
//  installed copy with no repo around it) it falls back to ~/.perch-support —
//  still never touching Application Support.
//
//  The Python sidecar resolves the SAME `<repo>/support/` directory from its own
//  file location (see browser-subagent/perch_subagent/config.py), so the app and
//  the sidecar agree on every path without passing them over the wire.
//

import Foundation

enum PerchSupportPaths {

    /// The repo root the running app belongs to, or nil if it can't be found.
    ///
    /// Order: explicit `PERCH_REPO_ROOT` env override, then the `PerchRepoRoot`
    /// Info.plist key, then walk up from the app bundle to the first ancestor that
    /// contains a `.git` entry. The Info.plist key matters for notch: a
    /// signed build launched from DerivedData (or via Finder) has no `.git`
    /// ancestor and no env vars, so without it the support dir would wrongly fall
    /// back to `~/.perch-support` and mismatch the Python sidecar's `<repo>/support/`.
    static let repoRootURL: URL? = {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["PERCH_REPO_ROOT"],
           !override.isEmpty {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: true)
            if fileManager.fileExists(atPath: overrideURL.path) { return overrideURL }
        }

        if let infoPlistRepoRoot = Bundle.main.object(forInfoDictionaryKey: "PerchRepoRoot") as? String,
           !infoPlistRepoRoot.isEmpty {
            let infoPlistRepoRootURL = URL(fileURLWithPath: infoPlistRepoRoot, isDirectory: true)
            if fileManager.fileExists(atPath: infoPlistRepoRootURL.path) { return infoPlistRepoRootURL }
        }

        var candidateURL = Bundle.main.bundleURL
        for _ in 0..<12 {
            let gitMarkerURL = candidateURL.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitMarkerURL.path) { return candidateURL }
            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path { break }
            candidateURL = parentURL
        }
        return nil
    }()

    /// `<repo>/support/`, created on first use. Honors a `PERCH_SUPPORT_DIRECTORY`
    /// override; falls back to `~/.perch-support` when no repo is resolvable —
    /// never Application Support.
    static let supportDirectoryURL: URL = {
        let baseURL: URL
        if let override = ProcessInfo.processInfo.environment["PERCH_SUPPORT_DIRECTORY"],
           !override.isEmpty {
            baseURL = URL(fileURLWithPath: override, isDirectory: true)
        } else if let repoRootURL {
            baseURL = repoRootURL.appendingPathComponent("support", isDirectory: true)
        } else {
            baseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".perch-support", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }()

    /// A named subdirectory of the support folder (e.g. "workflows",
    /// "subagent-traces"), created on first use.
    static func directory(_ name: String) -> URL {
        let directoryURL = supportDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// A file directly inside the support folder (e.g. "agent-runs.json").
    static func file(_ name: String) -> URL {
        return supportDirectoryURL.appendingPathComponent(name)
    }
}
