//
//  WorkflowDemonstrationMomentTap.swift
//  Perch
//
//  The timeline half of the demonstration recorder: a listen-only CGEvent tap
//  (same shape as LiveEventSource / the old WorkflowRecorder — it never posts
//  events) that timestamps significant moments against the video's start:
//
//    • ⌘C  → .copy   (real clipboard string read on a short settle delay)
//    • ⌘V  → .paste
//    • left click → .click (AX probe of the element under the cursor)
//    • Tab / Return → .navigationKey
//    • plain typing → .typingBurst (CHARACTER COUNT only, never content;
//      secure fields contribute nothing at all)
//    • app activation → .appSwitch (NSWorkspace notification)
//
//  Copy/paste/click moments also carry a bounded AX tree snapshot of the
//  focused window (debounced to at most one per second — snapshots are the
//  expensive part) plus the window's title/document so the analysis stage can
//  name the sources precisely.
//

import AppKit
import CoreGraphics
import Foundation

/// Not actor-isolated (mirrors LiveEventSource / the old WorkflowRecorder):
/// every entry point runs on the main run loop — the CGEvent tap source and the
/// NSWorkspace observer queue are both attached to it.
final class WorkflowDemonstrationMomentTap {

    /// Seconds since the video started rolling — injected by the demonstration
    /// recorder so moment offsets line up with video time.
    private var offsetProvider: () -> TimeInterval = { 0 }

    private var capturedMoments: [DemonstrationMoment] = []
    private var isCapturing = false

    // CGEvent tap plumbing (mirrors LiveEventSource / WorkflowRecorder).
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var appActivationObserver: NSObjectProtocol?

    // Typing burst accumulation: plain keystrokes coalesce into one moment,
    // flushed on a pause or when any other moment kind lands.
    private var pendingTypingBurstCharacterCount = 0
    private var pendingTypingBurstStartOffset: TimeInterval = 0
    private var pendingTypingBurstContext: FocusedWindowContext?
    private var typingBurstFlushTask: Task<Void, Never>?
    private static let typingBurstFlushGapSeconds: TimeInterval = 1.5

    /// AX tree snapshots are debounced — at most one per this interval.
    private var lastTreeSnapshotAt: Date = .distantPast
    private static let treeSnapshotDebounceSeconds: TimeInterval = 1.0

    private let keyCodeC: Int64 = 8
    private let keyCodeV: Int64 = 9
    private let keyCodeTab: Int64 = 48
    private let keyCodeReturn: Int64 = 36

    deinit {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    func start(offsetProvider: @escaping () -> TimeInterval) {
        capturedMoments.removeAll(keepingCapacity: true)
        pendingTypingBurstCharacterCount = 0
        lastTreeSnapshotAt = .distantPast
        self.offsetProvider = offsetProvider
        isCapturing = true
        startTap()
        startAppActivationObserver()
        WorkflowDebugLog.log("momentTap: started")
    }

    /// Stops capturing and returns the timeline, chronologically sorted (the
    /// copy moment's clipboard-settle delay can append slightly out of order).
    func stop() -> [DemonstrationMoment] {
        flushPendingTypingBurst()
        isCapturing = false
        stopTap()
        stopAppActivationObserver()
        let timeline = capturedMoments.sorted { $0.offsetSeconds < $1.offsetSeconds }
        WorkflowDebugLog.log("momentTap: stopped — \(timeline.count) moments")
        return timeline
    }

    // MARK: - Tap lifecycle

    private func startTap() {
        guard eventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.keyDown, .leftMouseDown]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let momentTap = Unmanaged<WorkflowDemonstrationMomentTap>
                .fromOpaque(userInfo).takeUnretainedValue()
            momentTap.handleTapEvent(eventType: eventType, event: event)
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
            WorkflowDebugLog.log("⚠️ momentTap: CGEvent tap creation FAILED (Accessibility?)")
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
    }

    private func stopTap() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func startAppActivationObserver() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedApplication = notification
                .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.recordAppSwitchMoment(to: activatedApplication)
        }
    }

    private func stopAppActivationObserver() {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    // MARK: - Event handling (main run loop)

    private func handleTapEvent(eventType: CGEventType, event: CGEvent) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        guard isCapturing else { return }

        if eventType == .leftMouseDown {
            recordClickMoment(at: event.location)
            return
        }
        guard eventType == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isCommandHeld = event.flags.contains(.maskCommand)

        if isCommandHeld && keyCode == keyCodeC {
            recordCopyMoment()
            return
        }
        if isCommandHeld && keyCode == keyCodeV {
            recordPasteMoment()
            return
        }
        if isCommandHeld { return }

        if keyCode == keyCodeTab {
            recordNavigationKeyMoment("tab")
        } else if keyCode == keyCodeReturn {
            recordNavigationKeyMoment("return")
        } else {
            accumulateTypingKeystroke()
        }
    }

    // MARK: - Moment recording

    private func recordCopyMoment() {
        let momentOffset = offsetProvider()
        // Context captured NOW, while the source app is still frontmost; the
        // clipboard needs a beat after ⌘C before it reflects the copy.
        let windowContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        let isSecureField = AccessibilityElementProbe.isFocusedElementSecure()
        let treeSnapshot = debouncedTreeSnapshot()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.isCapturing else { return }
            self.flushPendingTypingBurst()
            // Never carry a secure field's contents into the timeline.
            let copiedValue = isSecureField
                ? nil
                : NSPasteboard.general.string(forType: .string)
            self.capturedMoments.append(DemonstrationMoment(
                offsetSeconds: momentOffset,
                kind: .copy,
                applicationBundleIdentifier: windowContext.applicationBundleIdentifier,
                applicationName: windowContext.applicationName,
                windowTitle: windowContext.windowTitle,
                documentPathOrURL: windowContext.documentPathOrURL,
                detail: copiedValue,
                focusedWindowTreeSnapshot: treeSnapshot
            ))
            WorkflowDebugLog.log(
                "momentTap: + copy in \(windowContext.applicationBundleIdentifier ?? "?") "
                    + "@\(String(format: "%.1f", momentOffset))s"
            )
        }
    }

    private func recordPasteMoment() {
        flushPendingTypingBurst()
        let windowContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        let focusedElement = AccessibilityElementProbe.focusedElementSnapshot()
        capturedMoments.append(DemonstrationMoment(
            offsetSeconds: offsetProvider(),
            kind: .paste,
            applicationBundleIdentifier: windowContext.applicationBundleIdentifier,
            applicationName: windowContext.applicationName,
            windowTitle: windowContext.windowTitle,
            documentPathOrURL: windowContext.documentPathOrURL,
            focusedElementRole: focusedElement.role,
            focusedElementLabel: focusedElement.label,
            focusedWindowTreeSnapshot: debouncedTreeSnapshot()
        ))
        WorkflowDebugLog.log(
            "momentTap: + paste into \(windowContext.applicationBundleIdentifier ?? "?")"
        )
    }

    private func recordClickMoment(at screenPoint: CGPoint) {
        flushPendingTypingBurst()
        let windowContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        let clickedElement = AccessibilityElementProbe.elementSnapshot(atScreenPoint: screenPoint)
        capturedMoments.append(DemonstrationMoment(
            offsetSeconds: offsetProvider(),
            kind: .click,
            applicationBundleIdentifier: windowContext.applicationBundleIdentifier,
            applicationName: windowContext.applicationName,
            windowTitle: windowContext.windowTitle,
            documentPathOrURL: windowContext.documentPathOrURL,
            focusedElementRole: clickedElement.role,
            focusedElementLabel: clickedElement.label,
            focusedWindowTreeSnapshot: debouncedTreeSnapshot()
        ))
    }

    private func recordNavigationKeyMoment(_ keyName: String) {
        flushPendingTypingBurst()
        let windowContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        capturedMoments.append(DemonstrationMoment(
            offsetSeconds: offsetProvider(),
            kind: .navigationKey,
            applicationBundleIdentifier: windowContext.applicationBundleIdentifier,
            applicationName: windowContext.applicationName,
            windowTitle: windowContext.windowTitle,
            detail: keyName
        ))
    }

    private func recordAppSwitchMoment(to application: NSRunningApplication?) {
        guard isCapturing else { return }
        // Ignore Perch's own surfaces taking key.
        guard application?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        flushPendingTypingBurst()
        capturedMoments.append(DemonstrationMoment(
            offsetSeconds: offsetProvider(),
            kind: .appSwitch,
            applicationBundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.localizedName
        ))
        WorkflowDebugLog.log(
            "momentTap: + appSwitch → \(application?.bundleIdentifier ?? "?")"
        )
    }

    // MARK: - Typing bursts

    private func accumulateTypingKeystroke() {
        // Secure fields contribute nothing — not even a character count.
        guard !AccessibilityElementProbe.isFocusedElementSecure() else { return }

        if pendingTypingBurstCharacterCount == 0 {
            pendingTypingBurstStartOffset = offsetProvider()
            pendingTypingBurstContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        }
        pendingTypingBurstCharacterCount += 1

        // Restart the flush timer: a pause ends the burst. Hops back to the
        // main queue, where all other mutation of this class happens.
        typingBurstFlushTask?.cancel()
        typingBurstFlushTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.typingBurstFlushGapSeconds * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async { self?.flushPendingTypingBurst() }
        }
    }

    private func flushPendingTypingBurst() {
        typingBurstFlushTask?.cancel()
        typingBurstFlushTask = nil
        guard pendingTypingBurstCharacterCount > 0 else { return }
        let burstContext = pendingTypingBurstContext
        capturedMoments.append(DemonstrationMoment(
            offsetSeconds: pendingTypingBurstStartOffset,
            kind: .typingBurst,
            applicationBundleIdentifier: burstContext?.applicationBundleIdentifier,
            applicationName: burstContext?.applicationName,
            windowTitle: burstContext?.windowTitle,
            detail: "\(pendingTypingBurstCharacterCount) characters typed"
        ))
        pendingTypingBurstCharacterCount = 0
        pendingTypingBurstContext = nil
    }

    // MARK: - AX snapshots

    /// A bounded focused-window tree, or nil when one was taken within the
    /// debounce window (snapshots are the expensive part of a moment).
    private func debouncedTreeSnapshot() -> AccessibilityNodeSnapshot? {
        let now = Date()
        guard now.timeIntervalSince(lastTreeSnapshotAt) >= Self.treeSnapshotDebounceSeconds else {
            return nil
        }
        lastTreeSnapshotAt = now
        return AccessibilityTreeSnapshotter.snapshotFocusedWindow()
    }
}
