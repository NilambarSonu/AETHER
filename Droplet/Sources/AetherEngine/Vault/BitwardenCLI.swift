// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Darwin
import Foundation

/// Runs official Bitwarden CLI (`bw`) imports strictly on explicit user action with
/// process-group termination on timeout or `Droplet.deactivate()`.
public enum BitwardenCLI {
    public struct Status: Equatable, Sendable {
        public var version: String?
        public var server = "https://bitwarden.com"
        public var email: String?
        public var state = "unauthenticated"

        public var region: Region? { Region.allCases.first { server.contains($0.domain) } }
        public var loggedIn: Bool { state != "unauthenticated" }

        public init(
            version: String? = nil,
            server: String = "https://bitwarden.com",
            email: String? = nil,
            state: String = "unauthenticated"
        ) {
            self.version = version
            self.server = server
            self.email = email
            self.state = state
        }
    }

    public enum Region: String, CaseIterable, Identifiable, Sendable {
        case us = "US"
        case eu = "EU"
        public var id: Self { self }
        public var domain: String { self == .us ? "bitwarden.com" : "bitwarden.eu" }
        public var server: String { "https://vault.\(domain)" }
    }

    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?
        public init(errorDescription: String?) { self.errorDescription = errorDescription }
    }

    private static let activeLock = NSLock()
    private static var activePIDs = Set<pid_t>()

    /// Stops any active `bw` child process groups when AETHER deactivates.
    public static func cancelAllActive() {
        let pids = activeLock.withLock { Array(activePIDs) }
        for pid in pids where pid > 0 {
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)
        }
    }

    public static func status() async -> Status {
        guard let version = try? await run(["--version"]) else { return Status() }
        var status = Status(version: String(decoding: version, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        if let data = try? await run(["status"]), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let server = json["serverUrl"] as? String { status.server = server }
            status.email = json["userEmail"] as? String
            status.state = json["status"] as? String ?? status.state
        }
        return status
    }

    public static func setServer(_ region: Region) async throws {
        _ = try await run(["config", "server", region.server])
    }

    public static func importCodes(password: String, session pasted: String) async throws -> (codes: [VaultCode], unreadable: [String]) {
        var session = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasLocked = await status().state != "unlocked"
        if session.isEmpty {
            let raw = try await run(["unlock", "--passwordenv", "AETHER_BW_PASSWORD", "--raw"], env: ["AETHER_BW_PASSWORD": password])
            session = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let unlockedHere = pasted.isEmpty && wasLocked
        do {
            _ = try await run(["sync"], env: ["BW_SESSION": session])
            let items = try await run(["list", "items"], env: ["BW_SESSION": session], timeout: 120)
            if unlockedHere { _ = try? await run(["lock"]) }
            return try VaultCode.fromBitwarden(items)
        } catch {
            if unlockedHere { _ = try? await run(["lock"]) }
            throw error
        }
    }

    private static let resolvedPath: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        guard let out = try? executeSync(shell, ["-l", "-c", "printf %s \"$PATH\""], env: [:], timeout: 8),
            out.status == 0, !out.stdout.isEmpty
        else { return fallback }
        return String(decoding: out.stdout, as: UTF8.self) + ":" + fallback
    }()

    private static func run(_ args: [String], env: [String: String] = [:], timeout: TimeInterval = 60) async throws -> Data {
        try await withTaskCancellationHandler {
            try await Task.detached {
                let out = try executeSync(
                    "/usr/bin/env",
                    ["bw"] + args + ["--nointeraction"],
                    env: env.merging(["PATH": resolvedPath]) { $1 },
                    timeout: timeout
                )
                try Task.checkCancellation()
                guard out.status == 0 else {
                    let message =
                        String(decoding: out.stderr.isEmpty ? out.stdout : out.stderr, as: UTF8.self)
                        .split(separator: "\n").first.map(String.init) ?? "Bitwarden CLI stopped with error \(out.status)"
                    throw Failure(errorDescription: out.status == 127 ? "Bitwarden CLI not found" : message)
                }
                return out.stdout
            }.value
        } onCancel: {
            cancelAllActive()
        }
    }

    private static func executeSync(
        _ tool: String,
        _ args: [String],
        env: [String: String],
        timeout: TimeInterval
    ) throws -> (status: Int32, stdout: Data, stderr: Data) {
        // droppykit-lint: allow process: User-initiated Bitwarden bw CLI TOTP import with process-group deadline, pipe draining, and deactivate cancellation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        let stdout = Pipe()
        let stderr = Pipe()
        (process.standardOutput, process.standardError, process.standardInput) = (stdout, stderr, FileHandle.nullDevice)

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exitSemaphore.signal() }

        try process.run()
        let pid = process.processIdentifier
        _ = setpgid(pid, pid)
        activeLock.withLock { _ = activePIDs.insert(pid) }
        defer { activeLock.withLock { _ = activePIDs.remove(pid) } }

        let deadline = DispatchWorkItem {
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        var errData = Data()
        let drained = DispatchGroup()
        DispatchQueue.global().async(group: drained) { errData = stderr.fileHandleForReading.readDataToEndOfFile() }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        exitSemaphore.wait()
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus, outData, errData)
    }
}
