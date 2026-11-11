// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Combine
import Foundation

public struct AgentLogEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let date: Date
    public let caller: String
    public let site: String
    public let outcome: String

    public init(id: UUID = UUID(), date: Date, caller: String, site: String, outcome: String) {
        self.id = id
        self.date = date
        self.caller = caller
        self.site = site
        self.outcome = outcome
    }
}

public struct AgentStatusSnapshot: Codable, Sendable, Equatable {
    public let dropletVersion: String?
    public let accessEnabled: Bool
    public let allowAll: Bool
    public let shareSignInLinks: Bool
    public let ruleCount: Int
    public let sourcesWorking: Int
    public let sourcesFailing: Int

    public init(
        dropletVersion: String?,
        accessEnabled: Bool,
        allowAll: Bool,
        shareSignInLinks: Bool,
        ruleCount: Int,
        sourcesWorking: Int,
        sourcesFailing: Int
    ) {
        self.dropletVersion = dropletVersion
        self.accessEnabled = accessEnabled
        self.allowAll = allowAll
        self.shareSignInLinks = shareSignInLinks
        self.ruleCount = ruleCount
        self.sourcesWorking = sourcesWorking
        self.sourcesFailing = sourcesFailing
    }
}

/// Manages MCP / agent requests for verification codes using AETHER's security guarantees:
/// Touch ID or password approval, DMARC sender verification, 20/hr rate limit, 3-denial auto-off.
@MainActor
public final class AetherAgentAccess: ObservableObject {
    public struct Request: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let caller: AgentCaller
        public let query: SiteQuery
        public let asked: Date
        public var item: CodeItem?
        public var unnamed = false
    }

    public enum Always: Equatable, Sendable { case site, allSites }
    public enum Presentation: Sendable {
        case card(Request)
        case notice(CodeItem, AgentCaller, AgentRule?)
        case hide
    }

    public static let lookback: TimeInterval = 30
    public static let maxLookback: TimeInterval = 300
    public nonisolated static let mcpMaxTimeout: TimeInterval = 55
    public static let ruleLimit = 20
    public static let denialLimit = 3

    @Published public private(set) var config = AgentConfig()
    @Published public private(set) var request: Request?
    @Published public private(set) var log: [AgentLogEntry]
    @Published public private(set) var error: String?
    @Published public private(set) var authenticating = false

    public var present: (Presentation) -> Void = { _ in }
    public var approvalGrace: TimeInterval = 45

    private let items: () -> [CodeItem]
    private let readingAnySource: () -> Bool
    private let markUsed: (CodeItem) -> Void
    private let authenticate: (String) async throws -> Void
    private let load: () throws -> AgentConfig
    private let save: (AgentConfig) throws -> Void
    private let defaults: UserDefaults
    private let now: () -> Date

    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var decision: (request: UUID, continuation: CheckedContinuation<Decision, Never>)?
    private var denials = 0
    private var cancelled: String?
    private static let logKey = "agentLog"

    private enum Decision {
        case allow(Always?)
        case deny, timeout
        case cancelled(String)
    }

    public init(
        items: @escaping () -> [CodeItem],
        readingAnySource: @escaping () -> Bool,
        markUsed: @escaping (CodeItem) -> Void,
        authenticate: @escaping (String) async throws -> Void,
        load: @escaping () throws -> AgentConfig,
        save: @escaping (AgentConfig) throws -> Void,
        defaults: UserDefaults,
        now: @escaping () -> Date = Date.init
    ) {
        self.items = items
        self.readingAnySource = readingAnySource
        self.markUsed = markUsed
        self.authenticate = authenticate
        self.load = load
        self.save = save
        self.defaults = defaults
        self.now = now
        log = defaults.data(forKey: Self.logKey).flatMap { try? JSONDecoder().decode([AgentLogEntry].self, from: $0) } ?? []
    }

    public func restore() {
        do { config = try load() } catch { self.error = error.localizedDescription }
    }

    public func stop() {
        cancel("AETHER was deactivated before the request finished.")
        for id in Array(waiters.keys) { wake(id) }
        waiters.removeAll()
        request = nil
        present(.hide)
    }

    public static let accessOff = AgentError(.accessOff, "Agent access is off. Turn it on in Droppy → Settings → Droplets → AETHER → Agents.")

    public func get(
        site: String,
        since: Date?,
        timeout: TimeInterval?,
        caller: AgentCaller,
        maxTimeout: TimeInterval = mcpMaxTimeout,
        progress: @escaping (String) -> Void = { _ in }
    ) async -> Result<CodeItem, AgentError> {
        guard config.enabled else { return .failure(Self.accessOff) }
        guard request == nil else { return .failure(AgentError(.busy, "AETHER is handling another request. Try again shortly.")) }
        guard let query = SiteQuery(site) else { return .failure(AgentError(.usage, "\"\(site)\" isn't a site. Use a domain, URL or service name.")) }
        let asked = now()
        let wait = min(max(timeout ?? min(AgentWire.defaultTimeout, maxTimeout), 1), maxTimeout)
        let deadline = asked.addingTimeInterval(wait)
        let from = since.map { max($0, asked.addingTimeInterval(-Self.maxLookback)) } ?? asked.addingTimeInterval(-Self.lookback)
        request = Request(caller: caller, query: query, asked: asked)
        cancelled = nil
        defer { request = nil }

        var announced = false
        while true {
            guard !Task.isCancelled else { return failure(.approvalTimeout, "The request was cancelled.", query, caller, log: "Cancelled") }
            guard config.enabled else { return .failure(Self.accessOff) }
            if let (item, unnamed) = candidate(for: query, from: from) {
                return await offer(item, unnamed: unnamed, deadline: deadline, progress: progress)
            }
            guard now() < deadline else {
                let next =
                    readingAnySource()
                    ? "Send a new one and try again."
                    : "AETHER isn't reading any messages or mail right now. Enable a source in Droppy → Settings → Droplets → AETHER → Sources."
                return failure(.noCode, "No \(query.label) code arrived in \(Int(wait)) seconds. \(next)", query, caller, log: "No code arrived")
            }
            if !announced {
                progress("waiting up to \(Int(wait))s for a \(query.label) code…")
                announced = true
            }
            await nextChange(until: deadline)
        }
    }

    private func candidate(for query: SiteQuery, from: Date) -> (CodeItem, unnamed: Bool)? {
        let fresh = items().filter {
            [.messages, .mail].contains($0.origin) && !$0.used && now() < $0.expires && $0.received >= from
                && (!$0.isLink || config.links)
        }
        let newest = { (a: CodeItem, b: CodeItem) in a.received < b.received }
        if let item = fresh.filter({ Self.matches($0, query) }).max(by: newest) { return (item, false) }
        if let sms = fresh.filter({ $0.origin == .messages && $0.domain == nil && !$0.code.isEmpty }).max(by: newest) { return (sms, true) }
        return nil
    }

    public static func matches(_ item: CodeItem, _ query: SiteQuery) -> Bool {
        guard item.origin != .mail || item.domain != nil,
            item.domain != nil || item.service.lowercased() != item.sender.lowercased(),
            query.matches(domain: item.domain, service: item.service)
        else { return false }
        return !item.isLink || releasesLink(item, for: query)
    }

    public static func releasesLink(_ item: CodeItem, for query: SiteQuery) -> Bool {
        guard item.link != nil, !item.resetsPassword, item.senderVerified == true, item.linkNotice?.warns != true,
            let host = item.destination?.host, let domain = query.domain
        else { return false }
        return ServiceIdentity.registrable(host) == domain
    }

    private func offer(_ item: CodeItem, unnamed: Bool, deadline: Date, progress: (String) -> Void) async -> Result<CodeItem, AgentError> {
        guard var currentRequest = self.request else { return .failure(AgentError(.failed, "The request ended.")) }
        let query = currentRequest.query
        let caller = currentRequest.caller
        let rule = config.allowAll ? nil : rule(for: item, caller: caller)
        let releases = recentRuleReleases
        if !unnamed, item.origin != .mail || item.senderVerified == true,
            rule != nil || config.allowAll, releases.count < Self.ruleLimit
        {
            var updated = config
            updated.releases = releases + [now()]
            if store(updated) {
                release(item, query, caller, log: rule == nil ? "Allowed by Allow All" : "Allowed by rule")
                present(.notice(item, caller, rule))
                return .success(item)
            }
        }
        currentRequest.item = item
        currentRequest.unnamed = unnamed
        self.request = currentRequest
        present(.card(currentRequest))
        progress("\(item.isLink ? "sign-in link" : "code") arrived. Approve in Droppy to release it.")
        let decision = await awaitDecision(for: currentRequest.id, until: min(deadline.addingTimeInterval(min(approvalGrace, 20)), now().addingTimeInterval(max(10, approvalGrace))))
        present(.hide)
        switch decision {
        case .allow(let always):
            if let why = cancelled ?? (Task.isCancelled ? "The request was cancelled." : nil) {
                return failure(.approvalTimeout, why, query, caller, log: "Cancelled")
            }
            guard config.enabled, !item.isLink || config.links,
                let current = items().first(where: { $0.id == item.id }),
                !current.used, now() < current.expires,
                current.code == item.code, current.link == item.link
            else {
                return failure(.failed, "The code expired or changed before it was approved.", query, caller, log: "Expired")
            }
            denials = 0
            if let always, let app = caller.app, !unnamed, item.origin != .mail || item.senderVerified == true,
                always == .allSites || item.domain != nil
            {
                addRule(AgentRule(app: app, site: always == .site ? item.domain : nil, added: now()))
            }
            release(item, query, caller, log: always == nil ? "Allowed" : "Allowed, and always from now on")
            return .success(item)
        case .deny:
            denials += 1
            if denials >= Self.denialLimit { turnOff(reason: "Turned off after you said no \(Self.denialLimit) times in a row") }
            return failure(.denied, "The user said no. Don't ask again unless they tell you to.", query, caller, log: "Denied")
        case .timeout:
            return failure(.approvalTimeout, "Approval timed out in AETHER.", query, caller, log: "Not approved in time")
        case .cancelled(let why):
            return failure(.approvalTimeout, why, query, caller, log: "Cancelled")
        }
    }

    private func rule(for item: CodeItem, caller: AgentCaller) -> AgentRule? {
        guard let app = caller.app else { return nil }
        return config.rules.first { rule in
            rule.app.same(as: app) && (rule.site == nil || rule.site == item.domain)
        }
    }

    private var recentRuleReleases: [Date] {
        config.releases.filter { now().timeIntervalSince($0) < 3600 }
    }

    private func release(_ item: CodeItem, _ query: SiteQuery, _ caller: AgentCaller, log outcome: String) {
        markUsed(item)
        record(caller, query, outcome)
    }

    private func failure(_ code: AgentError.Code, _ message: String, _ query: SiteQuery, _ caller: AgentCaller, log outcome: String) -> Result<CodeItem, AgentError> {
        record(caller, query, outcome)
        return .failure(AgentError(code, message))
    }

    public func allow(_ always: Always? = nil) async {
        guard let request, let item = request.item, decision?.request == request.id, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let app = request.caller.name
        let site = item.domain ?? request.query.label
        let reason =
            switch always {
            case nil: "give \(app) \(item.isLink ? "a \(site) sign-in link" : "your \(site) code")"
            case .site: "give \(app) your \(site) code, and \(site) codes from now on without asking"
            case .allSites: "give \(app) your \(site) code, and all codes from now on without asking"
            }
        do { try await authenticate(reason) } catch { return }
        resolve(.allow(always), for: request.id)
    }

    public func deny() {
        guard let request else { return }
        resolve(.deny, for: request.id)
    }

    public func cancel(_ why: String) {
        guard let request, request.item != nil else { return }
        cancelled = why
        resolve(.cancelled(why), for: request.id)
    }

    private func awaitDecision(for id: UUID, until deadline: Date) async -> Decision {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                decision = (id, continuation)
                let delay = max(0, deadline.timeIntervalSince(now()))
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    self?.resolve(.timeout, for: id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(.cancelled("The request was cancelled."), for: id) }
        }
    }

    private func resolve(_ value: Decision, for id: UUID) {
        guard let pending = decision, pending.request == id else { return }
        decision = nil
        pending.continuation.resume(returning: value)
    }

    public func itemsChanged() {
        for id in Array(waiters.keys) { wake(id) }
    }

    private func nextChange(until deadline: Date) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
                let delay = max(0, deadline.timeIntervalSince(now()))
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    self?.wake(id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake(id) }
        }
    }

    private func wake(_ id: UUID) { waiters.removeValue(forKey: id)?.resume() }

    public var isWaiting: Bool { request != nil }

    public func setEnabled(_ on: Bool) async {
        guard await set(\.enabled, on, asking: "let agents ask for your verification codes via Droppy MCP") else { return }
        denials = 0
        if !on {
            cancel("Agent access was turned off.")
            itemsChanged()
        }
    }

    public func setLinks(_ on: Bool) async {
        guard await set(\.links, on, asking: "let agents receive verified sign-in links, which sign them in as you") else { return }
        if !on, request?.item?.isLink == true { cancel("Sign-in links were turned off.") }
    }

    public func setAllowAll(_ on: Bool) async {
        await set(\.allowAll, on, asking: "give any approved agent your codes without asking")
    }

    @discardableResult
    private func set(_ setting: WritableKeyPath<AgentConfig, Bool>, _ on: Bool, asking reason: String) async -> Bool {
        guard on != config[keyPath: setting] else { return false }
        if on {
            do { try await authenticate(reason) } catch { return false }
        }
        var updated = config
        updated[keyPath: setting] = on
        return store(updated, revoking: !on)
    }

    public func removeRules(_ ids: Set<AgentRule.ID>) {
        var updated = config
        updated.rules.removeAll { ids.contains($0.id) }
        store(updated, revoking: true)
    }

    public func removeRule(_ id: AgentRule.ID) { removeRules([id]) }

    private func addRule(_ rule: AgentRule) {
        var updated = config
        updated.rules.removeAll { $0.app.same(as: rule.app) && ($0.site == rule.site || rule.site == nil) }
        updated.rules.append(rule)
        store(updated)
    }

    private func turnOff(reason: String) {
        var updated = config
        updated.enabled = false
        store(updated, revoking: true)
        log.insert(AgentLogEntry(date: now(), caller: "AETHER", site: "", outcome: reason), at: 0)
        saveLog()
    }

    @discardableResult
    private func store(_ updated: AgentConfig, revoking: Bool = false) -> Bool {
        if revoking { config = updated }
        do {
            try save(updated)
            config = updated
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return revoking
        }
    }

    private func record(_ caller: AgentCaller, _ query: SiteQuery, _ outcome: String) {
        log.insert(AgentLogEntry(date: now(), caller: caller.logLabel, site: query.label, outcome: outcome), at: 0)
        saveLog()
    }

    private func saveLog() {
        log = Array(log.prefix(50))
        defaults.set(try? JSONEncoder().encode(log), forKey: Self.logKey)
    }

    public func clearLog() {
        log = []
        defaults.removeObject(forKey: Self.logKey)
    }

    public static func wire(_ item: CodeItem) -> AgentItem {
        let code = item.code.isEmpty ? nil : item.code
        let link = code == nil ? item.link?.absoluteString : nil
        return AgentItem(
            kind: code == nil ? .link : .code,
            value: code ?? link ?? "",
            code: code,
            link: link,
            service: item.service,
            domain: item.domain,
            source: item.origin == .mail ? "mail" : "messages",
            senderVerified: item.senderVerified,
            received: item.received,
            expires: item.expires
        )
    }
}
