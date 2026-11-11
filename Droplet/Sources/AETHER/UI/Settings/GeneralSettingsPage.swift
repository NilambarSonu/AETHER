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
                settingsSectionHeader("Arrival delivery")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Show notification banner",
                        icon: "rectangle.inset.topright.filled",
                        iconColor: .blue,
                        topColor: .cyan,
                        infoTip: "Posts an interactive banner in Droppy's notch notification stack without stealing app focus.",
                        isOn: model.boolBinding(AetherPrefs.showBanner)
                    )

                    AetherSettingsToggleRow(
                        title: "Show notch HUD",
                        icon: "macbook.gen2",
                        iconColor: .indigo,
                        topColor: .blue,
                        infoTip: "Shows the sender logo, email/address, and verification code directly inside the notch.",
                        isOn: model.boolBinding(AetherPrefs.showNotchHUD)
                    )

                    AetherSettingsToggleRow(
                        title: "Play arrival sound",
                        icon: "speaker.wave.2.fill",
                        iconColor: .pink,
                        topColor: Color(red: 1.0, green: 0.34, blue: 0.56),
                        infoTip: "Plays a subtle chime when a fresh verification code or sign-in link arrives.",
                        isOn: model.boolBinding(AetherPrefs.sound)
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Automatic input")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Automatically copy codes",
                        icon: "doc.on.clipboard.fill",
                        iconColor: .purple,
                        topColor: .indigo,
                        infoTip: "Copies arriving OTP digits to a concealed local pasteboard while unlocked. Sign-in links are never auto-copied.",
                        isOn: model.boolBinding(AetherPrefs.autoCopy)
                    )

                    AetherSettingsToggleRow(
                        title: "Automatically type codes",
                        icon: "text.cursor",
                        iconColor: .teal,
                        topColor: .mint,
                        infoTip: "Types arriving codes into verified input fields while blocking chat, notes, screen-share apps, and mismatched browser domains.",
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
                        AetherSettingsControlRow(
                            title: "Accessibility permission",
                            subtitle: trusted ? "Droppy is authorized to type codes." : "Required in System Settings → Accessibility.",
                            icon: "accessibility",
                            iconColor: trusted ? .green : .orange
                        ) {
                            if trusted {
                                Label("Allowed", systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            } else {
                                Button("Allow…") {
                                    AccessibilityTrust.requestTrust(force: true)
                                    droplet.openAccessibilitySettings()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Keyboard shortcuts")
            } content: {
                DropletSettingsCard {
                    AetherSettingsToggleRow(
                        title: "Global keyboard shortcuts",
                        icon: "command",
                        iconColor: .gray,
                        topColor: Color(white: 0.48),
                        infoTip: "Registers Copy Latest Code and Show Verification Codes hotkeys inside Droppy.",
                        isOn: model.boolBinding(AetherPrefs.hotkeys)
                    )
                    .onChange(of: hotkeys) { _, _ in
                        droplet.syncShortcuts()
                    }

                    AetherSettingsControlRow(
                        title: "Customize shortcuts",
                        icon: "keyboard.fill",
                        iconColor: .blue,
                        infoTip: "Rebind AETHER shortcuts inside Droppy's Shortcuts page."
                    ) {
                        Button("Open Shortcuts…") {
                            droplet.openShortcutsSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
