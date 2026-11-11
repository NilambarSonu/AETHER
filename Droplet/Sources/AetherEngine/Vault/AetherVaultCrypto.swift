// Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CryptoKit
import Foundation
import Security

/// Provides local-only authenticated encryption (`AES-256-GCM`), `HKDF-SHA256` domain subkey
/// derivation, AAD tamper binding, keyed HMAC digests, and `SecRandomCopyBytes` CSPRNG randomness.
///
/// The 256-bit master wrapping key lives strictly inside macOS Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (never synced off-device via iCloud Keychain).
public enum AetherVaultCrypto {
    public enum SecretDomain: String, Sendable {
        case vaultCodes = "vault.codes"
        case unlockPolicy = "policy.unlock"
        case agentConfig = "agent.config"
        case agentAuditLog = "agent.audit"
        case mailSecret = "mail.secret"
        case oauthClient = "oauth.client"
        case iconCacheSalt = "icon.salt"
    }

    public enum Failure: LocalizedError, Sendable {
        case randomGenerationFailed(OSStatus)
        case corruptMasterKey
        case malformedEnvelope
        case integrityCheckFailed

        public var errorDescription: String? {
            switch self {
            case .randomGenerationFailed(let status):
                "System random number generator failed (\(status))."
            case .corruptMasterKey:
                "AETHER's local Keychain encryption key could not be decoded."
            case .malformedEnvelope:
                "Stored encrypted record has an invalid format."
            case .integrityCheckFailed:
                "Stored record failed cryptographic integrity verification and was rejected."
            }
        }
    }

    private static let envelopePrefix = "aether.v2."
    private static let masterKeyAccount = "aether.device.master.v2"
    private static let kdfSalt = Data("app.getdroppy.droplet.aether.kdf.v2".utf8)
    private static let masterKeyCacheLock = NSLock()
    private static var masterKeyCache: [ObjectIdentifier: SymmetricKey] = [:]

    /// Returns `true` when `value` is wrapped in AETHER's `aether.v2.` AEAD envelope.
    public static func isSealed(_ value: String) -> Bool {
        value.hasPrefix(envelopePrefix)
    }

    /// Generates `count` cryptographically secure random bytes using macOS `SecRandomCopyBytes`.
    public static func randomBytes(count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw Failure.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    /// Generates an unbiased CSPRNG string from RFC 3986 unreserved characters using `SecRandomCopyBytes`.
    public static func randomURLSafeString(length: Int) -> String {
        guard length > 0 else { return "" }
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        let upperBound = UInt8(256 - (256 % charset.count)) // 264 -> 198 to avoid modulo bias
        var output = [UInt8]()
        output.reserveCapacity(length)
        var scratch = [UInt8](repeating: 0, count: max(length * 2, 64))
        while output.count < length {
            let status = SecRandomCopyBytes(kSecRandomDefault, scratch.count, &scratch)
            guard status == errSecSuccess else {
                // CSPRNG should never fail on macOS; fall back safely if OS entropy service errors.
                for _ in output.count..<length {
                    output.append(charset[Int.random(in: 0..<charset.count)])
                }
                break
            }
            for byte in scratch where byte < upperBound {
                output.append(charset[Int(byte) % charset.count])
                if output.count == length { break }
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Encrypts `plaintext` with AES-256-GCM using an HKDF-SHA256 subkey and AAD bound to `domain` + `recordKey`.
    public static func seal(
        _ plaintext: Data,
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> String {
        let subkey = try derivedSubkey(domain: domain, recordKey: recordKey, using: secrets)
        let aad = associatedData(domain: domain, recordKey: recordKey)
        let sealed = try AES.GCM.seal(plaintext, using: subkey, authenticating: aad)
        guard let combined = sealed.combined else {
            throw Failure.malformedEnvelope
        }
        return envelopePrefix + combined.base64EncodedString()
    }

    /// Convenience UTF-8 string sealing wrapper.
    public static func sealString(
        _ plaintext: String,
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> String {
        try seal(Data(plaintext.utf8), domain: domain, recordKey: recordKey, using: secrets)
    }

    /// Decrypts and authenticates an `aether.v2.` envelope, failing closed on any modification or AAD mismatch.
    public static func open(
        _ envelope: String,
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> Data {
        guard envelope.hasPrefix(envelopePrefix) else {
            throw Failure.malformedEnvelope
        }
        let encoded = String(envelope.dropFirst(envelopePrefix.count))
        guard let combined = Data(base64Encoded: encoded) else {
            throw Failure.malformedEnvelope
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        let subkey = try derivedSubkey(domain: domain, recordKey: recordKey, using: secrets)
        let aad = associatedData(domain: domain, recordKey: recordKey)
        do {
            return try AES.GCM.open(box, using: subkey, authenticating: aad)
        } catch {
            throw Failure.integrityCheckFailed
        }
    }

    /// Convenience UTF-8 string decryption wrapper.
    public static func openString(
        _ envelope: String,
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> String {
        let data = try open(envelope, domain: domain, recordKey: recordKey, using: secrets)
        guard let text = String(data: data, encoding: .utf8) else {
            throw Failure.malformedEnvelope
        }
        return text
    }

    /// Derives a keyed HMAC-SHA256 hex digest (first 32 hex chars / 128 bits) for opaque cache naming.
    public static func hmacHex(
        _ input: String,
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> String {
        let subkey = try derivedSubkey(domain: domain, recordKey: recordKey, using: secrets)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(input.lowercased().utf8), using: subkey)
        return mac.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Clears the in-process cached master key reference.
    public static func clearCachedMasterKey(for secrets: AetherSecretStore? = nil) {
        masterKeyCacheLock.withLock {
            if let secrets {
                masterKeyCache.removeValue(forKey: ObjectIdentifier(secrets))
            } else {
                masterKeyCache.removeAll()
            }
        }
    }

    private static func derivedSubkey(
        domain: SecretDomain,
        recordKey: String,
        using secrets: AetherSecretStore
    ) throws -> SymmetricKey {
        let master = try masterKey(in: secrets)
        let info = Data("aether.kdf|\(domain.rawValue)|\(recordKey)".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            salt: kdfSalt,
            info: info,
            outputByteCount: 32
        )
    }

    private static func associatedData(domain: SecretDomain, recordKey: String) -> Data {
        Data("\(AetherSecretStore.defaultService)|\(domain.rawValue)|\(recordKey)".utf8)
    }

    private static func masterKey(in secrets: AetherSecretStore) throws -> SymmetricKey {
        let storeID = ObjectIdentifier(secrets)
        if let cached = masterKeyCacheLock.withLock({ masterKeyCache[storeID] }) {
            return cached
        }
        if let encoded = try secrets.read(masterKeyAccount) {
            guard let raw = Data(base64Encoded: encoded), raw.count == 32 else {
                throw Failure.corruptMasterKey
            }
            let key = SymmetricKey(data: raw)
            masterKeyCacheLock.withLock { masterKeyCache[storeID] = key }
            return key
        }
        let generated = try randomBytes(count: 32)
        try secrets.set(generated.base64EncodedString(), for: masterKeyAccount)
        let key = SymmetricKey(data: generated)
        masterKeyCacheLock.withLock { masterKeyCache[storeID] = key }
        return key
    }
}

