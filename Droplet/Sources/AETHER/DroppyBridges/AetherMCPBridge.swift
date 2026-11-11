// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import Foundation

/// Exposes typed AI agent tools (`droplet_aether_*`) via Droppy's native MCP server (`MCPToolProviding`).
enum AetherMCPBridge {
    private struct GetCodeArgs: Decodable {
        let site: String
        let since: TimeInterval?
        let timeout: TimeInterval?
    }

    private struct EmptyResult: Encodable {}

    private struct ErrorPayload: Encodable {
        let error: String
        let detail: String
    }

    static var tools: [DropletMCPTool] {
        [
            DropletMCPTool(
                name: "get_code",
                title: "Get Verification Code",
                summary: "Waits up to 55s for a fresh 2FA code or verified sign-in link for a site/domain, gated on user Touch ID approval and security rules.",
                inputSchemaJSON: #"{"type":"object","properties":{"site":{"type":"string","description":"Domain, URL, or service name (e.g. github.com)"},"since":{"type":"number","description":"Optional Unix timestamp captured before requesting the code"},"timeout":{"type":"number","description":"Wait timeout in seconds (1 to 55)"}},"required":["site"]}"#
            ),
            DropletMCPTool(
                name: "get_status",
                title: "Get AETHER Status",
                summary: "Returns agent access status, rule count, and count of healthy/failing local and mail code sources without exposing secrets.",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#
            ),
            DropletMCPTool(
                name: "list_recent_services",
                title: "List Recent Code Services",
                summary: "Lists recent service names, domains, timestamps, and expiry metadata (never returns plaintext codes or links).",
                inputSchemaJSON: #"{"type":"object","properties":{}}"#
            ),
        ]
    }

    @MainActor
    static func perform(
        named name: String,
        argumentsJSON: String,
        model: AetherAppModel
    ) async throws -> String {
        switch name {
        case "get_code":
            let data = Data(argumentsJSON.utf8)
            let args = try JSONDecoder().decode(GetCodeArgs.self, from: data)
            let sinceDate = args.since.map { Date(timeIntervalSince1970: $0) }
            let caller = AgentCaller(app: nil, appPath: nil, process: "Droppy MCP")
            let result = await model.agents.get(
                site: args.site,
                since: sinceDate,
                timeout: args.timeout,
                caller: caller,
                maxTimeout: AetherAgentAccess.mcpMaxTimeout
            )
            switch result {
            case .success(let item):
                return try encodeJSON(AetherAgentAccess.wire(item))
            case .failure(let agentError):
                throw NSError(
                    domain: "app.getdroppy.droplet.aether.mcp",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: agentError.message]
                )
            }

        case "get_status":
            return try encodeJSON(model.agentStatus)

        case "list_recent_services":
            struct ServiceMetadata: Encodable {
                let service: String
                let domain: String?
                let kind: String
                let received: Date
                let expires: Date
                let used: Bool
            }
            let recent = model.items.prefix(20).map { item in
                ServiceMetadata(
                    service: item.service,
                    domain: item.domain,
                    kind: item.isLink ? (item.resetsPassword ? "password_reset" : "sign_in_link") : "code",
                    received: item.received,
                    expires: item.expires,
                    used: item.used
                )
            }
            return try encodeJSON(recent)

        default:
            throw NSError(
                domain: "app.getdroppy.droplet.aether.mcp",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Unknown AETHER MCP tool: \(name)"]
            )
        }
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
