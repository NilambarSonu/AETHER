// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import DroppyKit
import SwiftUI

struct AddAccountSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Recommended OAuth providers")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Google / Gmail",
                        subtitle: "Sign in securely with Google OAuth (read-only) or use an App Password",
                        page: AetherSettingsRoute.newAccount("gmail")
                    ) {
                        AetherSymbolTile(symbol: "envelope.badge.fill", color: .red, size: DropletSettingsPageLink.tileSize)
                    }

                    DropletSettingsPageLink(
                        "Microsoft Outlook / 365",
                        subtitle: "Sign in securely with Microsoft Graph OAuth (Mail.Read) or IMAP",
                        page: AetherSettingsRoute.newAccount("outlook")
                    ) {
                        AetherSymbolTile(symbol: "envelope.fill", color: .blue, size: DropletSettingsPageLink.tileSize)
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("App Password / IMAP")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "iCloud Mail",
                        subtitle: "Connect using an Apple ID app-specific password (imap.mail.me.com)",
                        page: AetherSettingsRoute.newAccount("icloud")
                    ) {
                        AetherSymbolTile(symbol: "icloud.fill", color: .cyan, size: DropletSettingsPageLink.tileSize)
                    }

                    DropletSettingsPageLink(
                        "Yahoo Mail",
                        subtitle: "Connect using a Yahoo app password (imap.mail.yahoo.com)",
                        page: AetherSettingsRoute.newAccount("yahoo")
                    ) {
                        AetherSymbolTile(symbol: "envelope.open.fill", color: .purple, size: DropletSettingsPageLink.tileSize)
                    }

                    DropletSettingsPageLink(
                        "Other IMAP server",
                        subtitle: "Connect to Fastmail, Proton Bridge, or any TLS IMAP server (port 993)",
                        page: AetherSettingsRoute.newAccount("imap")
                    ) {
                        AetherSymbolTile(symbol: "server.rack", color: .gray, size: DropletSettingsPageLink.tileSize)
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
    }
}

struct AccountEditorSettingsPage: View {
    @ObservedObject var droplet: AetherDroplet
    @ObservedObject var model: AetherAppModel

    let existingAccountID: UUID?
    let preset: String?

    @StateObject private var signIn = MailSignIn()
    @State private var account: MailAccount
    @State private var useOAuth: Bool
    @State private var password = ""
    @State private var portText: String
    @State private var hasEditedHost = false
    @State private var hasEditedLabel = false
    @State private var statusMessage: String?
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var testTask: Task<Void, Never>?

    private let originalAccount: MailAccount?

    init(
        droplet: AetherDroplet,
        model: AetherAppModel,
        existingAccountID: UUID? = nil,
        preset: String? = nil
    ) {
        self.droplet = droplet
        self.model = model
        self.existingAccountID = existingAccountID
        self.preset = preset

        let existing = existingAccountID.flatMap { id in model.accounts.first(where: { $0.id == id }) }
        self.originalAccount = existing

        let initial: MailAccount
        if let existing {
            initial = existing
        } else {
            switch preset {
            case "gmail":
                initial = MailAccount(label: "Gmail", host: MailAccount.gmailHost, port: 993, user: "", signedIn: true)
            case "outlook":
                initial = MailAccount(label: "Outlook", host: MailAccount.outlookHost, port: 993, user: "", signedIn: true)
            case "icloud":
                initial = MailAccount(label: "iCloud", host: "imap.mail.me.com", port: 993, user: "", signedIn: false)
            case "yahoo":
                initial = MailAccount(label: "Yahoo", host: "imap.mail.yahoo.com", port: 993, user: "", signedIn: false)
            default:
                initial = MailAccount(label: "", host: "", port: 993, user: "", signedIn: false)
            }
        }

        _account = State(initialValue: initial)
        _useOAuth = State(initialValue: initial.provider != nil && (existing == nil ? initial.usesSignIn : initial.usesSignIn))
        _portText = State(initialValue: String(initial.port))
        _hasEditedHost = State(initialValue: existing != nil || (preset != nil && preset != "imap"))
        _hasEditedLabel = State(initialValue: existing != nil || !initial.label.isEmpty)
    }

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Account details")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Email address",
                        icon: "at",
                        iconColor: .blue,
                        infoTip: "Email address for this inbox. AETHER only reads recent messages for codes and never marks mail read."
                    ) {
                        TextField("you@example.com", text: $account.user)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .onChange(of: account.user) { _, newValue in
                                guard originalAccount == nil else { return }
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard trimmed.contains("@") else { return }
                                let guessed = MailAccount.guess(for: trimmed)
                                if !hasEditedHost || account.host.isEmpty {
                                    account.host = guessed.host
                                }
                                if !hasEditedLabel || account.label.isEmpty {
                                    account.label = guessed.label
                                }
                                if let detectedProvider = account.provider {
                                    useOAuth = true
                                    account.signedIn = true
                                    _ = detectedProvider
                                }
                            }
                    }

                    DropletControlRow(
                        title: "Display label",
                        icon: "tag.fill",
                        iconColor: .teal,
                        infoTip: "Optional short label shown when differentiating multiple mail accounts."
                    ) {
                        TextField("Personal Gmail", text: $account.label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .onChange(of: account.label) { _, value in
                                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    hasEditedLabel = true
                                }
                            }
                    }

                    DropletToggleRow(
                        title: "Watch this inbox",
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        subtitle: "Automatically fetches arriving verification codes and sign-in links in the background.",
                        isOn: $account.enabled
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader(LocalizedStringKey(account.provider.map { "\($0.name) authentication" } ?? "IMAP connection"))
            } content: {
                DropletSettingsCard {
                    if let provider = account.provider {
                        DropletControlRow(
                            title: "Sign-in method",
                            icon: "person.badge.key.fill",
                            iconColor: .indigo,
                            infoTip: "OAuth uses your browser and saves a read-only Keychain token. You can also use an app-specific IMAP password."
                        ) {
                            Picker("Sign-in method", selection: $useOAuth) {
                                Text("OAuth Sign-In").tag(true)
                                Text("App Password").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 230)
                            .onChange(of: useOAuth) { _, oauth in
                                account.signedIn = oauth
                            }
                        }

                        if useOAuth {
                            oauthSection(provider: provider)
                        } else {
                            imapFields(showPasswordHelp: true)
                        }
                    } else {
                        imapFields(showPasswordHelp: account.isGmail || account.host.contains("icloud") || account.host.contains("yahoo"))
                    }
                }
            }

            if let statusMessage {
                DropletSettingsSection {
                    settingsSectionHeader("Connection")
                } content: {
                    DropletSettingsCard {
                        AetherWarningRow(message: statusMessage, calm: true)
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

            DropletSettingsSection {
                settingsSectionHeader("Actions")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: originalAccount == nil ? "Add mail account" : "Save changes",
                        icon: "checkmark.circle.fill",
                        iconColor: .blue
                    ) {
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                signIn.cancel()
                                testTask?.cancel()
                                droplet.goBackInSettings()
                            }
                            .buttonStyle(.bordered)

                            Button(originalAccount == nil ? "Save Account" : "Save") {
                                saveAccount()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSave || signIn.isBusy)
                        }
                    }

                    if let originalAccount {
                        DropletControlRow(
                            title: "Remove account",
                            icon: "trash.fill",
                            iconColor: .red,
                            infoTip: "Stops reading this inbox and revokes or removes its Keychain credentials."
                        ) {
                            Button("Remove…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Remove \(originalAccount.label)?",
                                    message: "AETHER will stop watching \(originalAccount.user) and remove its saved Keychain credentials.",
                                    confirmTitle: "Remove Account",
                                    symbol: "trash.fill"
                                )
                                guard confirmed else { return }
                                do {
                                    try model.remove(originalAccount)
                                    droplet.goBackInSettings()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .background(AetherWindowAnchorReader())
        .onDisappear {
            signIn.cancel()
            testTask?.cancel()
        }
    }

    @ViewBuilder
    private func oauthSection(provider: MailOAuth) -> some View {
        let trimmedUser = account.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNewGrant = signIn.token(for: normalizedAccount) != nil
        let hasExistingGrant = originalAccount?.usesSignIn == true
            && originalAccount?.secretKey == normalizedAccount.secretKey
            && originalAccount?.hasCredential(in: model.secrets) == true

        DropletControlRow(
            title: "\(provider.name) access",
            icon: hasNewGrant || hasExistingGrant ? "checkmark.shield.fill" : "globe",
            iconColor: hasNewGrant || hasExistingGrant ? .green : .blue,
            infoTip: "Opens your default browser via macOS ASWebAuthenticationSession with PKCE."
        ) {
            HStack(spacing: 8) {
                if hasNewGrant {
                    Text("Authorized as \(trimmedUser)")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if hasExistingGrant {
                    Text("Signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(signIn.isBusy ? "Signing in…" : (hasNewGrant || hasExistingGrant ? "Re-authenticate" : "Sign in with \(provider.name)…")) {
                    startOAuthSignIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(signIn.isBusy)
            }
        }
    }

    @ViewBuilder
    private func imapFields(showPasswordHelp: Bool) -> some View {
        DropletControlRow(
            title: "IMAP server",
            icon: "network",
            iconColor: .gray
        ) {
            TextField("imap.example.com", text: $account.host)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onChange(of: account.host) { _, _ in
                    hasEditedHost = true
                }
        }

        DropletControlRow(
            title: "TLS port",
            icon: "number.square",
            iconColor: .gray
        ) {
            TextField("993", text: $portText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .onChange(of: portText) { _, newValue in
                    if let parsed = Int(newValue.trimmingCharacters(in: .whitespaces)) {
                        account.port = parsed
                    }
                }
        }

        DropletControlRow(
            title: originalAccount?.hasCredential(in: model.secrets) == true && originalAccount?.usesSignIn == false
                ? "New app password (optional)"
                : "App password",
            icon: "key.fill",
            iconColor: .orange,
            infoTip: "Stored only in macOS Keychain under AETHER."
        ) {
            HStack(spacing: 8) {
                SecureField(
                    originalAccount?.usesSignIn == false && originalAccount?.hasCredential(in: model.secrets) == true
                        ? "Keep existing"
                        : "Required",
                    text: $password
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)

                if showPasswordHelp {
                    Link("Guide", destination: MailAccount.appPasswordHelp)
                        .font(.caption)
                }
            }
        }

        DropletControlRow(
            title: "Verify connection",
            icon: "bolt.horizontal.circle",
            iconColor: .teal
        ) {
            Button(isTesting ? "Testing…" : "Test IMAP Login") {
                runConnectionTest()
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || !canRunIMAPTest)
        }
    }

    private var normalizedAccount: MailAccount {
        var copy = account
        copy.user = account.user.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.host = account.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            let guessed = MailAccount.guess(for: copy.user)
            copy.label = guessed.label.isEmpty ? (copy.user.isEmpty ? "Mail" : copy.user) : guessed.label
        } else {
            copy.label = trimmedLabel
        }
        copy.port = Int(portText.trimmingCharacters(in: .whitespaces)) ?? account.port
        copy.signedIn = useOAuth && copy.provider != nil
        return copy
    }

    private var canRunIMAPTest: Bool {
        let candidate = normalizedAccount
        let secret = password.isEmpty ? originalAccount?.password(in: model.secrets) : password
        return !candidate.user.isEmpty && !candidate.host.isEmpty && (1...65535).contains(candidate.port) && !(secret ?? "").isEmpty
    }

    private var canSave: Bool {
        let candidate = normalizedAccount
        guard !candidate.user.isEmpty, !candidate.host.isEmpty, (1...65535).contains(candidate.port) else {
            return false
        }
        if candidate.usesSignIn {
            let hasNewToken = signIn.token(for: candidate) != nil
            let hasSavedToken = originalAccount?.usesSignIn == true
                && originalAccount?.secretKey == candidate.secretKey
                && originalAccount?.hasCredential(in: model.secrets) == true
            return hasNewToken || hasSavedToken
        } else {
            let hasSavedPassword = originalAccount?.usesSignIn == false
                && originalAccount?.secretKey == candidate.secretKey
                && originalAccount?.hasCredential(in: model.secrets) == true
            return !password.isEmpty || hasSavedPassword
        }
    }

    private func startOAuthSignIn() {
        errorMessage = nil
        statusMessage = nil
        let target = normalizedAccount
        Task {
            do {
                let signedEmail = try await signIn.signIn(for: target)
                account.user = signedEmail
                account.signedIn = true
                if account.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    account.label = MailAccount.guess(for: signedEmail).label
                }
                statusMessage = "Authenticated cleanly as \(signedEmail). Click Save to begin watching this inbox."
            } catch {
                if (error as? CancellationError) == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func runConnectionTest() {
        let candidate = normalizedAccount
        let secret = password.isEmpty ? (originalAccount?.password(in: model.secrets) ?? "") : password
        guard !secret.isEmpty else {
            errorMessage = "Enter an app password first."
            return
        }
        errorMessage = nil
        statusMessage = nil
        isTesting = true
        testTask?.cancel()
        testTask = Task {
            defer { isTesting = false }
            do {
                let conn = try IMAPConnection(account: candidate)
                try await conn.open(user: candidate.user, password: secret)
                await conn.close()
                statusMessage = "Connected to \(candidate.host):\(candidate.port) cleanly."
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveAccount() {
        errorMessage = nil
        let candidate = normalizedAccount
        let newRefreshToken = candidate.usesSignIn ? signIn.token(for: candidate) : nil
        let effectivePassword: String = {
            if candidate.usesSignIn { return "" }
            if !password.isEmpty { return password }
            if let existing = originalAccount, existing.secretKey != candidate.secretKey {
                return existing.password(in: model.secrets) ?? ""
            }
            return ""
        }()

        do {
            try model.saveAccount(candidate, password: effectivePassword, refreshToken: newRefreshToken)
            if let originalAccount, originalAccount.secretKey != candidate.secretKey {
                try? model.removeUnusedCredentials(for: originalAccount)
            }
            droplet.goBackInSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
