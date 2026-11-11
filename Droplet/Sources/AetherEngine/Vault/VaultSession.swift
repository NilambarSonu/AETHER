// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Combine
import Foundation

@MainActor
public final class VaultSession: ObservableObject {
    public enum Failure: LocalizedError, Sendable {
        case locked, busy
        public var errorDescription: String? {
            self == .locked ? "Unlock AETHER first." : "Unlock is already in progress."
        }
    }

    @Published public private(set) var codes: [VaultCode] = []
    @Published public private(set) var isUnlocked = false
    @Published public private(set) var isBusy = false
    public var didLock: () -> Void = {}
    public var cancelAuthentication: () -> Void = {}
    private let authenticate: () async throws -> Void
    private let read: () throws -> [VaultCode]
    private let write: ([VaultCode]) throws -> Void
    private let erase: () throws -> Void
    public private(set) var generation = 0

    public init(
        authenticate: @escaping () async throws -> Void,
        read: @escaping () throws -> [VaultCode],
        write: @escaping ([VaultCode]) throws -> Void,
        remove: @escaping () throws -> Void
    ) {
        self.authenticate = authenticate
        self.read = read
        self.write = write
        self.erase = remove
    }

    public func unlock() async throws {
        if isUnlocked { return }
        guard !isBusy else { throw Failure.busy }
        isBusy = true
        let request = generation
        defer { if request == generation { isBusy = false } }
        try await authenticate()
        guard request == generation, !Task.isCancelled else { throw CancellationError() }
        let loaded = try read()
        codes = loaded
        isUnlocked = true
    }

    public func lock() {
        generation += 1
        cancelAuthentication()
        didLock()
        codes = []
        isUnlocked = false
        isBusy = false
    }

    public func replace(_ codes: [VaultCode]) throws {
        guard isUnlocked else { throw Failure.locked }
        try write(codes)
        self.codes = codes
    }

    public func remove() throws {
        guard isUnlocked else { throw Failure.locked }
        try erase()
        lock()
    }
}
