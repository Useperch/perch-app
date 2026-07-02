//
//  WorkflowAgentActuator.swift
//  Perch
//
//  Executes ONE agent action against the user's real desktop. This is the only
//  place in the app that *posts* events (every CGEvent tap elsewhere is
//  listen-only). The keyboard/clipboard/AppleScript primitives are lifted from
//  the verified old WorkflowExecutor — including the real-modifier chord
//  workaround Microsoft Office needs and the AppleScript string escaping.
//
//  Safety gates, enforced on EVERY action:
//    • keep synthetic input on the app the task targets — bring it frontmost if
//      focus drifted, refuse rather than type/paste into the wrong app
//    • never act while Perch itself is frontmost
//    • never type/paste into a secure (password) field
//    • every AppleScript source is logged verbatim BEFORE execution (the audit
//      trail for model-authored automation)
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class WorkflowAgentActuator: WorkflowActionPerforming {

    /// Virtual key codes (US layout), matching the listen-only taps.
    private static let keyCodeByPressableKey: [WorkflowAgentPressableKey: CGKeyCode] = [
        .tab: 48, .return: 36, .escape: 53, .delete: 51, .space: 49,
        .left: 123, .right: 124, .down: 125, .up: 126,
        .pageup: 116, .pagedown: 121, .home: 115, .end: 119,
    ]

    /// Virtual key codes for plain letters and digits (US ANSI layout), so the
    /// agent can press chords like ⌘C / ⌘A.
    private static let keyCodeByCharacter: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
        "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
        "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28,
        "9": 25, "0": 29,
    ]

    /// Real modifier key codes (US layout) and their event flags. We post a real
    /// modifier keyDown/keyUp around the key (not just the flag) because Office
    /// apps track physical modifier state and drop flag-only synthetic chords.
    private static let modifierKeyCodeAndFlag:
        [WorkflowAgentKeyModifier: (keyCode: CGKeyCode, flag: CGEventFlags)] = [
            .command: (55, .maskCommand),
            .shift: (56, .maskShift),
            .option: (58, .maskAlternate),
            .control: (59, .maskControl),
        ]

    private static let keyCodeV: CGKeyCode = 9

    /// Pacing so the destination app keeps up with synthesized input (same
    /// values the verified executor used).
    private let delayAfterClipboardSetNanoseconds: UInt64 = 60_000_000   // 60 ms
    private let delayBetweenTypedCharactersNanoseconds: UInt64 = 25_000_000  // 25 ms
    private let delayBetweenClickPhasesNanoseconds: UInt64 = 40_000_000  // 40 ms

    private var savedClipboardString: String?

    /// Whether this actuator owns the clipboard save/restore around a run. True
    /// for a normal agent run (it restores the user's clipboard when the run
    /// ends); a caller doing its own clipboard save/restore can pass false.
    private let managesClipboard: Bool

    init(managesClipboard: Bool = true) {
        self.managesClipboard = managesClipboard
    }

    func beginRun() {
        guard managesClipboard else { return }
        savedClipboardString = NSPasteboard.general.string(forType: .string)
    }

    func endRun() {
        guard managesClipboard else { return }
        NSPasteboard.general.clearContents()
        if let savedClipboardString {
            NSPasteboard.general.setString(savedClipboardString, forType: .string)
        }
        savedClipboardString = nil
    }

    func perform(
        _ action: WorkflowAgentAction,
        perception: WorkflowAgentPerception
    ) async -> WorkflowAgentActionOutcome {
        // Gate: keep synthetic input on the app this task targets. If focus has
        // drifted to another app (a stray ⌘TAB, a window that stole focus), a blind
        // ⌘V / keystroke would land in the WRONG app — this is the bug where an
        // essay meant for Word got pasted into a terminal and a browser. Only the
        // input-synthesizing actions are guarded; clicks/scrolls are position-
        // targeted, and AppleScript/shell don't depend on keyboard focus.
        if let targetBundleIdentifier = perception.targetApplicationBundleIdentifier {
            switch action {
            case .typeText, .pasteText, .pressKey:
                if let refusal = await ensureTargetIsFrontmost(targetBundleIdentifier) {
                    return refusal
                }
            default:
                break
            }
        }

        // Gate: never synthesize into Perch itself (e.g. focus bounced back).
        // `run_shell` is exempt — it synthesizes no input into the frontmost app
        // (it generates files / runs scripts), so it must work even when Perch
        // itself happens to be frontmost.
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontmostBundleIdentifier == Bundle.main.bundleIdentifier {
            if case .runShell = action {} else {
                return WorkflowAgentActionOutcome(
                    succeeded: false,
                    resultDescription: "REFUSED: Perch itself is the frontmost app — switch focus to the workflow's app first (click on it)."
                )
            }
        }

        switch action {
        case .clickElement(let ref, let role, let label):
            return await clickElement(
                ref: ref, role: role, label: label, perception: perception
            )
        case .clickAt(let xPixels, let yPixels):
            return await clickAtScreenshotPixels(
                xPixels: xPixels, yPixels: yPixels, perception: perception
            )
        case .typeText(let text):
            return await typeTextIntoFocusedElement(text)
        case .pasteText(let text):
            return await pasteTextIntoFocusedElement(text)
        case .pressKey(let key, let modifiers):
            return pressKey(key: key, modifiers: modifiers)
        case .scroll(let xPixels, let yPixels, let scrollDown, let lineCount):
            return scrollAtScreenshotPixels(
                xPixels: xPixels, yPixels: yPixels, scrollDown: scrollDown,
                lineCount: lineCount, perception: perception
            )
        case .runAppleScript(let source):
            return runAppleScript(source: source)
        case .runShell(let command):
            return await runShell(command: command)
        case .done, .fail:
            // Terminal actions end the loop before reaching the actuator.
            return WorkflowAgentActionOutcome(succeeded: true, resultDescription: "No-op.")
        }
    }

    // MARK: - Clicking

    /// Resolve a click target ref-first (exact, against the snapshot the agent
    /// saw), then by role+label (fallback). A ref whose element changed under us
    /// or a name that no longer exists yields a machine-readable recovery code
    /// (`STALE_REF:` / `ELEMENT_NOT_FOUND:`) so Core re-perceives and retries
    /// instead of clicking the wrong thing.
    private func clickElement(
        ref: String?,
        role: String?,
        label: String?,
        perception: WorkflowAgentPerception
    ) async -> WorkflowAgentActionOutcome {
        // 1. Exact ref against the snapshot the agent reasoned over.
        if let ref {
            if let resolved = perception.refResolutionMap[ref] {
                guard AccessibilityTreeSnapshotter.elementIsLive(
                    resolved.element, expectedRole: resolved.role
                ) else {
                    return WorkflowAgentActionOutcome(
                        succeeded: false,
                        resultDescription: "STALE_REF: @\(ref) no longer matches a live \(resolved.role) — the UI changed. Re-read the accessibility tree and target the element again."
                    )
                }
                return await pressOrClick(
                    element: resolved.element,
                    targetDescription: targetDescription(role: resolved.role, label: resolved.label)
                )
            }
            // A ref the current snapshot doesn't know about — only usable if the
            // model also named a role+label to fall back on.
            if role == nil || label == nil {
                return WorkflowAgentActionOutcome(
                    succeeded: false,
                    resultDescription: "STALE_REF: @\(ref) is not in the current accessibility tree. Re-read the tree and target the element again."
                )
            }
        }

        // 2. Fallback: first element matching role + label in the live tree.
        guard let role, let label else {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "ELEMENT_NOT_FOUND: click_element needs a ref or a role+label."
            )
        }
        guard let element = AccessibilityTreeSnapshotter.findElementInFocusedWindow(
            role: role, label: label
        ) else {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "ELEMENT_NOT_FOUND: no \(role) \"\(label)\" in the focused window — check the accessibility context for the actual role/label/ref, or use click_at."
            )
        }
        return await pressOrClick(
            element: element,
            targetDescription: targetDescription(role: role, label: label)
        )
    }

    /// Press an element via its AX press action, falling back to a synthesized
    /// click at its center when the element doesn't support pressing.
    private func pressOrClick(
        element: AXUIElement,
        targetDescription: String
    ) async -> WorkflowAgentActionOutcome {
        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if pressResult == .success {
            return WorkflowAgentActionOutcome(
                succeeded: true,
                resultDescription: "Pressed \(targetDescription) via accessibility."
            )
        }

        guard let elementFrame = AccessibilityTreeSnapshotter.copyFrame(of: element) else {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "\(targetDescription) exists but can't be pressed and has no frame to click."
            )
        }
        // AX frames are global top-left-origin screen points — the same space
        // CGEvent mouse positions use. No conversion needed.
        await postSyntheticClick(at: CGPoint(x: elementFrame.midX, y: elementFrame.midY))
        return WorkflowAgentActionOutcome(
            succeeded: true,
            resultDescription: "Clicked the center of \(targetDescription) at (\(Int(elementFrame.midX)), \(Int(elementFrame.midY)))."
        )
    }

    /// A human-readable name for a click target, e.g. `AXButton "Save"` or just
    /// `AXCell` when the element exposed no label.
    private func targetDescription(role: String, label: String?) -> String {
        if let label, !label.isEmpty {
            return "\(role) \"\(label)\""
        }
        return role
    }

    private func clickAtScreenshotPixels(
        xPixels: Int, yPixels: Int, perception: WorkflowAgentPerception
    ) async -> WorkflowAgentActionOutcome {
        switch screenPointFromScreenshotPixels(
            xPixels: xPixels, yPixels: yPixels, perception: perception
        ) {
        case .failure(let failureOutcome):
            return failureOutcome
        case .success(let clickPoint):
            await postSyntheticClick(at: clickPoint)
            return WorkflowAgentActionOutcome(
                succeeded: true,
                resultDescription: "Clicked at screenshot pixel (\(xPixels), \(yPixels)) → screen point (\(Int(clickPoint.x)), \(Int(clickPoint.y)))."
            )
        }
    }

    private func scrollAtScreenshotPixels(
        xPixels: Int, yPixels: Int, scrollDown: Bool, lineCount: Int,
        perception: WorkflowAgentPerception
    ) -> WorkflowAgentActionOutcome {
        switch screenPointFromScreenshotPixels(
            xPixels: xPixels, yPixels: yPixels, perception: perception
        ) {
        case .failure(let failureOutcome):
            return failureOutcome
        case .success(let scrollPoint):
            let eventSource = CGEventSource(stateID: .combinedSessionState)
            // Negative wheel delta scrolls the content up (revealing what is
            // BELOW), matching a physical wheel rolled toward the user.
            let wheelDelta = Int32(scrollDown ? -lineCount : lineCount)
            if let scrollEvent = CGEvent(
                scrollWheelEvent2Source: eventSource, units: .line,
                wheelCount: 1, wheel1: wheelDelta, wheel2: 0, wheel3: 0
            ) {
                // Scroll events are routed by position, not keyboard focus —
                // the location IS the targeting.
                scrollEvent.location = scrollPoint
                scrollEvent.post(tap: .cghidEventTap)
            }
            return WorkflowAgentActionOutcome(
                succeeded: true,
                resultDescription: "Scrolled \(scrollDown ? "down" : "up") \(lineCount) lines at screenshot pixel (\(xPixels), \(yPixels))."
            )
        }
    }

    /// Outcome of converting model-supplied screenshot pixels to a screen
    /// point: the point, or the failure to feed back to the model.
    private enum ScreenPointConversion {
        case success(CGPoint)
        case failure(WorkflowAgentActionOutcome)
    }

    /// Screenshot pixels → display points (the screenshot covers exactly
    /// displayFrame), then AppKit bottom-left-origin → CG top-left-origin
    /// global coordinates for the event. Same conversion shape the companion's
    /// [POINT:x,y] pointing path uses.
    private func screenPointFromScreenshotPixels(
        xPixels: Int, yPixels: Int, perception: WorkflowAgentPerception
    ) -> ScreenPointConversion {
        guard perception.screenshotWidthInPixels > 0, perception.screenshotHeightInPixels > 0 else {
            return .failure(WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "No screenshot geometry available to convert pixel coordinates."
            ))
        }
        guard xPixels >= 0, xPixels <= perception.screenshotWidthInPixels,
              yPixels >= 0, yPixels <= perception.screenshotHeightInPixels else {
            return .failure(WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "Coordinates (\(xPixels), \(yPixels)) fall outside the \(perception.screenshotWidthInPixels)x\(perception.screenshotHeightInPixels) screenshot."
            ))
        }

        let scaleX = perception.displayFrame.width / CGFloat(perception.screenshotWidthInPixels)
        let scaleY = perception.displayFrame.height / CGFloat(perception.screenshotHeightInPixels)
        let appKitX = perception.displayFrame.minX + CGFloat(xPixels) * scaleX
        let appKitY = perception.displayFrame.maxY - CGFloat(yPixels) * scaleY
        let primaryScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?
            .frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        return .success(CGPoint(x: appKitX, y: primaryScreenHeight - appKitY))
    }

    private func postSyntheticClick(at globalTopLeftPoint: CGPoint) async {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        if let mouseDownEvent = CGEvent(
            mouseEventSource: eventSource, mouseType: .leftMouseDown,
            mouseCursorPosition: globalTopLeftPoint, mouseButton: .left
        ) {
            mouseDownEvent.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(nanoseconds: delayBetweenClickPhasesNanoseconds)
        if let mouseUpEvent = CGEvent(
            mouseEventSource: eventSource, mouseType: .leftMouseUp,
            mouseCursorPosition: globalTopLeftPoint, mouseButton: .left
        ) {
            mouseUpEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Focus targeting

    /// Make sure the app this task targets is frontmost before we synthesize input
    /// into it. If focus has drifted, bring the target app forward and re-check; if
    /// it still isn't frontmost, return a refusal so the caller feeds it back to the
    /// model instead of pasting into the wrong window. Returns `nil` when the target
    /// is (or becomes) frontmost and the action may proceed.
    private func ensureTargetIsFrontmost(
        _ targetBundleIdentifier: String
    ) async -> WorkflowAgentActionOutcome? {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleIdentifier {
            return nil
        }
        // Focus drifted — try to bring the target app forward, then give it a beat
        // to actually become frontmost before we re-check.
        if let targetApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: targetBundleIdentifier
        ).first {
            targetApplication.activate(options: [])
            try? await Task.sleep(nanoseconds: delayAfterClipboardSetNanoseconds)
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleIdentifier {
            return nil
        }
        let actualFrontmost =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        return WorkflowAgentActionOutcome(
            succeeded: false,
            resultDescription: "REFUSED: the target app (\(targetBundleIdentifier)) is not frontmost — \(actualFrontmost) is. Not sending keystrokes into the wrong app; bring the target app forward and retry."
        )
    }

    // MARK: - Typing & pasting

    private func typeTextIntoFocusedElement(_ text: String) async -> WorkflowAgentActionOutcome {
        if AccessibilityElementProbe.isFocusedElementSecure() {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "REFUSED: the focused element is a secure (password) field."
            )
        }
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        for character in text {
            let unicodeScalars = Array(String(character).utf16)
            if let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
                keyDownEvent.keyboardSetUnicodeString(
                    stringLength: unicodeScalars.count, unicodeString: unicodeScalars
                )
                keyDownEvent.post(tap: .cghidEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(
                    stringLength: unicodeScalars.count, unicodeString: unicodeScalars
                )
                keyUpEvent.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: delayBetweenTypedCharactersNanoseconds)
        }
        return WorkflowAgentActionOutcome(
            succeeded: true,
            resultDescription: "Typed \(text.count) characters."
        )
    }

    private func pasteTextIntoFocusedElement(_ text: String) async -> WorkflowAgentActionOutcome {
        if AccessibilityElementProbe.isFocusedElementSecure() {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "REFUSED: the focused element is a secure (password) field."
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try? await Task.sleep(nanoseconds: delayAfterClipboardSetNanoseconds)
        postKeyChord(keyCode: Self.keyCodeV, modifiers: [.command])
        return WorkflowAgentActionOutcome(
            succeeded: true,
            resultDescription: "Pasted \"\(text.prefix(48))\(text.count > 48 ? "…" : "")\" via ⌘V."
        )
    }

    // MARK: - Keys

    private func pressKey(
        key: String, modifiers: Set<WorkflowAgentKeyModifier>
    ) -> WorkflowAgentActionOutcome {
        let keyCode: CGKeyCode
        if let pressableKey = WorkflowAgentPressableKey(rawValue: key),
           let specialKeyCode = Self.keyCodeByPressableKey[pressableKey] {
            keyCode = specialKeyCode
        } else if key.count == 1, let character = key.first,
                  let characterKeyCode = Self.keyCodeByCharacter[character] {
            keyCode = characterKeyCode
        } else {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "Unknown key \"\(key)\"."
            )
        }
        postKeyChord(keyCode: keyCode, modifiers: modifiers)
        return WorkflowAgentActionOutcome(
            succeeded: true,
            resultDescription: "Pressed \(Self.describeChord(key: key, modifiers: modifiers))."
        )
    }

    /// Renders a chord for the result log, e.g. ⌘C or ⇧⌘Z (Cocoa modifier order).
    private static func describeChord(
        key: String, modifiers: Set<WorkflowAgentKeyModifier>
    ) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + key.uppercased()
    }

    /// Posts a key down+up at the HID level. For each held modifier we post a
    /// REAL modifier keyDown/keyUp around the key, not just the flag — Microsoft
    /// Office apps track physical modifier state and silently drop flag-only
    /// synthetic chords.
    private func postKeyChord(keyCode: CGKeyCode, modifiers: Set<WorkflowAgentKeyModifier>) {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        let heldModifiers = modifiers.compactMap { Self.modifierKeyCodeAndFlag[$0] }
        let combinedFlags = heldModifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) }

        // Press each modifier down (real keyDown) before the key.
        for modifier in heldModifiers {
            if let modifierDownEvent = CGEvent(
                keyboardEventSource: eventSource, virtualKey: modifier.keyCode, keyDown: true
            ) {
                modifierDownEvent.flags = combinedFlags
                modifierDownEvent.post(tap: .cghidEventTap)
            }
        }

        if let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true) {
            keyDownEvent.flags = combinedFlags
            keyDownEvent.post(tap: .cghidEventTap)
        }
        if let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) {
            keyUpEvent.flags = combinedFlags
            keyUpEvent.post(tap: .cghidEventTap)
        }

        // Release each modifier (real keyUp) after the key.
        for modifier in heldModifiers.reversed() {
            if let modifierUpEvent = CGEvent(
                keyboardEventSource: eventSource, virtualKey: modifier.keyCode, keyDown: false
            ) {
                modifierUpEvent.flags = []
                modifierUpEvent.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - AppleScript

    private func runAppleScript(source: String) -> WorkflowAgentActionOutcome {
        // The audit trail: the EXACT model-authored script, logged before it
        // can do anything.
        WorkflowDebugLog.log("actuator: applescript >>>\n\(source)\n<<<")

        var executionErrorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&executionErrorInfo)
        if let executionErrorInfo {
            let errorMessage = (executionErrorInfo[NSAppleScript.errorMessage] as? String)
                ?? "AppleScript error \(executionErrorInfo[NSAppleScript.errorNumber] ?? "?")"
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "AppleScript failed: \(errorMessage)"
            )
        }
        return WorkflowAgentActionOutcome(
            succeeded: true,
            resultDescription: "AppleScript ran without error."
        )
    }

    // MARK: - Shell

    /// How long a single `run_shell` command may run before it is killed. Long
    /// enough to generate a file or fetch from an API; short enough that a hung
    /// command can't stall the run.
    private static let shellCommandTimeoutSeconds: TimeInterval = 60

    /// The most output text threaded back to the model, so a chatty command
    /// can't blow the decision token budget.
    private static let shellOutputMaxCharacters = 4000

    /// Run a model-authored shell command in the repo scratch directory and
    /// return its combined stdout+stderr to the model. The general
    /// code-execution path: generate a file in its native format and `open` it,
    /// fetch data from an API, or run any other scripted task.
    private func runShell(command: String) async -> WorkflowAgentActionOutcome {
        // The audit trail: the EXACT model-authored command, logged before it
        // can do anything.
        WorkflowDebugLog.log("actuator: run_shell >>>\n\(command)\n<<<")

        // Confine the command's working directory to a repo scratch folder
        // (on-disk state stays in the repo — see CLAUDE.md), and overlay any
        // repo-local `.env` keys so the command can reach configured services.
        let scratchDirectoryURL = PerchSupportPaths.directory("agent-scratch")
        let subprocessEnvironment = WorkflowAgentActuator.subprocessEnvironment()

        // Run the process off the main actor so a slow command never stalls the
        // UI; the work blocks on a background queue and resumes the continuation.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = WorkflowAgentActuator.executeShellCommand(
                    command,
                    workingDirectoryURL: scratchDirectoryURL,
                    environment: subprocessEnvironment
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    /// The environment a `run_shell` subprocess sees: the (minimal, when
    /// GUI-launched) inherited environment overlaid with every `<repo>/.env`
    /// pair, so a configured key like `EXA_API_KEY` reaches model-authored code.
    private static func subprocessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in DotEnvConfiguration.allValues {
            environment[key] = value
        }
        return environment
    }

    /// Blocking process execution (called on a background queue). Captures
    /// stdout+stderr together, enforces a hard timeout (terminating a command
    /// that overruns), and reports the exit status. Reads the output pipe on its
    /// own thread so a chatty command can't deadlock against a full pipe buffer.
    private static func executeShellCommand(
        _ command: String,
        workingDirectoryURL: URL,
        environment: [String: String]
    ) -> WorkflowAgentActionOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectoryURL
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Drain the pipe on a background thread, so the child never blocks
        // writing into a full buffer while we wait for it to exit.
        var collectedOutputData = Data()
        let outputReadGroup = DispatchGroup()
        outputReadGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            collectedOutputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputReadGroup.leave()
        }

        // Signal exit via the termination handler so we can wait with a timeout.
        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exitSemaphore.signal() }

        do {
            try process.run()
        } catch {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "Shell command could not start: \(error.localizedDescription)"
            )
        }

        var didTimeOut = false
        if exitSemaphore.wait(timeout: .now() + shellCommandTimeoutSeconds) == .timedOut {
            didTimeOut = true
            process.terminate() // SIGTERM
            // Give the terminated process a brief moment to actually exit so the
            // pipe closes and the reader thread can finish; if it ignores SIGTERM,
            // SIGKILL it so the reader can never hang this turn indefinitely.
            if exitSemaphore.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exitSemaphore.wait(timeout: .now() + 2)
            }
        }
        outputReadGroup.wait()

        let rawOutput = String(data: collectedOutputData, encoding: .utf8) ?? ""
        let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputForModel = WorkflowAgentActuator.truncatedForModel(trimmedOutput)

        if didTimeOut {
            return WorkflowAgentActionOutcome(
                succeeded: false,
                resultDescription: "Shell command timed out after \(Int(shellCommandTimeoutSeconds))s and was terminated. Output so far:\n\(outputForModel)"
            )
        }

        let exitStatus = process.terminationStatus
        if exitStatus == 0 {
            let outputSuffix = outputForModel.isEmpty ? " (no output)" : ":\n\(outputForModel)"
            return WorkflowAgentActionOutcome(
                succeeded: true,
                resultDescription: "Shell command exited 0\(outputSuffix)"
            )
        }
        return WorkflowAgentActionOutcome(
            succeeded: false,
            resultDescription: "Shell command exited \(exitStatus):\n\(outputForModel)"
        )
    }

    /// Trim captured output to the model-facing cap, keeping the tail (where an
    /// error message usually is) and noting how much was dropped.
    private static func truncatedForModel(_ text: String) -> String {
        guard text.count > shellOutputMaxCharacters else { return text }
        let keptTail = text.suffix(shellOutputMaxCharacters)
        let droppedCharacterCount = text.count - keptTail.count
        return "…[\(droppedCharacterCount) earlier characters omitted]\n\(keptTail)"
    }
}
