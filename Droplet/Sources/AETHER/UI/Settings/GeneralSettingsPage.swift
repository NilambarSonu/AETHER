// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct GeneralSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    private var autoType: Bool { model.isOn(AetherPrefs.autoType) }
    private var hotkeys: Bool { model.isOn(AetherPrefs.hotkeys) }

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("When a code or link arrives")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show notification banner",
                        icon: "rectangle.inset.topright.filled",
                        iconColor: .blue,
                        subtitle: "Posts in Droppy's banner stack without taking focus from the active app.",
                        isOn: model.boolBinding(AetherPrefs.showBanner)
                    )

                    DropletToggleRow(
                        title: "Show notch HUD",
                        icon: "macbook.gen2",
                        iconColor: .cyan,
                        subtitle: "Briefly shows the code or sign-in link in the notch strip and card.",
                        isOn: model.boolBinding(AetherPrefs.showNotchHUD)
                    )

                    DropletToggleRow(
                        title: "Automatically copy codes",
                        icon: "doc.on.clipboard.fill",
                        iconColor: .indigo,
                        subtitle: "Copies new verification codes while AETHER is unlocked. Sign-in links are never copied automatically.",
                        isOn: model.boolBinding(AetherPrefs.autoCopy)
                    )

                    DropletToggleRow(
                        title: "Automatically type codes",
                        icon: "text.cursor",
                        iconColor: .teal,
                        subtitle: "Types arriving codes key by key into the focused field while unlocked (also fills split digit boxes). Needs Accessibility trust.",
                        isOn: model.boolBinding(AetherPrefs.autoType)
                    )
                    .onChange(of: autoType) { _, enabled in
                        if enabled {
                            AccessibilityTrust.requestTrust()
                        }
                    }

                    if autoType {
                        let _ = model.now
                        let trusted = AccessibilityTrust.isTrusted
                        DropletControlRow(
                            title: "Accessibility permission",
                            icon: "accessibility",
                            iconColor: .blue,
                            infoTip: trusted
                                ? "Droppy is trusted to type codes."
                                : "Grant Accessibility permission to Droppy in System Settings so AETHER can type codes."
                        ) {
                            if trusted {
                                Label {
                                    Text("Allowed").foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            } else {
                                Button("Allow…") {
                                    AccessibilityTrust.requestTrust(force: true)
                                    droplet.openAccessibilitySettings()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    DropletToggleRow(
                        title: "Play sound",
                        icon: "speaker.wave.2.fill",
                        iconColor: .pink,
                        subtitle: "Plays an alert sound when a verification code or sign-in link arrives.",
                        isOn: model.boolBinding(AetherPrefs.sound)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Keyboard")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Global keyboard shortcuts",
                        icon: "command",
                        iconColor: .gray,
                        subtitle: "Registers Copy Latest Code and Show Verification Codes hotkeys in Droppy.",
                        isOn: model.boolBinding(AetherPrefs.hotkeys)
                    )
                    .onChange(of: hotkeys) { _, _ in
                        droplet.syncShortcuts()
                    }

                    DropletControlRow(
                        title: "Configure shortcuts",
                        icon: "keyboard",
                        iconColor: .secondary,
                        infoTip: "Rebind Copy Latest Code or Show Verification Codes on Droppy's Shortcuts page."
                    ) {
                        Button("Open Shortcuts…") {
                            droplet.openShortcutsSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Host & lifecycle")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Open at login",
                        icon: "power",
                        iconColor: .green,
                        infoTip: "Controlled automatically by Droppy's own startup preference."
                    ) {
                        DropletValuePill(text: "Managed by Droppy")
                    }

                    DropletControlRow(
                        title: "Updates & bundle",
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue,
                        infoTip: "All source monitors, OAuth clients, and engines run inside this standalone droplet."
                    ) {
                        DropletValuePill(text: "AETHER 2.0.0")
                    }
                }
            }
        }
    }
}
