import Darwin
import Foundation

/// Manages filesystem boundaries, permissions, exclusive file locks, and inode-verified cleanup for the Unix Domain Socket.
public final class AetherSocketEndpoint: @unchecked Sendable {
    public static let maxPathLength: Int = 103  // 104 bytes in sockaddr_un.sun_path minus null terminator

    public let socketPath: String
    public let lockPath: String

    private(set) public var listeningFD: Int32 = -1
    private(set) public var lockFD: Int32 = -1
    private(set) public var boundInode: ino_t = 0
    private(set) public var boundDev: dev_t = 0
    private(set) public var lockInode: ino_t = 0
    private(set) public var lockDev: dev_t = 0
    private let stateLock = NSLock()

    public init(socketPath: String? = nil) {
        if let socketPath {
            self.socketPath = socketPath
            self.lockPath = socketPath + ".lock"
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.socketPath = appSupport.appendingPathComponent("Aether/droplet.sock").path
            self.lockPath = appSupport.appendingPathComponent("Aether/droplet.sock.lock").path
        }
    }

    /// Verifies and creates the parent directory with mode 0700 (rwx------), rejecting symlinks and mismatched ownership.
    public static func validateAndCreateParentDirectory(_ path: String) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        var st = stat()
        guard lstat(path, &st) == 0 else {
            throw AetherTransportError.parentDirectoryInsecure("Cannot lstat directory")
        }

        // Must be a directory, NOT a symlink
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            if (st.st_mode & S_IFMT) == S_IFLNK {
                throw AetherTransportError.parentDirectoryIsSymlink
            }
            throw AetherTransportError.parentDirectoryInsecure("Path is not a directory")
        }

        // Must be owned by current user
        guard st.st_uid == getuid() else {
            throw AetherTransportError.parentDirectoryNotOwnedByUser
        }

        // Enforce permissions 0700
        let currentPerms = st.st_mode & 0o777
        if currentPerms != 0o700 {
            chmod(path, 0o700)
        }
    }

    /// Binds and listens on the Unix domain socket after acquiring exclusive lock and validating filesystem security.
    public func bindAndListen(backlog: Int32 = 4) throws -> Int32 {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard listeningFD < 0 else { return listeningFD }

        // 1. Verify path length for sun_path
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count <= Self.maxPathLength else {
            throw AetherTransportError.socketPathTooLong(pathBytes.count)
        }

        // 2. Validate and secure parent directory
        let parentDir = (socketPath as NSString).deletingLastPathComponent
        try Self.validateAndCreateParentDirectory(parentDir)

        // 3. Acquire exclusive non-blocking lock on lockPath
        let lock = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else {
            throw AetherTransportError.lockAcquisitionFailed(errno)
        }

        var lockStat = stat()
        guard fstat(lock, &lockStat) == 0,
            (lockStat.st_mode & S_IFMT) == S_IFREG,
            lockStat.st_uid == getuid()
        else {
            close(lock)
            throw AetherTransportError.lockAcquisitionFailed(errno)
        }

        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock)
            throw AetherTransportError.anotherHostInstanceRunning
        }
        self.lockFD = lock
        self.lockInode = lockStat.st_ino
        self.lockDev = lockStat.st_dev

        // 4. Stale socket cleanup with lock held: check path type before unlinking
        var existingStat = stat()
        if lstat(socketPath, &existingStat) == 0 {
            // Only unlink if it's genuinely a socket
            guard (existingStat.st_mode & S_IFMT) == S_IFSOCK else {
                throw AetherTransportError.parentDirectoryInsecure("Existing non-socket file at socket path: \(socketPath)")
            }
            unlink(socketPath)
        }

        // 5. Create AF_UNIX SOCK_STREAM socket
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            closeLock()
            throw AetherTransportError.socketBindFailed(errno)
        }

        // Disable SIGPIPE
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking mode
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // 6. Bind to address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0  // null-terminate
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let err = errno
            Darwin.close(fd)
            closeLock()
            throw AetherTransportError.socketBindFailed(err)
        }

        // Set socket permissions to 0600
        chmod(socketPath, 0o600)

        // Record inode and dev for safe cleanup
        var boundStat = stat()
        if lstat(socketPath, &boundStat) == 0 {
            self.boundInode = boundStat.st_ino
            self.boundDev = boundStat.st_dev
        }

        // 7. Listen for incoming connections
        guard Darwin.listen(fd, backlog) == 0 else {
            let err = errno
            Darwin.close(fd)
            unlink(socketPath)
            closeLock()
            throw AetherTransportError.socketListenFailed(err)
        }

        self.listeningFD = fd
        return fd
    }

    /// Safely tears down the listening socket, verifying inode before unlinking.
    public func closeAndCleanup() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if listeningFD >= 0 {
            Darwin.close(listeningFD)
            listeningFD = -1
        }

        // Inode-verified socket unlinking
        if boundInode != 0 {
            var currentStat = stat()
            if lstat(socketPath, &currentStat) == 0 {
                if currentStat.st_ino == boundInode && currentStat.st_dev == boundDev {
                    unlink(socketPath)
                }
            }
            boundInode = 0
            boundDev = 0
        }

        closeLock()
    }

    private func closeLock() {
        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            Darwin.close(lockFD)
            if lockInode != 0 {
                var check = stat()
                if lstat(lockPath, &check) == 0 && check.st_ino == lockInode && check.st_dev == lockDev {
                    unlink(lockPath)
                }
                lockInode = 0
                lockDev = 0
            } else {
                unlink(lockPath)
            }
            lockFD = -1
        }
    }

    deinit {
        closeAndCleanup()
    }
}
