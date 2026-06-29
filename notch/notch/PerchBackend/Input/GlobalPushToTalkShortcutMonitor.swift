//
//  GlobalPushToTalkShortcutMonitor.swift
//  leanring-buddy
//
//  Captures push-to-talk keyboard shortcuts while makesomething is running in the
//  background. Uses a listen-only CGEvent tap so modifier-only shortcuts like
//  ctrl + option behave more like a real system-wide voice tool.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class GlobalPushToTalkShortcutMonitor: ObservableObject {
    let shortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()

    /// Fires when the user presses the Escape key anywhere on the system. Perch
    /// uses this to immediately stop talking (cancel the in-flight response and
    /// TTS playback). Published from the same listen-only CGEvent tap that already
    /// powers push-to-talk, so it needs no extra permissions.
    let stopKeyPressedPublisher = PassthroughSubject<Void, Never>()

    /// Fires when the user taps the Control key twice in quick succession with
    /// no other modifiers — opens the notch text input ("press Control twice
    /// to enter text mode", matching the HeyPerch shortcut).
    let controlDoubleTapPublisher = PassthroughSubject<Void, Never>()

    /// The macOS virtual key code for the Escape key.
    private let escapeKeyCode: UInt16 = 53

    /// Maximum gap between the end of one lone-Control tap and the start of
    /// the next press for the pair to count as a double tap.
    private let controlDoubleTapWindowSeconds: TimeInterval = 0.45

    /// True while Control is held down alone (no other modifiers joined and
    /// no regular key was typed) — i.e. a candidate "lone Control tap".
    private var isLoneControlPressInFlight = false
    /// When the last clean lone-Control tap ended (key released).
    private var lastLoneControlTapReleaseTime: TimeInterval = 0

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    /// Mutated exclusively from the CGEvent tap callback, which runs on
    /// `CFRunLoopGetMain()` and therefore always executes on the main thread.
    /// Published so the overlay can hide immediately on key release without
    /// waiting for the async dictation state pipeline to catch up.
    @Published private(set) var isShortcutCurrentlyPressed = false

    deinit {
        stop()
    }

    func start() {
        // If the event tap is already running, don't restart it.
        // Restarting resets isShortcutCurrentlyPressed, which would kill
        // the waveform overlay mid-press when the permission poller calls
        // refreshAllPermissions → start() every few seconds.
        guard globalEventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { currentMask, eventType in
            currentMask | (CGEventMask(1) << eventType.rawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalPushToTalkShortcutMonitor = Unmanaged<GlobalPushToTalkShortcutMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalPushToTalkShortcutMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Global push-to-talk: couldn't create CGEvent tap")
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Global push-to-talk: couldn't create event tap run loop source")
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    func stop() {
        isShortcutCurrentlyPressed = false

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Pressing Escape anywhere tells Perch to stop talking immediately.
        if eventType == .keyDown && eventKeyCode == escapeKeyCode {
            stopKeyPressedPublisher.send(())
            return Unmanaged.passUnretained(event)
        }

        trackControlDoubleTap(eventType: eventType, modifierFlags: event.flags)

        let shortcutTransition = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: event.flags.rawValue,
            wasShortcutPreviouslyPressed: isShortcutCurrentlyPressed
        )

        switch shortcutTransition {
        case .none:
            break
        case .pressed:
            isShortcutCurrentlyPressed = true
            shortcutTransitionPublisher.send(.pressed)
        case .released:
            isShortcutCurrentlyPressed = false
            shortcutTransitionPublisher.send(.released)
        }

        return Unmanaged.passUnretained(event)
    }

    /// Detects a double tap of the Control key on its own. A "lone Control
    /// tap" is Control going down with no other modifiers, then back up
    /// without any other modifier joining or a regular key being typed —
    /// so ctrl+option push-to-talk and ctrl-key shortcuts never trigger it.
    private func trackControlDoubleTap(eventType: CGEventType, modifierFlags: CGEventFlags) {
        // Typing any regular key while Control is down means it was a keyboard
        // shortcut, not a tap.
        if eventType == .keyDown {
            isLoneControlPressInFlight = false
            return
        }

        guard eventType == .flagsChanged else { return }

        let isControlPressed = modifierFlags.contains(.maskControl)
        let isAnyOtherModifierPressed = modifierFlags.contains(.maskAlternate)
            || modifierFlags.contains(.maskCommand)
            || modifierFlags.contains(.maskShift)

        if isControlPressed && isAnyOtherModifierPressed {
            // Another modifier joined (e.g. ctrl+option push-to-talk) —
            // this press no longer counts as a lone tap.
            isLoneControlPressInFlight = false
        } else if isControlPressed && !isLoneControlPressInFlight {
            // Control just went down on its own. If the previous clean tap
            // ended a moment ago, this second press completes the double tap.
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastLoneControlTapReleaseTime < controlDoubleTapWindowSeconds {
                lastLoneControlTapReleaseTime = 0
                isLoneControlPressInFlight = false
                controlDoubleTapPublisher.send(())
            } else {
                isLoneControlPressInFlight = true
            }
        } else if !isControlPressed && isLoneControlPressInFlight {
            // Control released after a clean lone press — remember when, so
            // the next press can complete the double tap.
            isLoneControlPressInFlight = false
            lastLoneControlTapReleaseTime = ProcessInfo.processInfo.systemUptime
        }
    }
}
