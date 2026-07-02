//
//  AccessibilityElementProbe.swift
//  Perch
//
//  The "blind" half of the capture layer's grounding: best-effort lookups of
//  the accessibility role/label of the element under the cursor (for clicks) or
//  the currently focused element (for paste/typing). This is what lets a
//  captured event say "click the Add button" instead of "click at (812, 440)".
//
//  Requires the Accessibility permission. It is intentionally dumb — it reads
//  two attributes and never mutates anything — so the only thing to verify when
//  running the signed app is "do the role/label come back populated", a quick
//  manual smoke test rather than an open-ended debugging session.
//

import AppKit
import ApplicationServices

/// A tiny snapshot of one accessibility element: just the fields the detector
/// keys on.
struct AccessibilityElementSnapshot {
    let role: String?
    let label: String?
}

enum AccessibilityElementProbe {

    /// The element directly under the global screen point (used for clicks).
    static func elementSnapshot(atScreenPoint screenPoint: CGPoint) -> AccessibilityElementSnapshot {
        let systemWideElement = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &hitElement
        )
        guard hitResult == .success, let hitElement else {
            return AccessibilityElementSnapshot(role: nil, label: nil)
        }
        return snapshot(of: hitElement)
    }

    /// The currently focused UI element (used for paste / typing).
    static func focusedElementSnapshot() -> AccessibilityElementSnapshot {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        guard focusedResult == .success, let focusedElementValue else {
            return AccessibilityElementSnapshot(role: nil, label: nil)
        }
        // CFTypeRef holding an AXUIElement — safe to treat as such here.
        let focusedElement = focusedElementValue as! AXUIElement
        return snapshot(of: focusedElement)
    }

    /// Whether the focused element is a secure text field (password input). The
    /// capture layer must elide these absolutely.
    static func isFocusedElementSecure() -> Bool {
        let snapshot = focusedElementSnapshot()
        // AX role string for a password field; there is no SDK constant for it.
        return snapshot.role == "AXSecureTextField"
    }

    private static func snapshot(of element: AXUIElement) -> AccessibilityElementSnapshot {
        AccessibilityElementSnapshot(
            role: copyStringAttribute(kAXRoleAttribute, from: element),
            label: bestLabel(for: element)
        )
    }

    /// Prefer a human-meaningful label: title, then description, then value when
    /// it is a short string (e.g. a button rendered as its title).
    private static func bestLabel(for element: AXUIElement) -> String? {
        if let title = copyStringAttribute(kAXTitleAttribute, from: element), !title.isEmpty {
            return title
        }
        if let description = copyStringAttribute(kAXDescriptionAttribute, from: element), !description.isEmpty {
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
}
