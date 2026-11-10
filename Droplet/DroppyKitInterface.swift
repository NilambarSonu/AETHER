import Combine
import Foundation
import SwiftUI

// Exact DroppyKit ABI 1 Declarations

@objc public protocol DropletPrincipal: NSObjectProtocol {
    @MainActor func makeDroplet() -> AnyObject
}

public struct DropletID: RawRepresentable, ExpressibleByStringLiteral, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public init(_ value: String) { self.rawValue = value }
}

@MainActor
public protocol Droplet: AnyObject {
    nonisolated static var id: DropletID { get }
    func activate(host: DropletHost) throws
    func deactivate()
}

@MainActor public protocol DropletHUDService: AnyObject, Sendable {
    @discardableResult
    func present(_ request: DropletHUDRequest) -> Bool
    func dismiss(id: String)
}

@MainActor public protocol DropletWorkspaceService: AnyObject, Sendable {
    @discardableResult
    func open(_ url: URL) -> Bool
    func revealInFinder(_ url: URL)
    @discardableResult
    func copyToPasteboard(_ text: String) -> Bool
    @discardableResult
    func openSettings() -> Bool
    @discardableResult
    func openShortcuts() -> Bool
    @discardableResult
    func openSettingsPage(_ id: String, title: String) -> Bool
    @discardableResult
    func goBackInSettings() -> Bool
}

public enum DropletLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

@MainActor public protocol DropletLogService: AnyObject, Sendable {
    func log(_ level: DropletLogLevel, _ message: String)
}

extension DropletLogService {
    public func debug(_ message: String) { log(.debug, message) }
    public func info(_ message: String) { log(.info, message) }
    public func notice(_ message: String) { log(.notice, message) }
    public func error(_ message: String) { log(.error, message) }
}

public struct DropletHost: Sendable {
    public let hud: DropletHUDService
    public let workspace: DropletWorkspaceService
    public let log: DropletLogService

    public init(
        hud: DropletHUDService,
        workspace: DropletWorkspaceService,
        log: DropletLogService
    ) {
        self.hud = hud
        self.workspace = workspace
        self.log = log
    }
}

public enum DropletHUDPriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    public static func < (lhs: DropletHUDPriority, rhs: DropletHUDPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DropletHUDAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let isPrimary: Bool
    public let perform: @MainActor @Sendable () -> Void

    public init(
        id: String? = nil,
        title: String,
        isPrimary: Bool = false,
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.isPrimary = isPrimary
        self.perform = perform
    }
}

public struct DropletHUDCard: Sendable {
    public let title: String
    public let message: String?
    public let systemImage: String?
    public let tint: Color?
    public let progress: Double?
    public let actions: [DropletHUDAction]

    public init(
        title: String,
        message: String? = nil,
        systemImage: String? = nil,
        tint: Color? = nil,
        progress: Double? = nil,
        actions: [DropletHUDAction] = []
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.progress = progress
        self.actions = actions
    }
}

public struct DropletHUDStrip: Sendable {
    public let makeLeading: @MainActor @Sendable () -> AnyView
    public let makeTrailing: @MainActor @Sendable () -> AnyView

    public init(
        @ViewBuilder leading: @escaping @MainActor @Sendable () -> some View,
        @ViewBuilder trailing: @escaping @MainActor @Sendable () -> some View
    ) {
        self.makeLeading = { AnyView(leading()) }
        self.makeTrailing = { AnyView(trailing()) }
    }
}

public struct DropletHUDRequest: Sendable {
    public let id: String
    public let duration: TimeInterval?
    public let priority: DropletHUDPriority
    public let accessibilityLabel: String
    public let makeContent: @MainActor @Sendable () -> AnyView
    public let makeExpandedContent: (@MainActor @Sendable () -> AnyView)?
    public let isExpanded: Bool
    public let expandedContentHeight: CGFloat?
    public let strip: DropletHUDStrip?
    public let card: DropletHUDCard?

    public init<A: View>(
        id: String,
        duration: TimeInterval? = 2.0,
        priority: DropletHUDPriority = .normal,
        accessibilityLabel: String,
        @ViewBuilder content: @escaping @MainActor @Sendable () -> A
    ) {
        self.id = id
        self.duration = duration
        self.priority = priority
        self.accessibilityLabel = accessibilityLabel
        self.makeContent = { AnyView(content()) }
        self.makeExpandedContent = nil
        self.isExpanded = false
        self.expandedContentHeight = nil
        self.strip = nil
        self.card = nil
    }

    public init<A: View, B: View>(
        id: String,
        duration: TimeInterval? = 2.0,
        priority: DropletHUDPriority = .normal,
        accessibilityLabel: String,
        isExpanded: Bool,
        expandedContentHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping @MainActor @Sendable () -> A,
        @ViewBuilder expanded: @escaping @MainActor @Sendable () -> B
    ) {
        self.id = id
        self.duration = duration
        self.priority = priority
        self.accessibilityLabel = accessibilityLabel
        self.makeContent = { AnyView(content()) }
        self.makeExpandedContent = { AnyView(expanded()) }
        self.isExpanded = isExpanded
        self.expandedContentHeight = expandedContentHeight
        self.strip = nil
        self.card = nil
    }

    public init<A: View, B: View>(
        id: String,
        duration: TimeInterval? = 4.0,
        priority: DropletHUDPriority = .normal,
        accessibilityLabel: String,
        card: DropletHUDCard,
        isExpanded: Bool,
        @ViewBuilder leading: @escaping @MainActor @Sendable () -> A,
        @ViewBuilder trailing: @escaping @MainActor @Sendable () -> B
    ) {
        self.id = id
        self.duration = duration
        self.priority = priority
        self.accessibilityLabel = accessibilityLabel
        let s = DropletHUDStrip(leading: leading, trailing: trailing)
        self.strip = s
        self.card = card
        self.isExpanded = isExpanded
        self.expandedContentHeight = nil
        self.makeContent = s.makeLeading
        self.makeExpandedContent = nil
    }
}
