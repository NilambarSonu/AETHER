// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation
import LocalAuthentication

@MainActor
public final class DeviceAuthentication {
    public static var unlockMethods: String {
        supportsTouchID() ? "Touch ID or your Mac password" : "your Mac password"
    }

    public static func supportsTouchID(context: LAContext = LAContext()) -> Bool {
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            && context.biometryType == .touchID
    }

    private var context: LAContext?
    private let onBeforePrompt: @MainActor () -> Void
    private let onAfterPrompt: @MainActor () -> Void

    public init(
        onBeforePrompt: @escaping @MainActor () -> Void = {},
        onAfterPrompt: @escaping @MainActor () -> Void = {}
    ) {
        self.onBeforePrompt = onBeforePrompt
        self.onAfterPrompt = onAfterPrompt
    }

    public func authenticate(reason: String = "show your verification codes") async throws {
        let context = LAContext()
        self.context = context
        onBeforePrompt()
        defer {
            if self.context === context {
                self.context = nil
                onAfterPrompt()
            }
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
    }

    public func cancel() {
        context?.invalidate()
        context = nil
    }
}
