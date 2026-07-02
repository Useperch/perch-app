//
//  AccessibilityTreeSnapshotter.swift
//  Perch
//
//  Captures a bounded snapshot of the focused window's accessibility tree —
//  the desktop's "DOM" — for the workflow demonstration recorder (grounding
//  each significant moment) and the agent loop (grounding each perception).
//  Read-only, like AccessibilityElementProbe; never performs actions here.
//
//  Bounded on purpose: depth and node budgets keep a snapshot ~1-2K tokens so
//  several can ride along in one model call. Requires the Accessibility grant
//  the app already holds.
//

import AppKit
import ApplicationServices

/// Window-level identity of where the user currently is: app, window title,
/// and the window's document path or URL when the app exposes one.
struct FocusedWindowContext {
    let applicationBundleIdentifier: String?
    let applicationName: String?
    let windowTitle: String?
    let documentPathOrURL: String?
}

enum AccessibilityTreeSnapshotter {

    /// Element values longer than this are truncated — a giant text view's
    /// full contents would blow the token budget without adding grounding.
    private static let maxValueLength = 80

    /// Roles that the agent can meaningfully click/activate, so only these get a
    /// stable `@eN` ref. Non-interactive containers (groups, static text, etc.)
    /// stay ref-less to keep the token budget on the elements that matter.
    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXMenuItem", "AXMenuButton", "AXPopUpButton", "AXLink", "AXCell",
        "AXRow", "AXTab", "AXComboBox", "AXSlider", "AXDisclosureTriangle",
    ]

    // MARK: - Focused window context

    /// Best-effort identity of the frontmost app's focused window.
    static func focusedWindowContext() -> FocusedWindowContext {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard let processIdentifier = frontmostApplication?.processIdentifier else {
            return FocusedWindowContext(
                applicationBundleIdentifier: nil,
                applicationName: nil,
                windowTitle: nil,
                documentPathOrURL: nil
            )
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute, from: applicationElement
        )

        var windowTitle: String?
        var documentPathOrURL: String?
        if let focusedWindow {
            windowTitle = copyStringAttribute(kAXTitleAttribute, from: focusedWindow)
            // AXDocument carries a file path/URL for document windows; AXURL
            // (no SDK constant) carries the page URL in browsers.
            documentPathOrURL = copyStringAttribute(kAXDocumentAttribute, from: focusedWindow)
                ?? copyURLAttribute("AXURL", from: focusedWindow)

            // Many browsers (Chrome, Edge, Brave, Arc, Firefox) DON'T expose the
            // page URL on the window element — it lives on a descendant AXWebArea.
            // Safari does expose it at the window, so this fallback only kicks in
            // for the others, and only for known browsers (bounded search, skipped
            // for every other app so the 0.75s context monitor stays cheap).
            if documentPathOrURL == nil,
               let bundleIdentifier = frontmostApplication?.bundleIdentifier,
               Self.browserBundleIdentifiers.contains(bundleIdentifier) {
                documentPathOrURL = findURLInDescendants(of: focusedWindow)
            }
        }

        return FocusedWindowContext(
            applicationBundleIdentifier: frontmostApplication?.bundleIdentifier,
            applicationName: frontmostApplication?.localizedName,
            windowTitle: windowTitle,
            documentPathOrURL: documentPathOrURL
        )
    }

    /// Browsers whose page URL is often NOT on the window element (it's on a
    /// descendant AXWebArea), so `focusedWindowContext` does a bounded descendant
    /// search for them. Safari is included: in practice its window-level
    /// AXDocument/AXURL frequently come back nil and the URL is only reachable on
    /// the AXWebArea (confirmed via the integrations-debug log).
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// Breadth-first search of a browser window's subtree for the first element
    /// exposing an `AXURL` (the active tab's web area), bounded so it stays cheap
    /// enough to run on the 0.75s context-monitor tick. Returns the URL string or nil.
    private static func findURLInDescendants(
        of windowElement: AXUIElement,
        maxNodesSearched: Int = 400
    ) -> String? {
        var nodesSearched = 0
        var searchQueue: [AXUIElement] = [windowElement]
        while !searchQueue.isEmpty, nodesSearched < maxNodesSearched {
            let element = searchQueue.removeFirst()
            nodesSearched += 1
            // The canonical page URL lives on the AXWebArea's AXURL. Only accept
            // an http(s) URL so we don't pick up a stray file:// or about: value.
            if let url = copyURLAttribute("AXURL", from: element),
               url.hasPrefix("http://") || url.hasPrefix("https://") {
                return url
            }
            searchQueue.append(contentsOf: copyChildren(of: element))
        }
        return nil
    }

    // MARK: - Tree snapshot

    /// Snapshot of the frontmost app's focused window, bounded by depth and a
    /// global node budget. Returns nil when there is no focused window or the
    /// Accessibility grant is missing.
    static func snapshotFocusedWindow(
        maxDepth: Int = 4,
        maxNodes: Int = 120
    ) -> AccessibilityNodeSnapshot? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute, from: applicationElement
        ) else {
            return nil
        }
        var remainingNodeBudget = maxNodes
        return snapshotNode(
            focusedWindow,
            remainingDepth: maxDepth,
            remainingNodeBudget: &remainingNodeBudget
        )
    }

    private static func snapshotNode(
        _ element: AXUIElement,
        remainingDepth: Int,
        remainingNodeBudget: inout Int
    ) -> AccessibilityNodeSnapshot? {
        guard remainingNodeBudget > 0 else { return nil }
        remainingNodeBudget -= 1

        let role = copyStringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown"
        let label = bestLabel(for: element)

        // Secure fields' values are NEVER captured.
        var value: String?
        if role != "AXSecureTextField",
           let rawValue = copyStringAttribute(kAXValueAttribute, from: element),
           !rawValue.isEmpty {
            value = String(rawValue.prefix(maxValueLength))
        }

        let frame = copyFrame(of: element)

        var childSnapshots: [AccessibilityNodeSnapshot] = []
        if remainingDepth > 0 {
            for childElement in copyChildren(of: element) {
                guard remainingNodeBudget > 0 else { break }
                if let childSnapshot = snapshotNode(
                    childElement,
                    remainingDepth: remainingDepth - 1,
                    remainingNodeBudget: &remainingNodeBudget
                ) {
                    childSnapshots.append(childSnapshot)
                }
            }
        }

        return AccessibilityNodeSnapshot(
            role: role,
            label: label,
            value: value,
            frame: frame,
            children: childSnapshots
        )
    }

    // MARK: - Ref-aware snapshot (for the agent loop's stable click targeting)

    /// Same bounded snapshot as `snapshotFocusedWindow`, but additionally assigns a
    /// stable `eN` ref to each interactive element and returns a `ref → live
    /// AXUIElement` map. The agent picks an element by its `@eN` ref (exact),
    /// and the actuator resolves that ref against this map — avoiding the
    /// ambiguity of matching by role+label when several elements share both.
    ///
    /// The returned `AXUIElement`s are live references that can go stale if the UI
    /// changes before the agent acts; `elementIsLive(_:expectedRole:)` detects that.
    static func snapshotFocusedWindowWithRefs(
        maxDepth: Int = 4,
        maxNodes: Int = 120
    ) -> (snapshot: AccessibilityNodeSnapshot, refResolutionMap: [String: ResolvedAccessibilityElement])? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute, from: applicationElement
        ) else {
            return nil
        }
        var remainingNodeBudget = maxNodes
        var nextRefNumber = 1
        var refResolutionMap: [String: ResolvedAccessibilityElement] = [:]
        guard let snapshot = snapshotNodeWithRefs(
            focusedWindow,
            remainingDepth: maxDepth,
            remainingNodeBudget: &remainingNodeBudget,
            nextRefNumber: &nextRefNumber,
            refResolutionMap: &refResolutionMap
        ) else {
            return nil
        }
        return (snapshot, refResolutionMap)
    }

    private static func snapshotNodeWithRefs(
        _ element: AXUIElement,
        remainingDepth: Int,
        remainingNodeBudget: inout Int,
        nextRefNumber: inout Int,
        refResolutionMap: inout [String: ResolvedAccessibilityElement]
    ) -> AccessibilityNodeSnapshot? {
        guard remainingNodeBudget > 0 else { return nil }
        remainingNodeBudget -= 1

        let role = copyStringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown"
        let label = bestLabel(for: element)

        // Secure fields' values are NEVER captured.
        var value: String?
        if role != "AXSecureTextField",
           let rawValue = copyStringAttribute(kAXValueAttribute, from: element),
           !rawValue.isEmpty {
            value = String(rawValue.prefix(maxValueLength))
        }

        let frame = copyFrame(of: element)

        // Only interactive elements earn a ref + a slot in the resolution map.
        var ref: String?
        if interactiveRoles.contains(role) {
            let assignedRef = "e\(nextRefNumber)"
            nextRefNumber += 1
            ref = assignedRef
            refResolutionMap[assignedRef] = ResolvedAccessibilityElement(
                element: element, role: role, label: label
            )
        }

        var childSnapshots: [AccessibilityNodeSnapshot] = []
        if remainingDepth > 0 {
            for childElement in copyChildren(of: element) {
                guard remainingNodeBudget > 0 else { break }
                if let childSnapshot = snapshotNodeWithRefs(
                    childElement,
                    remainingDepth: remainingDepth - 1,
                    remainingNodeBudget: &remainingNodeBudget,
                    nextRefNumber: &nextRefNumber,
                    refResolutionMap: &refResolutionMap
                ) {
                    childSnapshots.append(childSnapshot)
                }
            }
        }

        return AccessibilityNodeSnapshot(
            role: role,
            label: label,
            value: value,
            frame: frame,
            ref: ref,
            children: childSnapshots
        )
    }

    /// Whether a ref's element is still the element the agent saw: re-reads its
    /// role and confirms it still matches. A read failure (the element was
    /// destroyed when the UI changed) or a role mismatch means the ref is stale.
    static func elementIsLive(_ element: AXUIElement, expectedRole: String) -> Bool {
        guard let currentRole = copyStringAttribute(kAXRoleAttribute, from: element) else {
            return false
        }
        return currentRole == expectedRole
    }

    // MARK: - Element lookup (for the agent's click_element action)

    /// Depth-first search of the frontmost app's focused window for an element
    /// matching role + label (same label derivation the snapshot uses), so the
    /// agent can act on elements it saw in a snapshot. Returns the live
    /// AXUIElement, which the actuator can press or locate.
    static func findElementInFocusedWindow(
        role targetRole: String,
        label targetLabel: String,
        maxNodesSearched: Int = 600
    ) -> AXUIElement? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute, from: applicationElement
        ) else {
            return nil
        }

        var nodesSearched = 0
        var searchStack: [AXUIElement] = [focusedWindow]
        while let element = searchStack.popLast(), nodesSearched < maxNodesSearched {
            nodesSearched += 1
            let role = copyStringAttribute(kAXRoleAttribute, from: element)
            if role == targetRole, bestLabel(for: element) == targetLabel {
                return element
            }
            searchStack.append(contentsOf: copyChildren(of: element))
        }
        return nil
    }

    /// The frontmost app's focused window frame in screen points (top-left
    /// origin, the space AX frames + CGEvent clicks use), or nil when there is
    /// no focused window. Used to anchor the Excel grid origin on screen so an
    /// agent cursor can fly to the exact cell it is writing.
    static func focusedWindowFrame() -> CGRect? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute, from: applicationElement
        ) else {
            return nil
        }
        return copyFrame(of: focusedWindow)
    }

    /// The element's screen frame in points (AX position is top-left-origin
    /// global screen coordinates — the same space CGEvent clicks use).
    static func copyFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        // CFTypeRef holding AXValue — guarded by the .success results above.
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Attribute helpers

    /// Same label preference order as AccessibilityElementProbe: title, then
    /// description, then a short value.
    private static func bestLabel(for element: AXUIElement) -> String? {
        if let title = copyStringAttribute(kAXTitleAttribute, from: element), !title.isEmpty {
            return title
        }
        if let description = copyStringAttribute(kAXDescriptionAttribute, from: element),
           !description.isEmpty {
            return description
        }
        if let value = copyStringAttribute(kAXValueAttribute, from: element),
           !value.isEmpty, value.count <= 64 {
            return value
        }
        return nil
    }

    private static func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var attributeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &attributeValue)
        guard result == .success else { return nil }
        return attributeValue as? String
    }

    /// Attributes (like AXURL) that come back as NSURL rather than String.
    private static func copyURLAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var attributeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &attributeValue)
        guard result == .success else { return nil }
        if let url = attributeValue as? URL { return url.absoluteString }
        return attributeValue as? String
    }

    private static func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var attributeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &attributeValue)
        guard result == .success, let attributeValue else { return nil }
        // CFTypeRef holding an AXUIElement — safe given the attribute semantics.
        return (attributeValue as! AXUIElement)
    }

    private static func copyChildren(of element: AXUIElement) -> [AXUIElement] {
        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenValue
        )
        guard result == .success, let childArray = childrenValue as? [AXUIElement] else {
            return []
        }
        return childArray
    }
}
