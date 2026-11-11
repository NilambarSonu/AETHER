import Foundation
import Security

/// Who signed a running program. Only valid signatures that chain to Apple count (Developer ID,
/// App Store, Apple's own); ad-hoc or broken ones give nil.
public enum CodeSignature {
    public struct Identity: Equatable, Sendable {
        public let identifier: String
        /// Nil for Apple's own programs, such as Terminal.
        public let team: String?
        /// Where the signed code is, read from the signature check itself, so the two can't come from
        /// different programs (a process can exec another while it is looked at).
        public var path: String? = nil
    }

    public static func of(auditToken: Data) -> Identity? {
        guest([kSecGuestAttributeAudit: auditToken as CFData])
    }

    public static func of(pid: pid_t) -> Identity? {
        guest([kSecGuestAttributePid: NSNumber(value: pid)])
    }

    /// This program's own signer; nil for an unsigned development build.
    public static var current: Identity? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        return identity(code)
    }

    /// An app bundle's signer, checked on disk: the main executable and its Info.plist against the
    /// signature, though not every resource (VS Code's would take seconds).
    public static func of(bundle url: URL) -> Identity? {
        var code: SecStaticCode?
        guard let appleIssued, SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
            SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), appleIssued) == errSecSuccess
        else { return nil }
        return info(code)
    }

    private static func guest(_ attributes: [CFString: Any]) -> Identity? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess, let code else { return nil }
        return identity(code)
    }

    nonisolated(unsafe) private static let appleIssued: SecRequirement? = {
        var requirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement)
        return requirement
    }()

    private static func identity(_ code: SecCode) -> Identity? {
        guard let appleIssued, SecCodeCheckValidity(code, [], appleIssued) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return info(staticCode)
    }

    private static func info(_ code: SecStaticCode) -> Identity? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dict = info as? [String: Any], let id = dict[kSecCodeInfoIdentifier as String] as? String
        else { return nil }
        var url: CFURL?
        SecCodeCopyPath(code, [], &url)
        return Identity(identifier: id, team: dict[kSecCodeInfoTeamIdentifier as String] as? String, path: (url as URL?)?.path)
    }
}
