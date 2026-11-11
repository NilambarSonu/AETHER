// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import AuthenticationServices
import CryptoKit

/// PKCE OAuth flow for Google Gmail (read-only) and Microsoft Graph (`Mail.Read`) via `ASWebAuthenticationSession`.
///
/// Upstream third-party CodeCatch OAuth client identifiers were intentionally removed so AETHER never
/// impersonates or routes users through CodeCatch's GCP / Microsoft Entra projects. Configure AETHER's
/// own Client IDs either at build time (`bundledGoogleClientID` / `bundledMicrosoftClientID`) or directly
/// in **Droppy → Settings → Droplets → AETHER → Account OAuth Configuration** (stored encrypted in Keychain).
public struct MailOAuth: Sendable {
    public enum ProviderKind: String, Sendable {
        case google
        case microsoft

        public var secretStorageKey: String {
            "oauth.client.\(rawValue)"
        }
    }

    public struct CustomClientCredential: Codable, Equatable, Sendable {
        public let clientID: String
        public let redirectURI: String?

        public init(clientID: String, redirectURI: String? = nil) {
            self.clientID = clientID
            self.redirectURI = redirectURI
        }
    }

    public enum Failure: LocalizedError, Sendable {
        case notConfigured(String)
        case denied(String)
        case noMailAccess(String)
        case token(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured(let name):
                "AETHER \(name) OAuth Client ID is not configured yet. Add your AETHER \(name) Client ID below or use an App Password."
            case .denied(let why):
                "Sign-in was not completed (\(why))."
            case .noMailAccess(let name):
                "AETHER needs read-only mail permission to detect verification codes. Sign in with \(name) again and allow mail access."
            case .token(let why):
                "The sign-in session was refused (\(why)). Sign in again."
            }
        }
    }

    public struct Grant: Equatable, Sendable {
        public let refreshToken: String
        public let email: String

        public init(refreshToken: String, email: String) {
            self.refreshToken = refreshToken
            self.email = email
        }
    }

    public let kind: ProviderKind
    public let name: String
    public let clientID: String
    public let redirect: String
    public let scope: String
    public let mailScope: String
    public let authorizeURL: String
    public let tokenURL: String
    public let revokeURL: String?
    public let address: @Sendable (String) async throws -> String

    /// Compiled-in first-party AETHER OAuth Client IDs (Google iOS PKCE + Microsoft Entra public client).
    public static let bundledGoogleClientID = "210406503188-m2pr68n1e17pv3pmqnj1hv946r6lbg22.apps.googleusercontent.com"
    public static let bundledMicrosoftClientID = "3265c45a-7440-4992-aaf7-b176bb294c44"
    public static let microsoftDefaultRedirect = "app.getdroppy.droplet.aether://auth"

    public var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !redirect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Provides the presentation anchor window (captured from Droppy Settings' SwiftUI view)
    /// without enumerating `NSApp.windows`.
    @MainActor public static var anchorProvider: (@MainActor () -> ASPresentationAnchor?) = {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    public static let google = MailOAuth.google(clientID: bundledGoogleClientID)
    public static let microsoft = MailOAuth.microsoft(clientID: bundledMicrosoftClientID)

    /// Builds a Google Gmail OAuth descriptor with automatic iOS-type reverse-DNS redirect URI derivation.
    public static func google(clientID: String, redirectURI: String? = nil) -> MailOAuth {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let derivedRedirect = redirectURI?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? deriveGoogleRedirectURI(for: trimmed)
        return MailOAuth(
            kind: .google,
            name: "Google",
            clientID: trimmed,
            redirect: derivedRedirect,
            scope: "https://www.googleapis.com/auth/gmail.readonly",
            mailScope: "https://www.googleapis.com/auth/gmail.readonly",
            authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenURL: "https://oauth2.googleapis.com/token",
            revokeURL: "https://oauth2.googleapis.com/revoke",
            address: { try await GmailAPI(auth: .issued($0)).emailAddress() }
        )
    }

    /// Builds a Microsoft Graph OAuth descriptor using AETHER's own bundle scheme by default.
    public static func microsoft(clientID: String, redirectURI: String? = nil) -> MailOAuth {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRedirect = redirectURI?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? microsoftDefaultRedirect
        return MailOAuth(
            kind: .microsoft,
            name: "Microsoft",
            clientID: trimmed,
            redirect: resolvedRedirect,
            scope: "offline_access User.Read Mail.Read",
            mailScope: "Mail.Read",
            authorizeURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            revokeURL: nil,
            address: { try await OutlookAPI(auth: .issued($0)).emailAddress() }
        )
    }

    public static func deriveGoogleRedirectURI(for clientID: String) -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "app.getdroppy.droplet.aether:/oauth2redirect" }
        let suffix = ".apps.googleusercontent.com"
        let prefix = trimmed.hasSuffix(suffix) ? String(trimmed.dropLast(suffix.count)) : trimmed
        return "com.googleusercontent.apps.\(prefix):/oauth2redirect"
    }

    public static func resolved(for kind: ProviderKind, in secrets: AetherSecretStore = .keychain) -> MailOAuth {
        let custom = customCredential(for: kind, in: secrets)
        switch kind {
        case .google:
            return google(
                clientID: custom?.clientID ?? bundledGoogleClientID,
                redirectURI: custom?.redirectURI
            )
        case .microsoft:
            return microsoft(
                clientID: custom?.clientID ?? bundledMicrosoftClientID,
                redirectURI: custom?.redirectURI
            )
        }
    }

    public static func customCredential(for kind: ProviderKind, in secrets: AetherSecretStore = .keychain) -> CustomClientCredential? {
        guard let stored = secrets.get(kind.secretStorageKey) else { return nil }
        let data: Data
        if AetherVaultCrypto.isSealed(stored) {
            guard let opened = try? AetherVaultCrypto.open(
                stored,
                domain: .oauthClient,
                recordKey: kind.secretStorageKey,
                using: secrets
            ) else { return nil }
            data = opened
        } else {
            data = Data(stored.utf8)
        }
        guard let cred = try? JSONDecoder().decode(CustomClientCredential.self, from: data),
            !cred.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return cred
    }

    public static func saveCustomCredential(
        clientID: String,
        redirectURI: String? = nil,
        for kind: ProviderKind,
        in secrets: AetherSecretStore = .keychain
    ) throws {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            try clearCustomCredential(for: kind, in: secrets)
            return
        }
        let cleanedRedirect = redirectURI?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let payload = try JSONEncoder().encode(CustomClientCredential(clientID: trimmedID, redirectURI: cleanedRedirect))
        let sealed = try AetherVaultCrypto.seal(
            payload,
            domain: .oauthClient,
            recordKey: kind.secretStorageKey,
            using: secrets
        )
        try secrets.set(sealed, for: kind.secretStorageKey)
    }

    public static func clearCustomCredential(for kind: ProviderKind, in secrets: AetherSecretStore = .keychain) throws {
        try secrets.remove(kind.secretStorageKey)
    }

    @MainActor
    public func signIn(email: String, anchor: ASPresentationAnchor? = nil) async throws -> Grant {
        guard isConfigured else {
            throw Failure.notConfigured(name)
        }
        let verifier = Self.randomString(64)
        let state = Self.randomString(32)
        var url = URLComponents(string: authorizeURL)!
        url.queryItems =
            [
                .init(name: "client_id", value: clientID),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: scope),
                .init(name: "state", value: state),
                .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URL),
                .init(name: "code_challenge_method", value: "S256"),
            ] + (email.isEmpty ? [] : [.init(name: "login_hint", value: email)])
        let callback = try await authorize(url.url!, anchor: anchor)
        guard let code = try authorizationCode(in: callback.absoluteString, state: state) else {
            throw Failure.denied("no sign-in code came back")
        }
        let tokens = try await tokenRequest([
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = tokens["refresh_token"] as? String, let access = tokens["access_token"] as? String else {
            throw Failure.token("no refresh token")
        }
        let granted = ((tokens["scope"] as? String) ?? "").split(separator: " ")
        guard granted.contains(where: { $0 == mailScope || $0.hasSuffix("/" + mailScope) }) else {
            throw Failure.noMailAccess(name)
        }
        return Grant(refreshToken: refresh, email: try await address(access))
    }

    private static var cache: [String: (token: String, expires: Date)] = [:]
    private static let lock = NSLock()

    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config)
    }()

    public func accessToken(tokenKey key: String, secrets: AetherSecretStore = .keychain) async throws -> String {
        guard isConfigured else {
            throw Failure.notConfigured(name)
        }
        if let hit = Self.lock.withLock({ Self.cache[key] }), hit.expires > Date().addingTimeInterval(60) { return hit.token }
        guard let stored = try secrets.read(key) else { throw Failure.token("no refresh token") }
        let refresh: String
        if AetherVaultCrypto.isSealed(stored) {
            refresh = try AetherVaultCrypto.openString(stored, domain: .mailSecret, recordKey: key, using: secrets)
        } else {
            refresh = stored
            if let sealed = try? AetherVaultCrypto.sealString(stored, domain: .mailSecret, recordKey: key, using: secrets) {
                try? secrets.set(sealed, for: key)
            }
        }
        let tokens = try await tokenRequest(["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"])
        guard let token = tokens["access_token"] as? String else { throw Failure.token("no access token") }
        if let next = tokens["refresh_token"] as? String, next != refresh {
            if let sealed = try? AetherVaultCrypto.sealString(next, domain: .mailSecret, recordKey: key, using: secrets) {
                try? secrets.set(sealed, for: key)
            }
        }
        let lifetime = (tokens["expires_in"] as? Double) ?? 3600
        Self.lock.withLock { Self.cache[key] = (token, Date().addingTimeInterval(lifetime)) }
        return token
    }

    public static func forgetAccessToken(tokenKey key: String) {
        lock.withLock { cache[key] = nil }
    }

    /// Wipes all cached short-lived OAuth bearer tokens from volatile memory on sleep, lock, or deactivation.
    public static func clearAllAccessTokens() {
        lock.withLock { cache.removeAll() }
    }

    public func revoke(_ refresh: String) async {
        guard let revokeURL else { return }
        _ = try? await Self.session.data(for: Self.formRequest(revokeURL, ["token": refresh]))
    }

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        let (data, response) = try await Self.session.data(for: Self.formRequest(tokenURL, form))
        let status = (response as? HTTPURLResponse)?.statusCode
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let error = json["error"] as? String, status == 400 || status == 401 { throw Failure.token(error) }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return json
    }

    private static func formRequest(_ url: String, _ form: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        return request
    }

    public func authorizationCode(in callback: String, state: String) throws -> String? {
        guard callback.hasPrefix(redirect + "?"),
            !callback.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
            callback.range(of: "%(?![0-9a-fA-F]{2})", options: .regularExpression) == nil,
            let url = URLComponents(string: callback), url.fragment == nil
        else { return nil }
        let items = (url.queryItems ?? []).filter { ["state", "code", "error"].contains($0.name) }
        guard Set(items.map(\.name)).count == items.count else { return nil }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard !state.isEmpty, values["state"] == state else { return nil }
        if let error = values["error"], !error.isEmpty { throw Failure.denied(error) }
        guard let code = values["code"], !code.isEmpty else { return nil }
        return code
    }

    @MainActor
    private func authorize(_ url: URL, anchor: ASPresentationAnchor?) async throws -> URL {
        let flow = SignInSheet(anchor: anchor ?? Self.anchorProvider() ?? ASPresentationAnchor())
        let scheme = String(redirect.prefix { $0 != ":" })
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let once = AetherOnce()
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { url, error in
                    once.run {
                        if let url {
                            cont.resume(returning: url)
                        } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            cont.resume(throwing: CancellationError())
                        } else {
                            cont.resume(throwing: error ?? Failure.denied("no response"))
                        }
                    }
                }
                session.presentationContextProvider = flow
                flow.session = session
                if !session.start() {
                    once.run { cont.resume(throwing: Failure.denied("the sign-in sheet did not open")) }
                }
            }
        } onCancel: {
            Task { @MainActor in flow.session?.cancel() }
        }
    }

    private static func randomString(_ n: Int) -> String {
        AetherVaultCrypto.randomURLSafeString(length: n)
    }
}

public enum MailAPIAuth: Sendable {
    case saved(MailOAuth.ProviderKind, tokenKey: String, secrets: AetherSecretStore = .keychain)
    case issued(String)

    public func accessToken() async throws -> String {
        switch self {
        case .saved(let kind, let key, let secrets):
            let oauth = MailOAuth.resolved(for: kind, in: secrets)
            return try await oauth.accessToken(tokenKey: key, secrets: secrets)
        case .issued(let token):
            return token
        }
    }

    public func forget() -> Bool {
        guard case .saved(_, let key, _) = self else { return false }
        MailOAuth.forgetAccessToken(tokenKey: key)
        return true
    }

    public func send(_ request: URLRequest, provider: String) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await MailOAuth.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 200: return data
        case 401 where forget(): return try await MailAPIAuth.issued(try await accessToken()).send(request, provider: provider)
        case 401: throw MailOAuth.Failure.token("unauthorized")
        case 403 where message.localizedCaseInsensitiveContains("insufficient") || message.localizedCaseInsensitiveContains("denied"):
            throw MailOAuth.Failure.noMailAccess(provider)
        case 404: throw MailAPIError.gone
        default: throw MailAPIError.http(status, message)
        }
    }
}

private final class SignInSheet: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    var session: ASWebAuthenticationSession?
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

extension Data {
    fileprivate var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
