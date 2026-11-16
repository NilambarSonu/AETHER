// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import Foundation

public enum AetherSubtitleFormatter {
    /// Produces a clean, single-line, human-readable description for notch HUDs and cards.
    /// Eliminates technical email noise (e.g. "no-reply@domain"), redundant service prefixes,
    /// and raw OTP digits from the subtitle line so the context is immediately clear and uncluttered.
    public static func cleanSubtitle(
        for item: CodeItem,
        unlocked: Bool,
        showPreviews: Bool
    ) -> String {
        if item.hasFailedSenderAuth {
            return "Unverified sender — tap Copy only if trusted"
        }
        if !unlocked {
            return "Unlock with Touch ID or password to copy"
        }
        if item.isLink {
            let noun = item.resetsPassword ? "Password reset link" : "Sign-in link"
            if showPreviews, let host = item.destination?.host, !host.isEmpty {
                return "\(noun) for \(host)"
            }
            return noun
        }
        guard showPreviews else {
            return "Verification code"
        }

        let rawPreview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawPreview.isEmpty {
            let cleaned = extractCleanPurpose(from: rawPreview, service: item.service, code: item.code)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        // Fallback: if sender is clean and not a robotic no-reply
        let sender = item.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sender.isEmpty && !sender.lowercased().hasPrefix("no-reply") && !sender.lowercased().hasPrefix("noreply") {
            return "From \(sender)"
        }

        switch item.origin {
        case .messages:
            return "Messages verification code"
        case .mail:
            return "Email verification code"
        case .vault:
            return "Authenticator code"
        case .test:
            return "Test verification code"
        }
    }

    private static func extractCleanPurpose(from text: String, service: String, code: String?) -> String {
        var str = text

        // 1. Strip common bracketed tags like "[OTP]", "[Notice]"
        let bracketRegex = try? NSRegularExpression(pattern: #"^\[[^\]]+\]\s*"#)
        if let match = bracketRegex?.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            if let range = Range(match.range, in: str) {
                str.removeSubrange(range)
            }
        }
        for prefix in ["fwd:", "re:", "otp:", "verification:", "notification:"] {
            if str.lowercased().hasPrefix(prefix) {
                str = String(str.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // 2. Strip redundant service name prefix: e.g. "Saathi AI - Password Reset Request" -> "Password Reset Request"
        let serviceLower = service.lowercased().trimmingCharacters(in: .whitespaces)
        let strLower = str.lowercased()
        if !serviceLower.isEmpty && strLower.hasPrefix(serviceLower) {
            let after = str.dropFirst(service.count).trimmingCharacters(in: .whitespaces)
            if after.hasPrefix("-") || after.hasPrefix(":") || after.hasPrefix("|") || after.hasPrefix("·") || after.hasPrefix("/") {
                str = String(after.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            }
        }

        // 3. Remove raw code if embedded (e.g. "686 943 - Reset Request" or "Your code is 686943")
        if let code, !code.isEmpty {
            str = str.replacingOccurrences(of: code, with: "").trimmingCharacters(in: .whitespaces)
            let digitsOnly = code.filter(\.isNumber)
            if !digitsOnly.isEmpty {
                str = str.replacingOccurrences(of: digitsOnly, with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Clean leading punctuation left over
        while let first = str.first, "-:·|/., \t".contains(first) {
            str.removeFirst()
        }
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = str.lowercased()

        // 4. Pattern heuristics for high-frequency OTP contexts
        if lower.contains("password reset") || lower.contains("reset password") || lower.contains("reset your password") {
            return "Password reset request"
        }
        if lower.contains("sign-in") || lower.contains("sign in") || lower.contains("login") || lower.contains("log in") {
            return "Sign-in verification"
        }
        if lower.contains("registration") || lower.contains("sign-up") || lower.contains("sign up") || lower.contains("signup") || lower.contains("register") {
            return "Account registration"
        }
        if lower.contains("refund") {
            if let refundRange = str.range(of: #"[Rr]efund\s+of\s+[^.,;\n]+"#, options: .regularExpression) {
                let found = String(str[refundRange])
                return found.prefix(1).uppercased() + found.dropFirst()
            }
            return "Refund verification"
        }
        if lower.contains("appeal status") || lower.contains("application status") || lower.contains("application/appeal") {
            return "Checking application / appeal status"
        }
        if lower.contains("transaction") || lower.contains("payment") || lower.contains("transfer") {
            return "Payment approval"
        }
        if lower.contains("two-factor") || lower.contains("2-step") || lower.contains("2fa") {
            return "Two-factor verification"
        }

        // If after cleaning, text is a concise sentence (< 48 chars) that isn't just "Verification code"
        if !str.isEmpty && str.count <= 48 && !lower.hasPrefix("your code is") && !lower.hasPrefix("verification code is") {
            return str.prefix(1).uppercased() + str.dropFirst()
        }

        return "One-time verification code"
    }
}
