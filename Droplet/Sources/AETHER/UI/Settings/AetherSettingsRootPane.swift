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
                settingsSectionHeader("Protection & quick preview")
            } content: {
                DropletSettingsCard {
                    AetherSettingsControlRow(
                        title: "Vault protection",
                        subtitle: model.isUnlocked
                            ? "Active OTPs and Bitwarden secrets are unlocked in memory."
                            : "Codes and vault secrets stay encrypted & locked until verified.",
                        icon: model.isUnlocked ? "lock.open.fill" : "lock.fill",
                        iconColor: model.isUnlocked ? .green : .orange,
                        infoTip: "Secrets are sealed in local macOS Keychain with AES-256-GCM; received OTPs never touch disk."
                    ) {
                        HStack(spacing: 8) {
                            Text(model.isUnlocked ? "Unlocked" : "Locked")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if model.isUnlocked {
                                Button("Lock") { model.vaultSession.lock() }
                                    .buttonStyle(.bordered)
                            } else {
                                Button(model.vaultSession.isBusy ? "Unlocking…" : "Unlock") {
                                    model.unlocked {}
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.vaultSession.isBusy)
                            }
                        }
                    }

                    AetherSettingsControlRow(
                        title: "Notch shelf widget",
                        subtitle: "View recent codes, search TOTP secrets, and trigger instant actions.",
                        icon: "rectangle.topthird.inset.filled",
                        iconColor: .blue,
                        topColor: .cyan
                    ) {
                        Button("Open Widget") {
                            _ = droplet.openShelfWidget()
                        }
                        .buttonStyle(.bordered)
                    }

                    AetherSettingsControlRow(
                        title: "Test code delivery",
                        subtitle: "Simulates an OTP arrival to verify the notch HUD, banner, and auto-copy.",
                        icon: "sparkles",
                        iconColor: .indigo,
                        topColor: .purple
                    ) {
                        Button("Send Test Code") {
                            model.showTestCode(userInitiated: true)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.isOn(AetherPrefs.receivedCodes))
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Configuration")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "General",
                        subtitle: generalSubtitle,
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
                        "Sources & accounts",
                        subtitle: sourcesSubtitle,
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
                        "Privacy & history",
                        subtitle: privacySubtitle,
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
                        "Agents & MCP",
                        subtitle: agentsSubtitle,
                        page: AetherSettingsRoute.agents.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "terminal.fill",
                            top: Color(red: 0.40, green: 0.38, blue: 0.96),
                            bottom: Color(red: 0.26, green: 0.22, blue: 0.78),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Recent emails",
                        subtitle: recoverySubtitle,
                        page: AetherSettingsRoute.recovery.rawValue
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "envelope.badge.shield.half.filled",
                            top: Color(red: 0.78, green: 0.28, blue: 0.92),
                            bottom: Color(red: 0.56, green: 0.14, blue: 0.76),
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

    private var generalSubtitle: String {
        var parts: [String] = []
        if model.isOn(AetherPrefs.showBanner) { parts.append("Banner") }
        if model.isOn(AetherPrefs.showNotchHUD) { parts.append("Notch HUD") }
        if model.isOn(AetherPrefs.autoCopy) { parts.append("Auto-copy") }
        if model.isOn(AetherPrefs.autoType) { parts.append("Auto-type") }
        return parts.isEmpty ? "Silent arrival mode" : parts.joined(separator: " · ")
    }

    private var sourcesSubtitle: String {
        let liveCount = model.sources.filter { $0.status == .live }.count
        let attentionCount = model.sources.filter { $0.status.needsAttention }.count
        if attentionCount > 0 {
            return "\(attentionCount) \(attentionCount == 1 ? "source needs" : "sources need") attention"
        }
        if liveCount > 0 {
            return "\(liveCount) active \(liveCount == 1 ? "source" : "sources") watching"
        }
        return "Messages, Apple Mail, Gmail, Outlook & IMAP"
    }

    private var privacySubtitle: String {
        let days = max(1, model.defaults.integer(forKey: AetherPrefs.historyDays))
        let lockDesc = model.isOn(AetherPrefs.unlockWithMac) ? "Unlock with Mac" : "Touch ID / password"
        return "\(lockDesc) · Keep \(days) \(days == 1 ? "day" : "days")"
    }

    private var agentsSubtitle: String {
        guard model.agents.config.enabled else { return "Off" }
        if model.agents.config.allowAll { return "Auto-releasing · max 20/hr" }
        let count = model.agents.config.rules.count
        return count == 0 ? "On · asks with Touch ID" : "On · \(count) saved \(count == 1 ? "rule" : "rules")"
    }

    private var recoverySubtitle: String {
        guard model.isUnlocked else { return "Unmatched emails from the last 30 minutes" }
        let count = model.recovery.entries.count
        return count == 0 ? "None captured recently" : "\(count) recent \(count == 1 ? "email" : "emails")"
    }
}
