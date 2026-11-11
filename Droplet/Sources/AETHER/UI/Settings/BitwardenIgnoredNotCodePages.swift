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
                    DropletControlRow(
                        title: "Bitwarden CLI (bw)",
                        icon: cliStatus.version != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: cliStatus.version != nil ? .green : .orange,
                        infoTip: "AETHER invokes the local Bitwarden CLI strictly when you click Import."
                    ) {
                        HStack(spacing: 8) {
                            if let version = cliStatus.version {
                                Text("v\(version) · \(cliStatus.email ?? cliStatus.state)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not found (install with `brew install bitwarden-cli`)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Button(isCheckingStatus ? "Checking…" : "Refresh") {
                                Task { await refreshStatus() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isCheckingStatus)
                        }
                    }

                    if cliStatus.version != nil {
                        DropletControlRow(
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
                        DropletControlRow(
                            title: "Master password",
                            icon: "lock.fill",
                            iconColor: .indigo,
                            infoTip: "Used once to unlock bw CLI during import and never written to disk."
                        ) {
                            SecureField("Required unless session key provided", text: $masterPassword)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                        }
                    }

                    DropletControlRow(
                        title: "Session key (optional)",
                        icon: "key.horizontal.fill",
                        iconColor: .gray,
                        infoTip: "Optional BW_SESSION token from `bw unlock --raw` if you prefer not entering your master password."
                    ) {
                        SecureField("BW_SESSION token", text: $sessionKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }

                    DropletControlRow(
                        title: "Import authenticator items",
                        icon: "arrow.down.doc.fill",
                        iconColor: .blue,
                        infoTip: "Syncs Bitwarden items containing TOTP secrets and stores only those TOTP keys in your macOS Keychain."
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
                    settingsSectionHeader("Saved vault keys")
                } content: {
                    DropletSettingsCard {
                        DropletControlRow(
                            title: "Imported authenticator entries",
                            icon: "key.viewfinder",
                            iconColor: .green
                        ) {
                            Text(model.vaultSession.isUnlocked ? "\(model.vault.count) logins with TOTP" : "Locked (unlock to view)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        DropletControlRow(
                            title: "Delete saved Bitwarden keys",
                            icon: "trash.fill",
                            iconColor: .red,
                            infoTip: "Deletes AETHER's Keychain copy only. Your Bitwarden vault is untouched."
                        ) {
                            Button("Remove Saved Keys…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Remove Bitwarden TOTP keys from AETHER?",
                                    message: "This deletes the TOTP secrets imported into AETHER's Keychain. Your Bitwarden account and vault are unchanged.",
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
                    settingsSectionHeader("Error")
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
                    DropletControlRow(
                        title: "Sender, phone number, or domain",
                        icon: "nosign",
                        iconColor: .gray,
                        infoTip: "Messages and emails matching these senders are skipped cleanly."
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
                            DropletControlRow(
                                title: sender,
                                icon: "person.crop.circle.badge.xmark",
                                iconColor: .secondary
                            ) {
                                Button("Restore") {
                                    model.stopIgnoring([sender])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        DropletControlRow(
                            title: "Restore all senders",
                            icon: "arrow.uturn.backward.circle",
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
                            message: "No patterns marked as \"Not a Code\". Mark any false positive from a code row's context menu.",
                            calm: true
                        )
                    } else {
                        ForEach(model.notCodes) { rule in
                            DropletControlRow(
                                title: rule.sender.isEmpty ? rule.key : rule.sender,
                                icon: "xmark.seal.fill",
                                iconColor: .secondary,
                                infoTip: "Rule key: \(rule.key)"
                            ) {
                                HStack(spacing: 8) {
                                    Text(rule.added.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Forget") {
                                        model.forgetNotCodes([rule.key])
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        DropletControlRow(
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
