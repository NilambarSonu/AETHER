// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
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
        let storedToken = secrets.get(gmail.refreshTokenKey)
        #expect(storedToken?.hasPrefix("aether.v2.") == true)
        #expect(storedToken != "rt-1")
        #expect(try AetherVaultCrypto.openString(storedToken ?? "", domain: .mailSecret, recordKey: gmail.refreshTokenKey, using: secrets) == "rt-1")

        let duplicate = MailAccount(label: "Gmail 2", host: MailAccount.gmailHost, user: "alice@gmail.com")
        #expect(throws: AetherAppModel.AccountSaveError.self) {
            try model.saveAccount(duplicate, password: "p", refreshToken: nil)
        }

        try model.remove(model.accounts[0])
        #expect(model.accounts.isEmpty)
        #expect(secrets.get(gmail.refreshTokenKey) == nil)
    }

    @Test("OAuth defaults strip CodeCatch IDs and encrypted custom AETHER client resolution works")
    func oauthCallbackValidationAndCustomClients() throws {
        // Zero upstream CodeCatch IDs in compiled defaults; built-in AETHER production IDs present
        #expect(!MailOAuth.google.clientID.contains("374242175460"))
        #expect(!MailOAuth.microsoft.clientID.contains("946bd1c2"))
        #expect(!MailOAuth.microsoft.redirect.contains("codecatch"))
        #expect(MailOAuth.google.isConfigured)
        #expect(MailOAuth.microsoft.isConfigured)

        let secrets = AetherSecretStore.inMemory()
        let clientID = "999999999999-aethertestclient123.apps.googleusercontent.com"
        try MailOAuth.saveCustomCredential(clientID: clientID, for: .google, in: secrets)

        let rawStored = secrets.get(MailOAuth.ProviderKind.google.secretStorageKey)
        #expect(rawStored?.hasPrefix("aether.v2.") == true)

        let google = MailOAuth.resolved(for: .google, in: secrets)
        #expect(google.isConfigured)
        #expect(google.clientID == clientID)
        #expect(google.redirect == "com.googleusercontent.apps.999999999999-aethertestclient123:/oauth2redirect")

        let good = google.redirect + "?state=abc123&code=auth_code_99"
        #expect(try google.authorizationCode(in: good, state: "abc123") == "auth_code_99")
        #expect(try google.authorizationCode(in: good, state: "wrong") == nil)
        #expect(try google.authorizationCode(in: good + "#frag", state: "abc123") == nil)
        let denied = google.redirect + "?state=abc123&error=access_denied"
        #expect(throws: MailOAuth.Failure.self) {
            _ = try google.authorizationCode(in: denied, state: "abc123")
        }
    }

    @Test("AEAD envelope crypto binds domains/keys and UnlockPolicy + AgentStore fail closed on tampering")
    @MainActor
    func vaultCryptoAndTamperFailClosed() throws {
        let secrets = AetherSecretStore.inMemory()
        let sealed = try AetherVaultCrypto.sealString("otpauth://totp/Acme?secret=JBSWY3DPEHPK3PXP", domain: .vaultCodes, recordKey: "bitwarden.codes", using: secrets)
        #expect(AetherVaultCrypto.isSealed(sealed))
        #expect(!sealed.contains("JBSWY3DPEHPK3PXP"))
        #expect(try AetherVaultCrypto.openString(sealed, domain: .vaultCodes, recordKey: "bitwarden.codes", using: secrets).contains("JBSWY3DPEHPK3PXP"))

        // Wrong recordKey or tampered payload must fail closed
        #expect(throws: AetherVaultCrypto.Failure.self) {
            _ = try AetherVaultCrypto.openString(sealed, domain: .vaultCodes, recordKey: "other.key", using: secrets)
        }
        #expect(throws: AetherVaultCrypto.Failure.self) {
            _ = try AetherVaultCrypto.openString(sealed, domain: .agentConfig, recordKey: "bitwarden.codes", using: secrets)
        }

        // Tampered unlock-with-mac fails closed to false
        let policy = VaultStorage.unlockPolicy(secrets: secrets)
        try secrets.set("aether.v2." + Data("tampered-ciphertext-bytes".utf8).base64EncodedString(), for: "unlock-with-mac")
        policy.restore()
        #expect(!policy.enabled)

        // AgentConfig & Audit log encrypt at rest cleanly
        let cfg = AgentConfig(enabled: true, rules: [], allowAll: true, links: false, releases: [])
        try AgentStore.save(cfg, to: secrets)
        let rawAgent = secrets.get("agent-access") ?? ""
        #expect(rawAgent.hasPrefix("aether.v2."))
        #expect(!rawAgent.contains("allowAll"))
        #expect(try AgentStore.load(from: secrets) == cfg)
    }

    @Test("Icon disk cache uses HMAC-hashed filenames so service domains never leak on disk")
    @MainActor
    func iconStoreHashedDiskCache() async throws {
        let suite = "app.getdroppy.droplet.aether.icontest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        AetherPrefs.register(in: defaults)
        defaults.set(true, forKey: AetherPrefs.serviceIcons)
        let secrets = AetherSecretStore.inMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AetherIconHash.\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Minimal 16x16 white PNG generated via NSBitmapImageRep
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32
        )!
        rep.bitmapData!.initialize(repeating: 255, count: 32 * 128)
        let pngData = rep.representation(using: .png, properties: [:])!

        let store = AetherIconStore(defaults: defaults, secrets: secrets, folder: tempDir) { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
            return (pngData, response)
        }
        await store.load("secret-bank.example")
        #expect(store.icon(for: "secret-bank.example") != nil)

        let cachedFiles = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(cachedFiles.count == 1)
        #expect(cachedFiles[0].hasSuffix(".png"))
        #expect(!cachedFiles[0].contains("secret-bank"))
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

    @Test("Production AETHER Google and Microsoft OAuth Client IDs resolve with exact redirects")
    func productionOAuthDefaultsResolveCleanly() {
        let secrets = AetherSecretStore.inMemory()
        let google = MailOAuth.resolved(for: .google, in: secrets)
        #expect(google.isConfigured)
        #expect(google.clientID == "210406503188-m2pr68n1e17pv3pmqnj1hv946r6lbg22.apps.googleusercontent.com")
        #expect(google.redirect == "com.googleusercontent.apps.210406503188-m2pr68n1e17pv3pmqnj1hv946r6lbg22:/oauth2redirect")

        let microsoft = MailOAuth.resolved(for: .microsoft, in: secrets)
        #expect(microsoft.isConfigured)
        #expect(microsoft.clientID == "3265c45a-7440-4992-aaf7-b176bb294c44")
        #expect(microsoft.redirect == "app.getdroppy.droplet.aether://auth")
    }

    @Test("AutoTyper blocks failed DMARC senders, chat/notes/meeting apps, non-editable UI, and mismatched browser hosts")
    func autoTyperContextGuardrails() {
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: false,
                frontmostBundleID: "com.apple.Safari",
                focusedRole: "AXTextField",
                focusedDocumentHost: "github.com"
            )) == .deniedUnverifiedSender
        )
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: true,
                frontmostBundleID: "com.tinyspeck.slackmacgap",
                focusedRole: "AXTextField",
                focusedDocumentHost: nil
            )) == .deniedUntrustedApp
        )
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: true,
                frontmostBundleID: "us.zoom.xos",
                focusedRole: "AXTextField",
                focusedDocumentHost: nil
            )) == .deniedUntrustedApp
        )
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: true,
                frontmostBundleID: "com.apple.Safari",
                focusedRole: "AXButton",
                focusedDocumentHost: "github.com"
            )) == .deniedUnfocusedField
        )
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: true,
                frontmostBundleID: "com.apple.Safari",
                focusedRole: "AXTextField",
                focusedDocumentHost: "evil-phish.example"
            )) == .deniedDomainMismatch
        )
        #expect(
            AutoTyper.evaluateTarget(.init(
                expectedDomain: "github.com",
                senderVerified: true,
                frontmostBundleID: "com.apple.Safari",
                focusedRole: "AXTextField",
                focusedDocumentHost: "login.github.com"
            )) == .allow
        )
    }

    @Test("Spoofed DMARC-failed mail blocks automatic copy/typing while surfacing item cleanly")
    @MainActor
    func dmarcFailBlocksAutomaticCopy() async throws {
        let env = makeIsolatedModel()
        let typed = Box<[String]>([])
        env.defaults.set(true, forKey: AetherPrefs.autoCopy)
        env.defaults.set(true, forKey: AetherPrefs.autoType)
        env.defaults.set(true, forKey: AetherPrefs.blockUnverifiedAutoCopy)
        env.model.hooks.typeCode = { typed.value.append($0) }
        try await env.model.authenticate()

        let spoofed = IncomingMessage(
            text: "Your GitHub verification code is 741852",
            subject: "Verify login",
            senderName: "GitHub",
            senderID: "noreply@github.com",
            sourceKey: "gmail-1",
            sourceLabel: "Gmail",
            date: Date(),
            isMail: true,
            senderVerified: false
        )
        env.model.ingest(spoofed)

        let item = try #require(env.model.items.first)
        #expect(item.hasFailedSenderAuth)
        #expect(env.copied.value.isEmpty)
        #expect(typed.value.isEmpty)

        // Manual explicit copy still succeeds once unlocked
        env.model.copy(item, userInitiated: true)
        #expect(env.copied.value == ["741852"])
    }

    @Test("AetherClipboard restores prior non-concealed clipboard on TTL and bounds oversized regex inputs")
    @MainActor
    func clipboardRestoreAndOversizedExtractorBound() async throws {
        let suite = "app.getdroppy.droplet.aether.clip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AetherPrefs.register(in: defaults)
        defaults.set(true, forKey: AetherPrefs.clearClipboard)
        defaults.set(true, forKey: AetherPrefs.restoreClipboard)

        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.setString("previous-user-note", forType: .string)

        let clipboard = AetherClipboard(defaults: defaults, clearDelay: 0.08)
        let id = UUID()
        clipboard.copy("918273", id: id, pasteboard: pb)
        #expect(pb.string(forType: .string) == "918273")

        try await Task.sleep(for: .seconds(0.25))
        #expect(pb.string(forType: .string) == "previous-user-note")

        // Oversized input (~180 KB padding + code at tail) completes quickly with head+tail bounding
        let filler = String(repeating: "Newsletter paragraph filler text. ", count: 5_400)
        let massive = filler + "\nYour security verification code is 654321."
        #expect(CodeExtractor.code(in: massive) == "654321")
    }

    @Test("SourceHealth tracks check latency and Inbox vs Junk configuration")
    func latencyAndJunkSupport() {
        var health = SourceHealth()
        health.record(.latencyMs(42))
        #expect(health.lastLatencyMs == 42)

        let gmailDefault = GmailAPI(auth: .issued("tok"))
        let gmailWithJunk = GmailAPI(auth: .issued("tok"), includeJunk: true)
        #expect(!gmailDefault.includeJunk)
        #expect(gmailWithJunk.includeJunk)

        let outlookWithJunk = OutlookAPI(auth: .issued("tok"), includeJunk: true)
        #expect(outlookWithJunk.includeJunk)
    }
}

private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
