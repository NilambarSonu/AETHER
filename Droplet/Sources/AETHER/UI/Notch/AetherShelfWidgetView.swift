// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

/// Premium Apple Liquid Glass Notch Shelf Widget for AETHER.
/// Matches Figma reference layout with K2D typography, green shield indicator, and exactly 4 controls:
/// Top-right: Refresh & Settings. Bottom-left: Recent Emails & Clean Notch.
struct AetherShelfWidgetView: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    @State private var query = ""
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    private var blurCodes: Bool { model.isOn(AetherPrefs.blurCodes) }
    private var showPreviews: Bool { model.isOn(AetherPrefs.showPreviews) }
    private var hideFromCapture: Bool { model.isOn(AetherPrefs.hideFromCapture) }

    @Environment(\.dropletWidgetLayout) private var layout
    @Environment(\.dropletShelfWidgetTextColor) private var textColor
    @Environment(\.dropletWidgetIsVisible) private var isVisible

    private var metrics: DroppyWidgetMetrics {
        layout?.metrics ?? .single
    }

    private var primaryInk: Color {
        textColor ?? layout?.foreground ?? .white
    }

    private var secondaryInk: Color {
        primaryInk.opacity(0.82)
    }

    private var usesAdaptiveForegrounds: Bool {
        layout?.usesAdaptiveForegrounds ?? false
    }

    var body: some View {
        DropletWidgetComposition {
            singleView
        } split: {
            splitView
        }
        .background(
            AetherScopedCaptureGuard(
                hideFromCapture: !(layout?.isPreview ?? false) && hideFromCapture && model.isUnlocked
            )
        )
        .onChange(of: isVisible) { _, visible in
            droplet.setWidgetVisible(visible)
        }
        .onAppear {
            droplet.setWidgetVisible(isVisible)
        }
        .onDisappear {
            droplet.setWidgetVisible(false)
        }
    }

    // MARK: - Single Mode

    private var singleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar(compact: false)

            contentView(compact: false)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, metrics.sectionSpacing)

            footerBar(compact: false)
                .padding(.top, metrics.rowSpacing)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .preference(key: ShelfWidgetHeaderPresenceKey.self, value: true)
    }

    // MARK: - Split Mode

    private var splitView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar(compact: true)

            contentView(compact: true)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.top, metrics.sectionSpacing)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .preference(key: ShelfWidgetHeaderPresenceKey.self, value: true)
    }

    // MARK: - Header Bar

    private func headerBar(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Vibrant green shield with keyhole
            AetherSVGIcon(
                name: AetherSVGAssets.securitySafe,
                fallbackSystemImage: "shield.lefthalf.filled",
                size: 16
            )
            .foregroundStyle(Color(red: 0.35, green: 0.84, blue: 0.45))
            .accessibilityHidden(true)

            // Brand title in K2D custom typography
            Text("AETHER")
                .font(AetherTypography.brand(size: 15))
                .tracking(0.8)
                .foregroundStyle(Color.white)

            Spacer(minLength: 8)

            // Exactly 2 circular liquid glass buttons: Refresh & Settings
            HStack(spacing: 8) {
                AetherLiquidGlassButton(
                    svgName: AetherSVGAssets.refreshCcw,
                    fallbackSystemImage: "arrow.clockwise",
                    tooltip: "Check mailboxes now",
                    iconSize: 13,
                    buttonSize: 28
                ) {
                    model.boostSources()
                }

                AetherLiquidGlassButton(
                    svgName: AetherSVGAssets.settings2,
                    fallbackSystemImage: "slider.horizontal.3",
                    tooltip: "AETHER Settings",
                    iconSize: 13,
                    buttonSize: 28
                ) {
                    _ = droplet.openSettings()
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: - Footer Bar

    private func footerBar(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Exactly 2 circular liquid glass buttons: Recent emails & Clean notch
            AetherLiquidGlassButton(
                svgName: AetherSVGAssets.recentlyOpened,
                fallbackSystemImage: "clock.arrow.circlepath",
                tooltip: "Unmatched recent emails",
                iconSize: 14,
                buttonSize: 28
            ) {
                droplet.openSettingsPage(
                    AetherSettingsRoute.recovery.rawValue,
                    title: "Unmatched emails"
                )
            }

            AetherLiquidGlassButton(
                svgName: AetherSVGAssets.urlCleaner,
                fallbackSystemImage: "bubbles.and.sparkles",
                tooltip: "Clean current notch display",
                iconSize: 13,
                buttonSize: 28
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.clearNotchDisplay()
                }
            }

            Spacer(minLength: 8)
        }
        .frame(height: 28)
    }

    // MARK: - Content View

    @ViewBuilder
    private func contentView(compact: Bool) -> some View {
        DroppyWidgetTimeline(every: 1) { tickNow in
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                if let attention = attentionSummary {
                    Button {
                        droplet.openSettingsPage(
                            AetherSettingsRoute.sources.rawValue,
                            title: "Sources & accounts"
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(verbatim: attention)
                                .font(metrics.font(.caption))
                                .foregroundStyle(primaryInk)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if !model.isUnlocked {
                    lockedContent(compact: compact)
                } else {
                    let allItems = combinedItems(at: tickNow)

                    if allItems.isEmpty {
                        emptyContent(compact: compact)
                    } else {
                        let displayed = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? allItems
                            : model.search.ranked(allItems, query: query, now: tickNow, secrets: true)

                        if displayed.isEmpty {
                            emptyContent(compact: compact)
                        } else {
                            ShelfWidgetRows(displayed, id: \.id, maximumRows: compact ? 2 : 4, scrollsWhenSingle: true) { item in
                                widgetRow(item: item, now: tickNow, compact: compact)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Locked Content

    @ViewBuilder
    private func lockedContent(compact: Bool) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text(model.latest != nil ? "Codes hidden while locked" : "AETHER is locked")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryInk)
            }
            if !compact {
                Button("Unlock to View Codes") {
                    model.unlocked {}
                }
                .buttonStyle(
                    DroppyWashPillButtonStyle(
                        height: 28,
                        tone: .accent(.blue),
                        usesAdaptiveForegrounds: usesAdaptiveForegrounds
                    )
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Content

    @ViewBuilder
    private func emptyContent(compact: Bool) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.35, green: 0.84, blue: 0.45).opacity(0.85))
                    .frame(width: 6, height: 6)
                Text(model.receiving ? "Waiting for verification codes" : "Monitoring paused")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            if !compact {
                Text(model.receiving ? "Codes from Messages, Mail, and Bitwarden appear here." : "Enable sources in Droppy → Settings → AETHER.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.50))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Code Row

    @ViewBuilder
    private func widgetRow(
        item: CodeItem,
        now: Date,
        compact: Bool
    ) -> some View {
        let concealed = blurCodes && hoveredID != item.id
        Button {
            triggerPrimaryAction(item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                AetherServiceAvatar(
                    item: item,
                    icons: model.icons,
                    model: model,
                    size: compact ? 22 : 28,
                    showsOriginBadge: !compact
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: item.service)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        if !compact {
                            AetherVerificationBadge(item: item, size: 10)
                        }
                    }

                    let sub = rowSubtitle(for: item)
                    if !sub.isEmpty {
                        Text(verbatim: sub)
                            .font(.system(size: 11))
                            .foregroundStyle(item.hasFailedSenderAuth ? AnyShapeStyle(.orange) : AnyShapeStyle(Color.white.opacity(0.70)))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                if item.isLink {
                    Image(systemName: copiedID == item.id ? "checkmark.circle.fill" : "arrow.up.right.square")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(copiedID == item.id ? .green : .teal)
                        .id(copiedID == item.id)
                        .transition(DroppyTransition.element)
                } else {
                    HStack(spacing: 6) {
                        if copiedID == item.id {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                                .transition(DroppyTransition.element)
                        } else {
                            AetherCodeDigitsText(
                                code: item.code,
                                locked: !model.isUnlocked,
                                concealed: concealed,
                                fontSize: compact ? 14 : 17
                            )
                            .foregroundStyle(Color.white)
                            .transition(DroppyTransition.element)
                        }

                        if item.expires > now {
                            AetherExpiryRing(item: item, now: now, size: compact ? 12 : 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .contextMenu {
            AetherCodeContextMenu(item: item, model: model)
        }
    }

    private func rowSubtitle(for item: CodeItem) -> String {
        if item.hasFailedSenderAuth {
            return "Unverified sender · DMARC fail"
        }
        if showPreviews && !item.sender.isEmpty && !item.preview.isEmpty {
            return "\(item.sender) · \(item.preview)"
        }
        if showPreviews && !item.preview.isEmpty {
            return item.preview
        }
        return item.sender
    }

    private func triggerPrimaryAction(_ item: CodeItem) {
        model.unlocked {
            if item.isLink {
                model.open(item)
            } else {
                model.copy(item, userInitiated: true)
            }
            copiedID = item.id
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedID == item.id { copiedID = nil }
            }
        }
    }

    private func combinedItems(at date: Date) -> [CodeItem] {
        let liveItems = model.items.filter { !model.notchDismissedIDs.contains($0.id) }
        let vaultItems = model.isOn(AetherPrefs.bitwarden) ? model.vault.compactMap { CodeItem($0, at: date) } : []
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let shortcuts = model.search.shortcuts(from: vaultItems)
            return liveItems + shortcuts
        }
        return liveItems + vaultItems
    }

    private var attentionSummary: String? {
        let issues = model.sources.filter(\.status.needsAttention)
        guard !issues.isEmpty else { return nil }
        if issues.count == 1, let first = issues.first {
            return "\(first.label): \(first.status.summary)"
        }
        return "\(issues.count) sources need attention"
    }
}
