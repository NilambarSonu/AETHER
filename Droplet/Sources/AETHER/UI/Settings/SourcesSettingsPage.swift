// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct SourcesSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    @State private var expandedSourceKey: String?

    private var messagesEnabled: Bool { model.isOn(AetherPrefs.messages) }
    private var appleMailEnabled: Bool { model.isOn(AetherPrefs.appleMail) }

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("What to catch")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Verification codes",
                        icon: "number",
                        iconColor: .blue,
                        subtitle: "Read OTP codes from Messages and mail. Turning this off stops reading Messages.",
                        isOn: setting(AetherPrefs.receivedCodes)
                    )

                    DropletToggleRow(
                        title: "Sign-in links",
                        icon: "link",
                        iconColor: .teal,
                        subtitle: "Read magic sign-in links from email. Links open only when clicked while unlocked.",
                        isOn: setting(AetherPrefs.signInLinks)
                    )

                    DropletToggleRow(
                        title: "Password reset links",
                        icon: "lock.rotation",
                        iconColor: .orange,
                        subtitle: "Read password-reset links from email. Never shared with AI agents.",
                        isOn: setting(AetherPrefs.resetLinks)
                    )

                    DropletSettingsPageLink(
                        "Ignored senders",
                        subtitle: ignoredSummary,
                        page: AetherSettingsRoute.ignoredSenders.rawValue
                    ) {
                        AetherSymbolTile(symbol: "nosign", color: .gray, size: DropletSettingsPageLink.tileSize)
                    }

                    DropletSettingsPageLink(
                        "Not a code",
                        subtitle: notCodeSummary,
                        page: AetherSettingsRoute.notCodes.rawValue
                    ) {
                        AetherSymbolTile(symbol: "xmark.seal.fill", color: .gray, size: DropletSettingsPageLink.tileSize)
                    }

                    if !model.receiving {
                        AetherWarningRow(message: "Messages and mail are paused while all three options above are off.", calm: true)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Messages")
            } content: {
                DropletSettingsCard {
                    let msgStatus = model.status[MessagesStore.sourceKey] ?? .off
                    let codesOn = model.isOn(AetherPrefs.receivedCodes)
                    DropletControlRow(
                        title: "Messages",
                        icon: "message.fill",
                        iconColor: .green,
                        infoTip: "Reads iMessage and forwarded SMS locally from chat.db using Droppy's Full Disk Access."
                    ) {
                        HStack(spacing: 8) {
                            AetherSourceStatusDot(status: msgStatus)
                            Text(codesOn ? msgStatus.summary : "Paused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                toggleHealth(MessagesStore.sourceKey)
                            } label: {
                                Image(systemName: expandedSourceKey == MessagesStore.sourceKey ? "chevron.up" : "info.circle")
                            }
                            .buttonStyle(.borderless)
                            Toggle("Messages", isOn: model.boolBinding(AetherPrefs.messages))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .onChange(of: messagesEnabled) { _, _ in model.restartMessages() }
                        }
                    }

                    if expandedSourceKey == MessagesStore.sourceKey {
                        sourceHealthPanel(
                            key: MessagesStore.sourceKey,
                            enabled: messagesEnabled && codesOn,
                            description: "Reads iMessage and forwarded SMS from ~/Library/Messages/chat.db."
                        )
                    }

                    if messagesEnabled && msgStatus.needsDiskAccess {
                        diskAccessRow
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Mail")
            } content: {
                DropletSettingsCard {
                    let mailStatus = model.status[AppleMailStore.sourceKey] ?? .off
                    DropletControlRow(
                        title: "Apple Mail",
                        icon: "tray.fill",
                        iconColor: .cyan,
                        infoTip: "Reads inboxes downloaded by the Apple Mail app read-only using Droppy's Full Disk Access."
                    ) {
                        HStack(spacing: 8) {
                            AetherSourceStatusDot(status: mailStatus)
                            Text(mailStatus.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                toggleHealth(AppleMailStore.sourceKey)
                            } label: {
                                Image(systemName: expandedSourceKey == AppleMailStore.sourceKey ? "chevron.up" : "info.circle")
                            }
                            .buttonStyle(.borderless)
                            Toggle("Apple Mail", isOn: model.boolBinding(AetherPrefs.appleMail))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .onChange(of: appleMailEnabled) { _, _ in model.restartAppleMail() }
                        }
                    }

                    if expandedSourceKey == AppleMailStore.sourceKey {
                        sourceHealthPanel(
                            key: AppleMailStore.sourceKey,
                            enabled: appleMailEnabled && model.receiving,
                            description: "Reads downloaded messages in ~/Library/Mail without altering read state."
                        )
                    }

                    if appleMailEnabled && mailStatus.needsDiskAccess {
                        diskAccessRow
                    }

                    ForEach(model.accounts) { account in
                        let key = account.id.uuidString
                        let accStatus = model.status[key] ?? .off
                        DropletControlRow(
                            title: account.label,
                            icon: "envelope.fill",
                            iconColor: account.isGmail ? .red : account.isOutlook ? .blue : .secondary,
                            infoTip: "\(account.user) — Nothing is changed or marked as read. Credentials stay in your Keychain."
                        ) {
                            HStack(spacing: 8) {
                                AetherSourceStatusDot(status: accStatus)
                                Text(account.user)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Button("Edit…") {
                                    droplet.openSettingsPage(
                                        AetherSettingsRoute.editAccount(account.id),
                                        title: account.label
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Toggle(
                                    "Watch \(account.label)",
                                    isOn: Binding(
                                        get: { account.enabled },
                                        set: { enabled in
                                            var updated = account
                                            updated.enabled = enabled
                                            model.save(updated)
                                        }
                                    )
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }

                    DropletSettingsPageLink(
                        "Add mail account…",
                        subtitle: "Google Gmail, Microsoft Outlook / 365, iCloud, Yahoo, or any IMAP server",
                        page: AetherSettingsRoute.addAccount.rawValue
                    ) {
                        AetherSymbolTile(symbol: "plus", color: .blue, size: DropletSettingsPageLink.tileSize)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Bitwarden")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Bitwarden authenticator",
                        subtitle: vaultSubtitle,
                        page: AetherSettingsRoute.bitwarden.rawValue
                    ) {
                        AetherSymbolTile(symbol: "key.fill", color: .blue, size: DropletSettingsPageLink.tileSize)
                    }

                    if model.hasVault {
                        DropletToggleRow(
                            title: "Enable Bitwarden codes",
                            icon: "key.fill",
                            iconColor: .blue,
                            subtitle: "Generates TOTP codes locally from Keychain-saved keys.",
                            isOn: setting(AetherPrefs.bitwarden)
                        )
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
    }

    private var diskAccessRow: some View {
        DropletControlRow(
            title: "Full Disk Access needed",
            icon: "lock.shield.fill",
            iconColor: .orange,
            infoTip: "Used only to read Messages and Apple Mail. Turn on Droppy in System Settings."
        ) {
            Button("Allow…") {
                droplet.openFullDiskAccessSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func sourceHealthPanel(key: String, enabled: Bool, description: String) -> some View {
        let h = model.monitor.health[key] ?? SourceHealth()
        return VStack(alignment: .leading, spacing: 6) {
            Text(description).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Text("Checked: \(relative(h.lastChecked))")
                Text("Message: \(relative(h.lastMessage))")
                Text("Code: \(relative(h.lastCode))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let retryAt = h.retryAt {
                Text("Retrying in \(max(0, Int(ceil(retryAt.timeIntervalSince(model.now)))))s")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Button("Check Now") {
                model.monitor.check(key)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!enabled)
        }
        .padding(.vertical, 4)
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "not yet" }
        if model.now.timeIntervalSince(date) < 1 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: model.now)
    }

    private func toggleHealth(_ key: String) {
        expandedSourceKey = expandedSourceKey == key ? nil : key
    }

    private func setting(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isOn(key) }, set: { model.set(key, on: $0) })
    }

    private var ignoredSummary: String {
        switch model.ignoredSenders.count {
        case 0: "None"
        case 1: "1 sender"
        case let count: "\(count) senders"
        }
    }

    private var notCodeSummary: String {
        switch model.notCodes.count {
        case 0: "None"
        case 1: "1 rule"
        case let count: "\(count) rules"
        }
    }

    private var vaultSubtitle: String {
        guard model.hasVault else { return "Import TOTP authenticator keys via Bitwarden CLI" }
        guard model.isOn(AetherPrefs.bitwarden) else { return "Off · saved keys preserved" }
        let state = model.vaultSession.isUnlocked ? "\(model.vault.count) codes" : "Locked"
        guard let imported = model.defaults.object(forKey: AetherPrefs.vaultImportedAt) as? Date else { return state }
        return "\(state) · imported \(imported.formatted(.relative(presentation: .named)))"
    }
}
