// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import SwiftUI

struct AetherSymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct AetherServiceMonogram: View {
    let name: String
    var size: CGFloat = 32

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal, .gray]

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let letter = trimmed.first.map { String($0).uppercased() } ?? "A"
        let hash = trimmed.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let tint = Self.palette[Int(hash.magnitude % UInt(Self.palette.count))]
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        shape
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(verbatim: letter)
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct AetherServiceAvatar: View {
    let item: CodeItem
    @ObservedObject var icons: AetherIconStore
    @ObservedObject var model: AetherAppModel
    var size: CGFloat = 32

    var body: some View {
        Group {
            if item.origin == .test {
                AetherSymbolTile(symbol: "checkmark.seal.fill", color: .blue, size: size)
            } else if let cached = icons.icon(for: item.domain) {
                let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                Group {
                    if cached.fullBleed {
                        Image(nsImage: cached.image).resizable().interpolation(.high).scaledToFill()
                    } else {
                        Color.white.overlay(
                            Image(nsImage: cached.image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(size * 0.16)
                        )
                    }
                }
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
            } else {
                AetherServiceMonogram(name: item.service, size: size)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: originSymbol)
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(.white)
                .padding(size * 0.11)
                .background(Circle().fill(originColor))
                .offset(x: size * 0.12, y: size * 0.12)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: calm ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(calm ? .secondary : .orange)
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
