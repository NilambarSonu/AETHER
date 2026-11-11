// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public enum AetherPrefs {
    public static let showBanner = "showHUD"
    public static let showNotchHUD = "showNotchHUD"
    public static let autoCopy = "autoCopy"
    public static let autoType = "autoType"
    public static let clearClipboard = "clearClipboard"
    public static let clipboardTTL = "clipboardTTL"
    public static let restoreClipboard = "restoreClipboard"
    public static let includeJunkMail = "includeJunkMail"
    public static let blockUnverifiedAutoCopy = "blockUnverifiedAutoCopy"
    public static let codeInMenuBar = "codeInMenuBar"
    public static let sound = "sound"
    public static let messages = "messagesEnabled"
    public static let appleMail = "appleMailEnabled"
    public static let historyDays = "historyDays"
    public static let serviceIcons = "serviceIcons"
    public static let hideFromCapture = "hideFromCapture"
    public static let blurCodes = "blurCodes"
    public static let showPreviews = "showPreviews"
    public static let clearOnLock = "clearOnLock"
    public static let clearedAt = "historyClearedAt"
    public static let ignoredSenders = "ignoredSenders"
    public static let dismissed = "dismissedMessages"
    public static let vaultImportedAt = "vaultImportedAt"
    public static let notCodes = "notCodes"
    public static let hotkeys = "hotkeys"
    public static let copyLatestShortcut = "shortcutCopyLatest"
    public static let searchShortcut = "shortcutSearch"
    /// Never stored in UserDefaults: `AetherAppModel.isOn` reads this from Keychain.
    public static let unlockWithMac = "unlockWithMac"

    public static let receivedCodes = "receivedCodes"
    public static let signInLinks = "signInLinks"
    public static let resetLinks = "passwordResetLinks"
    public static let bitwarden = "bitwardenEnabled"

    /// What messages are read for: with all three off, no source is watched.
    public static let receiving = [receivedCodes, signInLinks, resetLinks]

    public static func isReceiving(in defaults: UserDefaults) -> Bool {
        receiving.contains(where: defaults.bool(forKey:))
    }

    public static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [
            receivedCodes: true,
            signInLinks: true,
            resetLinks: true,
            bitwarden: true,
            showBanner: true,
            showNotchHUD: true,
            autoCopy: true,
            autoType: false,
            clearClipboard: true,
            clipboardTTL: 90,
            restoreClipboard: false,
            includeJunkMail: false,
            blockUnverifiedAutoCopy: true,
            codeInMenuBar: false,
            sound: false,
            messages: true,
            appleMail: false,
            historyDays: 7,
            serviceIcons: false,
            hideFromCapture: true,
            blurCodes: false,
            showPreviews: true,
            clearOnLock: false,
            hotkeys: true,
        ])
    }

    public static func clipboardTTLSeconds(in defaults: UserDefaults) -> TimeInterval {
        let raw = defaults.object(forKey: clipboardTTL) as? Int ?? 90
        return TimeInterval(min(max(raw, 15), 600))
    }

    public static func history(in defaults: UserDefaults) -> TimeInterval {
        let raw = defaults.object(forKey: historyDays) as? Int ?? 7
        return Double(max(1, raw)) * 86400
    }
}
