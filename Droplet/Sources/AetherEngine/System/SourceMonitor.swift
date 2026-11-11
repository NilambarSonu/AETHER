// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Combine
import Foundation
import Network

@MainActor
public final class SourceMonitor: ObservableObject {
    public struct Callbacks: Sendable {
        public let from: ReadPosition?
        public let status: @MainActor @Sendable (SourceStatus) -> Void
        public let deliver: @MainActor @Sendable (IncomingMessage) -> Void
        public let event: @MainActor @Sendable (SourceEvent) -> Void
        public let wakeSignal: PollWakeSignal?

        public init(
            from: ReadPosition?,
            status: @escaping @MainActor @Sendable (SourceStatus) -> Void,
            deliver: @escaping @MainActor @Sendable (IncomingMessage) -> Void,
            event: @escaping @MainActor @Sendable (SourceEvent) -> Void,
            wakeSignal: PollWakeSignal? = nil
        ) {
            self.from = from
            self.status = status
            self.deliver = deliver
            self.event = event
            self.wakeSignal = wakeSignal
        }
    }

    @Published public private(set) var health: [String: SourceHealth] = [:]
    public var deliver: (IncomingMessage) -> Void = { _ in }

    private let defaults: UserDefaults
    private let secrets: AetherSecretStore
    private var receiving: Bool { AetherPrefs.isReceiving(in: defaults) }
    private var accounts: [MailAccount] = []
    private var local: [String: LocalWatcher] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var wakeSignals: [String: PollWakeSignal] = [:]
    private var generations: [String: UUID] = [:]
    private var positions: [String: (position: ReadPosition, checked: Date)] = [:]
    private var pathMonitor: NWPathMonitor?
    private var network: (online: Bool, interfaces: [String])?
    private let watchMail: (MailAccount, Callbacks) async -> Void
    private let hasCredential: (MailAccount) -> Bool

    public init(
        defaults: UserDefaults,
        secrets: AetherSecretStore = .keychain,
        watchMail: ((MailAccount, Callbacks) async -> Void)? = nil,
        hasCredential: ((MailAccount) -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.secrets = secrets
        AetherPrefs.register(in: defaults)
        self.watchMail =
            watchMail ?? { account, callbacks in
                if account.usesSignIn {
                    await APIWatcher.watch(
                        account,
                        from: callbacks.from,
                        secrets: secrets,
                        status: callbacks.status,
                        deliver: callbacks.deliver,
                        event: callbacks.event,
                        lookback: AetherPrefs.history(in: defaults),
                        wakeSignal: callbacks.wakeSignal
                    )
                } else {
                    await MailWatcher.watch(
                        account,
                        from: callbacks.from,
                        secrets: secrets,
                        status: callbacks.status,
                        deliver: callbacks.deliver,
                        event: callbacks.event,
                        lookback: AetherPrefs.history(in: defaults)
                    )
                }
            }
        self.hasCredential = hasCredential ?? { $0.hasCredential(in: secrets) }
    }

    deinit {
        pathMonitor?.cancel()
        for watcher in local.values { watcher.stop() }
        for task in tasks.values { task.cancel() }
    }

    public func start(accounts: [MailAccount]) {
        restartMessages()
        restartAppleMail()
        restartMail(accounts)
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map(\.name).sorted()
            Task { @MainActor in self?.networkChanged(online: online, interfaces: interfaces) }
        }
        pathMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "app.getdroppy.droplet.aether.network"))
    }

    /// Deterministically shuts down all watchers, tasks, and network monitors (called from `Droplet.deactivate()`).
    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        network = nil
        for (_, watcher) in local { watcher.stop() }
        local.removeAll()
        for (_, task) in tasks { task.cancel() }
        tasks.removeAll()
        wakeSignals.removeAll()
        generations.removeAll()
        for key in health.keys {
            health[key]?.status = .off
            health[key]?.retryAt = nil
        }
    }

    public func resume() {
        restartMessages(resuming: true)
        restartAppleMail()
        restartMail(accounts, resuming: true)
    }

    public func restartMessages(resuming: Bool = false) {
        restart(
            MessagesStore.sourceKey,
            enabled: defaults.bool(forKey: AetherPrefs.receivedCodes) && defaults.bool(forKey: AetherPrefs.messages),
            resuming: resuming
        ) { MessagesStore(after: $0) }
    }

    public func restartAppleMail() {
        restart(
            AppleMailStore.sourceKey,
            enabled: receiving && defaults.bool(forKey: AetherPrefs.appleMail)
        ) { _ in AppleMailStore() }
    }

    private func restart(_ key: String, enabled: Bool, resuming: Bool = false, store: (ReadPosition?) -> LocalStore) {
        local.removeValue(forKey: key)?.stop()
        let callbacks = begin(key, resuming: resuming)
        guard enabled else { return }
        health[key]?.status = .connecting
        let watcher = LocalWatcher(store(callbacks.from))
        watcher.start(
            lookback: AetherPrefs.history(in: defaults),
            status: callbacks.status,
            deliver: callbacks.deliver,
            event: callbacks.event
        )
        local[key] = watcher
    }

    public func restartMail(_ accounts: [MailAccount], onlyChanged: Bool = false, resuming: Bool = false) {
        let previous = Set(self.accounts)
        self.accounts = accounts
        let keys = Set(accounts.map { $0.id.uuidString })
        for key in Array(health.keys) where ![MessagesStore.sourceKey, AppleMailStore.sourceKey].contains(key) && !keys.contains(key) {
            tasks.removeValue(forKey: key)?.cancel()
            wakeSignals.removeValue(forKey: key)
            generations.removeValue(forKey: key)
            health.removeValue(forKey: key)
            positions.removeValue(forKey: key)
        }
        for account in accounts where !onlyChanged || !previous.contains(account) { restart(account, resuming: resuming) }
    }

    public func check(_ key: String) {
        if key == MessagesStore.sourceKey {
            restartMessages()
        } else if key == AppleMailStore.sourceKey {
            restartAppleMail()
        } else if let account = accounts.first(where: { $0.id.uuidString == key }) {
            if account.usesSignIn, tasks[key] != nil, health[key]?.status == .live, let signal = wakeSignals[key] {
                signal.wake(burstSeconds: 45)
            } else {
                restart(account)
            }
        }
    }

    /// Triggers an immediate poll + burst window across all active cloud API mail watchers.
    public func boostAll(burstSeconds: TimeInterval = 45) {
        for signal in wakeSignals.values {
            signal.wake(burstSeconds: burstSeconds)
        }
    }

    public func receivedCode(sourceKey: String, date: Date) {
        guard var source = health[sourceKey] else { return }
        source.lastCode = max(source.lastCode ?? date, date)
        health[sourceKey] = source
    }

    public func networkChanged(online: Bool, interfaces: [String]) {
        let previous = network
        network = (online, interfaces)
        guard let previous else {
            if !online { restartMail(accounts, resuming: true) }
            return
        }
        if previous.online != online || previous.interfaces != interfaces { restartMail(accounts, resuming: true) }
    }

    private func restart(_ account: MailAccount, resuming: Bool = false) {
        let key = account.id.uuidString
        tasks.removeValue(forKey: key)?.cancel()
        wakeSignals.removeValue(forKey: key)
        let wakeSignal = account.usesSignIn ? PollWakeSignal() : nil
        let callbacks = begin(key, resuming: resuming, wakeSignal: wakeSignal)
        guard receiving, account.enabled else { return }
        guard hasCredential(account) else {
            health[key]?.status = .attention(SourceStatus.needsSignIn)
            return
        }
        guard network?.online != false else {
            health[key]?.status = .attention(SourceStatus.waitingForNetwork)
            return
        }
        if let wakeSignal {
            wakeSignals[key] = wakeSignal
        }
        health[key]?.status = .connecting
        let watch = watchMail
        tasks[key] = Task { await watch(account, callbacks) }
    }

    private func begin(_ key: String, resuming: Bool = false, wakeSignal: PollWakeSignal? = nil) -> Callbacks {
        let generation = UUID()
        generations[key] = generation
        if !resuming || Date().timeIntervalSince(positions[key]?.checked ?? .distantPast) >= AetherPrefs.history(in: defaults) {
            positions[key] = nil
        }
        var source = health[key] ?? SourceHealth()
        source.status = .off
        source.retryAt = nil
        health[key] = source
        return Callbacks(
            from: positions[key]?.position,
            status: { [weak self] status in
                guard let self, self.generations[key] == generation else { return }
                self.health[key]?.status = status
            },
            deliver: { [weak self] message in
                guard let self, self.generations[key] == generation else { return }
                self.deliver(message)
            },
            event: { [weak self] event in
                guard let self, self.generations[key] == generation else { return }
                if case .read(let position) = event {
                    self.positions[key] = (position, self.health[key]?.lastChecked ?? .distantPast)
                } else {
                    self.health[key]?.record(event)
                }
            },
            wakeSignal: wakeSignal
        )
    }
}
