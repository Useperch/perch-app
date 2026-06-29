//
//  CursorPositionProbe.swift
//  leanring-buddy
//
//  A tiny shared holder for the main Perch cursor's latest on-screen position,
//  in the notch screen's SwiftUI (top-left origin) coordinate space.
//
//  The cursor position changes ~60fps inside `BlueCursorView`. Publishing it
//  would re-render every observer 60 times a second, so instead the notch
//  overlay writes the latest value into this plain (non-observable) class. The
//  agent-swarm animation reads it ON DEMAND — only at the moment a triangle
//  needs its mitosis origin (spawn) or merge destination (done) — so nothing
//  re-renders per frame.
//

import Foundation

@MainActor
final class CursorPositionProbe {
    /// The main buddy triangle's latest position in the notch overlay's SwiftUI
    /// coordinates. Updated continuously by the notch-screen `BlueCursorView`;
    /// read only at spawn/merge moments by the agent swarm.
    var currentBuddyPosition: CGPoint = .zero
}
