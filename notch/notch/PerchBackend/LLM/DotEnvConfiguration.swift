//
//  DotEnvConfiguration.swift
//  leanring-buddy
//
//  Reads the repo-root `.env` file once and exposes simple key lookups.
//
//  The app is usually GUI-launched (`open Perch.app`), where the process
//  inherits only launchd's minimal environment — so a shell `export` never
//  reaches it. This loader gives a launch-method-independent place to read
//  repo-local config (the Cerebras / vision-gate keys, plus repo-local keys like
//  EXA_API_KEY overlaid onto spawned subprocesses).
//  Callers should still check `ProcessInfo` FIRST, so a terminal launch with an
//  exported override still wins over the file.
//

import Foundation

enum DotEnvConfiguration {

    /// Parsed `<repo>/.env`, loaded once. Empty when the file is absent or no
    /// repo root can be resolved.
    private static let values: [String: String] = {
        guard let repoRootURL = PerchSupportPaths.repoRootURL else { return [:] }
        let dotEnvURL = repoRootURL.appendingPathComponent(".env")
        guard let fileContents = try? String(contentsOf: dotEnvURL, encoding: .utf8) else {
            return [:]
        }

        var parsedValues: [String: String] = [:]
        for rawLine in fileContents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip one layer of surrounding quotes if present.
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            if !key.isEmpty { parsedValues[key] = value }
        }
        return parsedValues
    }()

    /// The value for `key` from `<repo>/.env`, or nil if absent.
    static func value(forKey key: String) -> String? {
        values[key]
    }

    /// Every parsed `<repo>/.env` pair. Used to overlay repo-local config (e.g.
    /// API keys like `EXA_API_KEY`) onto a spawned subprocess's environment, so
    /// model-authored code launched by the agent can reach configured services
    /// even though a GUI-launched app inherits only launchd's minimal environment.
    static var allValues: [String: String] {
        values
    }
}
