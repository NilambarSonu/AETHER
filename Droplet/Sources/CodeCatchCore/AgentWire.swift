import Foundation

/// What `codecatch` and the app say over the local socket: one JSON line from the CLI, then JSON
/// lines back: progress notes, and last a single item, status or error. Fields are only ever
/// added; renaming or retyping one bumps `version`.
public enum AgentWire {
    public static let version = 1

    /// The code-signing identifiers each side checks the other for; install.sh signs with the same.
    public static let appIdentifier = "com.uros.codecatch"
    public static let cliIdentifier = "com.uros.codecatch.cli"

    /// Readable only by this user: the folder is 0700, the socket 0600.
    public static func socketPath(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Application Support/CodeCatch/cli.sock"
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The longest request line the app reads; a site name and a few numbers fit many times over.
    public static let maxRequest = 4096
    public static let defaultTimeout: TimeInterval = 90
    public static let maxTimeout: TimeInterval = 600
}

public struct AgentRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable { case get, status }
    public var v = AgentWire.version
    public var command: Command
    public var site: String?
    /// Codes from before this are not returned; the app caps it at five minutes back.
    public var since: Date?
    public var timeout: TimeInterval?

    public init(command: Command, site: String? = nil, since: Date? = nil, timeout: TimeInterval? = nil) {
        self.command = command
        self.site = site
        self.since = since
        self.timeout = timeout
    }
}

public struct AgentItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case code, link }
    public var kind: Kind
    /// What to type, or the link to open.
    public var value: String
    public var code: String?
    public var link: String?
    public var service: String
    public var domain: String?
    /// "messages" or "mail".
    public var source: String
    public var senderVerified: Bool?
    public var received: Date
    public var expires: Date

    public init(
        kind: Kind, value: String, code: String?, link: String?, service: String, domain: String?, source: String,
        senderVerified: Bool?, received: Date, expires: Date
    ) {
        self.kind = kind
        self.value = value
        self.code = code
        self.link = link
        self.service = service
        self.domain = domain
        self.source = source
        self.senderVerified = senderVerified
        self.received = received
        self.expires = expires
    }
}

public struct AgentStatus: Codable, Equatable, Sendable {
    public var appVersion: String?
    public var access: Bool
    /// Sites allowed without asking: a count, never the list.
    public var rules: Int
    public var sourcesWorking: Int
    public var sourcesFailing: Int
    /// Every code goes out without asking. Optional: an app from before it existed leaves it out.
    public var allowAll: Bool?

    public init(appVersion: String?, access: Bool, rules: Int, sourcesWorking: Int, sourcesFailing: Int, allowAll: Bool = false) {
        self.appVersion = appVersion
        self.access = access
        self.rules = rules
        self.allowAll = allowAll
        self.sourcesWorking = sourcesWorking
        self.sourcesFailing = sourcesFailing
    }
}

public struct AgentError: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case denied
        case noCode = "no_code"
        case approvalTimeout = "approval_timeout"
        case accessOff = "access_off"
        case busy, usage, failed
    }
    public var code: Code
    public var message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    /// The agent's next step differs for each: stop, resend the code, ask the user, fix the setup.
    public var exitCode: Int32 {
        switch code {
        case .denied: 2
        case .noCode: 3
        case .accessOff: 4
        case .approvalTimeout: 5
        case .usage: 64
        case .busy, .failed: 1
        }
    }
}

public struct AgentReply: Codable, Equatable, Sendable {
    public var v = AgentWire.version
    public var progress: String?
    public var item: AgentItem?
    public var status: AgentStatus?
    public var error: AgentError?

    public init(progress: String? = nil, item: AgentItem? = nil, status: AgentStatus? = nil, error: AgentError? = nil) {
        self.progress = progress
        self.item = item
        self.status = status
        self.error = error
    }
}
