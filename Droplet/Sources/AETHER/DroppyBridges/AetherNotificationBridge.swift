// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import Combine
import DroppyKit
import Foundation

/// Routes arriving verification codes, sign-in links, and MCP agent approval prompts into Droppy's
/// native notification banner stack (`host.notifications`).
@MainActor
final class AetherNotificationBridge {
    private var cancellable: AnyCancellable?
    private var host: DropletHost?
    private weak var model: AetherAppModel?
    private var activeItemByNotificationID: [String: UUID] = [:]

    func start(host: DropletHost, model: AetherAppModel) {
        stop()
        self.host = host
        self.model = model
        cancellable = host.notifications.events.sink { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        activeItemByNotificationID.removeAll()
        host?.notifications.withdrawAll()
        host = nil
        model = nil
    }

    func presentCodeNotification(for item: CodeItem) {
        guard let host, let model else { return }
        let notificationID = Self.codeNotificationID(for: item.id)
        activeItemByNotificationID[notificationID] = item.id

        let unlocked = model.isUnlocked
        let showPreviews = model.isOn(AetherPrefs.showPreviews)
        let blur = model.isOn(AetherPrefs.blurCodes)

        let formattedCode = Self.formatCode(item.code)
        let title: String
        let body: String
        let actions: [DropletNotificationAction]

        if item.isLink {
            let kindTitle = item.resetsPassword ? "Password reset link" : "Sign-in link"
            title = "\(item.service) — \(kindTitle)"
            if !unlocked {
                body = "Locked — click Open to unlock with Touch ID or your password."
            } else if showPreviews {
                let hostText = item.destination?.host ?? item.service
                body = "\(hostText) · \(item.preview)"
            } else {
                body = item.destination?.host ?? kindTitle
            }
            actions = [
                DropletNotificationAction(id: "open", title: unlocked ? "Open Link" : "Unlock & Open"),
                DropletNotificationAction(id: "copy-link", title: "Copy Link"),
            ]
        } else {
            title = item.service
            if !unlocked {
                body = "Locked — click Copy to unlock with Touch ID or your password."
            } else if blur {
                body = "Code ready (hidden until hover)."
            } else if showPreviews, !item.preview.isEmpty {
                body = "\(formattedCode) · \(item.preview)"
            } else {
                body = "Verification code: \(formattedCode)"
            }
            actions = [
                DropletNotificationAction(id: "copy", title: unlocked ? "Copy Code" : "Unlock & Copy"),
                DropletNotificationAction(id: "dismiss", title: "Dismiss"),
            ]
        }

        _ = host.notifications.post(DropletNotification(
            id: notificationID,
            threadID: "aether-codes",
            title: title,
            body: body,
            systemImage: item.isLink ? "link" : "key.viewfinder",
            actions: actions
        ))
    }

    func withdrawCodeNotification(for itemID: UUID?) {
        guard let host else { return }
        if let itemID {
            let notificationID = Self.codeNotificationID(for: itemID)
            activeItemByNotificationID.removeValue(forKey: notificationID)
            host.notifications.withdraw(id: notificationID)
        }
    }

    func presentAgentState(_ presentation: AetherAgentAccess.Presentation) {
        guard let host else { return }
        switch presentation {
        case .card(let request):
            guard let item = request.item else { return }
            let site = item.domain ?? request.query.label
            let noun = item.isLink ? "sign-in link" : "verification code"
            _ = host.notifications.post(DropletNotification(
                id: Self.agentNotificationID,
                threadID: "aether-agent",
                title: "\(request.caller.name) wants your \(site) \(noun)",
                body: "From \(item.service). Approve with Touch ID to share.",
                systemImage: "terminal.fill",
                actions: [
                    DropletNotificationAction(id: "agent-allow", title: "Allow (Touch ID)"),
                    DropletNotificationAction(id: "agent-deny", title: "Deny"),
                ]
            ))
        case .notice(let item, let caller, let rule):
            let site = item.domain ?? item.service
            let noun = item.isLink ? "sign-in link" : "code"
            let detail = rule == nil
                ? "Allow All Agents is turned on."
                : (rule?.site.map { "\($0) is allowed automatically." } ?? "All sites allowed for \(caller.name).")
            _ = host.notifications.post(DropletNotification(
                id: Self.agentNoticeID,
                threadID: "aether-agent",
                title: "Shared \(site) \(noun) with \(caller.name)",
                body: detail,
                systemImage: "checkmark.shield.fill",
                actions: [
                    DropletNotificationAction(
                        id: rule.map { "agent-revoke-rule:\($0.id.uuidString)" } ?? "agent-disable-allow-all",
                        title: rule == nil ? "Turn Off Allow All" : "Stop Allowing"
                    )
                ]
            ))
        case .hide:
            host.notifications.withdraw(id: Self.agentNotificationID)
        }
    }

    private func handle(_ event: DropletNotificationEvent) {
        guard let model, let host else { return }
        switch event {
        case .opened(let id):
            if activeItemByNotificationID[id] != nil {
                _ = host.shelf.open(revealing: AetherDroplet.widgetID)
            }
        case .action(let id, let actionID):
            if id == Self.agentNotificationID {
                if actionID == "agent-allow" {
                    Task { await model.agents.allow() }
                } else if actionID == "agent-deny" {
                    model.agents.deny()
                }
                return
            }
            if id == Self.agentNoticeID {
                if actionID == "agent-disable-allow-all" {
                    Task { await model.agents.setAllowAll(false) }
                } else if actionID.hasPrefix("agent-revoke-rule:"),
                    let ruleID = UUID(uuidString: String(actionID.dropFirst("agent-revoke-rule:".count)))
                {
                    model.agents.removeRule(ruleID)
                }
                host.notifications.withdraw(id: Self.agentNoticeID)
                return
            }
            guard let itemID = activeItemByNotificationID[id],
                let item = model.items.first(where: { $0.id == itemID })
            else { return }
            switch actionID {
            case "copy":
                model.unlocked { [weak model] in
                    model?.copy(item, userInitiated: true)
                }
                host.notifications.withdraw(id: id)
            case "copy-link":
                model.unlocked { [weak model] in
                    model?.copyLink(item)
                }
                host.notifications.withdraw(id: id)
            case "open":
                model.unlocked { [weak model] in
                    model?.open(item)
                }
                host.notifications.withdraw(id: id)
            case "dismiss":
                model.dismiss(item)
                host.notifications.withdraw(id: id)
            default:
                break
            }
        case .dismissed(let id):
            activeItemByNotificationID.removeValue(forKey: id)
        case .shown:
            break
        @unknown default:
            break
        }
    }

    private static func codeNotificationID(for id: UUID) -> String { "aether-code-\(id.uuidString)" }
    private static let agentNotificationID = "aether-agent-approval"
    private static let agentNoticeID = "aether-agent-notice"

    static func formatCode(_ code: String) -> String {
        if code.count == 6, code.allSatisfy(\.isNumber) {
            return "\(code.prefix(3)) \(code.suffix(3))"
        }
        return code
    }
}
