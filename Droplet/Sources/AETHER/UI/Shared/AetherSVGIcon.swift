// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import SwiftUI

/// Vector asset manager for AETHER's custom SVG icons.
@MainActor
public enum AetherSVGAssets {
    public static let securitySafe = "security-safe-svgrepo-com"
    public static let settings2 = "settings-2-svgrepo-com"
    public static let refreshCcw = "refresh-ccw-svgrepo-com"
    public static let recentlyOpened = "data-development-workflow-data-exploration-recently-opened-svgrepo-com"
    public static let urlCleaner = "leon-urlcleaner-svgrepo-com"

    private static var imageCache: [String: NSImage] = [:]

    /// Loads the given SVG by name and configures it as a template image for SwiftUI tinting.
    public static func image(named name: String) -> NSImage? {
        if let cached = imageCache[name] {
            return cached
        }

        let bundle = Bundle(for: AETHERPrincipal.self)
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "svg", subdirectory: "Assets"),
            bundle.resourceURL?.appendingPathComponent("Assets/\(name).svg"),
            bundle.resourceURL?.appendingPathComponent("\(name).svg"),
            Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Assets"),
            URL(fileURLWithPath: "Droplet/Assets/\(name).svg"),
            URL(fileURLWithPath: "Assets/\(name).svg")
        ]

        for case let url? in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                imageCache[name] = img
                return img
            }
        }
        return nil
    }
}

/// SwiftUI View rendering an SVG template icon with fallback SF Symbol.
public struct AetherSVGIcon: View {
    let name: String
    let fallbackSystemImage: String
    var size: CGFloat = 16

    public init(name: String, fallbackSystemImage: String, size: CGFloat = 16) {
        self.name = name
        self.fallbackSystemImage = fallbackSystemImage
        self.size = size
    }

    public var body: some View {
        if let nsImage = AetherSVGAssets.image(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}

/// Apple premium circular liquid glass button for the Notch shelf widget.
public struct AetherLiquidGlassButton: View {
    let svgName: String
    let fallbackSystemImage: String
    let tooltip: String
    var iconSize: CGFloat = 14
    var buttonSize: CGFloat = 28
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    public init(
        svgName: String,
        fallbackSystemImage: String,
        tooltip: String,
        iconSize: CGFloat = 14,
        buttonSize: CGFloat = 28,
        action: @escaping () -> Void
    ) {
        self.svgName = svgName
        self.fallbackSystemImage = fallbackSystemImage
        self.tooltip = tooltip
        self.iconSize = iconSize
        self.buttonSize = buttonSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.22 : 0.12))

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.40 : 0.24),
                                Color.white.opacity(isHovered ? 0.14 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )

                AetherSVGIcon(name: svgName, fallbackSystemImage: fallbackSystemImage, size: iconSize)
                    .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.88))
            }
            .frame(width: buttonSize, height: buttonSize)
            .shadow(color: Color.black.opacity(0.30), radius: 3, x: 0, y: 1.5)
            .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.04 : 1.0))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

