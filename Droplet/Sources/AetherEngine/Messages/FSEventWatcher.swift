// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CoreServices
import Foundation

/// Monitors a directory path via CoreServices `FSEventStreamRef` for WAL/DB transaction updates.
public final class FSEventWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let queue: DispatchQueue
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var isRunning = false

    public init(paths: [String], latency: TimeInterval = 0.2, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.latency = latency
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() -> Bool {
        lock.withLock {
            guard !isRunning else { return true }
            let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.onChange()
            }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let cfPaths = paths as CFArray
            let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

            guard let s = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                cfPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else { return false }

            FSEventStreamSetDispatchQueue(s, queue)
            guard FSEventStreamStart(s) else {
                FSEventStreamInvalidate(s)
                FSEventStreamRelease(s)
                return false
            }

            self.stream = s
            self.isRunning = true
            return true
        }
    }

    public func stop() {
        let streamToRelease: FSEventStreamRef? = lock.withLock {
            guard isRunning, let s = stream else { return nil }
            isRunning = false
            stream = nil
            return s
        }

        if let s = streamToRelease {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
