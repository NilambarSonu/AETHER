// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import ApplicationServices
import CodeCatchCore
import Foundation

/// Context-aware key-by-key OTP auto-typing into focused external input fields
/// with sender authenticity checks, chat/notes/meeting blocklisting, and browser-domain matching.
public enum AutoTyper {
    public struct TargetContext: Equatable, Sendable {
        public let expectedDomain: String?
        public let senderVerified: Bool?
        public let frontmostBundleID: String?
        public let focusedRole: String?
        public let focusedDocumentHost: String?

        public init(
            expectedDomain: String? = nil,
            senderVerified: Bool? = nil,
            frontmostBundleID: String? = nil,
            focusedRole: String? = nil,
            focusedDocumentHost: String? = nil
        ) {
            self.expectedDomain = expectedDomain
            self.senderVerified = senderVerified
            self.frontmostBundleID = frontmostBundleID
            self.focusedRole = focusedRole
            self.focusedDocumentHost = focusedDocumentHost
        }
    }

    public enum Decision: Equatable, Sendable {
        case allow
        case deniedUnverifiedSender
        case deniedUntrustedApp
        case deniedUnfocusedField
        case deniedDomainMismatch
    }

    private static let digitKeys: [Character: CGKeyCode] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    /// Applications where blindly auto-typing an arriving OTP risks leaking it into chat, notes, or screen shares.
    public static let blockedBundleIdentifiers: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.discord",
        "ru.keepcoder.telegram",
        "net.whatsapp.whatsapp",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.mobilesms",
        "com.apple.notes",
        "com.apple.textedit",
        "com.apple.mail",
        "com.apple.facetime",
        "md.obsidian",
        "notion.id",
    ]

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        "AXSecureTextField",
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea",
    ]

    public static let queue = DispatchQueue(label: "app.getdroppy.droplet.aether.key-typer", qos: .userInteractive)

    @MainActor
    public static func canType(isHostActive: Bool? = nil) -> Bool {
        AccessibilityTrust.isTrusted && !(isHostActive ?? NSApp.isActive)
    }

    @MainActor
    public static func canTypeSafely(expectedDomain: String? = nil, senderVerified: Bool? = nil, isHostActive: Bool? = nil) -> Bool {
        guard canType(isHostActive: isHostActive) else { return false }
        let context = captureLiveContext(expectedDomain: expectedDomain, senderVerified: senderVerified)
        return evaluateTarget(context) == .allow
    }

    public static func evaluateTarget(_ context: TargetContext) -> Decision {
        if context.senderVerified == false {
            return .deniedUnverifiedSender
        }
        if let bundle = context.frontmostBundleID?.lowercased(), blockedBundleIdentifiers.contains(bundle) {
            return .deniedUntrustedApp
        }
        if let role = context.focusedRole, !editableRoles.contains(role) {
            return .deniedUnfocusedField
        }
        if let expected = context.expectedDomain?.lowercased(), !expected.isEmpty,
           let observed = context.focusedDocumentHost?.lowercased(), !observed.isEmpty
        {
            let expectedReg = ServiceIdentity.registrable(expected)
            let observedReg = ServiceIdentity.registrable(observed)
            if expectedReg != observedReg && observed != expected && !observed.hasSuffix("." + expectedReg) {
                return .deniedDomainMismatch
            }
        }
        return .allow
    }

    @MainActor
    private static func captureLiveContext(expectedDomain: String?, senderVerified: Bool?) -> TargetContext {
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        var focusedRole: String?
        var documentHost: String?

        if let pid = front?.processIdentifier, AccessibilityTrust.isTrusted {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let focusedRef
            {
                let element = focusedRef as! AXUIElement
                var roleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success {
                    focusedRole = roleRef as? String
                }
            }
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let windowRef
            {
                let window = windowRef as! AXUIElement
                var docRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef) == .success,
                   let urlString = docRef as? String,
                   let host = URL(string: urlString)?.host
                {
                    documentHost = host
                }
            }
        }

        return TargetContext(
            expectedDomain: expectedDomain,
            senderVerified: senderVerified,
            frontmostBundleID: bundleID,
            focusedRole: focusedRole,
            focusedDocumentHost: documentHost
        )
    }

    public static func type(
        _ text: String,
        allowed: @escaping @MainActor () -> Bool,
        modifiersHeld: @escaping () -> Bool = {
            !CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        },
        press: @escaping (Character) -> Void = press
    ) {
        queue.async {
            for _ in 0..<50 where modifiersHeld() { usleep(20_000) }
            guard !modifiersHeld(), DispatchQueue.main.sync(execute: { MainActor.assumeIsolated(allowed) }) else { return }
            for ch in text {
                press(ch)
                usleep(15_000)
            }
        }
    }

    public static func press(_ ch: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        var units = Array(String(ch).utf16)
        for down in [true, false] {
            // droppykit-lint: allow synthetic-input: Opt-in user-enabled OTP auto-type into focused external inputs gated on Accessibility trust
            let e = CGEvent(keyboardEventSource: source, virtualKey: digitKeys[ch] ?? 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // droppykit-lint: allow synthetic-input: Opt-in user-enabled OTP auto-type into focused external inputs gated on Accessibility trust
            e?.post(tap: .cghidEventTap)
        }
    }
}
