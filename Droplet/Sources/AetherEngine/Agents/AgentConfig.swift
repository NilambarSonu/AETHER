// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public struct AgentApp: Codable, Hashable, Sendable {
    public let id: String
    public let team: String?
    public let name: String

    public init(id: String, team: String?, name: String) {
        self.id = id
        self.team = team
        self.name = name
    }

    public func same(as other: AgentApp) -> Bool { id == other.id && team == other.team }
}

public struct AgentCaller: Equatable, Sendable {
    public var app: AgentApp?
    public var appPath: URL?
    public var process: String

    public init(app: AgentApp? = nil, appPath: URL? = nil, process: String) {
        self.app = app
        self.appPath = appPath
        self.process = process
    }

    public var name: String { app?.name ?? (process.isEmpty ? "Droppy MCP" : process) }
    public var logLabel: String { [app?.name ?? "MCP Client", process].filter { !$0.isEmpty }.joined(separator: " · ") }
}

public struct AgentRule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var app: AgentApp
    public var site: String?
    public var added = Date()

    public init(id: UUID = UUID(), app: AgentApp, site: String?, added: Date = Date()) {
        self.id = id
        self.app = app
        self.site = site
        self.added = added
    }
}

public struct AgentConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var rules: [AgentRule] = []
    public var allowAll = false
    public var links = false
    public var releases: [Date] = []

    public init(enabled: Bool = false, rules: [AgentRule] = [], allowAll: Bool = false, links: Bool = false, releases: [Date] = []) {
        self.enabled = enabled
        self.rules = rules
        self.allowAll = allowAll
        self.links = links
        self.releases = releases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        rules = try c.decodeIfPresent([AgentRule].self, forKey: .rules) ?? []
        allowAll = try c.decodeIfPresent(Bool.self, forKey: .allowAll) ?? false
        links = try c.decodeIfPresent(Bool.self, forKey: .links) ?? false
        releases = try c.decodeIfPresent([Date].self, forKey: .releases) ?? []
    }
}

public enum AgentStore {
    private static let key = "agent-access"

    public static func load(from secrets: AetherSecretStore = .keychain) throws -> AgentConfig {
        guard let stored = try secrets.read(key) else { return AgentConfig() }
        if AetherVaultCrypto.isSealed(stored) {
            let data = try AetherVaultCrypto.open(stored, domain: .agentConfig, recordKey: key, using: secrets)
            return try JSONDecoder().decode(AgentConfig.self, from: data)
        }
        let legacyData = Data(stored.utf8)
        let decoded = try JSONDecoder().decode(AgentConfig.self, from: legacyData)
        if let sealed = try? AetherVaultCrypto.seal(legacyData, domain: .agentConfig, recordKey: key, using: secrets) {
            try? secrets.set(sealed, for: key)
        }
        return decoded
    }

    public static func save(_ config: AgentConfig, to secrets: AetherSecretStore = .keychain) throws {
        let data = try JSONEncoder().encode(config)
        let sealed = try AetherVaultCrypto.seal(data, domain: .agentConfig, recordKey: key, using: secrets)
        try secrets.set(sealed, for: key)
    }
}

public enum AgentAuditStore {
    private static let key = "agent-audit-log"

    public static func load(from secrets: AetherSecretStore, migratingFrom defaults: UserDefaults, legacyKey: String) -> [AgentLogEntry] {
        if let stored = try? secrets.read(key), AetherVaultCrypto.isSealed(stored),
            let data = try? AetherVaultCrypto.open(stored, domain: .agentAuditLog, recordKey: key, using: secrets),
            let entries = try? JSONDecoder().decode([AgentLogEntry].self, from: data)
        {
            if defaults.object(forKey: legacyKey) != nil {
                defaults.removeObject(forKey: legacyKey)
            }
            return entries
        }

        if let legacyData = defaults.data(forKey: legacyKey),
            let legacyEntries = try? JSONDecoder().decode([AgentLogEntry].self, from: legacyData)
        {
            save(legacyEntries, to: secrets)
            defaults.removeObject(forKey: legacyKey)
            return legacyEntries
        }
        return []
    }

    public static func save(_ entries: [AgentLogEntry], to secrets: AetherSecretStore) {
        guard let data = try? JSONEncoder().encode(entries),
            let sealed = try? AetherVaultCrypto.seal(data, domain: .agentAuditLog, recordKey: key, using: secrets)
        else { return }
        try? secrets.set(sealed, for: key)
    }

    public static func clear(in secrets: AetherSecretStore) {
        try? secrets.remove(key)
    }
}
