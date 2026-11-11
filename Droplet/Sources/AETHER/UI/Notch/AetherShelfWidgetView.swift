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

    private var singleView: some View {
        ShelfWidgetScaffold("AETHER", systemImage: "key.viewfinder") {
            Button(model.isUnlocked ? "Lock" : "Unlock", systemImage: model.isUnlocked ? "lock.fill" : "lock.open.fill") {
                if model.isUnlocked {
                    model.vaultSession.lock()
                } else {
                    model.unlocked {}
                }
            }

            Button {
                model.boostSources()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Check mailboxes now")

            Button {
                _ = droplet.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Open AETHER Settings")
        } content: {
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
                        lockedContent(compact: false)
                    } else {
                        let allItems = combinedItems(at: tickNow)
                        if allItems.count > 1 || !query.isEmpty {
                            DroppyShelfTextField("Search codes or Bitwarden…", text: $query)
                        }

                        if allItems.isEmpty {
                            emptyContent(compact: false)
                        } else {
                            let displayed = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? allItems
                                : model.search.ranked(allItems, query: query, now: tickNow, secrets: true)

                            if displayed.isEmpty {
                                Text("No matches for \"\(query)\"")
                                    .font(metrics.font(.caption))
                                    .foregroundStyle(secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ShelfWidgetRows(displayed, id: \.id, maximumRows: 10, scrollsWhenSingle: true) { item in
                                    widgetRow(item: item, now: tickNow, compact: false)
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
        ShelfWidgetScaffold("AETHER", systemImage: "key.viewfinder") {
            Button("Settings", systemImage: "gearshape") {
                _ = droplet.openSettings()
            }
        } content: {
            DroppyWidgetTimeline(every: 1) { tickNow in
                if !model.isUnlocked {
                    lockedContent(compact: true)
                } else {
                    let allItems = combinedItems(at: tickNow)
                    if allItems.isEmpty {
                        emptyContent(compact: true)
                    } else {
                        ShelfWidgetRows(allItems, id: \.id, maximumRows: 2, scrollsWhenSingle: false) { item in
                            widgetRow(item: item, now: tickNow, compact: true)
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
                    triggerPrimaryAction(latest)
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
                droplet.openSettingsPage(
                    AetherSettingsRoute.recovery.rawValue,
                    title: "Recent emails"
                )
            }
        )
        controls.append(
            ShelfWidgetControl("Sources", systemImage: "tray.2") {
                droplet.openSettingsPage(
                    AetherSettingsRoute.sources.rawValue,
                    title: "Sources & accounts"
                )
            }
        )
        return controls
    }

    @ViewBuilder
    private func lockedContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text(model.latest != nil ? "Verification codes hidden while locked" : "AETHER is locked")
                    .font(metrics.font(.body))
                    .foregroundStyle(primaryInk)
                    .lineLimit(compact ? 2 : 1)
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
        }
    }

    @ViewBuilder
    private func emptyContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.receiving ? "Waiting for verification codes" : "Monitoring paused")
                .font(metrics.font(.body))
                .foregroundStyle(primaryInk)
                .lineLimit(1)
            if !compact {
                Text(model.receiving ? "Codes from Messages, Mail, and Bitwarden appear here." : "Enable sources in Droppy → Settings → AETHER.")
                    .font(metrics.font(.caption))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(2)
            }
        }
    }

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
            HStack(spacing: 8) {
                AetherServiceAvatar(
                    item: item,
                    icons: model.icons,
                    model: model,
                    size: compact ? 20 : 26,
                    showsOriginBadge: !compact
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: item.service)
                            .font(metrics.font(.body))
                            .foregroundStyle(primaryInk)
                            .lineLimit(1)
                        if !compact {
                            AetherVerificationBadge(item: item, size: 10)
                        }
                        let origin = model.origination(item)
                        if !compact && !origin.isEmpty {
                            Text(verbatim: origin)
                                .font(metrics.font(.caption))
                                .foregroundStyle(secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    if !compact {
                        let sub = rowSubtitle(for: item)
                        if !sub.isEmpty {
                            Text(verbatim: sub)
                                .font(metrics.font(.caption))
                                .foregroundStyle(item.hasFailedSenderAuth ? AnyShapeStyle(.orange) : AnyShapeStyle(secondaryInk))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 6)
                if item.isLink {
                    Image(systemName: copiedID == item.id ? "checkmark.circle.fill" : "arrow.up.right.square")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(copiedID == item.id ? .green : .teal)
                        .id(copiedID == item.id)
                        .transition(DroppyTransition.element)
                } else {
                    HStack(spacing: 5) {
                        if copiedID == item.id {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .font(metrics.font(.caption))
                                .foregroundStyle(.green)
                                .transition(DroppyTransition.element)
                        } else {
                            AetherCodeDigitsText(
                                code: item.code,
                                locked: !model.isUnlocked,
                                concealed: concealed,
                                fontSize: compact ? 13 : 15
                            )
                            .foregroundStyle(primaryInk)
                            .transition(DroppyTransition.element)
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
