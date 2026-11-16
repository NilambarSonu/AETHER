// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct AetherSettingsRootPane: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Status")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Vault",
                        icon: model.isUnlocked ? "lock.open.fill" : "lock.fill",
                        iconColor: model.isUnlocked ? .green : .orange,
                        infoTip: "Codes are held in memory only while unlocked."
                    ) {
                        HStack(spacing: DroppySpacing.sm) {
                            DropletValuePill(text: model.isUnlocked ? "Unlocked" : "Locked")
                            if model.isUnlocked {
                                Button("Lock") {
                                    model.vaultSession.lock()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button(model.vaultSession.isBusy ? "Unlocking…" : "Unlock") {
                                    model.unlocked {}
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(model.vaultSession.isBusy)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Quick actions")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Open notch widget",
                        icon: "rectangle.topthird.inset.filled",
                        iconColor: .blue
                    ) {
                        Button("Open") {
                            _ = droplet.openShelfWidget()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    DropletControlRow(
                        title: "Send test code",
                        icon: "sparkles",
                        iconColor: .indigo,
                        infoTip: "Preview how a code arrives."
                    ) {
                        Button("Send") {
                            model.showTestCode(userInitiated: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!model.isOn(AetherPrefs.receivedCodes))
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Connected accounts")
            } content: {
                DropletSettingsCard {
                    if model.accounts.isEmpty {
                        HStack(alignment: .center, spacing: DroppySpacing.md) {
                            Image(systemName: "tray")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .center)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("No accounts connected")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text("Add a mailbox to catch codes from email.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Button("Add account") {
                                droplet.openSettingsPage(AetherSettingsRoute.addAccount.rawValue, title: "Add mail account")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
                        .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)
                    } else {
                        let displayed = model.accounts.count > 4 ? Array(model.accounts.prefix(3)) : model.accounts
                        ForEach(displayed) { account in
                            ConnectedAccountRow(
                                account: account,
                                model: model,
                                onEdit: {
                                    droplet.openSettingsPage(AetherSettingsRoute.editAccount(account.id), title: "Edit mail account")
                                },
                                onSignInAgain: {
                                    droplet.openSettingsPage(AetherSettingsRoute.editAccount(account.id), title: "Edit mail account")
                                }
                            )
                        }

                        if model.accounts.count > 4 {
                            DropletSettingsPageLink(
                                "Show all in Sources",
                                subtitle: "\(model.accounts.count) connected accounts",
                                page: AetherSettingsRoute.sources.rawValue
                            ) {
                                Image(systemName: "tray.2")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        DropletControlRow(
                            title: "Add account…",
                            icon: "plus",
                            iconColor: .blue
                        ) {
                            Button("Add…") {
                                droplet.openSettingsPage(AetherSettingsRoute.addAccount.rawValue, title: "Add mail account")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Settings")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "General",
                        subtitle: generalSummary,
                        page: AetherSettingsRoute.general.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "gearshape.fill",
                            top: Color(red: 0.25, green: 0.56, blue: 0.98),
                            bottom: Color(red: 0.10, green: 0.36, blue: 0.86),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Sources",
                        subtitle: sourcesSummary,
                        page: AetherSettingsRoute.sources.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "tray.2.fill",
                            top: Color(red: 1.00, green: 0.64, blue: 0.16),
                            bottom: Color(red: 0.88, green: 0.42, blue: 0.05),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Privacy",
                        subtitle: privacySummary,
                        page: AetherSettingsRoute.privacy.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "hand.raised.fill",
                            top: Color(red: 0.20, green: 0.78, blue: 0.84),
                            bottom: Color(red: 0.08, green: 0.54, blue: 0.68),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "AI agents",
                        subtitle: agentsSummary,
                        page: AetherSettingsRoute.agents.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "terminal.fill",
                            top: Color(red: 0.40, green: 0.38, blue: 0.96),
                            bottom: Color(red: 0.26, green: 0.22, blue: 0.78),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }
                }
            }

            if let error = model.unlockError, !model.isUnlocked {
                DropletSettingsSection {
                    settingsSectionHeader("Unlock attention")
                } content: {
                    DropletSettingsCard {
                        AetherWarningRow(message: error)
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
    }

    private var generalSummary: String {
        var parts: [String] = []
        if model.isOn(AetherPrefs.showBanner) { parts.append("Banner") }
        if model.isOn(AetherPrefs.showNotchHUD) { parts.append("HUD") }
        if model.isOn(AetherPrefs.autoCopy) { parts.append("Copy") }
        if model.isOn(AetherPrefs.autoType) { parts.append("Type") }
        if model.isOn(AetherPrefs.sound) { parts.append("Sound") }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
    }

    private var sourcesSummary: String {
        var parts: [String] = []
        if model.isOn(AetherPrefs.messages) { parts.append("Messages") }
        if model.isOn(AetherPrefs.appleMail) { parts.append("Apple Mail") }
        let mailboxes = model.accounts.count
        if mailboxes > 0 {
            parts.append("\(mailboxes) \(mailboxes == 1 ? "mailbox" : "mailboxes")")
        }
        if model.isOn(AetherPrefs.bitwarden) && model.hasVault {
            parts.append("Bitwarden")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    private var privacySummary: String {
        let days = max(1, model.defaults.integer(forKey: AetherPrefs.historyDays))
        let daysText = "Codes kept \(days) \(days == 1 ? "day" : "days")"
        let touchIDRequired = !model.isOn(AetherPrefs.unlockWithMac)
        return touchIDRequired ? "Touch ID · \(daysText)" : daysText
    }

    private var agentsSummary: String {
        model.agents.config.enabled ? "On" : "Off"
    }
}
