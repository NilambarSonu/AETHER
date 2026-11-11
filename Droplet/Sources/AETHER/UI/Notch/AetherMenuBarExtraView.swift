// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

struct AetherMenuBarExtraView: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    @State private var query = ""
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    private var blurCodes: Bool { model.isOn(AetherPrefs.blurCodes) }
    private var showPreviews: Bool { model.isOn(AetherPrefs.showPreviews) }
    private var hideFromCapture: Bool { model.isOn(AetherPrefs.hideFromCapture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar

            if let pending = model.agents.request, let item = pending.item {
                pendingAgentBanner(pending: pending, item: item)
            }

            if let issue = attentionSource {
                Button {
                    droplet.openSettingsPage(
                        AetherSettingsRoute.sources.rawValue,
                        title: "Sources & accounts"
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: issue.label)
                                .font(.caption.weight(.semibold))
                            Text(verbatim: issue.status.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !model.isUnlocked {
                lockedState
            } else {
                let allItems = combinedItems
                if allItems.count > 1 || !query.isEmpty {
                    searchField
                }

                if allItems.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let filtered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? allItems
                            : model.search.ranked(allItems, query: query, now: context.date, secrets: true)
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                if filtered.isEmpty {
                                    Text("No verification codes match \"\(query)\"")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 16)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    ForEach(filtered) { item in
                                        popoverRow(item: item, now: context.date)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }
            }

            Divider()

            footerBar
        }
        .padding(12)
        .frame(width: 320)
        .background(
            AetherScopedCaptureGuard(
                hideFromCapture: hideFromCapture && model.isUnlocked
            )
        )
        .onAppear {
            droplet.setPopoverVisible(true)
        }
        .onDisappear {
            droplet.setPopoverVisible(false)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            AetherSettingsIconBadge(
                symbol: "key.viewfinder",
                top: Color(red: 0.24, green: 0.62, blue: 1.00),
                bottom: Color(red: 0.08, green: 0.40, blue: 0.88),
                size: 22
            )
            Text("AETHER")
                .font(.headline)
            Spacer()
            Button {
                model.boostSources()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Check mailboxes now")

            Button {
                if model.isUnlocked {
                    model.vaultSession.lock()
                } else {
                    model.unlocked {}
                }
            } label: {
                Image(systemName: model.isUnlocked ? "lock.open.fill" : "lock.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.isUnlocked ? "Lock codes" : "Unlock codes")

            Button {
                _ = droplet.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open AETHER Settings in Droppy")
        }
    }

    @ViewBuilder
    private func pendingAgentBanner(pending: AetherAgentAccess.Request, item: CodeItem) -> some View {
        let site = item.domain ?? pending.query.label
        VStack(alignment: .leading, spacing: 6) {
            Text("\(pending.caller.name) asks for \(site)")
                .font(.caption.weight(.semibold))
            Text("From \(item.service). Touch ID required to release.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("Deny") { model.agents.deny() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Allow") { Task { await model.agents.allow() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.agents.authenticating)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous))
    }

    private var lockedState: some View {
        VStack(spacing: 10) {
            AetherSettingsIconBadge(
                symbol: "lock.shield.fill",
                top: .orange,
                bottom: Color(red: 0.85, green: 0.42, blue: 0.05),
                size: 36
            )
            Text("Codes are protected")
                .font(.subheadline.weight(.medium))
            Button("Unlock with Touch ID / Password") {
                model.unlocked {}
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.viewfinder")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(model.receiving ? "Waiting for verification codes" : "Monitoring is paused")
                .font(.subheadline)
            Text(model.receiving
                ? "Messages, Mail, and Bitwarden TOTP codes appear automatically."
                : "Turn on sources in Droppy → Settings → Droplets → AETHER.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search codes or Bitwarden…", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func popoverRow(item: CodeItem, now: Date) -> some View {
        let concealed = blurCodes && hoveredID != item.id
        Button {
            triggerAction(item)
        } label: {
            HStack(spacing: 10) {
                AetherServiceAvatar(item: item, icons: model.icons, model: model, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: item.service)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        let origin = model.origination(item)
                        if !origin.isEmpty {
                            Text(verbatim: origin)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    let secondary = rowSubtitle(for: item)
                    if !secondary.isEmpty {
                        Text(verbatim: secondary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if item.origin != .vault {
                        Text(verbatim: item.received.aetherDayTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                if item.isLink {
                    Text(copiedID == item.id ? "Opened" : "Open")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copiedID == item.id ? .green : .teal)
                } else {
                    HStack(spacing: 6) {
                        if copiedID == item.id {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            AetherCodeDigitsText(
                                code: item.code,
                                locked: !model.isUnlocked,
                                concealed: concealed,
                                fontSize: 15
                            )
                        }
                        if item.expires > now {
                            AetherExpiryRing(item: item, now: now, size: 14)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                    .fill(hoveredID == item.id ? Color.primary.opacity(0.08) : Color.clear)
            )
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
        if showPreviews && !item.sender.isEmpty && !item.preview.isEmpty {
            return "\(item.sender) · \(item.preview)"
        }
        if showPreviews && !item.preview.isEmpty {
            return item.preview
        }
        return item.sender
    }

    private var footerBar: some View {
        HStack {
            Button("Recent Emails…") {
                droplet.openSettingsPage(
                    AetherSettingsRoute.recovery.rawValue,
                    title: "Recent emails"
                )
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if model.isUnlocked, let latest = model.latestCode {
                Button("Copy Latest") {
                    triggerAction(latest)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Settings…") {
                    _ = droplet.openSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func triggerAction(_ item: CodeItem) {
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

    private var combinedItems: [CodeItem] {
        let now = Date()
        let liveItems = model.items
        let vaultItems = model.isOn(AetherPrefs.bitwarden) ? model.vault.compactMap { CodeItem($0, at: now) } : []
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let shortcuts = model.search.shortcuts(from: vaultItems)
            return liveItems + shortcuts
        }
        return liveItems + vaultItems
    }

    private var attentionSource: (key: String, label: String, status: SourceStatus)? {
        model.sources.first(where: { $0.status.needsAttention })
    }
}
