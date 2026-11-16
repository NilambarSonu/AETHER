// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct SourcesSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    private var messagesEnabled: Bool { model.isOn(AetherPrefs.messages) }
    private var appleMailEnabled: Bool { model.isOn(AetherPrefs.appleMail) }

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Local")
            } content: {
                DropletSettingsCard {
                    HStack(alignment: .center, spacing: DroppySpacing.md) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green)
                            .frame(width: 20, alignment: .center)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Messages")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text("iMessage & SMS · \(messagesEnabled ? "Watching" : "Off")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Toggle("", isOn: model.boolBinding(AetherPrefs.messages))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: messagesEnabled) { _, _ in
                                model.restartMessages()
                            }
                    }
                    .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
                    .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)

                    HStack(alignment: .center, spacing: DroppySpacing.md) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .frame(width: 20, alignment: .center)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Mail")
                                .font(.body)
                                .foregroundStyle(.primary)

                            Text(appleMailEnabled ? "Watching" : "Off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Toggle("", isOn: model.boolBinding(AetherPrefs.appleMail))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: appleMailEnabled) { _, _ in
                                model.restartAppleMail()
                            }
                    }
                    .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
                    .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Mail accounts")
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
                        ForEach(model.accounts) { account in
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

                    DropletToggleRow(
                        title: "Include spam and junk",
                        icon: "tray.and.arrow.down.fill",
                        iconColor: .secondary,
                        subtitle: "Also checks Gmail Spam and Outlook Junk.",
                        isOn: model.boolBinding(AetherPrefs.includeJunkMail)
                    )
                    .onChange(of: model.isOn(AetherPrefs.includeJunkMail)) { _, _ in
                        model.restartMail()
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Authenticator")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Bitwarden",
                        icon: "shield.lefthalf.filled",
                        iconColor: .blue,
                        infoTip: "Import authenticator codes with the Bitwarden CLI."
                    ) {
                        HStack(spacing: DroppySpacing.sm) {
                            DropletValuePill(text: model.hasVault ? "Connected" : "Not connected")
                            Button(model.hasVault ? "Configure…" : "Connect…") {
                                droplet.openSettingsPage(AetherSettingsRoute.bitwarden.rawValue, title: "Bitwarden")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("What to detect")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Verification codes",
                        icon: "number",
                        iconColor: .blue,
                        subtitle: "Numeric and alphanumeric.",
                        isOn: model.boolBinding(AetherPrefs.receivedCodes)
                    )

                    DropletToggleRow(
                        title: "Sign-in links",
                        icon: "link",
                        iconColor: .teal,
                        subtitle: "Never copied automatically.",
                        isOn: model.boolBinding(AetherPrefs.signInLinks)
                    )

                    DropletToggleRow(
                        title: "Password reset links",
                        icon: "lock.rotation",
                        iconColor: .orange,
                        subtitle: "Flagged on this Mac. Never shared with AI agents.",
                        isOn: model.boolBinding(AetherPrefs.resetLinks)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Filters")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Ignored senders",
                        subtitle: model.ignoredSenders.isEmpty ? "None" : "\(model.ignoredSenders.count) \(model.ignoredSenders.count == 1 ? "sender" : "senders")",
                        page: AetherSettingsRoute.ignoredSenders.rawValue
                    ) {
                        Image(systemName: "nosign")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    DropletSettingsPageLink(
                        "Not-a-code rules",
                        subtitle: model.notCodes.isEmpty ? "None" : "\(model.notCodes.count) \(model.notCodes.count == 1 ? "rule" : "rules")",
                        page: AetherSettingsRoute.notCodes.rawValue
                    ) {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Troubleshooting")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Unmatched emails",
                        subtitle: recoverySummary,
                        page: AetherSettingsRoute.recovery.rawValue
                    ) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
    }

    private var recoverySummary: String {
        guard model.isUnlocked else { return "Locked" }
        let count = model.recovery.entries.count
        return count == 0 ? "None" : "\(count) \(count == 1 ? "email" : "emails")"
    }
}
