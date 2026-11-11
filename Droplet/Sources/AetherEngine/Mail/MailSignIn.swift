// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Combine
import Foundation

@MainActor
public final class MailSignIn: ObservableObject {
    @Published public private(set) var isBusy = false
    @Published private var credential: (key: String, token: String)?
    private var generation = 0
    private var task: Task<MailOAuth.Grant, Error>?
    private let authenticate: (MailAccount) async throws -> MailOAuth.Grant

    public init(
        secrets: AetherSecretStore = .keychain,
        authenticate: ((MailAccount) async throws -> MailOAuth.Grant)? = nil
    ) {
        self.authenticate = authenticate ?? { account in
            guard let provider = account.resolvedProvider(in: secrets) else {
                throw MailOAuth.Failure.denied("this server has no OAuth sign-in")
            }
            return try await provider.signIn(email: account.user)
        }
    }

    public func token(for account: MailAccount) -> String? {
        credential?.key == account.secretKey ? credential?.token : nil
    }

    @discardableResult
    public func signIn(for account: MailAccount) async throws -> String {
        cancel()
        let request = generation
        isBusy = true
        let authenticate = self.authenticate
        let task = Task { try await authenticate(account) }
        self.task = task
        defer {
            if request == generation {
                isBusy = false
                self.task = nil
            }
        }
        let result = await task.result
        guard request == generation, !Task.isCancelled else { throw CancellationError() }
        let grant = try result.get()
        var signedIn = account
        signedIn.user = grant.email
        credential = (signedIn.secretKey, grant.refreshToken)
        return grant.email
    }

    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        credential = nil
        isBusy = false
    }
}
