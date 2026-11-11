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
                    AetherSettingsToggleRow(
                        title: "Verification codes",
                        subtitle: "Detects numeric and alphanumeric OTPs in Messages and email.",
                        icon: "number",
                        iconColor: .blue,
                        isOn: setting(AetherPrefs.receivedCodes)
                    )

                    AetherSettingsToggleRow(
                        title: "Sign-in links",
                        subtitle: "Detects magic login links in email (never auto-copied).",
                        icon: "link",
                        iconColor: .teal,
                        isOn: setting(AetherPrefs.signInLinks)
                    )

                    AetherSettingsToggleRow(
                        title: "Password reset links",
                        subtitle: "Flags password reset links locally; strictly blocked from AI agents.",
                        icon: "lock.rotation",
                        iconColor: .orange,
                        isOn: setting(AetherPrefs.resetLinks)
                    )

                    if !model.receiving {
                        AetherWarningRow(
                            message: "Messages and mail monitoring are paused while all three options above are off.",
                            calm: true
                        )
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Filtering rules")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Ignored senders",
                        subtitle: ignoredSummary,
                        page: AetherSettingsRoute.ignoredSenders.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "nosign",
                            top: Color(white: 0.45),
                            bottom: Color(white: 0.28),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Not a code rules",
                        subtitle: notCodeSummary,
                        page: AetherSettingsRoute.notCodes.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "xmark.seal.fill",
                            top: Color(red: 0.56, green: 0.58, blue: 0.64),
                            bottom: Color(red: 0.36, green: 0.38, blue: 0.44),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Messages & Apple Mail")
            } content: {
                DropletSettingsCard {
                    let msgStatus = model.status[MessagesStore.sourceKey] ?? .off
                    let codesOn = model.isOn(AetherPrefs.receivedCodes)
                    AetherSettingsControlRow(
                        title: "Messages",
                        subtitle: codesOn ? "iMessage & SMS · \(msgStatus.summary)" : "Paused while Verification codes is off",
                        icon: "message.fill",
                        iconColor: .green,
                        infoTip: "Reads ~/Library/Messages/chat.db strictly read-only using Droppy's Full Disk Access."
                    ) {
                        HStack(spacing: 8) {
                            AetherSourceStatusDot(status: msgStatus)
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
                            description: "Reads iMessage and forwarded SMS via FSEvents without copying chat.db."
                        )
                    }

                    if messagesEnabled && msgStatus.needsDiskAccess {
                        diskAccessRow
                    }

                    let mailStatus = model.status[AppleMailStore.sourceKey] ?? .off
                    AetherSettingsControlRow(
                        title: "Apple Mail",
                        subtitle: "Local Mailboxes · \(mailStatus.summary)",
                        icon: "tray.fill",
                        iconColor: .cyan,
                        topColor: .blue,
                        infoTip: "Reads Mail.app inboxes strictly read-only without changing unread badges."
                    ) {
                        HStack(spacing: 8) {
                            AetherSourceStatusDot(status: mailStatus)
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
                            description: "Reads downloaded .emlx bodies in ~/Library/Mail without altering state."
                        )
                    }

                    if appleMailEnabled && mailStatus.needsDiskAccess {
                        diskAccessRow
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Cloud & IMAP mailboxes")
            } content: {
                if !model.accounts.isEmpty {
                    DropletSettingsCard {
                        ForEach(model.accounts) { account in
                            let key = account.id.uuidString
                            let accStatus = model.status[key] ?? .off
                            let style = accountBadgeStyle(for: account)
                            AetherSettingsControlRow(
                                title: account.label,
                                subtitle: "\(account.user) · \(accStatus.summary)",
                                icon: style.symbol,
                                iconColor: style.bottom,
                                topColor: style.top,
                                infoTip: "Credentials sealed with AES-256-GCM in macOS Keychain. Never modifies unread status."
                            ) {
                                HStack(spacing: 8) {
                                    AetherSourceStatusDot(status: accStatus)
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
                    }
                }

                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Add mail account…",
                        subtitle: "Google Gmail, Microsoft Outlook / 365, iCloud, Yahoo, or any IMAP server",
                        page: AetherSettingsRoute.addAccount.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "plus",
                            top: Color(red: 0.20, green: 0.56, blue: 1.00),
                            bottom: Color(red: 0.08, green: 0.36, blue: 0.88),
                            size: AetherSymbolTile.settingsLinkSize
                        )
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
                        AetherSettingsIconBadge(
                            symbol: "key.fill",
                            top: Color(red: 0.14, green: 0.48, blue: 0.96),
                            bottom: Color(red: 0.06, green: 0.30, blue: 0.78),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }
                }

                if model.hasVault {
                    DropletSettingsCard {
                        AetherSettingsToggleRow(
                            title: "Enable Bitwarden TOTP codes",
                            subtitle: "Generates local 2FA codes from encrypted Keychain secrets.",
                            icon: "lock.shield.fill",
                            iconColor: .blue,
                            isOn: setting(AetherPrefs.bitwarden)
                        )
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
    }

    private func accountBadgeStyle(for account: MailAccount) -> (symbol: String, top: Color, bottom: Color) {
        if account.isGmail {
            return ("envelope.badge.fill", Color(red: 0.94, green: 0.28, blue: 0.26), Color(red: 0.78, green: 0.14, blue: 0.14))
        }
        if account.isOutlook {
            return ("envelope.fill", Color(red: 0.12, green: 0.58, blue: 0.96), Color(red: 0.04, green: 0.38, blue: 0.82))
        }
        if account.host.lowercased().contains("icloud") {
            return ("icloud.fill", Color(red: 0.24, green: 0.76, blue: 0.98), Color(red: 0.10, green: 0.54, blue: 0.86))
        }
        if account.host.lowercased().contains("yahoo") {
            return ("envelope.open.fill", Color(red: 0.60, green: 0.24, blue: 0.90), Color(red: 0.42, green: 0.12, blue: 0.74))
        }
        return ("server.rack", Color(white: 0.46), Color(white: 0.30))
    }

    private var diskAccessRow: some View {
        AetherSettingsControlRow(
            title: "Full Disk Access required",
            subtitle: "Grant Full Disk Access to Droppy in System Settings.",
            icon: "lock.shield.fill",
            iconColor: .orange
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
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Text("Checked: \(relative(h.lastChecked))")
                Text("Last message: \(relative(h.lastMessage))")
                Text("Last code: \(relative(h.lastCode))")
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
        guard model.hasVault else { return "Import encrypted TOTP seeds via Bitwarden CLI" }
        guard model.isOn(AetherPrefs.bitwarden) else { return "Off · encrypted keys preserved" }
        let state = model.vaultSession.isUnlocked ? "\(model.vault.count) codes" : "Locked"
        guard let imported = model.defaults.object(forKey: AetherPrefs.vaultImportedAt) as? Date else { return state }
        return "\(state) · imported \(imported.formatted(.relative(presentation: .named)))"
    }
}
