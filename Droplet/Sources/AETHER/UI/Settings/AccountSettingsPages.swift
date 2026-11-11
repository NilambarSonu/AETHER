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
                settingsSectionHeader("Cloud mail providers (OAuth / App Password)")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "Google / Gmail",
                        subtitle: "Connect using AETHER's OAuth client or a Google App Password",
                        page: AetherSettingsRoute.newAccount("gmail")
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "envelope.badge.fill",
                            top: Color(red: 0.94, green: 0.28, blue: 0.26),
                            bottom: Color(red: 0.78, green: 0.14, blue: 0.14),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Microsoft Outlook / 365",
                        subtitle: "Connect using AETHER Microsoft Graph OAuth (Mail.Read) or IMAP",
                        page: AetherSettingsRoute.newAccount("outlook")
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "envelope.fill",
                            top: Color(red: 0.14, green: 0.60, blue: 0.98),
                            bottom: Color(red: 0.04, green: 0.38, blue: 0.84),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Direct TLS IMAP / App Password")
            } content: {
                DropletSettingsCard {
                    DropletSettingsPageLink(
                        "iCloud Mail",
                        subtitle: "Connect with an Apple ID app-specific password (imap.mail.me.com)",
                        page: AetherSettingsRoute.newAccount("icloud")
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "icloud.fill",
                            top: Color(red: 0.26, green: 0.78, blue: 0.98),
                            bottom: Color(red: 0.10, green: 0.54, blue: 0.86),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Yahoo Mail",
                        subtitle: "Connect with a Yahoo app password (imap.mail.yahoo.com)",
                        page: AetherSettingsRoute.newAccount("yahoo")
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "envelope.open.fill",
                            top: Color(red: 0.62, green: 0.26, blue: 0.92),
                            bottom: Color(red: 0.42, green: 0.12, blue: 0.74),
                            size: AetherSymbolTile.settingsLinkSize
                        )
                    }

                    DropletSettingsPageLink(
                        "Other IMAP server",
                        subtitle: "Fastmail, Proton Bridge, or any TLS IMAP mailbox (port 993)",
                        page: AetherSettingsRoute.newAccount("imap")
                    ) {
                        AetherSettingsIconBadge(
                            symbol: "server.rack",
                            top: Color(white: 0.48),
                            bottom: Color(white: 0.30),
                            size: AetherSymbolTile.settingsLinkSize
                        )
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

    @StateObject private var signIn: MailSignIn
    @State private var account: MailAccount
    @State private var useOAuth: Bool
    @State private var password = ""
    @State private var portText: String
    @State private var hasEditedHost = false
    @State private var hasEditedLabel = false
    @State private var customClientID = ""
    @State private var customRedirectURI = ""
    @State private var showClientSetup = false
    @State private var copiedRedirect = false
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

        let storedCred = initial.providerKind.flatMap { MailOAuth.customCredential(for: $0, in: model.secrets) }
        let resolved = initial.resolvedProvider(in: model.secrets)

        _signIn = StateObject(wrappedValue: MailSignIn(secrets: model.secrets))
        _account = State(initialValue: initial)
        _useOAuth = State(initialValue: initial.providerKind != nil && initial.usesSignIn)
        _portText = State(initialValue: String(initial.port))
        _hasEditedHost = State(initialValue: existing != nil || (preset != nil && preset != "imap"))
        _hasEditedLabel = State(initialValue: existing != nil || !initial.label.isEmpty)
        _customClientID = State(initialValue: storedCred?.clientID ?? "")
        _customRedirectURI = State(initialValue: storedCred?.redirectURI ?? "")
        _showClientSetup = State(initialValue: !(resolved?.isConfigured ?? true))
    }

    var body: some View {
        DropletSettingsPage {
            DropletSettingsSection {
                settingsSectionHeader("Mailbox identity")
            } content: {
                DropletSettingsCard {
                    AetherSettingsControlRow(
                        title: "Email address",
                        icon: "at",
                        iconColor: .blue,
                        infoTip: "AETHER monitors recent messages strictly read-only without changing read/unread state."
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
                                if let detectedKind = account.providerKind {
                                    useOAuth = true
                                    account.signedIn = true
                                    loadOAuthClientFields(for: detectedKind)
                                }
                            }
                    }

                    AetherSettingsControlRow(
                        title: "Display label",
                        icon: "tag.fill",
                        iconColor: .teal,
                        infoTip: "Friendly label shown in notifications, notch cards, and multi-inbox views."
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

                    AetherSettingsToggleRow(
                        title: "Watch this inbox",
                        subtitle: "Automatically detects arriving OTP codes and verified sign-in links.",
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        isOn: $account.enabled
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader(LocalizedStringKey(account.providerKind.map { "\($0 == .google ? "Google" : "Microsoft") authentication" } ?? "IMAP connection"))
            } content: {
                DropletSettingsCard {
                    if let kind = account.providerKind {
                        AetherSettingsControlRow(
                            title: "Sign-in method",
                            icon: "person.badge.key.fill",
                            iconColor: .indigo,
                            infoTip: "Use your AETHER OAuth Client ID (browser PKCE) or an App Password (direct TLS IMAP IDLE)."
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
                            oauthSection(kind: kind)
                        } else {
                            imapFields(showPasswordHelp: true)
                        }
                    } else {
                        imapFields(showPasswordHelp: account.isGmail || account.host.contains("icloud") || account.host.contains("yahoo"))
                    }
                }
            }

            if let kind = account.providerKind, useOAuth {
                DropletSettingsSection {
                    settingsSectionHeader("AETHER OAuth client")
                } content: {
                    DropletSettingsCard {
                        oauthClientConfigurationRows(kind: kind)
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
                    settingsSectionHeader("Attention")
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
                    AetherSettingsControlRow(
                        title: originalAccount == nil ? "Save new mailbox" : "Save changes",
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
                        AetherSettingsControlRow(
                            title: "Remove account",
                            icon: "trash.fill",
                            iconColor: .red,
                            infoTip: "Stops monitoring and erases saved encrypted Keychain tokens."
                        ) {
                            Button("Remove…") {
                                let confirmed = DropletConfirmationDialog.present(
                                    title: "Remove \(originalAccount.label)?",
                                    message: "AETHER will stop watching \(originalAccount.user) and wipe its encrypted Keychain credentials.",
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
    private func oauthSection(kind: MailOAuth.ProviderKind) -> some View {
        let provider = MailOAuth.resolved(for: kind, in: model.secrets)
        let trimmedUser = account.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNewGrant = signIn.token(for: normalizedAccount) != nil
        let hasExistingGrant = originalAccount?.usesSignIn == true
            && originalAccount?.secretKey == normalizedAccount.secretKey
            && originalAccount?.hasCredential(in: model.secrets) == true

        AetherSettingsControlRow(
            title: "\(provider.name) sign-in",
            subtitle: hasNewGrant
                ? "Authenticated as \(trimmedUser)"
                : provider.isConfigured
                    ? "Sign in with AETHER's configured OAuth client"
                    : "Configure an AETHER OAuth Client ID below, or switch to App Password",
            icon: hasNewGrant || hasExistingGrant ? "checkmark.shield.fill" : "globe",
            iconColor: hasNewGrant || hasExistingGrant ? .green : (provider.isConfigured ? .blue : .orange),
            infoTip: "Uses macOS ASWebAuthenticationSession with SecRandomCopyBytes PKCE. Zero third-party CodeCatch identifiers."
        ) {
            HStack(spacing: 8) {
                if !provider.isConfigured {
                    Button("Use App Password") {
                        useOAuth = false
                        account.signedIn = false
                    }
                    .buttonStyle(.bordered)
                }

                Button(signIn.isBusy ? "Signing in…" : (hasNewGrant || hasExistingGrant ? "Re-authenticate" : "Sign in with \(provider.name)…")) {
                    startOAuthSignIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(signIn.isBusy || !provider.isConfigured)
            }
        }
    }

    @ViewBuilder
    private func oauthClientConfigurationRows(kind: MailOAuth.ProviderKind) -> some View {
        let resolved = previewResolvedOAuth(for: kind)

        AetherSettingsControlRow(
            title: kind == .google ? "Google OAuth Client ID" : "Microsoft Client ID",
            subtitle: kind == .google
                ? "Create an iOS OAuth Client ID in Google Cloud Console under your AETHER brand."
                : "Create a Mobile & desktop public client in Microsoft Entra ID.",
            icon: "key.viewfinder",
            iconColor: resolved.isConfigured ? .green : .blue,
            infoTip: "Stored AES-256-GCM encrypted in macOS Keychain."
        ) {
            HStack(spacing: 8) {
                TextField(
                    kind == .google ? "123456-xxx.apps.googleusercontent.com" : "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                    text: $customClientID
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                Button("Apply") {
                    saveCustomOAuthClient(for: kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        AetherSettingsControlRow(
            title: "Redirect URI",
            subtitle: resolved.redirect,
            icon: "arrow.triangle.turn.up.right.circle.fill",
            iconColor: .teal,
            infoTip: "Register this exact redirect URI in your cloud console."
        ) {
            Button(copiedRedirect ? "Copied!" : "Copy URI") {
                droplet.copyText(resolved.redirect)
                copiedRedirect = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copiedRedirect = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func imapFields(showPasswordHelp: Bool) -> some View {
        AetherSettingsControlRow(
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

        AetherSettingsControlRow(
            title: "TLS port",
            icon: "number.square.fill",
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

        AetherSettingsControlRow(
            title: originalAccount?.hasCredential(in: model.secrets) == true && originalAccount?.usesSignIn == false
                ? "New app password"
                : "App password",
            icon: "key.fill",
            iconColor: .orange,
            infoTip: "Encrypted with AES-256-GCM inside your local macOS Keychain."
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

        AetherSettingsControlRow(
            title: "Verify connection",
            icon: "bolt.horizontal.circle.fill",
            iconColor: .teal
        ) {
            Button(isTesting ? "Testing…" : "Test IMAP Login") {
                runConnectionTest()
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || !canRunIMAPTest)
        }
    }

    private func previewResolvedOAuth(for kind: MailOAuth.ProviderKind) -> MailOAuth {
        let draftID = customClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftID.isEmpty {
            let draftRedirect = customRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
            return kind == .google
                ? MailOAuth.google(clientID: draftID, redirectURI: draftRedirect.isEmpty ? nil : draftRedirect)
                : MailOAuth.microsoft(clientID: draftID, redirectURI: draftRedirect.isEmpty ? nil : draftRedirect)
        }
        return MailOAuth.resolved(for: kind, in: model.secrets)
    }

    private func loadOAuthClientFields(for kind: MailOAuth.ProviderKind) {
        let cred = MailOAuth.customCredential(for: kind, in: model.secrets)
        customClientID = cred?.clientID ?? ""
        customRedirectURI = cred?.redirectURI ?? ""
    }

    private func saveCustomOAuthClient(for kind: MailOAuth.ProviderKind) {
        errorMessage = nil
        do {
            try MailOAuth.saveCustomCredential(
                clientID: customClientID,
                redirectURI: customRedirectURI,
                for: kind,
                in: model.secrets
            )
            statusMessage = customClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Cleared custom \(kind == .google ? "Google" : "Microsoft") OAuth Client ID."
                : "Saved custom \(kind == .google ? "Google" : "Microsoft") OAuth Client ID in encrypted Keychain."
        } catch {
            errorMessage = error.localizedDescription
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
        copy.signedIn = useOAuth && copy.providerKind != nil
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
        if let kind = account.providerKind {
            saveCustomOAuthClientIfEdited(for: kind)
        }
        let target = normalizedAccount
        Task {
            do {
                let signedEmail = try await signIn.signIn(for: target)
                account.user = signedEmail
                account.signedIn = true
                if account.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    account.label = MailAccount.guess(for: signedEmail).label
                }
                statusMessage = "Authenticated cleanly as \(signedEmail). Click Save Account to begin monitoring."
            } catch {
                if (error as? CancellationError) == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveCustomOAuthClientIfEdited(for kind: MailOAuth.ProviderKind) {
        let trimmed = customClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? MailOAuth.saveCustomCredential(
            clientID: trimmed,
            redirectURI: customRedirectURI,
            for: kind,
            in: model.secrets
        )
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
                statusMessage = "Connected to \(candidate.host):\(candidate.port) over TLS."
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
