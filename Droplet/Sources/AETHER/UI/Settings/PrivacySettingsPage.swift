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
                settingsSectionHeader("Unlock")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Ask for \(DeviceAuthentication.supportsTouchID() ? "Touch ID" : "your password") to show codes",
                        icon: "touchid",
                        iconColor: .pink,
                        subtitle: "Turn this off and AETHER unlocks whenever your Mac does, without asking for \(DeviceAuthentication.unlockMethods). Bitwarden codes follow the same lock.",
                        isOn: Binding(
                            get: { !model.isOn(AetherPrefs.unlockWithMac) },
                            set: { ask in Task { await model.setUnlockWithMac(!ask) } }
                        )
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("On screen")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Hide from screen capture",
                        icon: "rectangle.dashed.badge.record",
                        iconColor: .red,
                        subtitle: "Hides active code panels and recovery emails from screen capture while displayed.",
                        isOn: model.boolBinding(AetherPrefs.hideFromCapture)
                    )

                    DropletToggleRow(
                        title: "Hide codes until hover",
                        icon: "eye.slash.fill",
                        iconColor: .indigo,
                        subtitle: "Blurs displayed digits until you hover over a code row.",
                        isOn: model.boolBinding(AetherPrefs.blurCodes)
                    )

                    DropletToggleRow(
                        title: "Show live activity chip briefly",
                        icon: "menubar.rectangle",
                        iconColor: .gray,
                        subtitle: "Shows a compact chip beside the notch while a fresh unlocked code is uncopied or an agent waits for approval.",
                        isOn: model.boolBinding(AetherPrefs.codeInMenuBar)
                    )

                    DropletToggleRow(
                        title: "Show message previews",
                        icon: "text.bubble.fill",
                        iconColor: .green,
                        subtitle: "Includes the SMS excerpt or email subject under each code row.",
                        isOn: model.boolBinding(AetherPrefs.showPreviews)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Clipboard & network")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Clear clipboard after 90 seconds",
                        icon: "clock.arrow.circlepath",
                        iconColor: .orange,
                        subtitle: "Clears copied codes after 90 seconds if nothing else was copied. Codes stay on this Mac (Universal Clipboard and clipboard managers are skipped).",
                        isOn: model.boolBinding(AetherPrefs.clearClipboard)
                    )

                    DropletToggleRow(
                        title: "Show service logos",
                        icon: "app.badge.fill",
                        iconColor: .purple,
                        subtitle: "Disabled by default for privacy. When enabled, caches website icons through Google or DuckDuckGo proxies (sending your IP and site domain).",
                        isOn: model.boolBinding(AetherPrefs.serviceIcons)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("History")
            } content: {
                DropletSettingsCard {
                    DropletGroupedPickerRow(
                        title: "Keep codes for",
                        icon: "clock.fill",
                        iconColor: .teal,
                        subtitle: "AETHER rereads recent Messages and mail on launch and never saves codes to disk."
                    ) {
                        let historyBinding = model.intBinding(AetherPrefs.historyDays)
                        Picker("Keep codes for", selection: historyBinding) {
                            Text("1 Day").tag(1)
                            Text("7 Days").tag(7)
                            Text("30 Days").tag(30)
                        }
                        .onChange(of: model.defaults.integer(forKey: AetherPrefs.historyDays)) { _, _ in
                            model.restartMessages()
                            model.restartMail()
                        }
                    }

                    DropletToggleRow(
                        title: "Clear history when Mac locks",
                        icon: "lock.fill",
                        iconColor: .blue,
                        subtitle: "Clears recent codes and the clipboard on screen lock. Imported Bitwarden logins remain in your Keychain.",
                        isOn: model.boolBinding(AetherPrefs.clearOnLock)
                    )

                    DropletControlRow(
                        title: "Clear history",
                        icon: "trash.fill",
                        iconColor: .gray,
                        infoTip: "Cleared codes stay gone across restarts. Imported Bitwarden logins are kept."
                    ) {
                        Button("Clear Now…") {
                            let confirmed = DropletConfirmationDialog.present(
                                title: "Clear caught history?",
                                message: "AETHER clears all caught codes and recent emails. They will stay hidden across restarts, while Bitwarden logins stay saved.",
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
