//
//  WorkflowPlaybookStore.swift
//  leanring-buddy
//
//  Persists workflow playbooks as plain markdown files at
//  ~/Library/Application Support/Perch/workflows/<slug>.md — a durable,
//  user-editable artifact. The directory is injectable so the CLI harness can
//  round-trip into a temp dir.
//

import Foundation

struct WorkflowPlaybookStore {

    let directoryURL: URL

    /// The app's real playbook directory.
    static func standard() -> WorkflowPlaybookStore {
        return WorkflowPlaybookStore(directoryURL: PerchSupportPaths.directory("workflows"))
    }

    /// Writes the markdown under a slug derived from `title`, appending a
    /// numeric suffix on collision (each saved playbook keeps its own file).
    /// Returns the playbook with its slug and on-disk location filled in.
    func save(markdown: String, title: String) throws -> WorkflowPlaybook {
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )

        let baseSlug = Self.slugify(title)
        var candidateSlug = baseSlug
        var collisionCounter = 2
        while FileManager.default.fileExists(
            atPath: fileURL(forSlug: candidateSlug).path
        ) {
            candidateSlug = "\(baseSlug)-\(collisionCounter)"
            collisionCounter += 1
        }

        let destinationURL = fileURL(forSlug: candidateSlug)
        try markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
        return WorkflowPlaybook(
            title: title,
            slug: candidateSlug,
            markdown: markdown,
            fileURL: destinationURL
        )
    }

    func load(slug: String) throws -> WorkflowPlaybook {
        let sourceURL = fileURL(forSlug: slug)
        let markdown = try String(contentsOf: sourceURL, encoding: .utf8)
        return WorkflowPlaybook(
            title: Self.extractTitle(fromMarkdown: markdown) ?? slug,
            slug: slug,
            markdown: markdown,
            fileURL: sourceURL
        )
    }

    /// Human-gated self-healing seam. When a fresh demonstration resembles an
    /// existing skill, that resemblance MAY be worth folding back into the
    /// existing skill — but skills are **read-only**: we never rewrite one in
    /// place, because a single bad run would silently corrupt a working skill.
    /// So this only logs the candidate refinement for human review; it never
    /// touches disk. A real self-healing pass can plug in later, behind a gate.
    func proposeSkillUpdate(slug: String, suggestion: String) {
        WorkflowDebugLog.log(
            "proposeSkillUpdate: candidate refinement for \"\(slug)\" "
                + "(\(suggestion.count) chars) — logged for human review, not written"
        )
    }

    /// Every stored playbook, most recently modified first (the freshest ones
    /// are the likeliest match candidates for a new demonstration). Unreadable
    /// files are skipped rather than failing the whole listing.
    func listAllPlaybooks() -> [WorkflowPlaybook] {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        let markdownFileURLs = fileURLs
            .filter { $0.pathExtension == "md" }
            .sorted { firstURL, secondURL in
                let firstModified = (try? firstURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                let secondModified = (try? secondURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                return firstModified > secondModified
            }

        return markdownFileURLs.compactMap { markdownFileURL in
            let slug = markdownFileURL.deletingPathExtension().lastPathComponent
            return try? load(slug: slug)
        }
    }

    func fileURL(forSlug slug: String) -> URL {
        directoryURL.appendingPathComponent("\(slug).md")
    }

    /// The playbook's `# Title` line — the only structure code reads out of
    /// the markdown.
    static func extractTitle(fromMarkdown markdown: String) -> String? {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("# ") {
                let title = trimmedLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
        }
        return nil
    }

    /// Lowercase, alphanumerics only, hyphen-separated, length-capped.
    static func slugify(_ title: String) -> String {
        let lowercased = title.lowercased()
        var slugCharacters: [Character] = []
        var lastCharacterWasHyphen = true  // suppress leading hyphens
        for character in lowercased {
            if character.isLetter || character.isNumber {
                slugCharacters.append(character)
                lastCharacterWasHyphen = false
            } else if !lastCharacterWasHyphen {
                slugCharacters.append("-")
                lastCharacterWasHyphen = true
            }
        }
        while slugCharacters.last == "-" {
            slugCharacters.removeLast()
        }
        let slug = String(slugCharacters.prefix(64))
        return slug.isEmpty ? "workflow" : slug
    }
}
