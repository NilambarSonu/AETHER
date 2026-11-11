// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import Foundation
import os

public enum AetherLog {
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: "app.getdroppy.droplet.aether", category: category)
    }
}

/// Decoupled host presentation and permission callbacks provided by `AetherDroplet`.
public struct AetherRuntimeHooks {
    public typealias LinkConfirmation = @MainActor (String, String, String, (title: String, run: @MainActor () -> Void)?) -> Bool

    public var presentBanner: @MainActor (UUID) -> Void
    public var dismissBanner: @MainActor (UUID?) -> Void
    public var presentHUD: @MainActor (CodeItem, Bool) -> Void
    public var playArrivalSound: @MainActor () -> Void
    public var copyToClipboard: @MainActor (String, UUID) -> Void
    public var typeCode: @MainActor (String) -> Void
    public var confirmLink: LinkConfirmation
    public var openURL: @MainActor (URL) -> Void
    public var presentAgentState: @MainActor (AetherAgentAccess.Presentation) -> Void
    public var isUIVisible: @MainActor () -> Bool
    public var screenIsLocked: () -> Bool
    public var appVersion: @MainActor () -> String?

    @MainActor
    public init(
        presentBanner: @escaping @MainActor (UUID) -> Void = { _ in },
        dismissBanner: @escaping @MainActor (UUID?) -> Void = { _ in },
        presentHUD: @escaping @MainActor (CodeItem, Bool) -> Void = { _, _ in },
        playArrivalSound: @escaping @MainActor () -> Void = {},
        copyToClipboard: @escaping @MainActor (String, UUID) -> Void = { _, _ in },
        typeCode: @escaping @MainActor (String) -> Void = { _ in },
        confirmLink: @escaping LinkConfirmation = { _, _, _, _ in false },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        presentAgentState: @escaping @MainActor (AetherAgentAccess.Presentation) -> Void = { _ in },
        isUIVisible: @escaping @MainActor () -> Bool = { false },
        screenIsLocked: @escaping () -> Bool = AetherSystemLock.screenIsLocked,
        appVersion: @escaping @MainActor () -> String? = { nil }
    ) {
        self.presentBanner = presentBanner
        self.dismissBanner = dismissBanner
        self.presentHUD = presentHUD
        self.playArrivalSound = playArrivalSound
        self.copyToClipboard = copyToClipboard
        self.typeCode = typeCode
        self.confirmLink = confirmLink
        self.openURL = openURL
        self.presentAgentState = presentAgentState
        self.isUIVisible = isUIVisible
        self.screenIsLocked = screenIsLocked
        self.appVersion = appVersion
    }
}

public enum AetherSystemLock {
    public static func screenIsLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// Ensures one-shot async continuations resume at most once.
public final class AetherOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    public init() {}

    public func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if !done {
            done = true
            body()
        }
    }
}
