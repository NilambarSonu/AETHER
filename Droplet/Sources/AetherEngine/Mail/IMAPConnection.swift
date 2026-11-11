// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation
import Network

public enum IMAPError: LocalizedError, Sendable {
    case closed, timeout, invalidPort, invalidCredentials, invalidResponse, noPassword
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .closed: "The mail server closed the connection"
        case .timeout: "Server stopped responding"
        case .invalidPort: "The IMAP port must be between 1 and 65535"
        case .invalidCredentials: "The email or password has a character that can't be sent. Type it again."
        case .invalidResponse: "The mail server sent a reply AETHER can't read. It will try again."
        case .noPassword: "No app password saved"
        case .rejected: "The mail server rejected the request"
        }
    }
}

public protocol MailConnection: Sendable {
    var capabilities: Set<String> { get async }
    func openInbox(_ account: MailAccount, secrets: AetherSecretStore) async throws -> [IMAPConnection.Response]
    func search(_ criteria: String) async throws -> [Int]
    func fetch(_ uids: [Int], account: MailAccount) async throws -> [IncomingMessage]
    func idle(renewAfter: TimeInterval) async throws
    func command(_ cmd: String, timeout: TimeInterval) async throws -> [IMAPConnection.Response]
    func close() async
}

public actor IMAPConnection: MailConnection {
    public struct Response: Sendable {
        public var text: String
        public var literals: [Data]

        public init(text: String, literals: [Data]) {
            self.text = text
            self.literals = literals
        }

        public static func literalSize(in line: String) throws -> Int? {
            guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
            guard let count = Int(line[line.index(after: open)..<line.index(before: line.endIndex)]),
                (0...IncomingMessage.mailReadLimit).contains(count)
            else { throw IMAPError.invalidResponse }
            return count
        }

        public func number(after marker: String) -> Int? {
            guard let r = text.range(of: marker) else { return nil }
            return Int(text[r.upperBound...].prefix(while: \.isNumber))
        }
    }

    private let connection: NWConnection
    private var buffer = Data()
    private var pendingExists = false
    private var tag = 0
    public private(set) var capabilities: Set<String> = []
    public var uidValidity: Int?
    private var timedOut = false

    public init(host: String, port: Int) throws {
        guard (1...65535).contains(port) else { throw IMAPError.invalidPort }
        connection = NWConnection(host: .init(host), port: .init(integerLiteral: UInt16(port)), using: .tls)
    }

    public init(connection: NWConnection) { self.connection = connection }

    public init(account: MailAccount) throws {
        try self.init(host: account.host, port: account.port)
    }

    public func open(user: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = AetherOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { cont.resume() }
                case .failed(let e), .waiting(let e): once.run { cont.resume(throwing: e) }
                case .cancelled: once.run { cont.resume(throwing: IMAPError.closed) }
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "app.getdroppy.droplet.aether.imap"))
        }
        _ = try await withTimeout(20) { try await self.readResponse() }
        _ = try await command("LOGIN \(quote(user)) \(quote(password))")
        let caps = try await command("CAPABILITY")
        capabilities = Set(caps.flatMap { $0.text.uppercased().split(separator: " ").map(String.init) })
    }

    public func close() { connection.cancel() }

    @discardableResult
    public func openInbox(_ account: MailAccount, secrets: AetherSecretStore = .keychain) async throws -> [Response] {
        guard let password = account.password(in: secrets) else { throw IMAPError.noPassword }
        try await open(user: account.user, password: password)
        let response = try await command("EXAMINE INBOX")
        uidValidity = response.lazy.compactMap { $0.number(after: "UIDVALIDITY ") }.first
        return response
    }

    public func search(_ criteria: String) async throws -> [Int] {
        try await command("UID SEARCH \(criteria)").flatMap { r in
            r.text.hasPrefix("* SEARCH") ? r.text.split(separator: " ").dropFirst(2).compactMap { Int($0) } : []
        }
    }

    public func fetch(_ uids: [Int], account: MailAccount) async throws -> [IncomingMessage] {
        guard !uids.isEmpty else { return [] }
        let set = uids.map(String.init).joined(separator: ",")
        let internalDate = DateFormatter()
        internalDate.locale = Locale(identifier: "en_US_POSIX")
        internalDate.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return try await command("UID FETCH \(set) (UID INTERNALDATE BODY.PEEK[]<0.\(IncomingMessage.mailReadLimit)>)", timeout: 90).compactMap { r in
            guard let raw = r.literals.first, let q = r.text.range(of: "INTERNALDATE \"") else { return nil }
            let dateText = r.text[q.upperBound...].prefix(while: { $0 != "\"" }).trimmingCharacters(in: .whitespaces)
            return IncomingMessage(
                mail: raw,
                account: account,
                date: internalDate.date(from: dateText),
                messageID: r.number(after: "UID ").map { "\(uidValidity ?? 0):\($0)" }
            )
        }
    }

    @discardableResult
    public func command(_ cmd: String, timeout: TimeInterval = 30) async throws -> [Response] {
        tag += 1
        let t = "C\(tag)"
        try await send("\(t) \(cmd)\r\n")
        return try await withTimeout(timeout) { try await self.readUntilTagged(t) }
    }

    public func idle(renewAfter: TimeInterval = 240) async throws {
        tag += 1
        let t = "C\(tag)"
        if pendingExists {
            pendingExists = false
            return
        }
        try await send("\(t) IDLE\r\n")
        while !(try await withTimeout(30, { try await self.readResponse() }).text.hasPrefix("+")) {}
        let renew = Task { [weak self] in
            try await Task.sleep(for: .seconds(renewAfter))
            try await self?.send("DONE\r\n")
            try await Task.sleep(for: .seconds(30))
            await self?.expire()
        }
        defer { renew.cancel() }
        while true {
            if pendingExists {
                pendingExists = false
                renew.cancel()
                try await send("DONE\r\n")
                _ = try await withTimeout(30) { try await self.readUntilTagged(t) }
                return
            }
            let r = try await readResponse()
            if r.text.hasPrefix(t + " ") { return }
        }
    }

    public func wakeIdle() async {
        pendingExists = true
        try? await send("DONE\r\n")
    }

    private func readUntilTagged(_ t: String) async throws -> [Response] {
        var out: [Response] = []
        var bytes = 0
        while true {
            let r = try await readResponse()
            if r.text.hasPrefix(t + " ") {
                guard r.text.dropFirst(t.count + 1).hasPrefix("OK") else { throw IMAPError.rejected(r.text) }
                return out
            }
            bytes += r.text.utf8.count + r.literals.reduce(0) { $0 + $1.count }
            guard out.count < 1_000, bytes <= 128 * 1024 * 1024 else { throw IMAPError.invalidResponse }
            out.append(r)
        }
    }

    private func readResponse() async throws -> Response {
        var r = Response(text: "", literals: [])
        while true {
            let line = String(decoding: try await readLine(), as: UTF8.self)
            r.text += line
            guard r.text.utf8.count + r.literals.reduce(0, { $0 + $1.count }) <= 1_048_576 else { throw IMAPError.invalidResponse }
            if line.hasPrefix("* "), line.hasSuffix(" EXISTS") { pendingExists = true }
            guard let n = try Response.literalSize(in: line) else { return r }
            r.literals.append(try await read(count: n))
        }
    }

    private func readLine() async throws -> Data {
        while true {
            if let i = buffer.firstRange(of: Data("\r\n".utf8)) {
                guard i.lowerBound - buffer.startIndex <= 1_048_576 else { throw IMAPError.invalidResponse }
                let line = buffer[buffer.startIndex..<i.lowerBound]
                buffer = Data(buffer[i.upperBound...])
                return Data(line)
            }
            guard buffer.count <= 1_048_576 else { throw IMAPError.invalidResponse }
            try await fill()
        }
    }

    private func read(count: Int) async throws -> Data {
        while buffer.count < count { try await fill() }
        let out = buffer.prefix(count)
        buffer = Data(buffer.dropFirst(count))
        return Data(out)
    }

    private func fill() async throws {
        let data: Data = try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, complete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if complete {
                    cont.resume(throwing: IMAPError.closed)
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
        buffer.append(data)
    }

    private func send(_ s: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(s.utf8),
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }
    }

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: .seconds(seconds))
            await self?.expire()
        }
        defer { watchdog.cancel() }
        do { return try await body() } catch { throw timedOut ? IMAPError.timeout : error }
    }

    private func expire() {
        timedOut = true
        close()
    }

    private func quote(_ s: String) throws -> String {
        guard !s.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 }) else { throw IMAPError.invalidCredentials }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
