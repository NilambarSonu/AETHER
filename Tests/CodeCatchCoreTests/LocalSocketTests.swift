import Darwin
import Foundation
import Testing

@testable import CodeCatchCore

/// A client that stops reading must not hold the app's writer: `send` gives up at its deadline,
/// even with a reply far larger than the socket buffer.
@Test func sendGivesUpWhenTheReaderStopsReading() throws {
    var fds: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    defer {
        close(fds[0])
        close(fds[1])
    }
    _ = fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK)
    let started = ContinuousClock.now
    #expect(!LocalSocket.send(String(repeating: "x", count: 4 << 20), to: fds[0], within: 0.3))
    #expect(ContinuousClock.now - started < .seconds(2))
}

/// The app reads requests with a short socket timeout and a longer deadline: a client that pauses
/// longer than the timeout, but within the deadline, must still be heard.
@Test func readLineWaitsOutSocketTimeoutsUntilItsDeadline() throws {
    var fds: [Int32] = [0, 0]
    try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    defer {
        close(fds[0])
        close(fds[1])
    }
    var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
    try #require(setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
    let writer = fds[1]
    let started = DispatchSemaphore(value: 0)
    let cancelPause = DispatchSemaphore(value: 0)
    let wrote = DispatchSemaphore(value: 0)

    // Schedule the simulated client pause on a dedicated high-QoS thread rather than
    // DispatchQueue.global() so heavy parallel test load cannot starve the write past `within: 2`.
    let thread = Thread {
        started.signal()
        if cancelPause.wait(timeout: .now() + .milliseconds(250)) == .timedOut {
            let payload = Array("hello\n".utf8)
            var sent = 0
            while sent < payload.count {
                let n = payload.withUnsafeBytes { raw in
                    write(writer, raw.baseAddress! + sent, payload.count - sent)
                }
                if n > 0 {
                    sent += n
                } else if errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
        wrote.signal()
    }
    thread.name = "LocalSocketTests.delayedWriter"
    thread.qualityOfService = .userInteractive
    thread.start()

    // Wait until the writer thread is running before starting the 2-second deadline, and join it
    // before `fds[1]` closes so a delayed write can never target a reused descriptor.
    started.wait()
    defer {
        cancelPause.signal()
        wrote.wait()
    }
    var buffer = Data()
    #expect(LocalSocket.readLine(from: fds[0], buffer: &buffer, within: 2) == Data("hello".utf8))
}
