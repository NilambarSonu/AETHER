// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import CoreText
import Foundation
import SwiftUI

/// Handles registration and access to custom typography (K2D font family) for AETHER.
@MainActor
public enum AetherTypography {
    private static var isRegistered = false

    /// Ensures K2D-Bold is registered with CoreText for the active process.
    public static func ensureRegistered() {
        guard !isRegistered else { return }
        isRegistered = true

        let bundle = Bundle(for: AETHERPrincipal.self)
        let candidateURLs: [URL?] = [
            bundle.url(forResource: "K2D-Bold", withExtension: "ttf", subdirectory: "Assets"),
            bundle.resourceURL?.appendingPathComponent("Assets/K2D-Bold.ttf"),
            bundle.resourceURL?.appendingPathComponent("K2D-Bold.ttf"),
            Bundle.main.url(forResource: "K2D-Bold", withExtension: "ttf", subdirectory: "Assets"),
            URL(fileURLWithPath: "Droplet/Assets/K2D-Bold.ttf"),
            URL(fileURLWithPath: "Assets/K2D-Bold.ttf")
        ]

        for case let url? in candidateURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    return
                }
            }
        }
    }

    /// Primary brand font using K2D-Bold, falling back gracefully to system rounded bold.
    public static func brand(size: CGFloat = 15) -> Font {
        ensureRegistered()
        return Font.custom("K2D-Bold", size: size)
    }
}

