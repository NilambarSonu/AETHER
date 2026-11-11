// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import CodeCatchCore
import Combine

/// Opt-in service logo cache via Google/DuckDuckGo proxies (disabled by default for privacy).
@MainActor
public final class AetherIconStore: ObservableObject {
    public struct Icon {
        public let image: NSImage
        public let fullBleed: Bool

        public init(_ image: NSImage) {
            let tile = image.aetherTile
            self.image = tile ?? image
            fullBleed = tile != nil
        }
    }

    @Published private var icons: [String: Icon] = [:]
    private var requested: Set<String> = []
    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    private let defaults: UserDefaults
    private let secrets: AetherSecretStore
    private let folder: URL
    private let fetch: (URL) async throws -> (Data, URLResponse)

    public init(
        defaults: UserDefaults,
        secrets: AetherSecretStore = .keychain,
        folder: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AETHER/Icons", isDirectory: true),
        fetch: ((URL) async throws -> (Data, URLResponse))? = nil
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.folder = folder
        self.fetch = fetch ?? AetherIconStore.download
    }

    public func stop() {
        for task in inFlightTasks.values { task.cancel() }
        inFlightTasks.removeAll()
        requested.removeAll()
    }

    public func prefetch(domain: String?) {
        _ = icon(for: domain)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: IconProxyRedirects(), delegateQueue: nil)
    }()

    public func icon(for domain: String?) -> Icon? {
        guard let domain, defaults.bool(forKey: AetherPrefs.serviceIcons), ServiceIdentity.isHostname(domain) else { return nil }
        if let hit = icons[domain] { return hit }
        if requested.insert(domain).inserted {
            inFlightTasks[domain] = Task { [weak self] in
                await self?.load(domain)
                self?.inFlightTasks.removeValue(forKey: domain)
            }
        }
        return nil
    }

    public func load(_ domain: String) async {
        defer { if !defaults.bool(forKey: AetherPrefs.serviceIcons) { requested.remove(domain) } }
        guard defaults.bool(forKey: AetherPrefs.serviceIcons), ServiceIdentity.isHostname(domain) else { return }
        let stem = (try? AetherVaultCrypto.hmacHex(domain, domain: .iconCacheSalt, recordKey: "icons.v2", using: secrets)) ?? domain
        let touch = folder.appendingPathComponent("\(stem).touch.png")
        let plain = folder.appendingPathComponent("\(stem).png")
        let miss = folder.appendingPathComponent("\(stem).miss")
        for url in [touch, plain] {
            if let image = NSImage(contentsOf: url) {
                icons[domain] = Icon(image)
                return
            }
        }
        if let date = (try? miss.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
            date.timeIntervalSinceNow > -7 * 86400
        {
            return
        }

        var best: NSImage?
        var definite = true
        for url in Self.proxies(for: domain) {
            guard defaults.bool(forKey: AetherPrefs.serviceIcons), !Task.isCancelled else { return }
            guard let reply = try? await fetch(url), let http = reply.1 as? HTTPURLResponse,
                Self.isIconProxyURL(http.url), [200, 404].contains(http.statusCode)
            else {
                definite = false
                continue
            }
            guard http.statusCode == 200, let image = Self.usable(reply.0) else { continue }
            if image.aetherPixels > best?.aetherPixels ?? 0 { best = image }
            if image.aetherPixels >= 32 { break }
        }
        guard defaults.bool(forKey: AetherPrefs.serviceIcons), !Task.isCancelled else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let best, let png = best.aetherPngData else {
            if definite { FileManager.default.createFile(atPath: miss.path, contents: nil) }
            return
        }
        try? png.write(to: plain)
        icons[domain] = Icon(best)
    }

    private static func proxies(for domain: String) -> [URL] {
        var google = URLComponents(string: "https://www.google.com/s2/favicons")!
        google.queryItems = [.init(name: "domain", value: domain), .init(name: "sz", value: "128")]
        return [google.url!, URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")!]
    }

    private static func usable(_ data: Data) -> NSImage? {
        guard let image = NSImage(data: data),
            (1...2048).contains(image.size.width), (1...2048).contains(image.size.height), image.aetherPixels >= 16,
            image.representations.allSatisfy({ $0.pixelsWide <= 2048 && $0.pixelsHigh <= 2048 })
        else { return nil }
        return image
    }

    public nonisolated static func isIconProxyURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
            url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        return (host == "www.google.com" && url.path == "/s2/favicons")
            || (["t0.gstatic.com", "t1.gstatic.com", "t2.gstatic.com", "t3.gstatic.com"].contains(host) && url.path == "/faviconV2")
            || (host == "icons.duckduckgo.com" && url.path.hasPrefix("/ip3/") && url.path.hasSuffix(".ico")
                && ServiceIdentity.isHostname(String(url.path.dropFirst(5).dropLast(4))))
    }

    private nonisolated static func download(_ url: URL) async throws -> (Data, URLResponse) {
        let limit = 1_048_576
        let (bytes, response) = try await session.bytes(from: url)
        guard response.expectedContentLength <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class IconProxyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        AetherIconStore.isIconProxyURL(request.url) ? request : nil
    }
}

extension NSImage {
    fileprivate var aetherTile: NSImage? {
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = image.width
        let h = image.height
        var alpha = [UInt8](repeating: 0, count: w * h)
        let drawn = alpha.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ).map { $0.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)) } != nil
        }
        guard drawn else { return nil }
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        var opaque = 0
        for y in 0..<h {
            for x in 0..<w where alpha[y * w + x] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                opaque += 1
            }
        }
        let side = (w: maxX - minX + 1, h: maxY - minY + 1)
        guard maxX >= 0, side.w >= 2, abs(Double(side.w) / Double(side.h) - 1) < 0.04, Double(opaque) / Double(side.w * side.h) > 0.9,
            let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: side.w, height: side.h))
        else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: side.w, height: side.h))
    }

    fileprivate var aetherPixels: Int { representations.map(\.pixelsWide).max() ?? 0 }

    fileprivate var aetherPngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
