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
                settingsSectionHeader("Access")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Allow AI agents to request codes",
                        icon: "terminal.fill",
                        iconColor: .indigo,
                        isOn: Binding(
                            get: { model.agents.config.enabled },
                            set: { on in Task { await model.agents.setEnabled(on) } }
                        )
                    )

                    if model.agents.config.enabled {
                        DropletToggleRow(
                            title: "Allow sign-in links",
                            icon: "link",
                            iconColor: .teal,
                            isOn: Binding(
                                get: { model.agents.config.links },
                                set: { on in Task { await model.agents.setLinks(on) } }
                            )
                        )
                    }
                }

                Text("Every request needs Touch ID. Limits: 20 per hour, sender checks, password-reset links always blocked, auto-lock after 3 denials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DroppySettingsLayoutMetrics.sectionHeaderLeadingInset)
            }

            if model.agents.config.enabled {
                DropletSettingsSection {
                    settingsSectionHeader("Advanced")
                } content: {
                    DropletSettingsCard {
                        DropletToggleRow(
                            title: "Skip approval prompts",
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .orange,
                            subtitle: "Agents get codes without Touch ID. Not recommended.",
                            isOn: Binding(
                                get: { model.agents.config.allowAll },
                                set: { on in Task { await model.agents.setAllowAll(on) } }
                            )
                        )
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Connect an agent")
            } content: {
                DropletSettingsCard {
                    ForEach(AgentSkillKind.allCases) { kind in
                        let installed = kind.isInstalled(home: homeURL)
                        let state = skillStates[kind] ?? kind.state(home: homeURL)
                        DropletControlRow(
                            title: kind.name,
                            icon: state == .connected ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill",
                            iconColor: state == .connected ? .green : .secondary
                        ) {
                            skillControls(kind: kind, installed: installed, state: state)
                        }
                    }

                    DropletControlRow(
                        title: "Copy setup instructions",
                        icon: "doc.on.clipboard.fill",
                        iconColor: .blue
                    ) {
                        Button(copiedFeedback ? "Copied" : "Copy") {
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

                Text("Adds AETHER instructions to your coding agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DroppySettingsLayoutMetrics.sectionHeaderLeadingInset)
            }

            DropletSettingsSection {
                settingsSectionHeader("Activity")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Approval rules",
                        subtitle: rulesSubtitle,
                        page: AetherSettingsRoute.agentRules.rawValue
                    ) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.green)
                    }

                    DropletSettingsPageLink(
                        "Request log",
                        subtitle: historySubtitle,
                        page: AetherSettingsRoute.agentHistory.rawValue
                    ) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.purple)
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
        .navigationTitle("AI agents")
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
                settingsSectionHeader("Unmatched emails")
            } content: {
                if !model.isUnlocked {
                    DropletSettingsCard {
                        DropletControlRow(
                            title: "Inbox locked",
                            icon: "lock.fill",
                            iconColor: .orange,
                            infoTip: "Unmatched emails stay locked behind Touch ID."
                        ) {
                            Button("Unlock…") {
                                model.unlocked {}
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                } else if model.recovery.entries.isEmpty {
                    VStack(spacing: DroppySpacing.md) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text("Nothing to review")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Emails that looked like codes but didn't match are held in memory for 30 minutes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DroppySpacing.xxxl)
                } else {
                    DropletSettingsCard {
                        ForEach(model.recovery.entries) { entry in
                            VStack(alignment: .leading, spacing: DroppySpacing.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.message.subject ?? "No Subject")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(entry.message.date.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(senderDisplay(for: entry.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(entry.message.text)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                                HStack {
                                    Button(copiedID == entry.id ? "Copied" : "Copy email text") {
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
                                .padding(.top, 2)
                            }
                            .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
                            .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)
                        }
                    }
                }
            }
        }
        .navigationTitle("Unmatched emails")
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
