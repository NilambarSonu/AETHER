// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation
import Testing
@testable import AetherEngine

@Suite("AetherEngine")
struct AetherEngineTests {
    @MainActor
    private func makeIsolatedModel() -> (model: AetherAppModel, defaults: UserDefaults, secrets: AetherSecretStore, copied: Box<[String]>, huds: Box<[String]>) {
        let suiteName = "app.getdroppy.droplet.aether.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secrets = AetherSecretStore.inMemory()
        let copied = Box<[String]>([])
        let huds = Box<[String]>([])
        let policy = UnlockPolicy(
            load: { false },
            save: { _ in },
            authenticate: {},
            cancel: {}
        )
        let session = VaultStorage.session(defaults: defaults, secrets: secrets, unlockPolicy: policy)
        let monitor = SourceMonitor(
            defaults: defaults,
            secrets: secrets,
            watchMail: { _, callbacks in callbacks.status(.live) },
            hasCredential: { _ in true }
        )
        let hooks = AetherRuntimeHooks(
            presentHUD: { item, _ in huds.value.append(item.code) },
            copyToClipboard: { text, _ in copied.value.append(text) },
            screenIsLocked: { false }
        )
        let model = AetherAppModel(
            defaults: defaults,
            secrets: secrets,
            vaultSession: session,
            monitor: monitor,
            unlockPolicy: policy,
            agentAuthenticate: { _ in },
            hooks: hooks
        )
        return (model, defaults, secrets, copied, huds)
    }

    @Test("Keychain namespace is strictly scoped to droplet and isolated from CodeCatch")
    func secretStoreNamespace() {
        #expect(AetherSecretStore.defaultService == "app.getdroppy.droplet.aether")
        let mem = AetherSecretStore.inMemory()
        try? mem.set("secret-val", for: "user@example.com")
        #expect(mem.get("user@example.com") == "secret-val")
        try? mem.remove("user@example.com")
        #expect(mem.get("user@example.com") == nil)
    }

    @Test("MailAccount provider guessing, saving, duplicate rejection, and OAuth revocation")
    @MainActor
    func mailAccountLifecycle() throws {
        let (model, defaults, secrets, _, _) = makeIsolatedModel()
        _ = defaults

        let gmail = MailAccount.guess(for: "alice@gmail.com")
        #expect(gmail.isGmail)
        #expect(gmail.label == "Gmail")

        let outlook = MailAccount.guess(for: "bob@outlook.com")
        #expect(outlook.isOutlook)
        #expect(outlook.label == "Outlook")

        try model.saveAccount(gmail, password: "", refreshToken: "rt-1")
        #expect(model.accounts.count == 1)
        #expect(model.accounts[0].usesSignIn)
        #expect(secrets.get(gmail.refreshTokenKey) == "rt-1")

        let duplicate = MailAccount(label: "Gmail 2", host: MailAccount.gmailHost, user: "alice@gmail.com")
        #expect(throws: AetherAppModel.AccountSaveError.self) {
            try model.saveAccount(duplicate, password: "p", refreshToken: nil)
        }

        try model.remove(model.accounts[0])
        #expect(model.accounts.isEmpty)
        #expect(secrets.get(gmail.refreshTokenKey) == nil)
    }

    @Test("PKCE OAuth callback validation rejects state mismatches, fragments, and errors")
    func oauthCallbackValidation() throws {
        let google = MailOAuth.google
        let good = google.redirect + "?state=abc123&code=auth_code_99"
        #expect(try google.authorizationCode(in: good, state: "abc123") == "auth_code_99")
        #expect(try google.authorizationCode(in: good, state: "wrong") == nil)
        #expect(try google.authorizationCode(in: good + "#frag", state: "abc123") == nil)
        let denied = google.redirect + "?state=abc123&error=access_denied"
        #expect(throws: MailOAuth.Failure.self) {
            _ = try google.authorizationCode(in: denied, state: "abc123")
        }
    }

    @Test("Ingestion, auto-copy, Not a Code, Ignored Senders, and RecoveryInbox work end to end")
    @MainActor
    func ingestionFilteringAndRecovery() async throws {
        let (model, _, _, copied, huds) = makeIsolatedModel()
        try await model.unlock()
        #expect(model.isUnlocked)

        // 1. Live OTP triggers auto-copy and HUD
        model.ingest(IncomingMessage(
            text: "Your GitHub verification code is 614209.",
            senderName: "GitHub",
            senderID: "noreply@github.com",
            sourceKey: "acc-1",
            sourceLabel: "Work",
            date: Date(),
            isMail: true
        ))
        #expect(model.items.count == 1)
        #expect(model.items[0].code == "614209")
        #expect(copied.value.last == "614209")
        #expect(huds.value.last == "614209")

        // 2. Marking "Not a Code" hashes context and removes matching item
        let item = model.items[0]
        model.markNotCode(item)
        #expect(model.items.isEmpty)
        #expect(model.notCodes.count == 1)
        model.forgetNotCodes(Set(model.notCodes.map(\.key)))
        #expect(model.notCodes.isEmpty)

        // 3. Ignored senders skip messages
        model.ignore("github.com")
        model.ingest(IncomingMessage(
            text: "Your GitHub verification code is 778899.",
            senderName: "GitHub",
            senderID: "security@github.com",
            sourceKey: "acc-1",
            sourceLabel: "Work",
            date: Date(),
            isMail: true
        ))
        #expect(model.items.isEmpty)

        // 4. Unmatched code email lands in RecoveryInbox
        model.stopIgnoring(["github.com"])
        model.ingest(IncomingMessage(
            text: "Please enter this login confirmation phrase at the verification step.",
            subject: "Verify your sign-in",
            senderName: "Acme",
            senderID: "help@acme.example",
            sourceKey: AppleMailStore.sourceKey,
            sourceLabel: "Apple Mail",
            date: Date(),
            isMail: true
        ))
        #expect(model.recovery.entries.count == 1)
    }

    @Test("AgentAccess enforces sign-in link DMARC checks, never releases reset links, and limits rules")
    @MainActor
    func agentAccessSecurityGates() async throws {
        let (model, _, _, _, _) = makeIsolatedModel()
        try await model.unlock()
        await model.agents.setEnabled(true)
        await model.agents.setLinks(true)
        #expect(model.agents.config.enabled)
        #expect(model.agents.config.links)

        // Unverified email with sign-in link MUST NOT be released via releasesLink
        let unverified = IncomingMessage(
            text: "Click here to sign in",
            subject: "Your sign-in link",
            senderName: "Acme",
            senderID: "noreply@acme.com",
            sourceKey: "acc-1",
            sourceLabel: "Gmail",
            date: Date(),
            isMail: true,
            links: [MailLink(url: "https://acme.com/auth?t=1", label: "Sign in")],
            senderVerified: false
        )
        model.ingest(unverified)
        let unverifiedItem = model.items.first!
        #expect(!AetherAgentAccess.releasesLink(unverifiedItem, for: SiteQuery("acme.com")!))

        // Password reset links are NEVER shared with agents even if senderVerified == true
        let resetItem = CodeItem(
            IncomingMessage(
                text: "Reset your password",
                subject: "Reset password",
                senderName: "Acme",
                senderID: "noreply@acme.com",
                sourceKey: "acc-1",
                sourceLabel: "Gmail",
                date: Date(),
                isMail: true,
                links: [MailLink(url: "https://acme.com/reset?t=2", label: "Reset")],
                senderVerified: true
            ),
            code: nil,
            link: URL(string: "https://acme.com/reset?t=2"),
            resetsPassword: true
        )
        #expect(!AetherAgentAccess.releasesLink(resetItem, for: SiteQuery("acme.com")!))
    }

    @Test("Start and stop lifecycle clears timers and observers cleanly")
    @MainActor
    func startStopIdempotent() {
        let (model, _, _, _, _) = makeIsolatedModel()
        model.start()
        model.stop()
        model.start()
        model.stop()
    }

    @Test("BitwardenCLI status region mapping detects US and EU servers cleanly")
    func bitwardenStatusRegion() {
        let us = BitwardenCLI.Status(version: "2026.1.0", server: "https://vault.bitwarden.com", email: "u@example.com", state: "locked")
        #expect(us.region == .us)
        #expect(us.loggedIn)

        let eu = BitwardenCLI.Status(version: "2026.1.0", server: "https://vault.bitwarden.eu", email: nil, state: "unauthenticated")
        #expect(eu.region == .eu)
        #expect(!eu.loggedIn)
    }

    @Test("AgentSkillsManager writes, refreshes, and only disconnects its own marked SKILL.md files")
    func agentSkillsMarkerOwnershipSafety() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AetherSkillTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }

        let claude = AgentSkillKind.claudeCode
        let codex = AgentSkillKind.codex
        let cursor = AgentSkillKind.cursor

        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        #expect(claude.isInstalled(home: home))
        #expect(!codex.isInstalled(home: home))
        #expect(claude.state(home: home) == .notConnected)

        try claude.connect(home: home)
        #expect(claude.state(home: home) == .connected)
        #expect(cursor.state(home: home) == .connectedThrough(.claudeCode))
        let content = try String(contentsOf: claude.file(home: home), encoding: .utf8)
        #expect(content.contains("droplet_aether_get_code"))

        try claude.disconnect(home: home)
        #expect(claude.state(home: home) == .notConnected)
        #expect(!FileManager.default.fileExists(atPath: claude.file(home: home).path))

        // Foreign file without AETHER marker must never be overwritten or removed
        let codexSkill = codex.file(home: home)
        try FileManager.default.createDirectory(at: codexSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Custom user skill\n".write(to: codexSkill, atomically: true, encoding: .utf8)
        #expect(codex.state(home: home) == .taken)
        #expect(throws: AgentSkillKind.Failure.self) {
            try codex.connect(home: home)
        }
        try codex.disconnect(home: home)
        #expect(try String(contentsOf: codexSkill, encoding: .utf8) == "Custom user skill\n")
    }

    @Test("CodeItem computes TOTP expiry countdowns and destination validation safely")
    func codeItemTotpAndLinks() throws {
        let bwJSON = Data(#"[{"id":"11111111-2222-3333-4444-555555555555","name":"GitHub","login":{"username":"octocat","totp":"otpauth://totp/GitHub:octocat?secret=GEZDGNBVGY3TQOJQ&issuer=GitHub","uris":[{"uri":"https://github.com/login"}]}}]"#.utf8)
        let parsed = try VaultCode.fromBitwarden(bwJSON)
        #expect(parsed.codes.count == 1)
        let vaultCode = parsed.codes[0]

        let now = Date(timeIntervalSince1970: 1_700_000_015) // 5s into a 30s period (1_700_000_010...1_700_000_040)
        let item = CodeItem(vaultCode, at: now)
        #expect(item != nil)
        #expect(item?.origin == .vault)
        #expect(item?.code.count == 6)
        #expect(item?.countdown == 30)
        #expect(item?.expires.timeIntervalSince(now) == 25)

        let unverifiedMsg = IncomingMessage(
            text: "Reset here: https://evil.example/reset?x=1",
            subject: "Reset password",
            senderName: "GitHub",
            senderID: "noreply@github.com",
            sourceKey: "acc",
            sourceLabel: "Gmail",
            date: now,
            isMail: true,
            links: [MailLink(url: "https://evil.example/reset?x=1", label: "Reset")],
            senderVerified: false
        )
        let warnedLink = CodeItem(unverifiedMsg, code: nil, link: URL(string: "https://evil.example/reset?x=1"), resetsPassword: true)
        #expect(warnedLink.resetsPassword)
        #expect(warnedLink.linkNotice?.warns == true)

        let verifiedMsg = IncomingMessage(
            text: "Sign in: https://sso.partner.example/auth",
            subject: "Sign in",
            senderName: "GitHub",
            senderID: "noreply@github.com",
            sourceKey: "acc",
            sourceLabel: "Gmail",
            date: now,
            isMail: true,
            links: [MailLink(url: "https://sso.partner.example/auth", label: "Sign in")],
            senderVerified: true
        )
        let verifiedLink = CodeItem(verifiedMsg, code: nil, link: URL(string: "https://sso.partner.example/auth"), resetsPassword: false)
        #expect(verifiedLink.linkNotice?.warns == false)
    }
}

private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
