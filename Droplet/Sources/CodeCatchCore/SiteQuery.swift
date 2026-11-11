import Foundation

/// The site an agent asks for, as it may write it: "github.com", "https://github.com/login?x=1",
/// "GitHub", "accounts.google.com".
public struct SiteQuery: Equatable, Sendable {
    /// Registrable domain, when the text names one or a known service.
    public let domain: String?
    /// Lowercased, without spaces: "github", "amazon web services" → "amazonwebservices".
    public let name: String

    public init?(_ text: String) {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: host), let h = url.host, url.scheme != nil { host = h }
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        if let colon = host.lastIndex(of: ":"), host[host.index(after: colon)...].allSatisfy(\.isNumber) { host = String(host[..<colon]) }
        if host.hasSuffix(".") { host.removeLast() }
        if ServiceIdentity.isHostname(host) {
            let domain = ServiceIdentity.registrable(host)
            self.domain = domain
            name = String(domain.prefix { $0 != "." })
        } else {
            let name = host.filter { !$0.isWhitespace }
            guard !name.isEmpty, name.count <= 64, name.allSatisfy({ $0.isLetter || $0.isNumber || "-_&".contains($0) }) else { return nil }
            self.name = name
            domain = ServiceIdentity.knownDomain(for: name)
        }
    }

    /// What the card and messages call it.
    public var label: String { domain ?? name }

    /// The domains that count as this site: its own, plus the ones its codes come from
    /// (claude.ai sign-ins are mailed from anthropic.com).
    private var domains: Set<String> {
        guard let domain else { return [] }
        return Set([domain] + (Self.aliases[domain] ?? []))
    }

    /// Whether a code from `service`, sent from `domain`, is for this site. Only the sender's domain
    /// counts when there is one: a mail's display name, and where its link points, are the sender's
    /// choice ("GitHub" <x@evil.com> linking to a real github.com device-login page).
    public func matches(domain itemDomain: String?, service: String) -> Bool {
        if let itemDomain {
            if domains.contains(itemDomain) { return true }
            // A bare name nobody knows ("acme") matches the domain that starts with it.
            return domain == nil && itemDomain.prefix { $0 != "." } == name
        }
        // No sender domain (most SMS): the service the message names.
        return service.lowercased().filter { !$0.isWhitespace } == name
    }

    /// Where a site signs in and where its codes come from differ.
    private static let aliases: [String: [String]] = [
        "claude.ai": ["anthropic.com"], "chatgpt.com": ["openai.com"],
        "live.com": ["microsoft.com"], "microsoftonline.com": ["microsoft.com"], "office.com": ["microsoft.com"],
        "outlook.com": ["microsoft.com"], "xbox.com": ["microsoft.com"],
        "amazonaws.com": ["amazon.com"], "youtube.com": ["google.com"], "gmail.com": ["google.com"],
        "icloud.com": ["apple.com"], "twitter.com": ["x.com"], "steamcommunity.com": ["steampowered.com"],
    ]
}
