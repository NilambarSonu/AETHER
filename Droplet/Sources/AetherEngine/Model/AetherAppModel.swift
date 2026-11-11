// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import CodeCatchCore
import Combine
import Foundation
import LocalAuthentication

/// Core observable state machine driving standalone AETHER inside Droppy.
/// Owns lifecycle timers, observers, source watchers, vault lock state, history, and agent access.
@MainActor
public final class AetherAppModel: ObservableObject {
    public var history: TimeInterval { AetherPrefs.history(in: defaults) }

    @Published public private(set) var items: [CodeItem] = [] {
        didSet { agents.itemsChanged() }
    }
    public private(set) var now = Date()
    @Published public private(set) var unlockError: String?
    @Published public private(set) var ignoredSenders: [String] {
        didSet { defaults.set(ignoredSenders, forKey: AetherPrefs.ignoredSenders) }
    }
    @Published public private(set) var notCodes: [NotCodeRule] {
        didSet { defaults.set(try? JSONEncoder().encode(notCodes), forKey: AetherPrefs.notCodes) }
    }

    public let defaults: UserDefaults
    public let secrets: AetherSecretStore
    public let clipboard: AetherClipboard
    public let icons: AetherIconStore
    public let vaultSession: VaultSession
    public let monitor: SourceMonitor
    public let search: CodeSearch
    public let recovery = RecoveryInbox()
    public lazy var agents: AetherAgentAccess = AetherAgentAccess(
        items: { [unowned self] in items },
        readingAnySource: { [unowned self] in sources.contains { $0.status == .live } },
        markUsed: { [unowned self] in markUsed($0) },
        authenticate: agentAuthenticate,
        load: { [secrets] in try AgentStore.load(from: secrets) },
        save: { [secrets] in try AgentStore.save($0, to: secrets) },
        defaults: defaults
    )

    public var hooks: AetherRuntimeHooks
    private let unlockPolicy: UnlockPolicy
    private let agentAuthenticate: @Sendable (String) async throws -> Void
    private var observations = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var started = false

    public var vault: [VaultCode] { isOn(AetherPrefs.bitwarden) ? vaultSession.codes : [] }
    public var isUnlocked: Bool { vaultSession.isUnlocked }
    public var hasVault: Bool { defaults.object(forKey: AetherPrefs.vaultImportedAt) != nil || !vault.isEmpty }
    public var status: [String: SourceStatus] { monitor.health.mapValues(\.status) }
    public var supportsTouchID: Bool { DeviceAuthentication.supportsTouchID() }

    @Published public var accounts: [MailAccount] {
        didSet {
            MailAccount.save(accounts, in: defaults)
            retainRecoverySources()
            monitor.restartMail(accounts, onlyChanged: true)
        }
    }

    public init(
        defaults: UserDefaults,
        secrets: AetherSecretStore = .keychain,
        clipboard: AetherClipboard? = nil,
        icons: AetherIconStore? = nil,
        vaultSession: VaultSession? = nil,
        monitor: SourceMonitor? = nil,
        search: CodeSearch? = nil,
        accounts: [MailAccount]? = nil,
        unlockPolicy: UnlockPolicy? = nil,
        agentAuthenticate: @escaping @Sendable (String) async throws -> Void = { try await DeviceAuthentication().authenticate(reason: $0) },
        hooks: AetherRuntimeHooks? = nil
    ) {
        AetherPrefs.register(in: defaults)
        self.defaults = defaults
        self.secrets = secrets
        self.agentAuthenticate = agentAuthenticate
        let resolvedClipboard = clipboard ?? AetherClipboard(defaults: defaults)
        self.clipboard = resolvedClipboard
        self.icons = icons ?? AetherIconStore(defaults: defaults)
        self.accounts = accounts ?? MailAccount.load(from: defaults)
        self.ignoredSenders = defaults.stringArray(forKey: AetherPrefs.ignoredSenders) ?? []
        self.notCodes = defaults.data(forKey: AetherPrefs.notCodes).flatMap { try? JSONDecoder().decode([NotCodeRule].self, from: $0) } ?? []

        let policy = unlockPolicy ?? VaultStorage.unlockPolicy(secrets: secrets)
        self.unlockPolicy = policy
        let session = vaultSession ?? VaultStorage.session(
            defaults: defaults,
            secrets: secrets,
            unlockPolicy: policy,
            didLock: { resolvedClipboard.clearIfOurs() }
        )
        self.vaultSession = session
        self.monitor = monitor ?? SourceMonitor(defaults: defaults, secrets: secrets)
        self.search = search ?? CodeSearch(defaults: defaults)

        var resolvedHooks = hooks ?? AetherRuntimeHooks()
        if hooks == nil {
            resolvedHooks.copyToClipboard = { text, id in resolvedClipboard.copy(text, id: id) }
            resolvedHooks.typeCode = { code in
                AutoTyper.type(code) {
                    AutoTyper.canType() && session.isUnlocked && defaults.bool(forKey: AetherPrefs.autoType)
                }
            }
        }
        self.hooks = resolvedHooks

        self.vaultSession.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
        self.monitor.$health.map {
            $0.mapValues {
                var h = $0
                h.lastChecked = nil
                return h
            }
        }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        self.search.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
        self.recovery.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
        self.recovery.onRemove = { [weak self] in self?.clipboard.clearIfOurs(ids: $0) }
        self.monitor.deliver = { [weak self] in self?.ingest($0) }
    }

    deinit {
        tickTimer?.invalidate()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        for token in distributedObservers { DistributedNotificationCenter.default().removeObserver(token) }
    }

    public var latest: CodeItem? { items.first { $0.isRecent(at: now) } }
    public var latestCode: CodeItem? { latestCode(at: now) }
    private func latestCode(at date: Date) -> CodeItem? { items.first { $0.isRecent(at: date) && !$0.isLink } }
    public func isFresh(_ item: CodeItem) -> Bool { now < item.expires }

    public var sources: [(key: String, label: String, status: SourceStatus)] {
        [(MessagesStore.sourceKey, "Messages", status[MessagesStore.sourceKey] ?? .off)]
            + (isOn(AetherPrefs.appleMail) ? [(AppleMailStore.sourceKey, "Apple Mail", status[AppleMailStore.sourceKey] ?? .off)] : [])
            + accounts.map { ($0.id.uuidString, $0.label, status[$0.id.uuidString] ?? .off) }
    }

    public func start() {
        guard !started else { return }
        started = true

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tickTimer = timer

        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.monitor.resume()
                    self?.unlockWithMac()
                }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lock(because: "The Mac went to sleep") }
            }
        )

        let distCenter = DistributedNotificationCenter.default()
        distributedObservers.append(
            distCenter.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.lock(because: "The Mac locked")
                    guard self.isOn(AetherPrefs.clearOnLock) else { return }
                    self.clearHistory()
                    self.clipboard.clearIfOurs()
                }
            }
        )
        distributedObservers.append(
            distCenter.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unlockWithMac() }
            }
        )

        unlockPolicy.restore()
        unlockWithMac()
        agents.present = { [weak self] presentation in self?.hooks.presentAgentState(presentation) }
        agents.restore()
        AgentSkillKind.refresh(home: FileManager.default.homeDirectoryForCurrentUser)
        monitor.start(accounts: accounts)
    }

    /// Synchronously cancels all background timers, system observers, mail/local monitors,
    /// active `bw` child processes, and agent waiters when the droplet deactivates.
    public func stop() {
        guard started else { return }
        started = false
        tickTimer?.invalidate()
        tickTimer = nil
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        for token in distributedObservers { DistributedNotificationCenter.default().removeObserver(token) }
        distributedObservers.removeAll()

        monitor.stop()
        clipboard.stop()
        icons.stop()
        agents.stop()
        BitwardenCLI.cancelAllActive()
        vaultSession.lock()
    }

    private func lock(because event: String) {
        vaultSession.lock()
        agents.cancel("\(event) before the request was approved.")
    }

    public func tick(at date: Date = Date()) {
        let onScreen = hooks.isUIVisible()
        if onScreen || liveActivitySignature(at: now) != liveActivitySignature(at: date) {
            objectWillChange.send()
        }
        now = date
        let cutoff = now.addingTimeInterval(-history)
        if items.contains(where: { $0.received < cutoff }) {
            items.removeAll { $0.received < cutoff }
        }
        recovery.prune(at: now)
    }

    private func liveActivitySignature(at date: Date) -> (code: UUID?, recent: Bool) {
        let code = latestCode(at: date)
        return (code?.shouldAnnounce(at: date) == true ? code?.id : nil, items.contains { $0.isRecent(at: date) })
    }

    // MARK: - Settings

    public func isOn(_ key: String) -> Bool {
        key == AetherPrefs.unlockWithMac ? unlockPolicy.enabled : defaults.bool(forKey: key)
    }

    public var receiving: Bool { AetherPrefs.isReceiving(in: defaults) }

    public func set(_ key: String, on: Bool) {
        guard isOn(key) != on else { return }
        objectWillChange.send()
        defaults.set(on, forKey: key)
        if key == AetherPrefs.receivedCodes, !on { recovery.removeAll() }
        if key == AetherPrefs.bitwarden {
            vaultSession.lock()
            return
        }
        let previous = items
        items = items.compactMap(filtered)
        let changed = Set(previous.filter { old in !items.contains(old) }.map(\.id))
        clipboard.clearIfOurs(ids: changed)
        restartMessages()
        restartMail()
    }

    private func filtered(_ item: CodeItem) -> CodeItem? {
        var item = item
        if !isOn(AetherPrefs.receivedCodes) {
            item.code = ""
            item.notCodeKey = nil
        }
        if !isOn(item.linkSetting) { item.link = nil }
        return item.code.isEmpty && item.link == nil ? nil : item
    }

    // MARK: - Sources

    public func restartMessages() { monitor.restartMessages() }

    public func restartMail() {
        restartAppleMail()
        monitor.restartMail(accounts)
    }

    public func restartAppleMail() {
        retainRecoverySources()
        monitor.restartAppleMail()
    }

    public var mailSourceKeys: [String] {
        accounts.filter(\.enabled).map { $0.id.uuidString } + (isOn(AetherPrefs.appleMail) ? [AppleMailStore.sourceKey] : [])
    }

    public func origination(_ item: CodeItem) -> String {
        guard item.origin == .mail else { return item.origination }
        let account = accounts.first { $0.id.uuidString == item.sourceKey }
        let sharingBadge =
            !isOn(AetherPrefs.serviceIcons)
            ? mailSourceKeys.count
            : account.map { mine in accounts.filter { $0.enabled && $0.iconDomain == mine.iconDomain }.count } ?? 1
        guard sharingBadge > 1 else { return "" }
        guard let account else { return item.sourceLabel }
        return accounts.filter { $0.enabled && $0.label == account.label }.count > 1 ? account.user : account.label
    }

    private func retainRecoverySources() { recovery.retainSources(Set(mailSourceKeys)) }

    // MARK: - Ingestion & Actions

    public func ingest(_ message: IncomingMessage) {
        let age = Date().timeIntervalSince(message.date)
        guard age < history, message.date > clearedAt, !isIgnored(message.senderID) else { return }

        let detection = isOn(AetherPrefs.receivedCodes) ? CodeExtractor.detect(in: message.fullText) : nil
        let notCodeKey = detection.map { CodeItem.notCodeKey(for: $0, from: message) }
        let notCode = notCodeKey.map { key in notCodes.contains { $0.key == key } } ?? false
        let code = notCode ? nil : detection?.code
        let detectedLink = message.isMail ? SignInLink.find(in: message.links, subject: message.subject ?? "") : nil
        let resets = detectedLink?.kind == .passwordReset
        let link = isOn(resets ? AetherPrefs.resetLinks : AetherPrefs.signInLinks) ? detectedLink?.url : nil
        var item = CodeItem(message, code: code, link: link, resetsPassword: resets)
        if code != nil, item.origin != .test { item.notCodeKey = notCodeKey }

        guard !dismissed.contains(item.dismissKey) else { return }
        if code != nil || detectedLink != nil { recovery.remove(messageKey: message.dismissKey) }
        guard code != nil || link != nil else {
            if isOn(AetherPrefs.receivedCodes), detectedLink == nil, !notCode { recovery.record(message) }
            return
        }
        monitor.receivedCode(sourceKey: message.sourceKey, date: message.date)

        if let index = items.firstIndex(where: { $0.dismissKey == item.dismissKey }) {
            var updated = item
            updated.id = items[index].id
            updated.used = items[index].used
            items[index] = updated
            return
        }
        items.append(item)
        items.sort { $0.received > $1.received }

        guard item.shouldAnnounce(at: Date()) else { return }
        guard !agents.isWaiting else { return }
        if let code, isUnlocked {
            if isOn(AetherPrefs.autoCopy) { hooks.copyToClipboard(code, item.id) }
            if isOn(AetherPrefs.autoType) { hooks.typeCode(code) }
        }
        if isOn(AetherPrefs.showBanner) {
            unlockError = nil
            hooks.presentBanner(item.id)
        }
        if isOn(AetherPrefs.showNotchHUD) {
            hooks.presentHUD(item, false)
        }
        if isOn(AetherPrefs.sound) {
            hooks.playArrivalSound()
        }
    }

    public func unlock() async throws {
        try await authenticate()
        if isOn(AetherPrefs.autoCopy), let item = latestCode, !item.used, item.shouldAnnounce(at: Date()) {
            copy(item)
        }
    }

    @discardableResult
    public func unlocked(_ action: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        if isUnlocked {
            action()
            return nil
        }
        return Task { if (try? await authenticate()) != nil { action() } }
    }

    public func unlockWithMac() {
        guard isOn(AetherPrefs.unlockWithMac), !isUnlocked, !hooks.screenIsLocked() else { return }
        Task { try? await authenticate() }
    }

    public func setUnlockWithMac(_ enabled: Bool) async {
        if !enabled { vaultSession.lock() }
        unlockError = nil
        defer { objectWillChange.send() }
        do {
            try await unlockPolicy.setEnabled(enabled)
            if enabled { try await authenticate() }
        } catch {
            if !Self.isCancel(error) { unlockError = error.localizedDescription }
        }
    }

    public func authenticate() async throws {
        unlockError = nil
        do {
            try await vaultSession.unlock()
        } catch {
            if !Self.isCancel(error) { unlockError = error.localizedDescription }
            throw error
        }
    }

    public static func isCancel(_ error: Error) -> Bool {
        if error is CancellationError || error as? VaultSession.Failure == .busy { return true }
        guard let code = (error as? LAError)?.code else { return false }
        return [.userCancel, .appCancel, .systemCancel].contains(code)
    }

    public func copy(_ item: CodeItem, at date: Date = Date(), userInitiated: Bool = false) {
        let feature = item.origin == .vault ? AetherPrefs.bitwarden : item.isLink ? item.linkSetting : AetherPrefs.receivedCodes
        guard isUnlocked, isOn(feature) else { return }
        var current = item
        if item.origin == .vault {
            guard let saved = vault.first(where: { $0.id == item.sourceKey }), let fresh = CodeItem(saved, at: date) else { return }
            current = fresh
            search.recordUse(current)
        } else {
            guard let retained = items.first(where: { $0.id == item.id && $0.copyValue == item.copyValue }),
                !isIgnored(retained.sender)
            else { return }
            current = retained
        }
        objectWillChange.send()
        hooks.copyToClipboard(current.copyValue, current.id)
        markUsed(current)
        if userInitiated {
            hooks.presentHUD(current, true)
        }
    }

    public func copyLink(_ item: CodeItem) {
        guard let item = retainedLink(item), let link = item.link else { return }
        hooks.copyToClipboard(link.absoluteString, item.id)
    }

    private func retainedLink(_ item: CodeItem) -> CodeItem? {
        guard isUnlocked,
            let current = items.first(where: { $0.id == item.id && $0.link == item.link }),
            current.link != nil, isOn(current.linkSetting), !isIgnored(current.sender)
        else { return nil }
        return current
    }

    @discardableResult
    public func copyRecoveryText(_ text: String, from id: UUID, at date: Date = Date()) -> Bool {
        recovery.prune(at: date)
        guard isUnlocked, isOn(AetherPrefs.receivedCodes), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let entry = recovery.entries.first(where: { $0.id == id }), entry.message.fullText.contains(text)
        else { return false }
        hooks.copyToClipboard(text, id)
        return true
    }

    public func copyLatest(userInitiated: Bool = true) {
        guard let item = latestCode else {
            NSSound.beep()
            return
        }
        unlocked { [self] in
            copy(item, userInitiated: userInitiated)
        }
    }

    public func open(_ item: CodeItem) {
        guard let item = retainedLink(item), let link = item.link else { return }
        if let notice = item.linkNotice, notice.warns, let destination = item.destination, let host = destination.host {
            let address = host + destination.path
            let details = [
                "From: \(item.sender)",
                "Subject: \(item.preview)",
                "Link: \(address.count > 60 ? address.prefix(59) + "…" : address)",
            ].joined(separator: "\n")
            let email = source(of: item).map { src in
                (title: src.title, run: { @MainActor [openURL = hooks.openURL] in openURL(src.url) })
            }
            guard hooks.confirmLink(ServiceIdentity.registrable(host), notice.text, details, email),
                retainedLink(item) != nil
            else { return }
        }
        hooks.openURL(link)
        markUsed(item)
    }

    public func showTestCode(userInitiated: Bool = true) {
        let sample = IncomingMessage(
            text: "Your AETHER verification code is \(Int.random(in: 100_000...999_999)).",
            senderName: "",
            senderID: "",
            sourceKey: CodeItem.testSourceKey,
            sourceLabel: "Test",
            date: Date(),
            isMail: false
        )
        ingest(sample)
        if userInitiated, let item = items.first(where: { $0.origin == .test }) {
            hooks.presentHUD(item, true)
        }
    }

    public func source(of item: CodeItem) -> (title: String, url: URL)? {
        switch item.origin {
        case .messages:
            if item.sender.contains("@") || item.sender.allSatisfy({ $0.isNumber || "+ ()-".contains($0) }),
                let link = item.sender.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap({ URL(string: "sms:\($0)") })
            {
                return ("Show in Messages", link)
            }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS").map { ("Open Messages", $0) }
        case .mail:
            let mailApp = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "mailto:")!)
            let fromMail = item.sourceKey == AppleMailStore.sourceKey
            if !fromMail, let web = item.webURL {
                return ("Show in \(web.host == "mail.google.com" ? "Gmail" : "Outlook")", web)
            }
            if let id = item.internetMessageID?.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "@.-_"))),
                let link = URL(string: "message://%3C\(id)%3E"), let handler = NSWorkspace.shared.urlForApplication(toOpen: link),
                fromMail || handler == mailApp
            {
                return ("Show in Mail", link)
            }
            return mailApp.map { ("Open \(FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: ""))", $0) }
        case .test, .vault:
            return nil
        }
    }

    public func dismiss(_ item: CodeItem) {
        defaults.set(Array((dismissed + [item.dismissKey]).suffix(500)), forKey: AetherPrefs.dismissed)
        remove { $0.id == item.id }
        hooks.dismissBanner(item.id)
    }

    private func remove(where gone: (CodeItem) -> Bool) {
        clipboard.clearIfOurs(ids: Set(items.filter(gone).map(\.id)))
        items.removeAll(where: gone)
    }

    public func isIgnored(_ sender: String) -> Bool {
        ignoredSenders.contains { ServiceIdentity.ignores($0, sender: sender) }
    }

    public func ignore(_ sender: String) {
        let entry = sender.lowercased()
        guard !entry.isEmpty, !isIgnored(entry) else { return }
        ignoredSenders.append(entry)
        remove { ServiceIdentity.ignores(entry, sender: $0.sender) }
        recovery.remove(ignored: entry)
    }

    public func stopIgnoring(_ entries: Set<String>) {
        ignoredSenders.removeAll { entries.contains($0) }
        restartMessages()
        restartMail()
    }

    private var dismissed: [String] { defaults.stringArray(forKey: AetherPrefs.dismissed) ?? [] }

    public func markNotCode(_ item: CodeItem) {
        guard !item.isLink, let key = item.notCodeKey else { return }
        if !notCodes.contains(where: { $0.key == key }) {
            notCodes = Array((notCodes + [NotCodeRule(key: key, sender: item.sender, added: Date())]).suffix(200))
        }
        for match in items where match.notCodeKey == key { clipboard.clearIfHolds(match) }
        items = items.compactMap { entry in
            guard entry.notCodeKey == key else { return entry }
            guard entry.link != nil else { return nil }
            var link = entry
            link.code = ""
            link.notCodeKey = nil
            return link
        }
    }

    public func forgetNotCodes(_ keys: Set<String>) {
        notCodes.removeAll { keys.contains($0.key) }
        restartMessages()
        restartMail()
    }

    public func saveVault(_ codes: [VaultCode]) throws {
        let previousIDs = Set(vault.compactMap { CodeItem($0, at: now)?.id })
        try vaultSession.replace(codes)
        clipboard.clearIfOurs(ids: previousIDs)
    }

    public func removeVault() async throws {
        try await authenticate()
        try vaultSession.remove()
    }

    public var vaultItems: [CodeItem] { vault.compactMap { CodeItem($0, at: now) } }

    public var agentStatus: AgentStatusSnapshot {
        AgentStatusSnapshot(
            dropletVersion: hooks.appVersion(),
            accessEnabled: agents.config.enabled,
            allowAll: agents.config.allowAll,
            shareSignInLinks: agents.config.links,
            ruleCount: agents.config.rules.count,
            sourcesWorking: sources.filter { $0.status == .live }.count,
            sourcesFailing: sources.filter { $0.status.needsAttention }.count
        )
    }

    public var hasHistory: Bool { !items.isEmpty || !recovery.entries.isEmpty }

    public func clearHistory() {
        remove { _ in true }
        recovery.removeAll()
        defaults.set(Date().timeIntervalSince1970, forKey: AetherPrefs.clearedAt)
    }

    private var clearedAt: Date { Date(timeIntervalSince1970: defaults.double(forKey: AetherPrefs.clearedAt)) }

    private func markUsed(_ item: CodeItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), !items[i].used else { return }
        items[i].used = true
    }
}
