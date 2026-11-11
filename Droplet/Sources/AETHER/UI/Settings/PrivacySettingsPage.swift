// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct PrivacySettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Device authentication")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Ask for \(DeviceAuthentication.supportsTouchID() ? "Touch ID" : "your password") to show codes",
                        icon: "touchid",
                        iconColor: .pink,
                        topColor: .red,
                        infoTip: "Locks vault and code viewing whenever Mac sleeps or restarts; the policy itself is AES-256-GCM authenticated in Keychain.",
                        isOn: Binding(
                            get: { !model.isOn(AetherPrefs.unlockWithMac) },
                            set: { ask in Task { await model.setUnlockWithMac(!ask) } }
                        )
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("On screen & notch")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Hide from screen capture",
                        icon: "rectangle.dashed.badge.record",
                        iconColor: .red,
                        infoTip: "Masks active code panels, notch sheets, and recovery emails during screen sharing and recording.",
                        isOn: model.boolBinding(AetherPrefs.hideFromCapture)
                    )

                    AetherSettingsToggleRow(
                        title: "Hide codes until hover",
                        icon: "eye.slash.fill",
                        iconColor: .indigo,
                        infoTip: "Blurs OTP digits across shelf rows and menus until your pointer hovers them.",
                        isOn: model.boolBinding(AetherPrefs.blurCodes)
                    )

                    AetherSettingsToggleRow(
                        title: "Show compact notch chip",
                        icon: "menubar.rectangle",
                        iconColor: .gray,
                        topColor: Color(white: 0.48),
                        infoTip: "Shows a compact chip with the sender icon and code beside the notch until copied or used.",
                        isOn: model.boolBinding(AetherPrefs.codeInMenuBar)
                    )

                    AetherSettingsToggleRow(
                        title: "Show message previews",
                        icon: "text.bubble.fill",
                        iconColor: .green,
                        infoTip: "Shows the sender address, subject, or message excerpt in the notch HUD, shelf, and banner.",
                        isOn: model.boolBinding(AetherPrefs.showPreviews)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Clipboard & brand icons")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Clear clipboard after 90 seconds",
                        icon: "clock.arrow.circlepath",
                        iconColor: .orange,
                        infoTip: "Marks copied codes concealed & local-only (skipping Universal Clipboard) and wipes them after 90 seconds.",
                        isOn: model.boolBinding(AetherPrefs.clearClipboard)
                    )

                    AetherSettingsToggleRow(
                        title: "Fetch HD website brand logos",
                        subtitle: "Uses local brand tiles when off; caches fetched icons under opaque HMAC hashes when on.",
                        icon: "app.badge.fill",
                        iconColor: .purple,
                        infoTip: "Disabled by default so domains never leave this Mac. Enable to fetch high-resolution brand favicons via cookie-free HTTPS proxies.",
                        isOn: model.boolBinding(AetherPrefs.serviceIcons)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Memory & retention")
            } content: {
                DropletSettingsCard {
                    let historyBinding = model.intBinding(AetherPrefs.historyDays)
                    Picker(selection: historyBinding) {
                        Text("1 Day").tag(1)
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                    } label: {
                        AetherRowLabel(
                            title: "Keep recent codes for",
                            subtitle: "Codes stay strictly in RAM and are never written to any database.",
                            icon: "clock.fill",
                            color: .teal
                        )
                    }
                    .onChange(of: model.defaults.integer(forKey: AetherPrefs.historyDays)) { _, _ in
                        model.restartMessages()
                        model.restartMail()
                    }

                    AetherSettingsToggleRow(
                        title: "Clear history when Mac locks",
                        icon: "lock.fill",
                        iconColor: .blue,
                        infoTip: "Wipes volatile OTP memory, recovery emails, OAuth RAM caches, and pasteboard immediately on screen lock.",
                        isOn: model.boolBinding(AetherPrefs.clearOnLock)
                    )

                    AetherSettingsControlRow(
                        title: "Clear caught history",
                        icon: "trash.fill",
                        iconColor: .gray,
                        infoTip: "Clears recent codes and unmatched emails right now while keeping Bitwarden TOTP seeds in Keychain."
                    ) {
                        Button("Clear Now…") {
                            let confirmed = DropletConfirmationDialog.present(
                                title: "Clear caught history?",
                                message: "AETHER clears all caught codes and recent emails from memory. Bitwarden keys and mail accounts stay saved.",
                                confirmTitle: "Clear History",
                                symbol: "trash.fill"
                            )
                            if confirmed {
                                model.clearHistory()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.hasHistory)
                    }
                }
            }
        }
    }
}
