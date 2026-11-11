// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import AuthenticationServices
import CryptoKit

/// PKCE OAuth flow for Google Gmail (read-only) and Microsoft Graph (Mail.Read) via `ASWebAuthenticationSession`.
public struct MailOAuth: Sendable {
    public enum Failure: LocalizedError, Sendable {
        case denied(String)
        case noMailAccess(String)
        case token(String)
        public var errorDescription: String? {
            switch self {
            case .denied(let why): "Sign-in was not completed (\(why))."
            case .noMailAccess(let name): "AETHER needs to read your mail to find codes. Sign in with \(name) again and allow it."
            case .token(let why): "The sign-in was refused (\(why)). Sign in again."
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

    public let name: String
    public let clientID: String
    public let redirect: String
    public let scope: String
    public let mailScope: String
    public let authorizeURL: String
    public let tokenURL: String
    public let revokeURL: String?
    public let address: @Sendable (String) async throws -> String

    /// Provides the presentation anchor window (captured from Droppy Settings' SwiftUI view)
    /// without enumerating `NSApp.windows`.
    @MainActor public static var anchorProvider: (@MainActor () -> ASPresentationAnchor?) = {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    public static let google = MailOAuth(
        name: "Google",
        clientID: "374242175460-a4bpd97sclaa5k4bpc598ei64n67om6l.apps.googleusercontent.com",
        redirect: "com.googleusercontent.apps.374242175460-a4bpd97sclaa5k4bpc598ei64n67om6l:/oauth2redirect",
        scope: "https://www.googleapis.com/auth/gmail.readonly",
        mailScope: "https://www.googleapis.com/auth/gmail.readonly",
        authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenURL: "https://oauth2.googleapis.com/token",
        revokeURL: "https://oauth2.googleapis.com/revoke",
        address: { try await GmailAPI(auth: .issued($0)).emailAddress() }
    )

    public static let microsoft = MailOAuth(
        name: "Microsoft",
        clientID: "946bd1c2-64b4-443f-a51b-96f41bed07d1",
        redirect: "msauth.com.uros.codecatch://auth",
        scope: "offline_access User.Read Mail.Read",
        mailScope: "Mail.Read",
        authorizeURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        revokeURL: nil,
        address: { try await OutlookAPI(auth: .issued($0)).emailAddress() }
    )

    @MainActor
    public func signIn(email: String, anchor: ASPresentationAnchor? = nil) async throws -> Grant {
        let verifier = Self.randomString(64)
        let state = Self.randomString(24)
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
        if let hit = Self.lock.withLock({ Self.cache[key] }), hit.expires > Date().addingTimeInterval(60) { return hit.token }
        guard let refresh = try secrets.read(key) else { throw Failure.token("no refresh token") }
        let tokens = try await tokenRequest(["refresh_token": refresh, "client_id": clientID, "grant_type": "refresh_token"])
        guard let token = tokens["access_token"] as? String else { throw Failure.token("no access token") }
        if let next = tokens["refresh_token"] as? String, next != refresh { try? secrets.set(next, for: key) }
        let lifetime = (tokens["expires_in"] as? Double) ?? 3600
        Self.lock.withLock { Self.cache[key] = (token, Date().addingTimeInterval(lifetime)) }
        return token
    }

    public static func forgetAccessToken(tokenKey key: String) {
        lock.withLock { cache[key] = nil }
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
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}

public enum MailAPIAuth: Sendable {
    case saved(MailOAuth, tokenKey: String, secrets: AetherSecretStore = .keychain)
    case issued(String)

    public func accessToken() async throws -> String {
        switch self {
        case .saved(let oauth, let key, let secrets): try await oauth.accessToken(tokenKey: key, secrets: secrets)
        case .issued(let token): token
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
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
