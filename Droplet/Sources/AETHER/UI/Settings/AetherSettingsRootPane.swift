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
                settingsSectionHeader("Protection & quick actions")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Vault protection",
                        icon: model.isUnlocked ? "lock.open.fill" : "lock.fill",
                        iconColor: model.isUnlocked ? .green : .orange,
                        infoTip: "Codes and Bitwarden TOTP secrets stay hidden while locked."
                    ) {
                        HStack(spacing: 8) {
                            Text(model.isUnlocked ? "Unlocked" : "Locked")
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

                    DropletControlRow(
                        title: "Notch & banner delivery",
                        icon: "bell.badge.fill",
                        iconColor: .blue,
                        infoTip: "Sends a simulated verification code to test banners, notch HUD, and clipboard copy."
                    ) {
                        HStack(spacing: 8) {
                            Button("Send Test Code") {
                                model.showTestCode(userInitiated: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.isOn(AetherPrefs.receivedCodes))

                            Button("Show Widget") {
                                _ = droplet.openShelfWidget()
                            }
                            .buttonStyle(.bordered)
                        }
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
                        AetherSymbolTile(symbol: "gearshape.fill", color: .blue, size: AetherSymbolTile.settingsLinkSize)
                    }

                    DropletSettingsPageLink(
                        "Sources & accounts",
                        subtitle: sourcesSubtitle,
                        page: AetherSettingsRoute.sources.rawValue
                    ) {
                        AetherSymbolTile(symbol: "tray.2.fill", color: .orange, size: AetherSymbolTile.settingsLinkSize)
                    }

                    DropletSettingsPageLink(
                        "Privacy & history",
                        subtitle: privacySubtitle,
                        page: AetherSettingsRoute.privacy.rawValue
                    ) {
                        AetherSymbolTile(symbol: "hand.raised.fill", color: .teal, size: AetherSymbolTile.settingsLinkSize)
                    }

                    DropletSettingsPageLink(
                        "Agents & MCP",
                        subtitle: agentsSubtitle,
                        page: AetherSettingsRoute.agents.rawValue
                    ) {
                        AetherSymbolTile(symbol: "terminal.fill", color: .indigo, size: AetherSymbolTile.settingsLinkSize)
                    }

                    DropletSettingsPageLink(
                        "Recent emails",
                        subtitle: recoverySubtitle,
                        page: AetherSettingsRoute.recovery.rawValue
                    ) {
                        AetherSymbolTile(symbol: "envelope.badge.shield.half.filled", color: .purple, size: AetherSymbolTile.settingsLinkSize)
                    }
                }
            }

            if let error = model.unlockError, !model.isUnlocked {
                DropletSettingsSection {
                    settingsSectionHeader("Notice")
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
        var active: [String] = []
        if model.isOn(AetherPrefs.showBanner) { active.append("Banner") }
        if model.isOn(AetherPrefs.showNotchHUD) { active.append("Notch HUD") }
        if model.isOn(AetherPrefs.autoCopy) { active.append("Auto-copy") }
        if model.isOn(AetherPrefs.autoType) { active.append("Auto-type") }
        return active.isEmpty ? "Delivery paused" : active.joined(separator: " · ")
    }

    private var sourcesSubtitle: String {
        let attention = model.sources.filter(\.status.needsAttention).count
        if attention > 0 {
            return "\(attention) \(attention == 1 ? "source needs attention" : "sources need attention")"
        }
        let live = model.sources.filter { $0.status == .live }.count
        let vault = model.hasVault && model.isOn(AetherPrefs.bitwarden) ? " · Bitwarden" : ""
        return live == 0 ? "All sources off\(vault)" : "\(live) active \(live == 1 ? "source" : "sources")\(vault)"
    }

    private var privacySubtitle: String {
        let days = max(1, model.defaults.integer(forKey: AetherPrefs.historyDays))
        let lockDesc = model.isOn(AetherPrefs.unlockWithMac) ? "Unlock with Mac" : "Touch ID / password"
        return "\(lockDesc) · Keep \(days) \(days == 1 ? "day" : "days")"
    }

    private var agentsSubtitle: String {
        guard model.agents.config.enabled else { return "Off" }
        if model.agents.config.allowAll { return "Enabled · Allow all" }
        let count = model.agents.config.rules.count
        return count == 0 ? "Enabled · Ask per request" : "Enabled · \(count) \(count == 1 ? "rule" : "rules")"
    }

    private var recoverySubtitle: String {
        let count = model.recovery.entries.count
        return count == 0
            ? "Unmatched emails from the last 30 minutes"
            : "\(count) \(count == 1 ? "email" : "emails") held in memory"
    }
}
