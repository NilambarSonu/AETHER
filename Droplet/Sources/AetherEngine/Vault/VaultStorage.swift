// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

@MainActor
public enum VaultStorage {
    private static let key = "bitwarden.codes"
    private static let unlockPolicyKey = "unlock-with-mac"

    private struct PolicyRecord: Codable {
        let unlockWithMac: Bool
    }

    public static func unlockPolicy(
        secrets: AetherSecretStore = .keychain,
        authentication: DeviceAuthentication? = nil
    ) -> UnlockPolicy {
        let authentication = authentication ?? DeviceAuthentication()
        return UnlockPolicy(
            load: {
                guard let stored = try secrets.read(unlockPolicyKey) else { return false }
                if AetherVaultCrypto.isSealed(stored) {
                    let data = try AetherVaultCrypto.open(
                        stored,
                        domain: .unlockPolicy,
                        recordKey: unlockPolicyKey,
                        using: secrets
                    )
                    return try JSONDecoder().decode(PolicyRecord.self, from: data).unlockWithMac
                }
                // Legacy v1 plaintext boolean value: fail closed unless exact "true", and upgrade to AEAD immediately.
                let enabled = (stored == "true")
                let encoded = try JSONEncoder().encode(PolicyRecord(unlockWithMac: enabled))
                if let sealed = try? AetherVaultCrypto.seal(
                    encoded,
                    domain: .unlockPolicy,
                    recordKey: unlockPolicyKey,
                    using: secrets
                ) {
                    try? secrets.set(sealed, for: unlockPolicyKey)
                }
                return enabled
            },
            save: { enabled in
                let encoded = try JSONEncoder().encode(PolicyRecord(unlockWithMac: enabled))
                let sealed = try AetherVaultCrypto.seal(
                    encoded,
                    domain: .unlockPolicy,
                    recordKey: unlockPolicyKey,
                    using: secrets
                )
                try secrets.set(sealed, for: unlockPolicyKey)
            },
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
                guard let stored = try secrets.read(key) else { return [] }
                if AetherVaultCrypto.isSealed(stored) {
                    let data = try AetherVaultCrypto.open(
                        stored,
                        domain: .vaultCodes,
                        recordKey: key,
                        using: secrets
                    )
                    return try JSONDecoder().decode([VaultCode].self, from: data)
                }
                // Upgrade legacy unencrypted v1 vault JSON in place when decoded cleanly.
                let legacyData = Data(stored.utf8)
                let decoded = try JSONDecoder().decode([VaultCode].self, from: legacyData)
                if let sealed = try? AetherVaultCrypto.seal(
                    legacyData,
                    domain: .vaultCodes,
                    recordKey: key,
                    using: secrets
                ) {
                    try? secrets.set(sealed, for: key)
                }
                return decoded
            },
            write: { codes in
                let data = try JSONEncoder().encode(codes)
                let sealed = try AetherVaultCrypto.seal(
                    data,
                    domain: .vaultCodes,
                    recordKey: key,
                    using: secrets
                )
                try secrets.set(sealed, for: key)
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
