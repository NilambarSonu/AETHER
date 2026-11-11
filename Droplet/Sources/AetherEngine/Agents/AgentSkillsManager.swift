// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Darwin
import Foundation

/// Writes an `aether-otp` skill into installed AI coding agent directories (Claude Code, Codex, Cursor)
/// pointing them at Droppy's native MCP tools (`droplet_aether_get_code`, `droplet_aether_status`).
public enum AgentSkillKind: CaseIterable, Identifiable, Sendable {
    case claudeCode, codex, cursor

    public var id: Self { self }

    public var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    public var domain: String {
        switch self {
        case .claudeCode: "claude.ai"
        case .codex: "openai.com"
        case .cursor: "cursor.com"
        }
    }

    private var folder: String {
        switch self {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        case .cursor: ".cursor"
        }
    }

    public func isInstalled(home: URL) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(folder).path)
    }

    public func file(home: URL) -> URL {
        home.appendingPathComponent("\(folder)/skills/aether-otp/SKILL.md")
    }

    public enum State: Equatable, Sendable {
        case notConnected
        case connected
        case connectedThrough(AgentSkillKind)
        case taken
    }

    private func inherited(home: URL) -> AgentSkillKind? {
        guard self == .cursor else { return nil }
        return [.claudeCode, .codex].first { Self.owner($0.file(home: home)) == .ours }
    }

    public func state(home: URL) -> State {
        if let other = inherited(home: home) { return .connectedThrough(other) }
        switch Self.owner(file(home: home)) {
        case .ours: return .connected
        case .foreign: return .taken
        case nil: return .notConnected
        }
    }

    public func connect(home: URL, guidance: String = defaultGuidance) throws {
        let url = file(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard Self.write(Self.skill(guidance), to: url) else {
            throw Failure(errorDescription: "\(name) already has an aether-otp skill that AETHER didn't write.")
        }
        if self != .cursor { try? AgentSkillKind.cursor.disconnect(home: home) }
    }

    public func disconnect(home: URL) throws {
        let url = file(home: home)
        guard Self.removeOurs(url) else { return }
        rmdir(url.deletingLastPathComponent().path)
    }

    public static func refresh(home: URL, guidance: String = defaultGuidance) {
        for agent in allCases where owner(agent.file(home: home)) == .ours {
            try? agent.connect(home: home, guidance: guidance)
        }
    }

    public static let defaultGuidance = """
        When a site I asked you to sign in to needs a 2FA verification code or sign-in link, use the Droppy MCP tool `droplet_aether_get_code` with `{"site": "<domain>"}` (and optionally `since` UNIX timestamp captured before triggering the code).

        A request may ask for my Touch ID approval in Droppy first, so wait up to ~55 seconds cleanly. If AETHER denies a code or says no, do not ask again unless I ask you to retry.
        """

    public static let instructionsMarkdown = "## 2FA Codes (AETHER via Droppy MCP)\n\n" + defaultGuidance

    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?
        public init(errorDescription: String?) { self.errorDescription = errorDescription }
    }

    private static let marker = "<!-- Written by AETHER Droplet. Settings → Agents → Disconnect removes it. -->"

    public static func skill(_ guidance: String) -> String {
        """
        ---
        name: aether-otp
        description: Get a 2FA verification code or sign-in link from the user's Mac through Droppy AETHER MCP tools when signing in.
        ---
        \(marker)

        \(guidance)

        """
    }

    private enum Owner { case ours, foreign }

    private static func owner(_ url: URL) -> Owner? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return errno == ENOENT ? nil : .foreign }
        defer { close(fd) }
        return isOurs(fd) ? .ours : .foreign
    }

    private static func isOurs(_ fd: Int32) -> Bool { ownContent(fd) != nil }

    private static func ownContent(_ fd: Int32) -> [UInt8]? {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size < 64 * 1024 else { return nil }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).contains(marker) ? Array(data) : nil
    }

    private static func write(_ text: String, to url: URL) -> Bool {
        var fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        var old: [UInt8]?
        if fd < 0 {
            guard errno == EEXIST else { return false }
            fd = open(url.path, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { return false }
            old = ownContent(fd)
            guard old != nil else {
                close(fd)
                return false
            }
        }
        defer { close(fd) }
        func replace(with bytes: [UInt8]) -> Bool {
            var offset = 0
            while offset < bytes.count {
                let n = bytes.withUnsafeBytes { pwrite(fd, $0.baseAddress! + offset, bytes.count - offset, off_t(offset)) }
                guard n > 0 else { return false }
                offset += n
            }
            return ftruncate(fd, off_t(bytes.count)) == 0
        }
        if replace(with: Array(text.utf8)) { return true }
        if let old { _ = replace(with: old) }
        return false
    }

    private static func removeOurs(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var opened = stat()
        var moved = stat()
        guard isOurs(fd), fstat(fd, &opened) == 0 else { return false }
        let aside = url.deletingLastPathComponent().appendingPathComponent(".aether-\(UUID().uuidString)").path
        guard renamex_np(url.path, aside, UInt32(RENAME_EXCL)) == 0 else { return false }
        if lstat(aside, &moved) == 0, moved.st_dev == opened.st_dev, moved.st_ino == opened.st_ino { return unlink(aside) == 0 }
        renamex_np(aside, url.path, UInt32(RENAME_EXCL))
        return false
    }
}
