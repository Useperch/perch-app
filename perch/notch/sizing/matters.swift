//
//  sizeMatters.swift
//  notch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 640, height: 190)
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // DEBUG-only: let a developer simulate a different notch geometry (a narrow
    // 14" notch, a wide 16" notch, or a no-notch display) on a single Mac, so the
    // margins around the notch can be eyeballed across sizes without owning every
    // model. Because every notch surface re-derives from this one function, a forced
    // size here propagates through the whole UI. Never compiled into Release.
    #if DEBUG
    if let simulated = simulatedNotchSizeOverride(realScreen: selectedScreen) {
        return simulated
    }
    #endif

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}

#if DEBUG
/// Reads developer-only environment overrides for the closed-notch geometry, so
/// different notch sizes (and the no-notch case) can be tested on one machine:
///
///   PERCH_SIM_NO_NOTCH=1       → simulate a display without a notch: a top-center
///                                 pill sized to the real menu-bar height.
///   PERCH_SIM_NOTCH_WIDTH=160  → force the closed-notch width (points).
///   PERCH_SIM_NOTCH_HEIGHT=38  → force the closed-notch height (points).
///
/// Returns nil when no override is set, so the normal screen-derived path runs.
@MainActor private func simulatedNotchSizeOverride(realScreen: NSScreen?) -> CGSize? {
    let environment = ProcessInfo.processInfo.environment

    let simulateNoNotch = environment["PERCH_SIM_NO_NOTCH"] == "1"
    let widthOverride = environment["PERCH_SIM_NOTCH_WIDTH"].flatMap { Double($0) }.map { CGFloat($0) }
    let heightOverride = environment["PERCH_SIM_NOTCH_HEIGHT"].flatMap { Double($0) }.map { CGFloat($0) }

    guard simulateNoNotch || widthOverride != nil || heightOverride != nil else {
        return nil
    }

    // The menu-bar height of the real screen — the height the no-notch pill matches.
    let menuBarHeight: CGFloat = realScreen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? Defaults[.nonNotchHeight]

    if simulateNoNotch {
        // No-notch display: a narrow pill (the 185 fallback width) at menu-bar height,
        // with the same width override honored if the developer also set one.
        return .init(width: widthOverride ?? 185, height: heightOverride ?? menuBarHeight)
    }

    // Notch display with a forced width and/or height. Fall back to the current
    // closed-notch values for whichever dimension was not overridden.
    let currentSize = getClosedNotchSizeWithoutOverride(screen: realScreen)
    return .init(
        width: widthOverride ?? currentSize.width,
        height: heightOverride ?? currentSize.height
    )
}

/// The screen-derived closed-notch size with NO debug override applied — used so a
/// partial override (only width, or only height) can fill the other dimension from
/// the real screen instead of recursing back into `getClosedNotchSize`.
@MainActor private func getClosedNotchSizeWithoutOverride(screen: NSScreen?) -> CGSize {
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    if let screen = screen {
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
#endif
