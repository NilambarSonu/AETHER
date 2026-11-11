// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

@MainActor
public final class UnlockPolicy {
    public private(set) var enabled = false
    private let load: () throws -> Bool
    private let save: (Bool) throws -> Void
    private let authenticateOwner: () async throws -> Void
    private let cancel: () -> Void
    private var generation = 0

    public init(
        load: @escaping () throws -> Bool,
        save: @escaping (Bool) throws -> Void,
        authenticate: @escaping () async throws -> Void,
        cancel: @escaping () -> Void = {}
    ) {
        self.load = load
        self.save = save
        self.authenticateOwner = authenticate
        self.cancel = cancel
    }

    public func restore() { enabled = (try? load()) ?? false }

    public func setEnabled(_ enabled: Bool) async throws {
        generation += 1
        let request = generation
        if !enabled {
            self.enabled = false
            cancel()
            try save(false)
            return
        }
        try await authenticateOwner()
        guard request == generation, !Task.isCancelled else { throw CancellationError() }
        try save(true)
        self.enabled = true
    }

    public func authenticate() async throws {
        if !enabled { try await authenticateOwner() }
    }

    public func cancelAuthentication() {
        generation += 1
        cancel()
    }
}
