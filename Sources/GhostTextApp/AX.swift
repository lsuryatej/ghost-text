import ApplicationServices
import CoreGraphics

/// Thin, non-throwing wrappers over the Accessibility C API.
///
/// Every call here can fail and that is normal — Electron apps and browser text
/// fields routinely expose partial or unusable AX trees. Nothing in Ghost Text is
/// allowed to depend on these succeeding; AX is used for overlay geometry only.
enum AX {
    /// AX calls block. Electron apps in particular can stall for seconds, which
    /// would freeze the caller. Always bound the wait.
    static let messagingTimeout: Float = 0.25

    static func systemWide() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func raw(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        raw(element, attribute) as? String
    }

    static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func parameterizedAttributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var result = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &result) else { return nil }
        return result
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var result = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &result) else { return nil }
        return result
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var result = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &result) else { return nil }
        return result
    }

    /// Some apps vend `AXFrame` directly; the rest need position and size composed.
    static func frame(_ element: AXUIElement) -> CGRect? {
        if let value = raw(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() {
            var result = CGRect.zero
            if AXValueGetValue((value as! AXValue), .cgRect, &result) { return result }
        }
        guard let origin = point(element, kAXPositionAttribute as String),
              let size = size(element, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The call the whole overlay-positioning design hopes will work.
    static func boundsForRange(_ element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var request = CFRange(location: location, length: length)
        guard let argument = AXValueCreate(.cfRange, &request) else { return nil }

        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            argument,
            &value
        )
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var result = CGRect.zero
        guard AXValueGetValue((value as! AXValue), .cgRect, &result) else { return nil }
        return result
    }

    /// A caret rect is believable when it has real height in a plausible range.
    /// Zero-size rects and absurd heights mean the app handed back garbage.
    static func isPlausibleCaretRect(_ rect: CGRect) -> Bool {
        rect.height >= 4 && rect.height <= 200 && rect.width >= 0 && rect.width < 4000
            && rect.origin.x.isFinite && rect.origin.y.isFinite
    }
}
