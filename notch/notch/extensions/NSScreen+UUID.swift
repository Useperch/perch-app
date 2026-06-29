//
//  NSScreen+UUID.swift
//  notch
//
//  Created by Alexander on 2025-11-21.
//

import AppKit
import CoreGraphics

extension NSScreen {
    /// Returns a persistent UUID for this display
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        return uuidString
    }
    
    /// Find a screen by its UUID
    @MainActor static func screen(withUUID uuid: String) -> NSScreen? {
        return NSScreenUUIDCache.shared.screen(forUUID: uuid)
    }

    /// The Mac's built-in display — where the physical notch lives — or nil if the
    /// only displays attached are external.
    ///
    /// Detection prefers `CGDisplayIsBuiltin`, which is reliable the moment the app
    /// launches. We do NOT rely on `safeAreaInsets.top > 0` alone because that can
    /// momentarily read 0 during launch before the window server reports the notch,
    /// which previously stranded Perch's notch on an external monitor.
    static var builtInNotchScreen: NSScreen? {
        // Primary: the literal built-in display (the laptop's own screen).
        if let builtIn = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) == 1
        }) {
            return builtIn
        }
        // Fallback: any screen reporting a notch safe-area inset.
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
    }
    
    /// Get UUID to NSScreen mapping for all screens
    @MainActor static var screensByUUID: [String: NSScreen] {
        return NSScreenUUIDCache.shared.allScreens
    }
}

/// Cache for UUID to NSScreen mappings to avoid repeated lookups
@MainActor
final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()
    
    private var cache: [String: NSScreen] = [:]
    private var observer: Any?
    
    private init() {
        rebuildCache()
        setupObserver()
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildCache()
        }
    }
    
    private func rebuildCache() {
        var newCache: [String: NSScreen] = [:]
        
        for screen in NSScreen.screens {
            if let uuid = screen.displayUUID {
                newCache[uuid] = screen
            }
        }
        
        cache = newCache
    }
    
    func screen(forUUID uuid: String) -> NSScreen? {
        return cache[uuid]
    }
    
    var allScreens: [String: NSScreen] {
        return cache
    }
}
