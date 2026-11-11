// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct BitwardenSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    @State private var cliStatus = BitwardenCLI.Status()
    @State private var selectedRegion: BitwardenCLI.Region = .us
    @State private var masterPassword = ""
    @State private var sessionKey = ""
    @State private var isCheckingStatus = false
    @State private var isImporting = false
    @State private var feedbackMessage: String?
    @State private var unreadableEntries: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Bitwarden CLI status")
            } content: {
                DropletSettingsCard {
                    AetherSettingsControlRow(
                        title: "Bitwarden CLI (bw)",
                        subtitle: cliStatus.version.map { "v\($0) · \(cliStatus.email ?? cliStatus.state)" }
                            ?? "Not detected (install via `brew install bitwarden-cli`)",
                        icon: cliStatus.version != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: cliStatus.version != nil ? .green : .orange,
                        infoTip: "AETHER invokes the Bitwarden CLI strictly on demand during import."
                    ) {
                        Button(isCheckingStatus ? "Checking…" : "Refresh") {
                            Task { await refreshStatus() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isCheckingStatus)
                    }

                    if cliStatus.version != nil {
                        AetherSettingsControlRow(
                            title: "Server region",
                            icon: "globe",
                            iconColor: .blue,
                            infoTip: "Matches your Bitwarden account region (.com or .eu)."
                        ) {
                            Picker("Server region", selection: $selectedRegion) {
                                ForEach(BitwardenCLI.Region.allCases) { region in
                                    Text(region.rawValue).tag(region)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: selectedRegion) { _, newRegion in
                                Task {
                                    do {
                                        try await BitwardenCLI.setServer(newRegion)
                                        await refreshStatus()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Import TOTP authenticator keys")
            } content: {
                DropletSettingsCard {
                    if cliStatus.state != "unlocked" {
                        AetherSettingsControlRow(
                            title: "Master password",
                            icon: "lock.fill",
                            iconColor: .indigo,
                            infoTip: "Used once in memory to unlock bw CLI during import and cleared immediately afterward."
                        ) {
                            SecureField("Required unless session key provided", text: $masterPassword)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                        }
                    }

                    AetherSettingsControlRow(
                        title: "Session key (optional)",
                        icon: "key.horizontal.fill",
                        iconColor: .gray,
                        infoTip: "Optional BW_SESSION token from `bw unlock --raw`."
                    ) {
                        SecureField("BW_SESSION token", text: $sessionKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }

                    AetherSettingsControlRow(
                        title: "Import authenticator items",
                        subtitle: "Seals TOTP seeds with AES-256-GCM inside your macOS Keychain.",
                        icon: "arrow.down.doc.fill",
                        iconColor: .blue
                    ) {
                        Button(isImporting ? "Importing…" : "Import TOTP Codes") {
                            Task { await importCodes() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canImport || isImporting)
                    }
                }
            }

            if model.hasVault {
                DropletSettingsSection {
                    settingsSectionHeader("Encrypted vault keys")
                } content: {
                    DropletSettingsCard {
                        AetherSettingsControlRow(
                            title: "Imported authenticator entries",
                            icon: "key.viewfinder",
                            iconColor: .green
                        ) {
                            Text(model.vaultSession.isUnlocked ? "\(model.vault.count) logins with TOTP" : "Locked (unlock to view)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        AetherSettingsControlRow(
                            title: "Delete saved Bitwarden keys",
                            icon: "trash.fill",
                            iconColor: .red,
                            infoTip: "Deletes AETHER's Keychain copy only. Your Bitwarden account is untouched."
                        ) {
                            Button("Remove Saved Keys…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Remove Bitwarden TOTP keys from AETHER?",
                                    message: "This wipes the encrypted TOTP secrets imported into AETHER's Keychain. Your Bitwarden vault stays unchanged.",
                                    confirmTitle: "Remove Keys",
                                    symbol: "trash.fill"
                                )
                                guard confirmed else { return }
                                Task {
                                    do {
                                        try await model.removeVault()
                                        feedbackMessage = "Removed saved Bitwarden keys."
                                    } catch {
                                        if !AetherAppModel.isCancel(error) {
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let feedbackMessage {
                DropletSettingsSection {
                    settingsSectionHeader("Import result")
                } content: {
                    DropletSettingsCard {
                        AetherWarningRow(message: feedbackMessage, calm: true)
                        if !unreadableEntries.isEmpty {
                            AetherWarningRow(
                                message: "Skipped unsupported TOTP formats for: \(unreadableEntries.joined(separator: ", "))"
                            )
                        }
                    }
                }
            }

            if let errorMessage {
                DropletSettingsSection {
                    settingsSectionHeader("Attention")
                } content: {
                    DropletSettingsCard {
                        AetherWarningRow(message: errorMessage)
                    }
                }
            }
        }
        .task {
            await refreshStatus()
        }
        .onDisappear {
            masterPassword = ""
            sessionKey = ""
        }
    }

    private var canImport: Bool {
        guard cliStatus.version != nil, cliStatus.loggedIn else { return false }
        if cliStatus.state == "unlocked" { return true }
        return !masterPassword.isEmpty || !sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshStatus() async {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        let status = await BitwardenCLI.status()
        cliStatus = status
        if let detected = status.region {
            selectedRegion = detected
        }
    }

    private func importCodes() async {
        errorMessage = nil
        feedbackMessage = nil
        unreadableEntries = []
        isImporting = true
        defer { isImporting = false }

        do {
            try await model.authenticate()
            let imported = try await BitwardenCLI.importCodes(password: masterPassword, session: sessionKey)
            try model.saveVault(imported.codes)
            model.defaults.set(Date(), forKey: AetherPrefs.vaultImportedAt)
            model.set(AetherPrefs.bitwarden, on: true)
            masterPassword = ""
            sessionKey = ""
            unreadableEntries = imported.unreadable
            feedbackMessage = "Imported \(imported.codes.count) Bitwarden authenticator \(imported.codes.count == 1 ? "code" : "codes")."
            await refreshStatus()
        } catch {
            if !AetherAppModel.isCancel(error) {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct IgnoredSendersSettingsPage: View {
    @ObservedObject var model: AetherAppModel
    @State private var newSender = ""

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Add sender or domain")
            } content: {
                DropletSettingsCard {
                    AetherSettingsControlRow(
                        title: "Sender, number, or domain",
                        icon: "nosign",
                        iconColor: .gray,
                        infoTip: "Messages and emails from matching senders are ignored cleanly."
                    ) {
                        HStack(spacing: 8) {
                            TextField("noreply@example.com or example.com", text: $newSender)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 230)
                                .onSubmit(addEntry)
                            Button("Ignore") { addEntry() }
                                .buttonStyle(.borderedProminent)
                                .disabled(newSender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Ignored senders (\(model.ignoredSenders.count))")
            } content: {
                DropletSettingsCard {
                    if model.ignoredSenders.isEmpty {
                        AetherWarningRow(
                            message: "No senders are ignored. You can ignore a sender from any code row's context menu or above.",
                            calm: true
                        )
                    } else {
                        ForEach(model.ignoredSenders, id: \.self) { sender in
                            AetherSettingsControlRow(
                                title: sender,
                                icon: "person.crop.circle.badge.xmark",
                                iconColor: .gray
                            ) {
                                Button("Restore") {
                                    model.stopIgnoring([sender])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        AetherSettingsControlRow(
                            title: "Restore all senders",
                            icon: "arrow.uturn.backward.circle.fill",
                            iconColor: .blue
                        ) {
                            Button("Restore All…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Stop ignoring all senders?",
                                    message: "AETHER will resume reading codes from all previously ignored senders.",
                                    confirmTitle: "Restore All",
                                    symbol: "arrow.uturn.backward.circle"
                                )
                                if confirmed {
                                    model.stopIgnoring(Set(model.ignoredSenders))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func addEntry() {
        let trimmed = newSender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.ignore(trimmed)
        newSender = ""
    }
}

struct NotCodesSettingsPage: View {
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Ignored code patterns (\(model.notCodes.count))")
            } content: {
                DropletSettingsCard {
                    if model.notCodes.isEmpty {
                        AetherWarningRow(
                            message: "No patterns marked as \"Not a Code\". Mark false positives from any code row's context menu.",
                            calm: true
                        )
                    } else {
                        ForEach(model.notCodes) { rule in
                            AetherSettingsControlRow(
                                title: rule.sender.isEmpty ? rule.key : rule.sender,
                                subtitle: rule.added.formatted(.relative(presentation: .named)),
                                icon: "xmark.seal.fill",
                                iconColor: .gray,
                                infoTip: "Rule key: \(rule.key)"
                            ) {
                                Button("Forget") {
                                    model.forgetNotCodes([rule.key])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        AetherSettingsControlRow(
                            title: "Forget all rules",
                            icon: "trash.fill",
                            iconColor: .gray
                        ) {
                            Button("Forget All…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Forget all \"Not a Code\" rules?",
                                    message: "AETHER will detect numeric codes from those message formats again.",
                                    confirmTitle: "Forget All",
                                    symbol: "trash.fill"
                                )
                                if confirmed {
                                    model.forgetNotCodes(Set(model.notCodes.map(\.key)))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}
