// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct AgentsSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    @State private var skillStates: [AgentSkillKind: AgentSkillKind.State] = [:]
    @State private var errorMessage: String?
    @State private var copiedFeedback = false

    private let homeURL = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        DropletSettingsPage {
            if let pending = model.agents.request, let item = pending.item {
                DropletSettingsSection {
                    settingsSectionHeader("Pending approval")
                } content: {
                    DropletSettingsCard {
                        let site = item.domain ?? pending.query.label
                        DropletControlRow(
                            title: "\(pending.caller.name) wants \(site) \(item.isLink ? "sign-in link" : "code")",
                            icon: "hand.raised.fill",
                            iconColor: .orange,
                            infoTip: "From \(item.service). Touch ID or password approval is required before sharing."
                        ) {
                            HStack(spacing: 8) {
                                Button("Deny") { model.agents.deny() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                Button("Allow Once") {
                                    Task { await model.agents.allow() }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(model.agents.authenticating)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Droppy MCP agent access")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Allow AI agents to request codes",
                        icon: "terminal.fill",
                        iconColor: .indigo,
                        subtitle: "Exposes droplet_aether_get_code, droplet_aether_get_status, and droplet_aether_list_recent_services through Droppy's built-in MCP server.",
                        isOn: Binding(
                            get: { model.agents.config.enabled },
                            set: { on in Task { await model.agents.setEnabled(on) } }
                        )
                    )

                    DropletToggleRow(
                        title: "Allow sharing sign-in links",
                        icon: "link",
                        iconColor: .teal,
                        subtitle: "Lets approved requests receive DMARC-verified destination-matched sign-in links. Password-reset links are never shared.",
                        isOn: Binding(
                            get: { model.agents.config.links },
                            set: { on in Task { await model.agents.setLinks(on) } }
                        )
                    )
                    .disabled(!model.agents.config.enabled)

                    DropletToggleRow(
                        title: "Allow all requests without asking",
                        icon: "bolt.shield.fill",
                        iconColor: .orange,
                        subtitle: "Automatically releases domain-matched codes up to 20 per hour while enabled. Turn off any time.",
                        isOn: Binding(
                            get: { model.agents.config.allowAll },
                            set: { on in Task { await model.agents.setAllowAll(on) } }
                        )
                    )
                    .disabled(!model.agents.config.enabled)

                    AetherWarningRow(
                        message: "Security guardrails: 20 automatic releases/hour max, DMARC alignment enforced on email, password-reset links blocked, and automatic shutoff after 3 consecutive denials. Remember to enable Droppy's built-in MCP server in Settings → Droplet Store → MCP.",
                        calm: true
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Coding agent skills")
            } content: {
                DropletSettingsCard {
                    ForEach(AgentSkillKind.allCases) { kind in
                        let installed = kind.isInstalled(home: homeURL)
                        let state = skillStates[kind] ?? kind.state(home: homeURL)
                        DropletControlRow(
                            title: kind.name,
                            icon: state == .connected ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill",
                            iconColor: state == .connected ? .green : .secondary,
                            infoTip: "Writes the aether-otp skill into \(kind.name)'s local skills folder pointing to Droppy's native MCP tools."
                        ) {
                            skillControls(kind: kind, installed: installed, state: state)
                        }
                    }

                    DropletControlRow(
                        title: "Agent prompt snippet",
                        icon: "doc.on.clipboard",
                        iconColor: .blue,
                        infoTip: "Copies AETHER's MCP instructions for custom agent system prompts."
                    ) {
                        Button(copiedFeedback ? "Copied!" : "Copy Instructions") {
                            droplet.copyText(AgentSkillKind.instructionsMarkdown)
                            copiedFeedback = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.8))
                                copiedFeedback = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Rules & audit log")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Saved approval rules",
                        subtitle: rulesSubtitle,
                        page: AetherSettingsRoute.agentRules.rawValue
                    ) {
                        AetherSymbolTile(symbol: "checkmark.shield.fill", color: .green, size: AetherSymbolTile.settingsLinkSize)
                    }

                    DropletSettingsPageLink(
                        "Request log",
                        subtitle: historySubtitle,
                        page: AetherSettingsRoute.agentHistory.rawValue
                    ) {
                        AetherSymbolTile(symbol: "list.bullet.rectangle.portrait.fill", color: .indigo, size: AetherSymbolTile.settingsLinkSize)
                    }
                }
            }

            if let errorMessage = errorMessage ?? model.agents.error {
                DropletSettingsSection {
                    settingsSectionHeader("Error")
                } content: {
                    DropletSettingsCard {
                        AetherWarningRow(message: errorMessage)
                    }
                }
            }
        }
        .onAppear {
            refreshSkillStates()
        }
    }

    @ViewBuilder
    private func skillControls(kind: AgentSkillKind, installed: Bool, state: AgentSkillKind.State) -> some View {
        HStack(spacing: 8) {
            switch state {
            case .connected:
                Text("Connected").font(.caption).foregroundStyle(.green)
                Button("Disconnect") {
                    do {
                        try kind.disconnect(home: homeURL)
                        refreshSkillStates()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .connectedThrough(let hostKind):
                Text("Shared via \(hostKind.name)").font(.caption).foregroundStyle(.secondary)
            case .taken:
                Text("Existing external skill").font(.caption).foregroundStyle(.orange)
            case .notConnected:
                if installed {
                    Button("Connect") {
                        do {
                            try kind.connect(home: homeURL)
                            refreshSkillStates()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text("Not installed").font(.caption).foregroundStyle(.secondary)
                    Button("Install") {
                        do {
                            try kind.connect(home: homeURL)
                            refreshSkillStates()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func refreshSkillStates() {
        var next: [AgentSkillKind: AgentSkillKind.State] = [:]
        for kind in AgentSkillKind.allCases {
            next[kind] = kind.state(home: homeURL)
        }
        skillStates = next
    }

    private var rulesSubtitle: String {
        let count = model.agents.config.rules.count
        return count == 0 ? "None — asks with Touch ID each time" : "\(count) \(count == 1 ? "rule" : "rules")"
    }

    private var historySubtitle: String {
        let count = model.agents.log.count
        return count == 0 ? "No requests recorded" : "\(count) recent \(count == 1 ? "entry" : "entries")"
    }
}

struct AgentRulesSettingsPage: View {
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Automatic agent approvals (\(model.agents.config.rules.count))")
            } content: {
                DropletSettingsCard {
                    let rules = model.agents.config.rules
                    if rules.isEmpty {
                        AetherWarningRow(
                            message: "No saved auto-approval rules. Rules are created only when you explicitly grant site-wide or blanket access.",
                            calm: true
                        )
                    } else {
                        ForEach(rules) { rule in
                            DropletControlRow(
                                title: "\(rule.app.name) · \(rule.site ?? "All sites")",
                                icon: "checkmark.shield.fill",
                                iconColor: .green,
                                infoTip: "Bundle ID: \(rule.app.id) · Added \(rule.added.formatted(date: .abbreviated, time: .shortened))"
                            ) {
                                Button("Revoke") {
                                    model.agents.removeRule(rule.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        DropletControlRow(
                            title: "Revoke all rules",
                            icon: "trash.fill",
                            iconColor: .red
                        ) {
                            Button("Revoke All…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Revoke all agent approval rules?",
                                    message: "Agents will require explicit Touch ID or password approval for every request again.",
                                    confirmTitle: "Revoke All",
                                    symbol: "trash.fill"
                                )
                                if confirmed {
                                    model.agents.removeRules(Set(rules.map(\.id)))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

struct AgentHistorySettingsPage: View {
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Recent agent requests (\(model.agents.log.count))")
            } content: {
                DropletSettingsCard {
                    if model.agents.log.isEmpty {
                        AetherWarningRow(message: "No agent requests logged yet.", calm: true)
                    } else {
                        ForEach(model.agents.log) { entry in
                            DropletControlRow(
                                title: "\(entry.caller)\(entry.site.isEmpty ? "" : " · \(entry.site)")",
                                icon: "terminal",
                                iconColor: .secondary
                            ) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(entry.outcome)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Text(entry.date.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        DropletControlRow(
                            title: "Clear log",
                            icon: "trash.fill",
                            iconColor: .gray
                        ) {
                            Button("Clear Log") {
                                model.agents.clearLog()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

struct RecoveryEmailsSettingsPage: View {
    @ObservedObject var model: AetherAppModel
    @State private var copiedID: UUID?

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Unmatched recent emails")
            } content: {
                DropletSettingsCard {
                    if !model.isUnlocked {
                        DropletControlRow(
                            title: "Recovery inbox locked",
                            icon: "lock.fill",
                            iconColor: .orange,
                            infoTip: "Unmatched emails from the last 30 minutes stay locked behind Touch ID or your password."
                        ) {
                            Button("Unlock…") {
                                model.unlocked {}
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else if model.recovery.entries.isEmpty {
                        AetherWarningRow(
                            message: "No unmatched code-context emails from the last 30 minutes are currently held in memory.",
                            calm: true
                        )
                    } else {
                        ForEach(model.recovery.entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.message.subject ?? "No Subject")
                                        .font(.headline)
                                    Spacer()
                                    Text(entry.message.date.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("From: \(senderDisplay(for: entry.message))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.message.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .lineLimit(8)
                                HStack {
                                    Button(copiedID == entry.id ? "Copied" : "Copy Email Text") {
                                        if model.copyRecoveryText(entry.message.fullText, from: entry.id) {
                                            copiedID = entry.id
                                            Task {
                                                try? await Task.sleep(for: .seconds(1.5))
                                                if copiedID == entry.id { copiedID = nil }
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Spacer()
                                }
                            }
                            .padding(.vertical, 6)
                        }

                        DropletControlRow(
                            title: "Clear recovery emails",
                            icon: "trash.fill",
                            iconColor: .gray
                        ) {
                            Button("Clear All") {
                                model.recovery.removeAll()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .background(
            AetherScopedCaptureGuard(
                hideFromCapture: model.isOn(AetherPrefs.hideFromCapture) && model.isUnlocked
            )
        )
    }

    private func senderDisplay(for message: IncomingMessage) -> String {
        if message.senderName.isEmpty { return message.senderID }
        if message.senderID.isEmpty || message.senderName == message.senderID { return message.senderName }
        return "\(message.senderName) <\(message.senderID)>"
    }
}
