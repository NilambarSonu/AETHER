// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation
import Security

/// Login Keychain storage scoped strictly to the AETHER droplet service namespace.
/// Test suites substitute `.inMemory()` so unit tests never prompt or touch the user's Keychain.
public final class AetherSecretStore: @unchecked Sendable {
    public struct Failure: LocalizedError, Sendable {
        public let status: OSStatus
        public var isTransientLock: Bool {
            AetherSecretStore.isTransientLockStatus(status)
        }
        public var errorDescription: String? {
            if isTransientLock {
                return "Keychain is locked while the Mac starts up. Unlocking automatically…"
            }
            return "Couldn't use your Keychain (\(status)). Try again."
        }
    }

    public enum CredentialState: Equatable, Sendable {
        case present(String)
        case missing
        case locked(OSStatus)
    }

    public static func isTransientLockStatus(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed // -25308: interaction not allowed (locked at login)
            || status == errSecAuthFailed     // -25293: auth failed (login unlock in progress)
            || status == errSecNotAvailable   // -25291: keychain service not available yet
            || status == -128                 // user canceled / prompt not ready
    }

    private enum Backend: @unchecked Sendable {
        case keychain(service: String)
        case memory(NSLock, [String: String])
    }

    public static let defaultService = "app.getdroppy.droplet.aether"
    public static let keychain = AetherSecretStore(service: defaultService)

    private let backend: Backend
    private let memoryBox: MemoryBox?

    private final class MemoryBox: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: String] = [:]
    }

    public init(service: String = defaultService) {
        self.backend = .keychain(service: service)
        self.memoryBox = nil
    }

    private init(memoryBox: MemoryBox) {
        self.backend = .memory(memoryBox.lock, memoryBox.values)
        self.memoryBox = memoryBox
    }

    public static func inMemory() -> AetherSecretStore {
        AetherSecretStore(memoryBox: MemoryBox())
    }

    public func credentialState(_ account: String) -> CredentialState {
        if let memoryBox {
            return memoryBox.lock.withLock {
                if let val = memoryBox.values[account] { return .present(val) }
                return .missing
            }
        }
        guard case .keychain(let service) = backend else { return .missing }
        var q = Self.query(account, service: service)
        q[kSecReturnData as String] = true
        var data: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &data)
        if status == errSecSuccess, let raw = data as? Data, let val = String(data: raw, encoding: .utf8) {
            return .present(val)
        }
        if status == errSecItemNotFound {
            return .missing
        }
        if Self.isTransientLockStatus(status) {
            return .locked(status)
        }
        return .missing
    }

    public func get(_ account: String) -> String? {
        try? read(account)
    }

    public func read(_ account: String) throws -> String? {
        if let memoryBox {
            return memoryBox.lock.withLock { memoryBox.values[account] }
        }
        guard case .keychain(let service) = backend else { return nil }
        var q = Self.query(account, service: service)
        q[kSecReturnData as String] = true
        var data: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &data)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let raw = data as? Data else { throw Failure(status: status) }
        guard let value = String(data: raw, encoding: .utf8) else { throw Failure(status: errSecDecode) }
        return value
    }

    public func set(
        _ value: String,
        for account: String,
        update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate,
        add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd
    ) throws {
        if let memoryBox {
            memoryBox.lock.withLock { memoryBox.values[account] = value }
            return
        }
        guard case .keychain(let service) = backend else { return }
        let data = Data(value.utf8)
        let status = update(
            Self.query(account, service: service) as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure(status: status) }
        var item = Self.query(account, service: service)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = add(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    public func remove(_ account: String) throws {
        if let memoryBox {
            memoryBox.lock.withLock { memoryBox.values[account] = nil }
            return
        }
        guard case .keychain(let service) = backend else { return }
        let status = SecItemDelete(Self.query(account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    private static func query(_ account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
