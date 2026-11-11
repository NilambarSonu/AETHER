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
                        AetherSettingsControlRow(
                            title: "\(pending.caller.name) wants \(site) \(item.isLink ? "sign-in link" : "code")",
                            subtitle: "From \(item.service) · Touch ID approval required",
                            icon: "hand.raised.fill",
                            iconColor: .orange
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
                    AetherSettingsToggleRow(
                        title: "Allow AI agents to request codes",
                        icon: "terminal.fill",
                        iconColor: .indigo,
                        infoTip: "Exposes droplet_aether_get_code, droplet_aether_get_status, and droplet_aether_list_recent_services through Droppy's MCP server.",
                        isOn: Binding(
                            get: { model.agents.config.enabled },
                            set: { on in Task { await model.agents.setEnabled(on) } }
                        )
                    )

                    AetherSettingsToggleRow(
                        title: "Allow sharing sign-in links",
                        icon: "link",
                        iconColor: .teal,
                        infoTip: "Releases DMARC-verified, destination-matched sign-in links. Password-reset links are always blocked.",
                        isOn: Binding(
                            get: { model.agents.config.links },
                            set: { on in Task { await model.agents.setLinks(on) } }
                        )
                    )
                    .disabled(!model.agents.config.enabled)

                    AetherSettingsToggleRow(
                        title: "Allow all requests without asking",
                        icon: "bolt.shield.fill",
                        iconColor: .orange,
                        infoTip: "Auto-releases domain-matched codes up to 20 per hour. Config is AEAD tamper-sealed in Keychain.",
                        isOn: Binding(
                            get: { model.agents.config.allowAll },
                            set: { on in Task { await model.agents.setAllowAll(on) } }
                        )
                    )
                    .disabled(!model.agents.config.enabled)
                }

                DropletSettingsCard {
                    AetherWarningRow(
                        message: "Security guardrails: 20 automatic releases/hour max, DMARC alignment checked on email, password-reset links blocked, and auto-lock after 3 consecutive denials.",
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
                        AetherSettingsControlRow(
                            title: kind.name,
                            icon: state == .connected ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill",
                            iconColor: state == .connected ? .green : .gray,
                            infoTip: "Writes the aether-otp skill into \(kind.name)'s local skills folder pointing to Droppy MCP."
                        ) {
                            skillControls(kind: kind, installed: installed, state: state)
                        }
                    }

                    AetherSettingsControlRow(
                        title: "Agent prompt snippet",
                        icon: "doc.on.clipboard.fill",
                        iconColor: .blue,
                        infoTip: "Copies AETHER's MCP usage snippet for custom agent prompts."
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
                        AetherSettingsIconBadge(
                            symbol: "checkmark.shield.fill",
                            top: Color(red: 0.22, green: 0.78, blue: 0.36),
                            bottom: Color(red: 0.10, green: 0.56, blue: 0.24),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Encrypted request log",
                        subtitle: historySubtitle,
                        page: AetherSettingsRoute.agentHistory.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "list.bullet.rectangle.portrait.fill",
                            top: Color(red: 0.40, green: 0.38, blue: 0.96),
                            bottom: Color(red: 0.24, green: 0.22, blue: 0.78),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }
                }
            }

            if let errorMessage = errorMessage ?? model.agents.error {
                DropletSettingsSection {
                    settingsSectionHeader("Attention")
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
                            AetherSettingsControlRow(
                                title: "\(rule.app.name) · \(rule.site ?? "All sites")",
                                subtitle: rule.added.formatted(date: .abbreviated, time: .shortened),
                                icon: "checkmark.shield.fill",
                                iconColor: .green,
                                infoTip: "Bundle ID: \(rule.app.id)"
                            ) {
                                Button("Revoke") {
                                    model.agents.removeRule(rule.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        AetherSettingsControlRow(
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
                            AetherSettingsControlRow(
                                title: "\(entry.caller)\(entry.site.isEmpty ? "" : " · \(entry.site)")",
                                subtitle: entry.date.formatted(.relative(presentation: .named)),
                                icon: "terminal.fill",
                                iconColor: .indigo
                            ) {
                                Text(entry.outcome)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        AetherSettingsControlRow(
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
                        AetherSettingsControlRow(
                            title: "Recovery inbox locked",
                            subtitle: "Unmatched emails from the last 30 minutes stay locked behind Touch ID.",
                            icon: "lock.fill",
                            iconColor: .orange
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

                        AetherSettingsControlRow(
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
