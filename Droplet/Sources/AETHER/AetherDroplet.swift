// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import AppKit
import CodeCatchCore
import Combine
import DroppyKit
import SwiftUI

@objc(AETHERPrincipal)
public final class AETHERPrincipal: NSObject, DropletPrincipal {
    @MainActor
    public func makeDroplet() -> AnyObject {
        AetherDroplet()
    }
}

/// Standalone AETHER droplet providing local OTP/link monitoring (Messages, Apple Mail, Gmail,
/// Outlook, IMAP), Bitwarden TOTP import, privacy/clipboard safeguards, Settings UI inside Droppy
/// Settings (`SettingsPagesProviding`), Notch Shelf widget (`ShelfWidgetCompositionProviding`),
/// Command Center panel (`MenuBarExtraProviding`), HUD/banner alerts (`HUDPresenting`), ephemeral
/// notch live activity (`LiveActivityProviding`), and native Droppy MCP tools (`MCPToolProviding`).
@MainActor
public final class AetherDroplet:
    ObservableObject,
    Droplet,
    HUDPresenting,
    SettingsPagesProviding,
    ShelfWidgetCompositionProviding,
    MenuBarExtraProviding,
    LiveActivityProviding,
    MCPToolProviding
{
    nonisolated public static let id: DropletID = "aether"
    static let widgetID: ShelfWidgetID = "aether.codes"

    private var host: DropletHost?
    private lazy var fallbackDefaults: UserDefaults = {
        let suite = UserDefaults(suiteName: "app.getdroppy.droplet.aether.preview")!
        AetherPrefs.register(in: suite)
        return suite
    }()

    private var activeModel: AetherAppModel?
    private var modelObservation: AnyCancellable?

    private let notificationBridge = AetherNotificationBridge()
    private let hudBridge = AetherHUDBridge()
    private let shortcutsBridge = AetherShortcutsBridge()

    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    private var lastActivityKey: ActivitySignature?
    private var widgetVisible = false
    private var popoverVisible = false

    private struct ActivitySignature: Equatable {
        enum Kind: Equatable {
            case agent(UUID, String)
            case code(UUID, String)
        }
        let kind: Kind
    }

    var model: AetherAppModel {
        if let activeModel {
            return activeModel
        }
        let preview = AetherAppModel(defaults: fallbackDefaults)
        activeModel = preview
        return preview
    }

    public init() {}

    // MARK: - Droplet Lifecycle

    public func activate(host: DropletHost) throws {
        deactivate()
        self.host = host

        let defaults = host.preferences.userDefaults
        AetherPrefs.register(in: defaults)

        MailOAuth.anchorProvider = {
            AetherWindowAnchorStore.shared.settingsWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        }

        let newModel = AetherAppModel(defaults: defaults)
        configureHooks(on: newModel, host: host)
        activeModel = newModel

        notificationBridge.start(host: host, model: newModel)
        hudBridge.start(host: host, model: newModel)

        modelObservation = newModel.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.updateLiveActivity()
            }
        }

        newModel.start()
        shortcutsBridge.sync(host: host, model: newModel)
        updateLiveActivity()
    }

    public func deactivate() {
        modelObservation?.cancel()
        modelObservation = nil

        lastActivityKey = nil
        activitySubject.send(nil)

        shortcutsBridge.stop()
        notificationBridge.stop()
        hudBridge.stop()

        activeModel?.stop()
        activeModel = nil

        widgetVisible = false
        popoverVisible = false
        host = nil
    }

    // MARK: - SettingsPagesProviding

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "General notifications & auto-copy", keywords: ["banner", "hud", "clipboard", "auto-type", "shortcuts", "sound"]),
            SettingsSearchEntry(title: "Mail & Messages sources", keywords: ["messages", "imessage", "sms", "apple mail", "gmail", "outlook", "icloud", "yahoo", "imap", "oauth"]),
            SettingsSearchEntry(title: "Bitwarden TOTP authenticator", keywords: ["bitwarden", "totp", "bw", "vault", "authenticator"]),
            SettingsSearchEntry(title: "Privacy, Touch ID & history", keywords: ["touch id", "lock", "screen capture", "blur", "clipboard", "history", "icons"]),
            SettingsSearchEntry(title: "AI agents & Droppy MCP", keywords: ["mcp", "claude", "codex", "cursor", "agent", "rules", "log"]),
            SettingsSearchEntry(title: "Recent unmatched emails", keywords: ["recovery", "emails", "unmatched"]),
            SettingsSearchEntry(title: "Ignored senders & false positives", keywords: ["ignore", "sender", "not a code", "filter"]),
        ]
    }

    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(
            AetherSettingsRootPane(droplet: self, model: model)
                .defaultAppStorage(model.defaults)
        )
    }

    public func makeSettingsPage(id: String, context: SettingsPaneContext) -> AnyView? {
        let view: AnyView? = {
            if let editID = AetherSettingsRoute.parseEditAccountID(from: id) {
                return AnyView(AccountEditorSettingsPage(droplet: self, model: model, existingAccountID: editID))
            }
            if let preset = AetherSettingsRoute.parseNewAccountPreset(from: id) {
                return AnyView(AccountEditorSettingsPage(droplet: self, model: model, preset: preset))
            }
            guard let route = AetherSettingsRoute(rawValue: id) else { return nil }
            switch route {
            case .general:
                return AnyView(GeneralSettingsPage(droplet: self, model: model))
            case .sources:
                return AnyView(SourcesSettingsPage(droplet: self, model: model))
            case .privacy:
                return AnyView(PrivacySettingsPage(droplet: self, model: model))
            case .agents:
                return AnyView(AgentsSettingsPage(droplet: self, model: model))
            case .agentRules:
                return AnyView(AgentRulesSettingsPage(model: model))
            case .agentHistory:
                return AnyView(AgentHistorySettingsPage(model: model))
            case .recovery:
                return AnyView(RecoveryEmailsSettingsPage(model: model))
            case .ignoredSenders:
                return AnyView(IgnoredSendersSettingsPage(model: model))
            case .notCodes:
                return AnyView(NotCodesSettingsPage(model: model))
            case .addAccount:
                return AnyView(AddAccountSettingsPage(droplet: self, model: model))
            case .bitwarden:
                return AnyView(BitwardenSettingsPage(droplet: self, model: model))
            }
        }()
        return view.map { AnyView($0.defaultAppStorage(model.defaults)) }
    }

    public func makeSettingsPageToolbar(id: String, context: SettingsPaneContext) -> AnyView? {
        switch AetherSettingsRoute(rawValue: id) {
        case .sources:
            return AnyView(
                DropletSettingsToolbarButton("Add Account", systemImage: "plus") { [weak self] in
                    self?.openSettingsPage(AetherSettingsRoute.addAccount.rawValue, title: "Add mail account")
                }
            )
        case .recovery:
            return AnyView(
                DropletSettingsToolbarButton("Clear", systemImage: "trash") { [weak self] in
                    self?.model.recovery.removeAll()
                }
            )
        case .agentHistory:
            return AnyView(
                DropletSettingsToolbarButton("Clear", systemImage: "trash") { [weak self] in
                    self?.model.agents.clearLog()
                }
            )
        default:
            return nil
        }
    }

    // MARK: - ShelfWidgetCompositionProviding

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "AETHER",
                systemImage: "key.viewfinder",
                layoutTraits: ShelfWidgetLayoutTraits(
                    single: ShelfWidgetModeSize(width: 360, height: .fitting(range: 140...260)),
                    split: ShelfWidgetModeSize(width: 190, height: .fitting(range: 110...180)),
                    header: .standard
                ),
                focusPolicy: .keyboardFocusable,
                searchKeywords: ["otp", "2fa", "verification", "code", "totp", "bitwarden", "mail", "messages", "aether"]
            )
        ]
    }

    public func makeWidgetContent(_ id: ShelfWidgetID, layout: ShelfWidgetLayout) -> AnyView {
        AnyView(
            AetherShelfWidgetView(droplet: self, model: model)
                .defaultAppStorage(model.defaults)
        )
    }

    // MARK: - MenuBarExtraProviding

    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        MenuBarExtraDescriptor(title: "AETHER", systemImage: "key.viewfinder") { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                AetherMenuBarExtraView(droplet: self, model: self.model)
                    .defaultAppStorage(self.model.defaults)
            )
        }
    }

    // MARK: - LiveActivityProviding

    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public func makeCompactLeading(context: CompactLiveActivityContext) -> AnyView {
        if let pending = model.agents.request, pending.item != nil {
            return AnyView(
                Image(systemName: "terminal.fill")
                    .font(.system(size: DroppyLiveActivityMetrics.compactSymbolSize, weight: .semibold))
                    .foregroundStyle(.orange)
            )
        }
        return AnyView(
            Image(systemName: "key.viewfinder")
                .font(.system(size: DroppyLiveActivityMetrics.compactSymbolSize, weight: .semibold))
                .foregroundStyle(.blue)
        )
    }

    public func makeCompactTrailing(context: CompactLiveActivityContext) -> AnyView {
        if let pending = model.agents.request, let item = pending.item {
            let site = item.domain ?? pending.query.label
            return AnyView(
                Text(verbatim: site)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            )
        }
        if model.isUnlocked, let code = activeCodeForLiveActivity {
            let text = model.isOn(AetherPrefs.blurCodes)
                ? "••••••"
                : AetherNotificationBridge.formatCode(code.code)
            return AnyView(
                Text(verbatim: text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
            )
        }
        return AnyView(EmptyView())
    }

    // MARK: - MCPToolProviding

    public var mcpTools: [DropletMCPTool] {
        AetherMCPBridge.tools
    }

    public func performMCPTool(named name: String, argumentsJSON: String) async throws -> String {
        try await AetherMCPBridge.perform(named: name, argumentsJSON: argumentsJSON, model: model)
    }

    // MARK: - Workspace & Navigation Helpers

    @discardableResult
    func openShelfWidget() -> Bool {
        host?.shelf.open(revealing: Self.widgetID) ?? false
    }

    @discardableResult
    func openSettings() -> Bool {
        host?.workspace.openSettings() ?? false
    }

    func openSettingsPage(_ id: String, title: String) {
        _ = host?.workspace.openSettingsPage(id, title: title)
    }

    func goBackInSettings() {
        _ = host?.workspace.goBackInSettings()
    }

    func openAccessibilitySettings() {
        host?.permissions.openSystemSettings(for: .accessibility)
    }

    func openFullDiskAccessSettings() {
        host?.permissions.openSystemSettings(for: .fullDiskAccessProbe)
    }

    func openShortcutsSettings() {
        _ = host?.workspace.openShortcuts()
    }

    func syncShortcuts() {
        guard let host else { return }
        shortcutsBridge.sync(host: host, model: model)
    }

    func copyText(_ text: String) {
        _ = host?.workspace.copyToPasteboard(text)
    }

    func setWidgetVisible(_ visible: Bool) {
        widgetVisible = visible
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
    }

    // MARK: - Private Wiring

    private func configureHooks(on target: AetherAppModel, host: DropletHost) {
        target.hooks.presentBanner = { [weak self, weak target] itemID in
            guard let item = target?.items.first(where: { $0.id == itemID }) else { return }
            self?.notificationBridge.presentCodeNotification(for: item)
        }
        target.hooks.dismissBanner = { [weak self] itemID in
            self?.notificationBridge.withdrawCodeNotification(for: itemID)
        }
        target.hooks.presentHUD = { [weak self] item, userInitiated in
            self?.hudBridge.presentArrivalHUD(for: item, userInitiated: userInitiated)
        }
        target.hooks.playArrivalSound = {
            NSSound(named: "Glass")?.play()
        }
        target.hooks.confirmLink = { title, notice, details, email in
            let message = "\(notice)\n\n\(details)"
            let confirmed = DropletConfirmationDialog.present(
                title: "Open link to \(title)?",
                message: message,
                confirmTitle: "Open Link",
                symbol: "exclamationmark.triangle.fill"
            )
            if !confirmed, let email {
                let openSource = DropletConfirmationDialog.present(
                    title: "Inspect source message instead?",
                    message: "Open the original message in Mail to verify the sender first.",
                    confirmTitle: email.title,
                    symbol: "envelope.fill"
                )
                if openSource {
                    email.run()
                }
            }
            return confirmed
        }
        target.hooks.openURL = { [weak self] url in
            if self?.host?.workspace.open(url) != true {
                NSWorkspace.shared.open(url)
            }
        }
        target.hooks.presentAgentState = { [weak self] presentation in
            self?.notificationBridge.presentAgentState(presentation)
            self?.updateLiveActivity()
        }
        target.hooks.isUIVisible = { [weak self] in
            guard let self else { return false }
            return self.widgetVisible || self.popoverVisible
        }
        target.hooks.appVersion = {
            Bundle(for: AETHERPrincipal.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        }
    }

    private var activeCodeForLiveActivity: CodeItem? {
        guard model.isOn(AetherPrefs.codeInMenuBar), model.isUnlocked, let latest = model.latestCode else {
            return nil
        }
        guard !latest.used, latest.shouldAnnounce(at: model.now) else {
            return nil
        }
        return latest
    }

    private func updateLiveActivity() {
        if let pending = model.agents.request, let item = pending.item {
            let site = item.domain ?? pending.query.label
            let signature = ActivitySignature(kind: .agent(pending.id, site))
            guard lastActivityKey != signature else { return }
            lastActivityKey = signature
            activitySubject.send(
                LiveActivityState(
                    priority: .attention,
                    kind: .custom,
                    accessibilityTitle: "\(pending.caller.name) asks for \(site) code",
                    accessibilityValue: { site },
                    isInteractive: true,
                    joinsPersistentActivitySet: false,
                    expandedWidgetID: Self.widgetID.rawValue
                )
            )
            return
        }

        if let code = activeCodeForLiveActivity {
            let concealed = model.isOn(AetherPrefs.blurCodes)
            let formatted = concealed ? "hidden" : AetherNotificationBridge.formatCode(code.code)
            let signature = ActivitySignature(kind: .code(code.id, formatted))
            guard lastActivityKey != signature else { return }
            lastActivityKey = signature
            activitySubject.send(
                LiveActivityState(
                    priority: .status,
                    kind: .custom,
                    accessibilityTitle: "\(code.service) verification code",
                    accessibilityValue: { formatted },
                    isInteractive: true,
                    joinsPersistentActivitySet: false,
                    expandedWidgetID: Self.widgetID.rawValue
                )
            )
            return
        }

        if lastActivityKey != nil {
            lastActivityKey = nil
            activitySubject.send(nil)
        }
    }
}
