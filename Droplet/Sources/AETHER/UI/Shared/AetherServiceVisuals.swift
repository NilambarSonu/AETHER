// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

// MARK: - Colorful Static Squircle Badges (System Settings Language)

/// Crisp, static Apple System Settings-style colorful rounded-square icon badge.
struct AetherSettingsIconBadge: View {
    static let rowSize: CGFloat = 22
    static var pageLinkSize: CGFloat { DropletSettingsPageLink<AnyView>.tileSize }

    let symbol: String
    let colors: [Color]
    var size: CGFloat = rowSize
    var symbolScale: CGFloat = 0.52

    init(symbol: String, color: Color, size: CGFloat = rowSize, symbolScale: CGFloat = 0.52) {
        self.symbol = symbol
        self.colors = [color, color.opacity(0.82)]
        self.size = size
        self.symbolScale = symbolScale
    }

    init(symbol: String, top: Color, bottom: Color, size: CGFloat = rowSize, symbolScale: CGFloat = 0.52) {
        self.symbol = symbol
        self.colors = [top, bottom]
        self.size = size
        self.symbolScale = symbolScale
    }

    var body: some View {
        let radius = DroppyRadius.appIcon(forSide: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .black.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * symbolScale, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Preserved alias matching `DropletSettingsPageLink`'s 28pt tile metric.
struct AetherSymbolTile: View {
    static var settingsLinkSize: CGFloat { AetherSettingsIconBadge.pageLinkSize }

    let symbol: String
    let color: Color
    var size: CGFloat = AetherSettingsIconBadge.pageLinkSize

    var body: some View {
        AetherSettingsIconBadge(symbol: symbol, color: color, size: size, symbolScale: 0.50)
    }
}

// MARK: - Unified Native-Form Settings Rows with Colorful Badges

struct AetherRowLabel: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColors: [Color]
    let infoTip: String?

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        color: Color,
        topColor: Color? = nil,
        infoTip: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColors = topColor.map { [$0, color] } ?? [color, color.opacity(0.84)]
        let trimmed = infoTip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.infoTip = trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(spacing: 10) {
            AetherSettingsIconBadge(
                symbol: icon,
                top: iconColors[0],
                bottom: iconColors.last ?? iconColors[0],
                size: AetherSettingsIconBadge.rowSize
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .lineLimit(2)
                    if let infoTip {
                        SettingsInfoTip(infoTip)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct AetherSettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let iconColor: Color
    var topColor: Color? = nil
    var infoTip: String = ""
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            AetherRowLabel(
                title: title,
                subtitle: subtitle,
                icon: icon,
                color: iconColor,
                topColor: topColor,
                infoTip: infoTip
            )
        }
        .accessibilityLabel(Text(title))
    }
}

struct AetherSettingsControlRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let iconColor: Color
    var topColor: Color? = nil
    var infoTip: String = ""
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        LabeledContent {
            accessory()
        } label: {
            AetherRowLabel(
                title: title,
                subtitle: subtitle,
                icon: icon,
                color: iconColor,
                topColor: topColor,
                infoTip: infoTip
            )
        }
    }
}

// MARK: - On-Device Service Brand Recognition & Avatars

/// Rich local brand styling for recognizable 2FA senders (zero external network traffic).
enum AetherBrandCatalog {
    struct Style {
        let topColor: Color
        let bottomColor: Color
        let markText: String?
        let symbol: String?
        let foreground: Color
    }

    static func match(domain: String?, service: String) -> Style? {
        let key = (domain ?? service).lowercased()
        if key.contains("facebook") || key.contains("fb.com") {
            return Style(
                topColor: Color(red: 0.14, green: 0.52, blue: 0.98),
                bottomColor: Color(red: 0.06, green: 0.38, blue: 0.85),
                markText: "f",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("google") || key.contains("gmail") || key.contains("youtube") {
            return Style(
                topColor: Color(red: 0.26, green: 0.52, blue: 0.96),
                bottomColor: Color(red: 0.14, green: 0.40, blue: 0.84),
                markText: "G",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("microsoft") || key.contains("outlook") || key.contains("live.com") || key.contains("hotmail") {
            return Style(
                topColor: Color(red: 0.04, green: 0.65, blue: 0.95),
                bottomColor: Color(red: 0.00, green: 0.47, blue: 0.83),
                markText: nil,
                symbol: "square.grid.2x2.fill",
                foreground: .white
            )
        }
        if key.contains("apple") || key.contains("icloud") {
            return Style(
                topColor: Color(red: 0.30, green: 0.31, blue: 0.34),
                bottomColor: Color(red: 0.14, green: 0.15, blue: 0.17),
                markText: nil,
                symbol: "lock.shield.fill",
                foreground: .white
            )
        }
        if key.contains("github") {
            return Style(
                topColor: Color(red: 0.22, green: 0.25, blue: 0.30),
                bottomColor: Color(red: 0.10, green: 0.12, blue: 0.16),
                markText: nil,
                symbol: "chevron.left.forwardslash.chevron.right",
                foreground: .white
            )
        }
        if key.contains("instagram") {
            return Style(
                topColor: Color(red: 0.88, green: 0.19, blue: 0.42),
                bottomColor: Color(red: 0.97, green: 0.47, blue: 0.22),
                markText: nil,
                symbol: "camera.fill",
                foreground: .white
            )
        }
        if key.contains("whatsapp") {
            return Style(
                topColor: Color(red: 0.17, green: 0.84, blue: 0.42),
                bottomColor: Color(red: 0.07, green: 0.56, blue: 0.48),
                markText: nil,
                symbol: "phone.bubble.fill",
                foreground: .white
            )
        }
        if key == "x.com" || key.contains("twitter") || service.trimmingCharacters(in: .whitespaces).lowercased() == "x" {
            return Style(
                topColor: Color(red: 0.16, green: 0.17, blue: 0.20),
                bottomColor: Color(red: 0.05, green: 0.05, blue: 0.07),
                markText: "𝕏",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("discord") {
            return Style(
                topColor: Color(red: 0.39, green: 0.44, blue: 0.96),
                bottomColor: Color(red: 0.26, green: 0.31, blue: 0.88),
                markText: nil,
                symbol: "bubble.left.and.bubble.right.fill",
                foreground: .white
            )
        }
        if key.contains("openai") || key.contains("chatgpt") {
            return Style(
                topColor: Color(red: 0.08, green: 0.68, blue: 0.52),
                bottomColor: Color(red: 0.04, green: 0.52, blue: 0.40),
                markText: nil,
                symbol: "sparkles",
                foreground: .white
            )
        }
        if key.contains("anthropic") || key.contains("claude") {
            return Style(
                topColor: Color(red: 0.87, green: 0.49, blue: 0.35),
                bottomColor: Color(red: 0.72, green: 0.36, blue: 0.24),
                markText: "C",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("amazon") || key.contains("aws.") {
            return Style(
                topColor: Color(red: 1.00, green: 0.62, blue: 0.04),
                bottomColor: Color(red: 0.87, green: 0.47, blue: 0.02),
                markText: "a",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("paypal") {
            return Style(
                topColor: Color(red: 0.00, green: 0.44, blue: 0.73),
                bottomColor: Color(red: 0.00, green: 0.19, blue: 0.53),
                markText: "P",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("stripe") {
            return Style(
                topColor: Color(red: 0.42, green: 0.39, blue: 1.00),
                bottomColor: Color(red: 0.28, green: 0.25, blue: 0.82),
                markText: "S",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("slack") {
            return Style(
                topColor: Color(red: 0.48, green: 0.16, blue: 0.52),
                bottomColor: Color(red: 0.29, green: 0.08, blue: 0.29),
                markText: nil,
                symbol: "number",
                foreground: .white
            )
        }
        if key.contains("linkedin") {
            return Style(
                topColor: Color(red: 0.06, green: 0.44, blue: 0.80),
                bottomColor: Color(red: 0.02, green: 0.28, blue: 0.56),
                markText: "in",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("cloudflare") {
            return Style(
                topColor: Color(red: 0.96, green: 0.54, blue: 0.15),
                bottomColor: Color(red: 0.88, green: 0.38, blue: 0.08),
                markText: nil,
                symbol: "cloud.fill",
                foreground: .white
            )
        }
        if key.contains("binance") {
            return Style(
                topColor: Color(red: 0.96, green: 0.74, blue: 0.08),
                bottomColor: Color(red: 0.82, green: 0.58, blue: 0.02),
                markText: "B",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("coinbase") {
            return Style(
                topColor: Color(red: 0.04, green: 0.35, blue: 1.00),
                bottomColor: Color(red: 0.00, green: 0.22, blue: 0.80),
                markText: "C",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("netflix") {
            return Style(
                topColor: Color(red: 0.92, green: 0.08, blue: 0.13),
                bottomColor: Color(red: 0.68, green: 0.02, blue: 0.06),
                markText: "N",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("spotify") {
            return Style(
                topColor: Color(red: 0.13, green: 0.78, blue: 0.36),
                bottomColor: Color(red: 0.07, green: 0.56, blue: 0.24),
                markText: nil,
                symbol: "waveform",
                foreground: .white
            )
        }
        if key.contains("zoom") {
            return Style(
                topColor: Color(red: 0.22, green: 0.58, blue: 1.00),
                bottomColor: Color(red: 0.08, green: 0.40, blue: 0.88),
                markText: nil,
                symbol: "video.fill",
                foreground: .white
            )
        }
        if key.contains("odisha") || key.contains("rtiodisha") {
            return Style(
                topColor: Color(red: 0.05, green: 0.42, blue: 0.85),
                bottomColor: Color(red: 0.02, green: 0.22, blue: 0.58),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("saathi") {
            return Style(
                topColor: Color(red: 0.16, green: 0.72, blue: 0.40),
                bottomColor: Color(red: 0.08, green: 0.52, blue: 0.28),
                markText: nil,
                symbol: "leaf.fill",
                foreground: .white
            )
        }
        if key.contains("digilocker") {
            return Style(
                topColor: Color(red: 0.08, green: 0.48, blue: 0.95),
                bottomColor: Color(red: 0.02, green: 0.28, blue: 0.72),
                markText: nil,
                symbol: "lock.shield.fill",
                foreground: .white
            )
        }
        if key.contains("uidai") || key.contains("aadhaar") {
            return Style(
                topColor: Color(red: 0.95, green: 0.45, blue: 0.10),
                bottomColor: Color(red: 0.80, green: 0.20, blue: 0.10),
                markText: nil,
                symbol: "person.text.rectangle.fill",
                foreground: .white
            )
        }
        if key.contains("irctc") {
            return Style(
                topColor: Color(red: 0.12, green: 0.38, blue: 0.75),
                bottomColor: Color(red: 0.05, green: 0.20, blue: 0.52),
                markText: nil,
                symbol: "tram.fill",
                foreground: .white
            )
        }
        if key.contains("gov.") || key.hasSuffix(".gov.in") || key.hasSuffix(".nic.in") || key.hasSuffix(".gov") {
            return Style(
                topColor: Color(red: 0.15, green: 0.28, blue: 0.52),
                bottomColor: Color(red: 0.08, green: 0.16, blue: 0.36),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("phonepe") {
            return Style(
                topColor: Color(red: 0.42, green: 0.16, blue: 0.75),
                bottomColor: Color(red: 0.28, green: 0.08, blue: 0.56),
                markText: "पे",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("paytm") {
            return Style(
                topColor: Color(red: 0.05, green: 0.65, blue: 0.95),
                bottomColor: Color(red: 0.00, green: 0.42, blue: 0.75),
                markText: "Paytm",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("cred") {
            return Style(
                topColor: Color(red: 0.20, green: 0.20, blue: 0.22),
                bottomColor: Color(red: 0.08, green: 0.08, blue: 0.10),
                markText: "CRED",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("razorpay") {
            return Style(
                topColor: Color(red: 0.10, green: 0.46, blue: 0.95),
                bottomColor: Color(red: 0.02, green: 0.26, blue: 0.72),
                markText: "R",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("groww") {
            return Style(
                topColor: Color(red: 0.08, green: 0.74, blue: 0.58),
                bottomColor: Color(red: 0.02, green: 0.54, blue: 0.42),
                markText: nil,
                symbol: "chart.line.uptrend.xyaxis",
                foreground: .white
            )
        }
        if key.contains("zerodha") || key.contains("kite") {
            return Style(
                topColor: Color(red: 0.18, green: 0.55, blue: 0.98),
                bottomColor: Color(red: 0.08, green: 0.38, blue: 0.82),
                markText: nil,
                symbol: "arrow.up.right",
                foreground: .white
            )
        }
        if key.contains("swiggy") {
            return Style(
                topColor: Color(red: 0.98, green: 0.48, blue: 0.12),
                bottomColor: Color(red: 0.86, green: 0.32, blue: 0.04),
                markText: nil,
                symbol: "bag.fill",
                foreground: .white
            )
        }
        if key.contains("zomato") {
            return Style(
                topColor: Color(red: 0.92, green: 0.18, blue: 0.22),
                bottomColor: Color(red: 0.72, green: 0.08, blue: 0.12),
                markText: "Z",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("blinkit") {
            return Style(
                topColor: Color(red: 0.98, green: 0.78, blue: 0.08),
                bottomColor: Color(red: 0.12, green: 0.54, blue: 0.24),
                markText: "B",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("zepto") {
            return Style(
                topColor: Color(red: 0.65, green: 0.12, blue: 0.82),
                bottomColor: Color(red: 0.45, green: 0.05, blue: 0.62),
                markText: "Z",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("flipkart") {
            return Style(
                topColor: Color(red: 0.15, green: 0.45, blue: 0.95),
                bottomColor: Color(red: 0.95, green: 0.75, blue: 0.10),
                markText: "fk",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("hdfc") {
            return Style(
                topColor: Color(red: 0.08, green: 0.30, blue: 0.65),
                bottomColor: Color(red: 0.85, green: 0.15, blue: 0.15),
                markText: "HDFC",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("icici") {
            return Style(
                topColor: Color(red: 0.75, green: 0.18, blue: 0.12),
                bottomColor: Color(red: 0.95, green: 0.48, blue: 0.10),
                markText: "i",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("sbi") || key.contains("state bank") {
            return Style(
                topColor: Color(red: 0.10, green: 0.42, blue: 0.82),
                bottomColor: Color(red: 0.04, green: 0.24, blue: 0.60),
                markText: nil,
                symbol: "circle.circle.fill",
                foreground: .white
            )
        }
        if key.contains("wise") {
            return Style(
                topColor: Color(red: 0.00, green: 0.73, blue: 1.00),
                bottomColor: Color(red: 0.00, green: 0.51, blue: 0.70),
                markText: "₩",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("revolut") {
            return Style(
                topColor: Color(red: 0.15, green: 0.16, blue: 0.18),
                bottomColor: Color(red: 0.06, green: 0.07, blue: 0.08),
                markText: "R",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("monzo") {
            return Style(
                topColor: Color(red: 0.98, green: 0.35, blue: 0.28),
                bottomColor: Color(red: 0.12, green: 0.20, blue: 0.30),
                markText: "M",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("n26") {
            return Style(
                topColor: Color(red: 0.21, green: 0.63, blue: 0.55),
                bottomColor: Color(red: 0.15, green: 0.42, blue: 0.36),
                markText: "26",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("klarna") {
            return Style(
                topColor: Color(red: 1.00, green: 0.66, blue: 0.80),
                bottomColor: Color(red: 1.00, green: 0.52, blue: 0.70),
                markText: "K",
                symbol: nil,
                foreground: .black
            )
        }
        if key.contains("shopify") {
            return Style(
                topColor: Color(red: 0.58, green: 0.75, blue: 0.28),
                bottomColor: Color(red: 0.37, green: 0.56, blue: 0.24),
                markText: nil,
                symbol: "bag.fill",
                foreground: .white
            )
        }
        if key.contains("uber") {
            return Style(
                topColor: Color(red: 0.18, green: 0.18, blue: 0.20),
                bottomColor: Color(red: 0.05, green: 0.05, blue: 0.06),
                markText: "Uber",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("airbnb") {
            return Style(
                topColor: Color(red: 1.00, green: 0.35, blue: 0.37),
                bottomColor: Color(red: 0.85, green: 0.23, blue: 0.28),
                markText: "A",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("notion") {
            return Style(
                topColor: Color(red: 0.18, green: 0.18, blue: 0.20),
                bottomColor: Color(red: 0.08, green: 0.08, blue: 0.10),
                markText: "N",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("figma") {
            return Style(
                topColor: Color(red: 0.04, green: 0.81, blue: 0.51),
                bottomColor: Color(red: 0.64, green: 0.35, blue: 1.00),
                markText: nil,
                symbol: "square.grid.2x2",
                foreground: .white
            )
        }
        if key.contains("linear") {
            return Style(
                topColor: Color(red: 0.37, green: 0.42, blue: 0.82),
                bottomColor: Color(red: 0.24, green: 0.28, blue: 0.63),
                markText: "L",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("steam") {
            return Style(
                topColor: Color(red: 0.11, green: 0.16, blue: 0.22),
                bottomColor: Color(red: 0.09, green: 0.10, blue: 0.13),
                markText: nil,
                symbol: "gamecontroller.fill",
                foreground: .white
            )
        }
        if key.contains("playstation") || key.contains("sony") {
            return Style(
                topColor: Color(red: 0.00, green: 0.22, blue: 0.57),
                bottomColor: Color(red: 0.00, green: 0.12, blue: 0.36),
                markText: nil,
                symbol: "gamecontroller.fill",
                foreground: .white
            )
        }
        if key.contains("xbox") {
            return Style(
                topColor: Color(red: 0.06, green: 0.49, blue: 0.06),
                bottomColor: Color(red: 0.04, green: 0.32, blue: 0.04),
                markText: nil,
                symbol: "gamecontroller.fill",
                foreground: .white
            )
        }
        if key.contains("nintendo") {
            return Style(
                topColor: Color(red: 0.90, green: 0.00, blue: 0.07),
                bottomColor: Color(red: 0.66, green: 0.00, blue: 0.05),
                markText: nil,
                symbol: "gamecontroller.fill",
                foreground: .white
            )
        }
        if key.contains("epicgames") || key.contains("epic games") {
            return Style(
                topColor: Color(red: 0.20, green: 0.20, blue: 0.22),
                bottomColor: Color(red: 0.08, green: 0.08, blue: 0.10),
                markText: "EPIC",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("bitwarden") {
            return Style(
                topColor: Color(red: 0.09, green: 0.36, blue: 0.86),
                bottomColor: Color(red: 0.04, green: 0.23, blue: 0.55),
                markText: nil,
                symbol: "shield.lefthalf.filled",
                foreground: .white
            )
        }
        if key.contains("1password") {
            return Style(
                topColor: Color(red: 0.04, green: 0.52, blue: 0.92),
                bottomColor: Color(red: 0.02, green: 0.32, blue: 0.56),
                markText: nil,
                symbol: "key.fill",
                foreground: .white
            )
        }
        if key.contains("proton") {
            return Style(
                topColor: Color(red: 0.43, green: 0.29, blue: 1.00),
                bottomColor: Color(red: 0.26, green: 0.13, blue: 0.70),
                markText: nil,
                symbol: "lock.shield.fill",
                foreground: .white
            )
        }
        if key.contains("okta") {
            return Style(
                topColor: Color(red: 0.00, green: 0.49, blue: 0.76),
                bottomColor: Color(red: 0.00, green: 0.31, blue: 0.48),
                markText: nil,
                symbol: "circle.circle.fill",
                foreground: .white
            )
        }
        if key.contains("duo") {
            return Style(
                topColor: Color(red: 0.32, green: 0.72, blue: 0.28),
                bottomColor: Color(red: 0.22, green: 0.51, blue: 0.19),
                markText: nil,
                symbol: "shield.fill",
                foreground: .white
            )
        }
        if key.contains("vercel") {
            return Style(
                topColor: Color(red: 0.15, green: 0.15, blue: 0.16),
                bottomColor: Color(red: 0.04, green: 0.04, blue: 0.05),
                markText: "▲",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("supabase") {
            return Style(
                topColor: Color(red: 0.24, green: 0.81, blue: 0.56),
                bottomColor: Color(red: 0.14, green: 0.58, blue: 0.38),
                markText: nil,
                symbol: "bolt.fill",
                foreground: .white
            )
        }
        if key.contains("gitlab") {
            return Style(
                topColor: Color(red: 0.99, green: 0.43, blue: 0.15),
                bottomColor: Color(red: 0.89, green: 0.26, blue: 0.16),
                markText: nil,
                symbol: "chevron.left.forwardslash.chevron.right",
                foreground: .white
            )
        }
        if key.contains("chase") {
            return Style(
                topColor: Color(red: 0.07, green: 0.48, blue: 0.79),
                bottomColor: Color(red: 0.00, green: 0.31, blue: 0.55),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("bankofamerica") || key.contains("bofa") {
            return Style(
                topColor: Color(red: 0.89, green: 0.09, blue: 0.22),
                bottomColor: Color(red: 0.00, green: 0.32, blue: 0.61),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("wellsfargo") {
            return Style(
                topColor: Color(red: 0.84, green: 0.12, blue: 0.16),
                bottomColor: Color(red: 0.62, green: 0.08, blue: 0.10),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("citi") {
            return Style(
                topColor: Color(red: 0.00, green: 0.23, blue: 0.44),
                bottomColor: Color(red: 0.00, green: 0.14, blue: 0.28),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("capitalone") {
            return Style(
                topColor: Color(red: 0.00, green: 0.28, blue: 0.47),
                bottomColor: Color(red: 0.63, green: 0.16, blue: 0.19),
                markText: nil,
                symbol: "creditcard.fill",
                foreground: .white
            )
        }
        if key.contains("amex") || key.contains("americanexpress") || key.contains("american express") {
            return Style(
                topColor: Color(red: 0.00, green: 0.44, blue: 0.81),
                bottomColor: Color(red: 0.00, green: 0.25, blue: 0.48),
                markText: nil,
                symbol: "creditcard.fill",
                foreground: .white
            )
        }
        if key.contains("barclays") {
            return Style(
                topColor: Color(red: 0.00, green: 0.68, blue: 0.94),
                bottomColor: Color(red: 0.00, green: 0.35, blue: 0.53),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("hsbc") {
            return Style(
                topColor: Color(red: 0.86, green: 0.00, blue: 0.07),
                bottomColor: Color(red: 0.55, green: 0.00, blue: 0.04),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("santander") {
            return Style(
                topColor: Color(red: 0.93, green: 0.00, blue: 0.00),
                bottomColor: Color(red: 0.61, green: 0.00, blue: 0.00),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("deutschebank") || key.contains("db.com") {
            return Style(
                topColor: Color(red: 0.00, green: 0.09, blue: 0.66),
                bottomColor: Color(red: 0.00, green: 0.05, blue: 0.33),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }
        if key.contains("nubank") {
            return Style(
                topColor: Color(red: 0.51, green: 0.04, blue: 0.82),
                bottomColor: Color(red: 0.32, green: 0.02, blue: 0.52),
                markText: "Nu",
                symbol: nil,
                foreground: .white
            )
        }
        if key.contains("mercadopago") || key.contains("mercado pago") {
            return Style(
                topColor: Color(red: 0.00, green: 0.62, blue: 0.89),
                bottomColor: Color(red: 0.00, green: 0.42, blue: 0.65),
                markText: nil,
                symbol: "hand.wave.fill",
                foreground: .white
            )
        }
        return nil
    }
}

// MARK: - Universal Category-Aware Semantic Classifier (Worldwide Fallback)

/// Maps any unlisted domain or sender anywhere in the world into an authoritative,
/// Apple-grade semantic icon and continuous squircle gradient badge.
enum AetherCategoryClassifier {
    static func classify(domain: String?, service: String) -> AetherBrandCatalog.Style? {
        let key = (domain ?? service).lowercased()
        let nameLower = service.lowercased()

        // 1. Government & Public Sector (.gov, .gov.in, .gob.mx, .gouv.fr, .nic.in, ministries, parliament)
        if key.contains(".gov") || key.contains(".gob.") || key.contains(".gouv.") || key.contains(".nic.in")
            || key.contains(".mil") || key.contains("odisha") || key.contains("aadhaar") || key.contains("passport")
            || key.contains("parliament") || key.contains("incometax") || key.contains("epfindia")
            || nameLower.contains("government") || nameLower.contains("ministry") || nameLower.contains("department")
            || nameLower.contains("portal") || nameLower.contains("citizen") || nameLower.contains("state") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.11, green: 0.22, blue: 0.42),
                bottomColor: Color(red: 0.05, green: 0.12, blue: 0.26),
                markText: nil,
                symbol: "building.columns.fill",
                foreground: .white
            )
        }

        // 2. Banking, Fintech, Crypto & Payments (bank, pay, wallet, credit, card, crypto, invest, wealth, capital)
        if key.contains("bank") || key.contains("pay") || key.contains("wallet") || key.contains("credit")
            || key.contains("card") || key.contains("crypto") || key.contains("coin") || key.contains("finance")
            || key.contains("invest") || key.contains("fund") || key.contains("loan") || key.contains("wealth")
            || key.contains("capital") || key.contains("cash") || key.contains("checkout") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.05, green: 0.52, blue: 0.36),
                bottomColor: Color(red: 0.02, green: 0.32, blue: 0.22),
                markText: nil,
                symbol: "creditcard.fill",
                foreground: .white
            )
        }

        // 3. Identity, Authentication & Security (auth, login, sso, id, identity, pass, security, shield, vault, token)
        if key.contains("auth") || key.contains("login") || key.contains("sso") || key.contains("identity")
            || key.contains("pass") || key.contains("security") || key.contains("shield") || key.contains("vault")
            || key.contains("token") || key.contains("verify") || key.contains("access") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.18, green: 0.28, blue: 0.72),
                bottomColor: Color(red: 0.10, green: 0.16, blue: 0.48),
                markText: nil,
                symbol: "lock.shield.fill",
                foreground: .white
            )
        }

        // 4. Cloud, Hosting & Developer Infrastructure (cloud, api, dev, code, git, host, server, deploy, infra, db)
        if key.contains("cloud") || key.contains("api") || key.contains("dev") || key.contains("code")
            || key.contains("git") || key.contains("host") || key.contains("server") || key.contains("deploy")
            || key.contains("infra") || key.contains("stack") || key.contains("db") || key.contains("database") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.18, green: 0.22, blue: 0.28),
                bottomColor: Color(red: 0.08, green: 0.10, blue: 0.14),
                markText: nil,
                symbol: "cpu.fill",
                foreground: .white
            )
        }

        // 5. Messaging, Mail & Social (mail, post, message, chat, talk, social, forum, community)
        if key.contains("mail") || key.contains("post") || key.contains("message") || key.contains("chat")
            || key.contains("talk") || key.contains("social") || key.contains("forum") || key.contains("community") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.08, green: 0.56, blue: 0.88),
                bottomColor: Color(red: 0.02, green: 0.38, blue: 0.68),
                markText: nil,
                symbol: "paperplane.fill",
                foreground: .white
            )
        }

        // 6. E-Commerce, Delivery & Shopping (shop, store, market, cart, order, buy, delivery, mart)
        if key.contains("shop") || key.contains("store") || key.contains("market") || key.contains("cart")
            || key.contains("order") || key.contains("buy") || key.contains("delivery") || key.contains("mart") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.92, green: 0.42, blue: 0.12),
                bottomColor: Color(red: 0.76, green: 0.26, blue: 0.05),
                markText: nil,
                symbol: "bag.fill",
                foreground: .white
            )
        }

        // 7. Travel, Airlines & Transit (air, flight, fly, travel, hotel, ride, transit, train, rail, bus, booking)
        if key.contains("air") || key.contains("flight") || key.contains("fly") || key.contains("travel")
            || key.contains("hotel") || key.contains("ride") || key.contains("transit") || key.contains("train")
            || key.contains("booking") || key.contains("trip") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.05, green: 0.48, blue: 0.78),
                bottomColor: Color(red: 0.02, green: 0.30, blue: 0.54),
                markText: nil,
                symbol: "airplane",
                foreground: .white
            )
        }

        // 8. Health, Medical & Wellness (health, med, care, clinic, hospital, pharma, rx, doctor)
        if key.contains("health") || key.contains("med") || key.contains("care") || key.contains("clinic")
            || key.contains("hospital") || key.contains("pharma") || key.contains("rx") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.88, green: 0.18, blue: 0.32),
                bottomColor: Color(red: 0.64, green: 0.08, blue: 0.20),
                markText: nil,
                symbol: "cross.case.fill",
                foreground: .white
            )
        }

        // 9. Education & Academia (.edu, .ac., univ, college, school, academy, learn, course)
        if key.contains(".edu") || key.contains(".ac.") || key.contains("univ") || key.contains("college")
            || key.contains("school") || key.contains("academy") || key.contains("course") || key.contains("learn") {
            return AetherBrandCatalog.Style(
                topColor: Color(red: 0.45, green: 0.12, blue: 0.28),
                bottomColor: Color(red: 0.28, green: 0.05, blue: 0.18),
                markText: nil,
                symbol: "graduationcap.fill",
                foreground: .white
            )
        }

        return nil
    }
}

// MARK: - Elevated Liquid-Glass Two-Letter Monograms

struct AetherServiceMonogram: View {
    let name: String
    var domain: String? = nil
    var size: CGFloat = 32

    private static let palette: [(Color, Color)] = [
        (Color(red: 0.12, green: 0.48, blue: 0.98), Color(red: 0.04, green: 0.28, blue: 0.78)), // Apple Blue
        (Color(red: 0.36, green: 0.32, blue: 0.88), Color(red: 0.22, green: 0.18, blue: 0.70)), // Indigo
        (Color(red: 0.62, green: 0.26, blue: 0.88), Color(red: 0.46, green: 0.12, blue: 0.72)), // Purple
        (Color(red: 0.88, green: 0.20, blue: 0.52), Color(red: 0.70, green: 0.10, blue: 0.38)), // Magenta
        (Color(red: 0.95, green: 0.30, blue: 0.24), Color(red: 0.78, green: 0.14, blue: 0.12)), // Coral Red
        (Color(red: 0.96, green: 0.52, blue: 0.10), Color(red: 0.82, green: 0.36, blue: 0.04)), // Amber Orange
        (Color(red: 0.18, green: 0.68, blue: 0.38), Color(red: 0.08, green: 0.50, blue: 0.26)), // Emerald Green
        (Color(red: 0.10, green: 0.62, blue: 0.74), Color(red: 0.04, green: 0.44, blue: 0.56)), // Teal
        (Color(red: 0.24, green: 0.58, blue: 0.92), Color(red: 0.12, green: 0.38, blue: 0.78)), // Sky Azure
        (Color(red: 0.48, green: 0.22, blue: 0.56), Color(red: 0.32, green: 0.10, blue: 0.40)), // Plum
        (Color(red: 0.82, green: 0.18, blue: 0.34), Color(red: 0.62, green: 0.08, blue: 0.22)), // Crimson
        (Color(red: 0.22, green: 0.65, blue: 0.62), Color(red: 0.10, green: 0.48, blue: 0.46)), // Mint / Seafoam
        (Color(red: 0.78, green: 0.45, blue: 0.12), Color(red: 0.60, green: 0.30, blue: 0.05)), // Warm Ochre
        (Color(red: 0.30, green: 0.38, blue: 0.72), Color(red: 0.16, green: 0.22, blue: 0.54)), // Slate Cobalt
        (Color(red: 0.54, green: 0.36, blue: 0.82), Color(red: 0.38, green: 0.20, blue: 0.66)), // Violet
        (Color(red: 0.15, green: 0.55, blue: 0.48), Color(red: 0.06, green: 0.38, blue: 0.32)), // Forest Jade
    ]

    var body: some View {
        let radius = DroppyRadius.appIcon(forSide: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if let brand = AetherBrandCatalog.match(domain: domain, service: name) ?? AetherCategoryClassifier.classify(domain: domain, service: name) {
            shape
                .fill(LinearGradient(colors: [brand.topColor, brand.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(shape)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .white.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
                )
                .overlay {
                    if let symbol = brand.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.48, weight: .semibold))
                            .foregroundStyle(brand.foreground)
                    } else if let text = brand.markText {
                        Text(verbatim: text)
                            .font(.system(size: size * (text.count > 1 ? 0.38 : 0.50), weight: .bold, design: .rounded))
                            .foregroundStyle(brand.foreground)
                    }
                }
                .accessibilityHidden(true)
        } else {
            let initials = Self.extractInitials(from: name.isEmpty ? (domain ?? "A") : name)
            let hash = (domain ?? name).lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
            let pair = Self.palette[Int(hash.magnitude % UInt(Self.palette.count))]
            shape
                .fill(LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(shape)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
                )
                .overlay(
                    Text(verbatim: initials)
                        .font(.system(size: size * (initials.count > 1 ? 0.40 : 0.48), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                )
                .accessibilityHidden(true)
        }
    }

    private static func extractInitials(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "AE" }
        let words = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words[0].first.map(String.init) ?? ""
            let second = words[1].first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
        // Decompose CamelCase (e.g. "RazorPay" -> "RP", "DropBox" -> "DB", "BitWarden" -> "BW")
        let uppers = trimmed.filter { $0.isUppercase }
        if uppers.count >= 2 {
            return String(uppers.prefix(2))
        }
        // Single word: use first 2 letters if >= 2 letters, ensuring a rich 2-letter monogram
        let letters = trimmed.filter { $0.isLetter }
        if letters.count >= 2 {
            return String(letters.prefix(2)).uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }
}

struct AetherServiceAvatar: View {
    let item: CodeItem
    @ObservedObject var icons: AetherIconStore
    @ObservedObject var model: AetherAppModel
    var size: CGFloat = 32
    var showsOriginBadge: Bool = true

    var body: some View {
        let radius = DroppyRadius.appIcon(forSide: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if item.origin == .test {
                AetherAppIconBadge(size: size)
            } else if let cached = icons.icon(for: item.domain) {
                Group {
                    if cached.fullBleed {
                        Image(nsImage: cached.image).resizable().interpolation(.high).scaledToFill()
                    } else {
                        Color.white.overlay(
                            Image(nsImage: cached.image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(size * 0.14)
                        )
                    }
                }
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
            } else {
                AetherServiceMonogram(name: item.service, domain: item.domain, size: size)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsOriginBadge {
                Image(systemName: originSymbol)
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(size * 0.11)
                    .background(
                        Circle()
                            .fill(originColor)
                            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                    )
                    .offset(x: size * 0.10, y: size * 0.10)
            }
        }
    }

    private var originSymbol: String {
        switch item.origin {
        case .messages: "message.fill"
        case .mail: "envelope.fill"
        case .vault: "key.fill"
        case .test: "sparkles"
        }
    }

    private var originColor: Color {
        switch item.origin {
        case .messages: .green
        case .mail: .blue
        case .vault: .indigo
        case .test: .orange
        }
    }
}

struct AetherExpiryRing: View {
    let item: CodeItem
    let now: Date
    var size: CGFloat = 16

    var body: some View {
        let total = max(1, item.countdown)
        let left = max(0, item.expires.timeIntervalSince(now))
        let fraction = min(max(left / total, 0), 1)
        let tint: Color = left <= 30 ? .orange : .accentColor
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct AetherCodeDigitsText: View {
    let code: String
    let locked: Bool
    let concealed: Bool
    var fontSize: CGFloat = 22
    var weight: Font.Weight = .bold

    var body: some View {
        let shown: String = locked
            ? String(repeating: "•", count: max(4, min(code.count, 8)))
            : AetherNotificationBridge.formatCode(code)
        Text(verbatim: shown)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .monospacedDigit()
            .blur(radius: (!locked && concealed) ? 5 : 0)
    }
}

struct AetherSourceStatusDot: View {
    let status: SourceStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityLabel(status.summary)
    }

    private var color: Color {
        switch status {
        case .off: .secondary.opacity(0.45)
        case .connecting: .blue
        case .live: .green
        case .attention: .orange
        case .failed: .red
        }
    }
}

struct AetherWarningRow: View {
    let message: String
    var calm: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AetherSettingsIconBadge(
                symbol: calm ? "info" : "exclamationmark.triangle.fill",
                top: calm ? Color(white: 0.44) : .orange,
                bottom: calm ? Color(white: 0.30) : Color(red: 0.85, green: 0.42, blue: 0.05),
                size: AetherSettingsIconBadge.rowSize
            )
            Text(verbatim: message)
                .font(.caption)
                .foregroundStyle(calm ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

extension SourceStatus {
    var displayColor: Color {
        switch self {
        case .off: .secondary
        case .connecting: .blue
        case .live: .green
        case .attention: .orange
        case .failed: .red
        }
    }
}

extension Date {
    var aetherDayTitle: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private final class AetherBundleResourceAnchor {}

enum AetherBundleResources {
    @MainActor
    static let appIconImage: NSImage? = {
        let bundle = Bundle(for: AetherBundleResourceAnchor.self)
        if let url = bundle.url(forResource: "aether", withExtension: "png", subdirectory: "Assets"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }()
}

struct AetherAppIconBadge: View {
    var size: CGFloat = 24

    var body: some View {
        let radius = DroppyRadius.appIcon(forSide: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let image = AetherBundleResources.appIconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
            } else {
                AetherSettingsIconBadge(
                    symbol: "key.viewfinder",
                    top: Color(red: 1.00, green: 0.68, blue: 0.54),
                    bottom: Color(red: 0.66, green: 0.56, blue: 0.96),
                    size: size
                )
            }
        }
        .accessibilityHidden(true)
    }
}

struct AetherVerificationBadge: View {
    let item: CodeItem
    var size: CGFloat = 11

    var body: some View {
        if item.hasFailedSenderAuth {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.orange)
                .help("Sender failed DMARC domain verification")
        } else if item.isVerifiedSender {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.green)
                .help("Sender domain verified by DMARC")
        }
    }
}
