// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

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

    private var singleView: some View {
        let resolved = layout ?? .standalone
        let metrics = resolved.metrics
        let ink = DroppyWidgetInk(layout: resolved, override: textColor)

        return ShelfWidgetScaffold("AETHER", systemImage: "key.viewfinder") {
            Button(model.isUnlocked ? "Lock" : "Unlock", systemImage: model.isUnlocked ? "lock.fill" : "lock.open.fill") {
                if model.isUnlocked {
                    model.vaultSession.lock()
                } else {
                    model.unlocked {}
                }
            }

            Button("Settings", systemImage: "gearshape") {
                _ = droplet.openSettings()
            }
        } content: {
            DroppyWidgetTimeline(every: 1) { tickNow in
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    if let attention = attentionSummary {
                        Button {
                            _ = droplet.openSettingsPage(
                                AetherSettingsRoute.sources.rawValue,
                                title: "Sources & accounts"
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(verbatim: attention)
                                    .font(metrics.font(.caption))
                                    .foregroundStyle(ink.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(ink.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    if !model.isUnlocked {
                        lockedContent(metrics: metrics, ink: ink, compact: false)
                    } else {
                        let allItems = combinedItems(at: tickNow)
                        if allItems.count > 1 || !query.isEmpty {
                            DroppyShelfTextField("Search codes or Bitwarden…", text: $query)
                        }

                        if allItems.isEmpty {
                            emptyContent(metrics: metrics, ink: ink, compact: false)
                        } else {
                            let displayed = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? allItems
                                : model.search.ranked(allItems, query: query, now: tickNow, secrets: true)

                            if displayed.isEmpty {
                                Text("No matches for \"\(query)\"")
                                    .font(metrics.font(.caption))
                                    .foregroundStyle(ink.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ShelfWidgetRows(displayed, id: \.id, maximumRows: 10, scrollsWhenSingle: true) { item in
                                    widgetRow(item: item, now: tickNow, metrics: metrics, ink: ink, compact: false)
                                }
                            }
                        }
                    }
                }
            }
        } footer: {
            ShelfWidgetControlRow(footerControls)
        }
    }

    private var splitView: some View {
        let resolved = layout ?? .standalone
        let metrics = resolved.metrics
        let ink = DroppyWidgetInk(layout: resolved, override: textColor)

        return ShelfWidgetScaffold("AETHER", systemImage: "key.viewfinder") {
            Button("Settings", systemImage: "gearshape") {
                _ = droplet.openSettings()
            }
        } content: {
            DroppyWidgetTimeline(every: 1) { tickNow in
                if !model.isUnlocked {
                    lockedContent(metrics: metrics, ink: ink, compact: true)
                } else {
                    let allItems = combinedItems(at: tickNow)
                    if allItems.isEmpty {
                        emptyContent(metrics: metrics, ink: ink, compact: true)
                    } else {
                        ShelfWidgetRows(allItems, id: \.id, maximumRows: 2, scrollsWhenSingle: false) { item in
                            widgetRow(item: item, now: tickNow, metrics: metrics, ink: ink, compact: true)
                        }
                    }
                }
            }
        }
    }

    private var footerControls: [ShelfWidgetControl] {
        var controls: [ShelfWidgetControl] = []
        if model.isUnlocked, let latest = model.latestCode {
            controls.append(
                ShelfWidgetControl("Copy Latest", systemImage: "doc.on.doc", tone: .accent(.blue)) {
                    model.copy(latest, userInitiated: true)
                }
            )
        } else if !model.isUnlocked {
            controls.append(
                ShelfWidgetControl("Unlock", systemImage: "touchid", tone: .accent(.blue)) {
                    model.unlocked {}
                }
            )
        }
        controls.append(
            ShelfWidgetControl("Recent Emails", systemImage: "envelope.badge.shield.half.filled") {
                _ = droplet.openSettingsPage(
                    AetherSettingsRoute.recovery.rawValue,
                    title: "Recent emails"
                )
            }
        )
        controls.append(
            ShelfWidgetControl("Sources", systemImage: "tray.2") {
                _ = droplet.openSettingsPage(
                    AetherSettingsRoute.sources.rawValue,
                    title: "Sources & accounts"
                )
            }
        )
        return controls
    }

    @ViewBuilder
    private func lockedContent(metrics: DroppyWidgetMetrics, ink: DroppyWidgetInk, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text(model.latest != nil ? "Verification codes hidden while locked" : "AETHER is locked")
                    .font(metrics.font(.body))
                    .foregroundStyle(ink.primary)
                    .lineLimit(compact ? 2 : 1)
            }
            if !compact {
                let resolved = layout ?? .standalone
                Button("Unlock to View Codes") {
                    model.unlocked {}
                }
                .buttonStyle(
                    DroppyWashPillButtonStyle(
                        height: 28,
                        tone: .accent(.blue),
                        usesAdaptiveForegrounds: resolved.usesAdaptiveForegrounds
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func emptyContent(metrics: DroppyWidgetMetrics, ink: DroppyWidgetInk, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.receiving ? "Waiting for verification codes" : "Monitoring paused")
                .font(metrics.font(.body))
                .foregroundStyle(ink.primary)
                .lineLimit(1)
            if !compact {
                Text(model.receiving ? "Codes from Messages, Mail, and Bitwarden appear here." : "Enable sources in Droppy → Settings → AETHER.")
                    .font(metrics.font(.caption))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func widgetRow(
        item: CodeItem,
        now: Date,
        metrics: DroppyWidgetMetrics,
        ink: DroppyWidgetInk,
        compact: Bool
    ) -> some View {
        let concealed = blurCodes && hoveredID != item.id
        Button {
            triggerPrimaryAction(item)
        } label: {
            HStack(spacing: 8) {
                if !compact {
                    AetherServiceAvatar(item: item, icons: model.icons, model: model, size: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: item.service)
                            .font(metrics.font(.body))
                            .foregroundStyle(ink.primary)
                            .lineLimit(1)
                        let origin = model.origination(item)
                        if !compact && !origin.isEmpty {
                            Text(verbatim: origin)
                                .font(metrics.font(.caption))
                                .foregroundStyle(ink.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !compact && showPreviews && !item.preview.isEmpty {
                        Text(verbatim: item.preview)
                            .font(metrics.font(.caption))
                            .foregroundStyle(ink.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if item.isLink {
                    Image(systemName: copiedID == item.id ? "checkmark.circle.fill" : "arrow.up.right.square")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(copiedID == item.id ? .green : .teal)
                } else {
                    HStack(spacing: 5) {
                        if copiedID == item.id {
                            Text("Copied")
                                .font(metrics.font(.caption))
                                .foregroundStyle(.green)
                        } else {
                            AetherCodeDigitsText(
                                code: item.code,
                                locked: !model.isUnlocked,
                                concealed: concealed,
                                fontSize: compact ? 13 : 15
                            )
                            .foregroundStyle(ink.primary)
                        }
                        if item.expires > now {
                            AetherExpiryRing(item: item, now: now, size: compact ? 12 : 14)
                        }
                    }
                }
            }
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
        let liveItems = model.items
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
