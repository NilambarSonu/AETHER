// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

/// Presents transient notch strips and cards through Droppy's fair `host.hud` queue,
/// displaying real service brand icons and sender identity inside the notch.
@MainActor
final class AetherHUDBridge {
    private var host: DropletHost?
    private weak var model: AetherAppModel?

    func start(host: DropletHost, model: AetherAppModel) {
        self.host = host
        self.model = model
    }

    func stop() {
        host = nil
        model = nil
    }

    func presentArrivalHUD(for item: CodeItem, userInitiated: Bool) {
        guard let host, let model else { return }

        if userInitiated && !item.isLink && model.isUnlocked && model.clipboard.holds(item) {
            presentCopiedHUD(service: item.service)
            return
        }

        let itemID = item.id
        let hudID = "aether-arrival-\(itemID.uuidString)"

        host.hud.present(
            DropletHUDRequest(
                id: hudID,
                duration: 5.5,
                priority: .normal,
                accessibilityLabel: "\(item.service) \(item.isLink ? "sign-in link" : "verification code")",
                isExpanded: true,
                expandedContentHeight: 88
            ) {
                AetherHUDStripView(
                    item: item,
                    model: model,
                    icons: model.icons
                )
            } expanded: {
                AetherHUDCardView(
                    item: item,
                    model: model,
                    icons: model.icons,
                    onCopyOrOpen: { [weak model, weak self, weak host] in
                        model?.unlocked { [weak model, weak self] in
                            guard let model else { return }
                            if item.isLink {
                                model.open(item)
                            } else {
                                model.copy(item, userInitiated: false)
                                self?.presentCopiedHUD(service: item.service)
                            }
                            host?.hud.dismiss(id: hudID)
                        }
                    },
                    onOpenShelf: { [weak host] in
                        host?.hud.dismiss(id: hudID)
                        _ = host?.shelf.open(revealing: AetherDroplet.widgetID)
                    }
                )
            }
        )
    }

    func presentCopiedHUD(service: String) {
        guard let host else { return }
        host.hud.present(DropletHUDRequest(
            id: "aether-copied",
            duration: 2.0,
            priority: .normal,
            accessibilityLabel: "Copied \(service) code",
            card: DropletHUDCard(
                title: "Copied to clipboard",
                message: service,
                systemImage: "checkmark.circle.fill",
                tint: .green
            ),
            isExpanded: false
        ) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                .foregroundStyle(.green)
        } trailing: {
            Text(verbatim: "Copied")
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        })
    }
}

private struct AetherHUDStripView: View {
    let item: CodeItem
    @ObservedObject var model: AetherAppModel
    @ObservedObject var icons: AetherIconStore

    var body: some View {
        let unlocked = model.isUnlocked
        let blur = model.isOn(AetherPrefs.blurCodes)
        let trailingText = item.isLink
            ? (item.destination?.host ?? "Link")
            : (!unlocked ? "Locked" : blur ? "••••••" : AetherNotificationBridge.formatCode(item.code))

        HStack(spacing: DroppyLiveActivityMetrics.contentSpacing) {
            HStack(spacing: 6) {
                AetherServiceAvatar(
                    item: item,
                    icons: icons,
                    model: model,
                    size: 18,
                    showsOriginBadge: false
                )
                Text(verbatim: item.service)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(verbatim: trailingText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(unlocked ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
        }
    }
}

private struct AetherHUDCardView: View {
    let item: CodeItem
    @ObservedObject var model: AetherAppModel
    @ObservedObject var icons: AetherIconStore
    let onCopyOrOpen: () -> Void
    let onOpenShelf: () -> Void

    var body: some View {
        let unlocked = model.isUnlocked
        let blur = model.isOn(AetherPrefs.blurCodes)
        let showPreviews = model.isOn(AetherPrefs.showPreviews)

        VStack(alignment: .leading, spacing: DroppySpacing.smd) {
            HStack(alignment: .center, spacing: DroppySpacing.md) {
                AetherServiceAvatar(
                    item: item,
                    icons: icons,
                    model: model,
                    size: 38,
                    showsOriginBadge: true
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.service)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)

                    if let secondary = secondarySubtitle(unlocked: unlocked, showPreviews: showPreviews) {
                        Text(verbatim: secondary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: DroppySpacing.sm)

                if item.isLink {
                    Image(systemName: item.resetsPassword ? "lock.rotation" : "link.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(item.resetsPassword ? .orange : .teal)
                } else if unlocked {
                    HStack(spacing: 6) {
                        AetherCodeDigitsText(
                            code: item.code,
                            locked: false,
                            concealed: blur,
                            fontSize: 20,
                            weight: .bold
                        )
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        if item.expires > model.now {
                            AetherExpiryRing(item: item, now: model.now, size: 15)
                        }
                    }
                } else {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: DroppySpacing.sm) {
                Button(action: onCopyOrOpen) {
                    Text(primaryButtonTitle(unlocked: unlocked))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyAccentButtonStyle(color: item.isLink ? .teal : .blue, size: .small))

                Button(action: onOpenShelf) {
                    Text("View")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondarySubtitle(unlocked: Bool, showPreviews: Bool) -> String? {
        if !unlocked {
            return "Unlock with Touch ID or your password to copy"
        }
        if item.isLink {
            if showPreviews, !item.sender.isEmpty {
                return "\(item.sender) · \(item.destination?.host ?? item.kind.title)"
            }
            return item.destination?.host ?? item.kind.title
        }
        if showPreviews {
            if !item.sender.isEmpty, !item.preview.isEmpty {
                return "\(item.sender) · \(item.preview)"
            }
            if !item.sender.isEmpty {
                return item.sender
            }
            if !item.preview.isEmpty {
                return item.preview
            }
        }
        return item.sender.isEmpty ? item.sourceLabel : item.sender
    }

    private func primaryButtonTitle(unlocked: Bool) -> String {
        if item.isLink {
            return unlocked ? "Open Link" : "Unlock & Open"
        }
        return unlocked ? "Copy Code" : "Unlock & Copy"
    }
}
