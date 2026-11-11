// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

/// Presents transient notch strips and cards through Droppy's fair `host.hud` queue.
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

        let unlocked = model.isUnlocked
        let blur = model.isOn(AetherPrefs.blurCodes)
        let displayCode = item.isLink
            ? (item.destination?.host ?? "Sign-in link")
            : (!unlocked ? "Locked" : blur ? "••••••" : AetherNotificationBridge.formatCode(item.code))

        let cardTitle = item.isLink
            ? "\(item.service) — \(item.kind.title)"
            : (!unlocked ? "\(item.service) code arrived" : "\(item.service) · \(displayCode)")
        let cardMessage: String? = {
            if !unlocked { return "Unlock with Touch ID or your password to copy." }
            if item.isLink { return item.destination?.host ?? item.preview }
            return model.isOn(AetherPrefs.showPreviews) && !item.preview.isEmpty ? item.preview : nil
        }()

        let primaryAction: DropletHUDAction = item.isLink
            ? DropletHUDAction(title: unlocked ? "Open Link" : "Unlock", isPrimary: true) { [weak model] in
                model?.unlocked { [weak model] in model?.open(item) }
            }
            : DropletHUDAction(title: unlocked ? "Copy Code" : "Unlock & Copy", isPrimary: true) { [weak model, weak self] in
                model?.unlocked { [weak model, weak self] in
                    model?.copy(item, userInitiated: false)
                    self?.presentCopiedHUD(service: item.service)
                }
            }

        let secondaryAction = DropletHUDAction(title: "View") { [weak self] in
            _ = self?.host?.shelf.open(revealing: AetherDroplet.widgetID)
        }

        let priority: DropletHUDPriority = .normal
        host.hud.present(DropletHUDRequest(
            id: "aether-arrival-\(item.id.uuidString)",
            duration: 5.0,
            priority: priority,
            accessibilityLabel: "\(item.service) \(item.isLink ? "sign-in link" : "verification code")",
            card: DropletHUDCard(
                title: cardTitle,
                message: cardMessage,
                systemImage: item.isLink ? "link" : "key.viewfinder",
                tint: item.isLink ? .teal : .blue,
                actions: [primaryAction, secondaryAction]
            ),
            isExpanded: true
        ) {
            Image(systemName: item.isLink ? "link" : "key.viewfinder")
                .font(.system(size: DroppyLiveActivityMetrics.compactSymbolSize, weight: .semibold))
                .foregroundStyle(item.isLink ? .teal : .blue)
        } trailing: {
            Text(verbatim: displayCode)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        })
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
                .font(.system(size: DroppyLiveActivityMetrics.compactSymbolSize, weight: .semibold))
                .foregroundStyle(.green)
        } trailing: {
            Text(verbatim: "Copied")
                .font(.system(size: 13, weight: .semibold))
        })
    }
}
