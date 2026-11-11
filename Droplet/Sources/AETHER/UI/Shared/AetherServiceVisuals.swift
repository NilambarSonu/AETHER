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
        return nil
    }
}

struct AetherServiceMonogram: View {
    let name: String
    var domain: String? = nil
    var size: CGFloat = 32

    private static let palette: [(Color, Color)] = [
        (.blue, Color(red: 0.10, green: 0.36, blue: 0.85)),
        (.indigo, Color(red: 0.26, green: 0.22, blue: 0.78)),
        (.purple, Color(red: 0.52, green: 0.20, blue: 0.78)),
        (.pink, Color(red: 0.78, green: 0.16, blue: 0.44)),
        (.orange, Color(red: 0.86, green: 0.42, blue: 0.06)),
        (.green, Color(red: 0.10, green: 0.58, blue: 0.30)),
        (.teal, Color(red: 0.08, green: 0.52, blue: 0.64)),
    ]

    var body: some View {
        let radius = DroppyRadius.appIcon(forSide: size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if let brand = AetherBrandCatalog.match(domain: domain, service: name) {
            shape
                .fill(LinearGradient(colors: [brand.topColor, brand.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
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
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let letter = trimmed.first.map { String($0).uppercased() } ?? "A"
            let hash = trimmed.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
            let pair = Self.palette[Int(hash.magnitude % UInt(Self.palette.count))]
            shape
                .fill(LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    shape.strokeBorder(.white.opacity(0.20), lineWidth: 0.6)
                )
                .overlay(
                    Text(verbatim: letter)
                        .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)
        }
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
                AetherSettingsIconBadge(
                    symbol: "checkmark.seal.fill",
                    top: Color(red: 0.24, green: 0.62, blue: 1.00),
                    bottom: Color(red: 0.08, green: 0.42, blue: 0.88),
                    size: size
                )
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
