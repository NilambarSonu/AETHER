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
                settingsSectionHeader("Alerts")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show banner",
                        icon: "rectangle.inset.topright.filled",
                        iconColor: .blue,
                        isOn: model.boolBinding(AetherPrefs.showBanner)
                    )

                    DropletToggleRow(
                        title: "Show notch HUD",
                        icon: "macbook.gen2",
                        iconColor: .indigo,
                        isOn: model.boolBinding(AetherPrefs.showNotchHUD)
                    )

                    DropletToggleRow(
                        title: "Play sound",
                        icon: "speaker.wave.2.fill",
                        iconColor: .pink,
                        isOn: model.boolBinding(AetherPrefs.sound)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("After a code arrives")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Copy to clipboard",
                        icon: "doc.on.clipboard.fill",
                        iconColor: .purple,
                        isOn: model.boolBinding(AetherPrefs.autoCopy)
                    )

                    DropletToggleRow(
                        title: "Type automatically",
                        icon: "text.cursor",
                        iconColor: .teal,
                        subtitle: "Needs Accessibility access. Types into the focused field.",
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
                        if !trusted {
                            DropletControlRow(
                                title: "Accessibility permission",
                                icon: "accessibility",
                                iconColor: .orange
                            ) {
                                Button("Allow…") {
                                    AccessibilityTrust.requestTrust(force: true)
                                    droplet.openAccessibilitySettings()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Notch")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Compact chip",
                        icon: "menubar.rectangle",
                        iconColor: .secondary,
                        isOn: model.boolBinding(AetherPrefs.codeInMenuBar)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Shortcuts")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Global shortcuts",
                        icon: "command",
                        iconColor: .secondary,
                        isOn: model.boolBinding(AetherPrefs.hotkeys)
                    )
                    .onChange(of: hotkeys) { _, _ in
                        droplet.syncShortcuts()
                    }

                    if hotkeys {
                        DropletControlRow(
                            title: "Customize",
                            icon: "keyboard.fill",
                            iconColor: .secondary
                        ) {
                            Button("Open Shortcuts…") {
                                droplet.openShortcutsSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}
