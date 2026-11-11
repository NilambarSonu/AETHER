// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

enum AetherSettingsRoute: String {
    case general
    case sources
    case privacy
    case agents
    case agentRules
    case agentHistory
    case recovery
    case ignoredSenders
    case notCodes
    case addAccount
    case bitwarden

    static let editAccountPrefix = "editAccount:"
    static let newAccountPrefix = "newAccount:"

    static func editAccount(_ id: UUID) -> String {
        editAccountPrefix + id.uuidString
    }

    static func newAccount(_ preset: String) -> String {
        newAccountPrefix + preset
    }

    static func parseEditAccountID(from pageID: String) -> UUID? {
        guard pageID.hasPrefix(editAccountPrefix) else { return nil }
        return UUID(uuidString: String(pageID.dropFirst(editAccountPrefix.count)))
    }

    static func parseNewAccountPreset(from pageID: String) -> String? {
        guard pageID.hasPrefix(newAccountPrefix) else { return nil }
        return String(pageID.dropFirst(newAccountPrefix.count))
    }
}
