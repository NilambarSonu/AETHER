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
                settingsSectionHeader("Access")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Require Touch ID to view codes",
                        icon: "touchid",
                        iconColor: .pink,
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
                        isOn: model.boolBinding(AetherPrefs.hideFromCapture)
                    )

                    DropletToggleRow(
                        title: "Hide codes until hover",
                        icon: "eye.slash.fill",
                        iconColor: .indigo,
                        isOn: model.boolBinding(AetherPrefs.blurCodes)
                    )

                    DropletToggleRow(
                        title: "Show message previews",
                        icon: "text.bubble.fill",
                        iconColor: .green,
                        isOn: model.boolBinding(AetherPrefs.showPreviews)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Clipboard")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Auto-clear copied codes",
                        icon: "clock.arrow.circlepath",
                        iconColor: .orange,
                        isOn: model.boolBinding(AetherPrefs.clearClipboard)
                    )

                    if model.isOn(AetherPrefs.clearClipboard) {
                        DropletGroupedPickerRow(
                            title: "Clear after",
                            icon: "timer",
                            iconColor: .orange
                        ) {
                            Picker("Clear after", selection: model.intBinding(AetherPrefs.clipboardTTL)) {
                                Text("30 seconds").tag(30)
                                Text("60 seconds").tag(60)
                                Text("90 seconds").tag(90)
                                Text("2 minutes").tag(120)
                                Text("5 minutes").tag(300)
                            }
                        }

                        DropletToggleRow(
                            title: "Restore previous clipboard",
                            icon: "arrow.uturn.backward.circle.fill",
                            iconColor: .blue,
                            isOn: model.boolBinding(AetherPrefs.restoreClipboard)
                        )
                    }

                    DropletToggleRow(
                        title: "Confirm unverified emails",
                        icon: "exclamationmark.shield.fill",
                        iconColor: .red,
                        subtitle: "Ask before copying codes from emails that fail sender checks.",
                        isOn: model.boolBinding(AetherPrefs.blockUnverifiedAutoCopy)
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
                        iconColor: .teal
                    ) {
                        Picker("Keep codes for", selection: model.intBinding(AetherPrefs.historyDays)) {
                            Text("1 day").tag(1)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                        }
                        .onChange(of: model.defaults.integer(forKey: AetherPrefs.historyDays)) { _, _ in
                            model.restartMessages()
                            model.restartMail()
                        }
                    }

                    DropletToggleRow(
                        title: "Clear when Mac locks",
                        icon: "lock.fill",
                        iconColor: .blue,
                        isOn: model.boolBinding(AetherPrefs.clearOnLock)
                    )

                    DropletControlRow(
                        title: "Clear history",
                        icon: "trash.fill",
                        iconColor: .secondary
                    ) {
                        Button("Clear…") {
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
                        .controlSize(.small)
                        .disabled(!model.hasHistory)
                    }
                }

                Text("Codes stay in memory only and are never saved to disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DroppySettingsLayoutMetrics.sectionHeaderLeadingInset)
            }

            DropletSettingsSection {
                settingsSectionHeader("Network")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Download sender logos",
                        icon: "app.badge.fill",
                        iconColor: .purple,
                        subtitle: "Off uses built-in icons.",
                        isOn: model.boolBinding(AetherPrefs.serviceIcons)
                    )
                }
            }
        }
    }
}
