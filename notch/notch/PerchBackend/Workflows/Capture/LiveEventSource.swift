//
//  LiveEventSource.swift
//  leanring-buddy
//
//  The thin, permission-gated WorkflowEventSource that turns real OS input into
//  normalized SemanticInputEvents. It is deliberately "dumb": it does no
//  pattern analysis (that's the detector's job) — it only observes and maps.
//
//  Two independent signals feed it:
//   • A listen-only, session-scoped CGEvent tap (the same shape as
//     GlobalPushToTalkShortcutMonitor) for paste (⌘V), clicks (left mouse
//     down), and typing into a field. Needs Accessibility / Input Monitoring.
//   • NSPasteboard.changeCount polling for copies. This path needs NO
//     permission at all, so it can be smoke-tested before any TCC grant.
//
//  Verification when running the signed app is one property only: "does it emit
//  events shaped like the JSONL fixtures?" — see WorkflowFixtures + the mock
//  source for the canonical shapes.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

final class LiveEventSource: WorkflowEventSource {

    private var onEvent: ((SemanticInputEvent) -> Void)?

    // CGEvent tap plumbing (mirrors GlobalPushToTalkShortcutMonitor).
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    // Clipboard polling.
    private var clipboardPollTimer: Timer?
    private var lastObservedPasteboardChangeCount: Int

    /// Set synchronously when a ⌘C is handled in the tap, so the slower
    /// clipboard poller doesn't double-count the same copy.
    private var recentlyHandledCopyAt: Date?

    /// Virtual key codes we care about.
    private let keyCodeC: Int64 = 8
    private let keyCodeV: Int64 = 9

    /// Non-character keys that move the selection or edit structurally — Tab,
    /// Return, Escape, Delete, the arrow keys, page up/down. These must NOT be
    /// recorded as "typing" (e.g. Tab-advancing between spreadsheet cells is
    /// navigation, not a content keystroke).
    private let navigationKeyCodes: Set<Int64> = [48, 36, 53, 51, 123, 124, 125, 126, 116, 121]

    init() {
        lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        stop()
    }

    func start(onEvent: @escaping (SemanticInputEvent) -> Void) {
        self.onEvent = onEvent
        WorkflowDebugLog.log("LiveEventSource.start — beginning capture")
        startClipboardPolling()
        startEventTap()
    }

    func stop() {
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = nil

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        onEvent = nil
    }

    // MARK: - Clipboard polling (copies; no permission required)

    private func startClipboardPolling() {
        let pollTimer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollPasteboardForCopy()
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        clipboardPollTimer = pollTimer
    }

    private func pollPasteboardForCopy() {
        let generalPasteboard = NSPasteboard.general
        guard generalPasteboard.changeCount != lastObservedPasteboardChangeCount else { return }
        lastObservedPasteboardChangeCount = generalPasteboard.changeCount

        // If a ⌘C was just handled synchronously in the tap, that path already
        // emitted this copy with the correct source app — don't double-count it.
        if let handledAt = recentlyHandledCopyAt, Date().timeIntervalSince(handledAt) < 0.6 {
            return
        }

        // A menu / right-click copy. Matched on app + action only (see emit).
        emit(
            actionType: .copy,
            role: nil,
            label: nil,
            clipboardContentHash: ClipboardContentHasher.hash(of: generalPasteboard.string(forType: .string))
        )
    }

    // MARK: - CGEvent tap (paste / click / type)

    private func startEventTap() {
        guard eventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.keyDown, .leftMouseDown]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let liveSource = Unmanaged<LiveEventSource>.fromOpaque(userInfo).takeUnretainedValue()
            liveSource.handleTapEvent(eventType: eventType, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ LiveEventSource: couldn't create CGEvent tap (Accessibility not granted?)")
            WorkflowDebugLog.log("⚠️ CGEvent tap creation FAILED — Accessibility / Input Monitoring not granted?")
            return
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0) else {
            CFMachPortInvalidate(createdTap)
            return
        }

        eventTap = createdTap
        eventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        WorkflowDebugLog.log("CGEvent tap created + enabled (keyDown + leftMouseDown)")
    }

    /// Runs on the main run loop (the tap is attached to CFRunLoopGetMain()).
    private func handleTapEvent(eventType: CGEventType, event: CGEvent) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }

        switch eventType {
        case .leftMouseDown:
            handleLeftMouseDown(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleLeftMouseDown(_ event: CGEvent) {
        // Clicks are matched on app + action only (the per-element grounding
        // varies per cell/row and would break the "copy/paste over and over"
        // repetition the detector is looking for).
        emit(actionType: .click, role: nil, label: nil)
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isCommandHeld = event.flags.contains(.maskCommand)

        // Copy (⌘C): capture synchronously, while the *source* app is still
        // frontmost. The clipboard poller runs up to 0.4s later — by then the
        // user may have switched to the destination app, mis-attributing the
        // copy and breaking the repeating cycle.
        if isCommandHeld && keyCode == keyCodeC {
            handleCopyShortcut()
            return
        }

        // Paste (⌘V): attribute the *current* clipboard content as what's pasted.
        if isCommandHeld && keyCode == keyCodeV {
            emit(
                actionType: .paste,
                role: nil,
                label: nil,
                clipboardContentHash: ClipboardContentHasher.hash(of: NSPasteboard.general.string(forType: .string))
            )
            return
        }

        // Other shortcuts are noise.
        if isCommandHeld { return }

        // Navigation / structural keys (Tab between cells, Return, arrows) are
        // not "typing".
        if navigationKeyCodes.contains(keyCode) { return }

        // A plain character keystroke into a focused field = typing. We never
        // capture the text itself; secure fields are elided entirely.
        if AccessibilityElementProbe.isFocusedElementSecure() { return }

        let focused = AccessibilityElementProbe.focusedElementSnapshot()
        guard let role = focused.role, role.contains("TextField") || role.contains("TextArea") else { return }
        emit(actionType: .typeText, role: nil, label: nil)
    }

    /// Records a ⌘C. The source app is read now (synchronously); the clipboard
    /// hash is read a beat later, once the app has actually written it.
    private func handleCopyShortcut() {
        // Mark immediately (synchronously) so the poller's next tick skips this
        // same copy even if it fires before the deferred read below runs.
        recentlyHandledCopyAt = Date()
        let sourceApplicationBundleIdentifier =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            let copiedContentHash =
                ClipboardContentHasher.hash(of: NSPasteboard.general.string(forType: .string))
            self.lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
            self.recentlyHandledCopyAt = Date()
            self.emit(
                actionType: .copy,
                role: nil,
                label: nil,
                clipboardContentHash: copiedContentHash,
                applicationBundleIdentifier: sourceApplicationBundleIdentifier
            )
        }
    }

    // MARK: - Emit

    private func emit(
        actionType: WorkflowActionType,
        role: String?,
        label: String?,
        clipboardContentHash: String? = nil,
        applicationBundleIdentifier: String? = nil
    ) {
        // Secure input is elided absolutely — if the system reports secure event
        // input is on, we record nothing about this keystroke.
        if actionType == .typeText && IsSecureEventInputEnabled() { return }

        let resolvedApplicationBundleIdentifier = applicationBundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ?? "unknown"

        WorkflowDebugLog.log(
            "emit app=\(resolvedApplicationBundleIdentifier) action=\(actionType.rawValue) "
                + "content=\(clipboardContentHash != nil)"
        )

        onEvent?(
            SemanticInputEvent(
                applicationBundleIdentifier: resolvedApplicationBundleIdentifier,
                actionType: actionType,
                targetAccessibilityRole: role,
                targetAccessibilityLabel: label,
                clipboardContentHash: clipboardContentHash
            )
        )
    }
}
