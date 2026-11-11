// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public extension AetherAppModel {
    enum AccountSaveError: LocalizedError, Sendable {
        case duplicate
        public var errorDescription: String? { "This mail account is already saved. Edit the existing account instead." }
    }

    struct AccountKeychain: Sendable {
        public var read: @Sendable (String) -> String?
        public var write: @Sendable (String, String) throws -> Void
        public var remove: @Sendable (String) throws -> Void
        public var revoke: @Sendable (MailOAuth, String) -> Void

        public init(
            read: @escaping @Sendable (String) -> String?,
            write: @escaping @Sendable (String, String) throws -> Void,
            remove: @escaping @Sendable (String) throws -> Void,
            revoke: @escaping @Sendable (MailOAuth, String) -> Void
        ) {
            self.read = read
            self.write = write
            self.remove = remove
            self.revoke = revoke
        }

        public static func backing(_ store: AetherSecretStore) -> AccountKeychain {
            AccountKeychain(
                read: { store.get($0) },
                write: { try store.set($0, for: $1) },
                remove: { try store.remove($0) },
                revoke: { provider, token in Task { await provider.revoke(token) } }
            )
        }
    }

    func save(_ account: MailAccount) {
        let unchanged = accounts.contains(account)
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
        if unchanged { monitor.check(account.id.uuidString) }
    }

    func saveAccount(
        _ account: MailAccount,
        password: String,
        refreshToken: String?,
        keychain: AccountKeychain? = nil
    ) throws {
        let kc = keychain ?? .backing(secrets)
        guard !accounts.contains(where: { $0.id != account.id && $0.secretKey == account.secretKey }) else {
            throw AccountSaveError.duplicate
        }
        var updated = account
        if let refreshToken {
            try kc.write(refreshToken, updated.refreshTokenKey)
            updated.signedIn = true
        } else if !updated.usesSignIn {
            if !password.isEmpty { try kc.write(password, updated.secretKey) }
            try forgetSignIn(updated, kc)
        }
        save(updated)
    }

    func remove(_ account: MailAccount, keychain: AccountKeychain? = nil) throws {
        let kc = keychain ?? .backing(secrets)
        guard let saved = accounts.first(where: { $0.id == account.id }) else { return }
        if !accounts.contains(where: { $0.id != saved.id && $0.secretKey == saved.secretKey }) {
            try kc.remove(saved.secretKey)
            try forgetSignIn(saved, kc)
        }
        accounts.removeAll { $0.id == saved.id }
    }

    func removeUnusedCredentials(for account: MailAccount, keychain: AccountKeychain? = nil) throws {
        let kc = keychain ?? .backing(secrets)
        guard !accounts.contains(where: { $0.secretKey == account.secretKey }) else { return }
        try kc.remove(account.secretKey)
        try forgetSignIn(account, kc)
    }

    private func forgetSignIn(_ account: MailAccount, _ keychain: AccountKeychain) throws {
        let token = keychain.read(account.refreshTokenKey)
        try keychain.remove(account.refreshTokenKey)
        MailOAuth.forgetAccessToken(tokenKey: account.refreshTokenKey)
        if let token, let provider = account.provider { keychain.revoke(provider, token) }
    }
}
