// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

@MainActor
public enum VaultStorage {
    private static let key = "bitwarden.codes"

    public static func unlockPolicy(
        secrets: AetherSecretStore = .keychain,
        authentication: DeviceAuthentication? = nil
    ) -> UnlockPolicy {
        let authentication = authentication ?? DeviceAuthentication()
        return UnlockPolicy(
            load: { try secrets.read("unlock-with-mac") == "true" },
            save: { try secrets.set($0 ? "true" : "false", for: "unlock-with-mac") },
            authenticate: { try await authentication.authenticate() },
            cancel: { authentication.cancel() }
        )
    }

    public static func session(
        defaults: UserDefaults,
        secrets: AetherSecretStore = .keychain,
        unlockPolicy: UnlockPolicy? = nil,
        didLock: @escaping () -> Void = {}
    ) -> VaultSession {
        let policy = unlockPolicy ?? self.unlockPolicy(secrets: secrets)
        let session = VaultSession(
            authenticate: { try await policy.authenticate() },
            read: {
                guard defaults.bool(forKey: AetherPrefs.bitwarden) else { return [] }
                guard let json = try secrets.read(key) else { return [] }
                return try JSONDecoder().decode([VaultCode].self, from: Data(json.utf8))
            },
            write: { codes in
                let data = try JSONEncoder().encode(codes)
                try secrets.set(String(decoding: data, as: UTF8.self), for: key)
                defaults.set(Date(), forKey: AetherPrefs.vaultImportedAt)
            },
            remove: {
                try secrets.remove(key)
                defaults.removeObject(forKey: AetherPrefs.vaultImportedAt)
            }
        )
        session.cancelAuthentication = { policy.cancelAuthentication() }
        session.didLock = didLock
        return session
    }
}
