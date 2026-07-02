//
//  ClipboardContentHasher.swift
//  Perch
//
//  Reduces clipboard / typed text to a short, one-way hash. The capture layer
//  records *only* this hash — never the raw content — which is exactly enough
//  for the repetition detector to tell "the content changed between
//  repetitions" apart from "the same thing happened twice", and nothing more.
//
//  Pure and Foundation/CryptoKit only, so it is unit-testable in isolation.
//

import CryptoKit
import Foundation

enum ClipboardContentHasher {

    /// A short hex fingerprint of `content`, or `nil` for empty/absent input.
    /// Truncated to 16 hex characters: collision-resistant enough to
    /// distinguish two clipboard values while carrying none of the content.
    static func hash(of content: String?) -> String? {
        guard let content, !content.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
