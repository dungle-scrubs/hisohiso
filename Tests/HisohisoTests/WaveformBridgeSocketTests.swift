import Darwin
import Foundation
@testable import Hisohiso
import XCTest

/// Exercises the real `WaveformBridge` against a live Unix-domain socket to prove
/// it connects and emits the `state`/`levels` line protocol that an external
/// waveform display (e.g. a notch-bar plugin) parses.
final class WaveformBridgeSocketTests: XCTestCase {
    func testBridgePushesStateAndLevelsToSocket() throws {
        let path = "/tmp/hisohiso-waveform.sock"
        unlink(path)

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        try XCTSkipIf(listener < 0, "could not create listener socket")
        defer {
            close(listener)
            unlink(path)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                strcpy(dst, src)
            }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0, "bind failed (errno \(errno))")
        XCTAssertEqual(Darwin.listen(listener, 1), 0)

        let received = NSMutableData()
        let lock = NSLock()
        let done = expectation(description: "received state + levels")

        DispatchQueue.global().async {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var buf = [UInt8](repeating: 0, count: 1024)
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                let n = read(client, &buf, buf.count)
                if n <= 0 { break }
                lock.lock()
                received.append(buf, length: n)
                let snapshot = String(data: received as Data, encoding: .utf8) ?? ""
                lock.unlock()
                if snapshot.contains("state recording"), snapshot.contains("levels ") {
                    break
                }
            }
            done.fulfill()
        }

        usleep(150_000) // let accept() arm
        WaveformBridge.shared.checkAvailability()
        WaveformBridge.shared.sendState(.recording)
        WaveformBridge.shared.sendLevels([10, 20, 30, 40, 50, 60, 70])

        wait(for: [done], timeout: 6)

        lock.lock()
        let text = String(data: received as Data, encoding: .utf8) ?? ""
        lock.unlock()
        XCTAssertTrue(text.contains("state recording"), "missing state line; got: \(text)")
        XCTAssertTrue(text.contains("levels 10,20,30,40,50,60,70"), "missing levels line; got: \(text)")
    }
}
