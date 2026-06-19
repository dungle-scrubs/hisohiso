import Darwin
import Foundation

/// Errors returned by the local control socket client.
enum ControlSocketClientError: Error, LocalizedError {
    case connectFailed(String)
    case decodeFailed
    case encodeFailed
    case pathTooLong
    case readFailed(String)
    case socketCreateFailed
    case timedOut
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .connectFailed(message):
            "Failed to connect to Hisohiso control socket: \(message)"
        case .decodeFailed:
            "Failed to decode control response"
        case .encodeFailed:
            "Failed to encode control request"
        case .pathTooLong:
            "Control socket path is too long"
        case let .readFailed(message):
            "Failed to read control response: \(message)"
        case .socketCreateFailed:
            "Failed to create control client socket"
        case .timedOut:
            "Control request timed out"
        case let .writeFailed(message):
            "Failed to send control request: \(message)"
        }
    }
}

/// Synchronous request/response client for Hisohiso's control socket.
struct ControlSocketClient {
    private static let maxResponseBytes = 64 * 1024

    /// Send one control request and wait for one response.
    /// - Parameters:
    ///   - request: Control request payload.
    ///   - socketPath: Unix socket path.
    ///   - timeout: Max send/receive time in seconds.
    /// - Returns: Decoded control response.
    static func send(
        request: ControlRequest,
        socketPath: String = AppConstants.controlSocketPath,
        timeout: TimeInterval = 2.0
    ) -> Result<ControlResponse, ControlSocketClientError> {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return .failure(.socketCreateFailed)
        }
        defer { Darwin.close(fd) }

        do {
            try configureTimeouts(fd, timeout: timeout)

            var address = try makeSocketAddress(path: socketPath)
            let connected = withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connected == 0 else {
                let message = String(cString: strerror(errno))
                return .failure(.connectFailed(message))
            }

            guard let encodedRequest = try? JSONEncoder().encode(request) else {
                return .failure(.encodeFailed)
            }

            var outbound = encodedRequest
            outbound.append(0x0A)
            try writeAll(outbound, to: fd)

            let inbound = try readLine(from: fd, maxBytes: maxResponseBytes)
            guard let response = try? JSONDecoder().decode(ControlResponse.self, from: inbound) else {
                return .failure(.decodeFailed)
            }

            return .success(response)
        } catch {
            return .failure((error as? ControlSocketClientError) ?? .connectFailed(error.localizedDescription))
        }
    }

    /// Build a Unix domain socket address for client connection.
    /// - Parameter path: Socket file path.
    /// - Returns: Filled `sockaddr_un` structure.
    /// - Throws: `ControlSocketClientError.pathTooLong` when the path exceeds `sun_path`.
    private static func makeSocketAddress(path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let bytes = path.utf8CString
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= maxLength else {
            throw ControlSocketClientError.pathTooLong
        }

        bytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        }

        return addr
    }

    /// Configure socket send/receive timeouts.
    /// - Parameters:
    ///   - fd: Socket file descriptor.
    ///   - timeout: Timeout value in seconds.
    /// - Throws: `ControlSocketClientError.readFailed` when timeout setup fails.
    private static func configureTimeouts(_ fd: Int32, timeout: TimeInterval) throws {
        let boundedTimeout = max(0.1, timeout)
        let wholeSeconds = floor(boundedTimeout)
        let fraction = boundedTimeout - wholeSeconds
        let seconds = __darwin_time_t(wholeSeconds)
        let microseconds = __darwin_suseconds_t(fraction * 1_000_000)
        var value = timeval(tv_sec: seconds, tv_usec: microseconds)

        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            throw ControlSocketClientError.readFailed(String(cString: strerror(errno)))
        }

        guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            throw ControlSocketClientError.writeFailed(String(cString: strerror(errno)))
        }

        var disableSigPipe: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &disableSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw ControlSocketClientError.writeFailed(String(cString: strerror(errno)))
        }
    }

    /// Write all bytes to a socket.
    /// - Parameters:
    ///   - data: Bytes to write.
    ///   - fd: Destination socket file descriptor.
    /// - Throws: `ControlSocketClientError` when writing fails or times out.
    private static func writeAll(_ data: Data, to fd: Int32) throws {
        var writtenBytes = 0

        while writtenBytes < data.count {
            let result = data.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                let pointer = baseAddress.advanced(by: writtenBytes)
                return Darwin.write(fd, pointer, data.count - writtenBytes)
            }

            if result > 0 {
                writtenBytes += result
                continue
            }

            if result == 0 {
                throw ControlSocketClientError.writeFailed("Socket closed while writing request")
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw ControlSocketClientError.timedOut
            }

            throw ControlSocketClientError.writeFailed(String(cString: strerror(errno)))
        }
    }

    /// Read one newline-delimited payload from a socket.
    /// - Parameters:
    ///   - fd: Source file descriptor.
    ///   - maxBytes: Maximum accepted payload size.
    /// - Returns: Raw payload bytes without trailing newline.
    /// - Throws: `ControlSocketClientError` when reading fails or times out.
    private static func readLine(from fd: Int32, maxBytes: Int) throws -> Data {
        var payload = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while payload.count < maxBytes {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                payload.append(chunk, count: count)
                if let newlineIndex = payload.firstIndex(of: 0x0A) {
                    return payload.prefix(upTo: newlineIndex)
                }
                continue
            }

            if count == 0 {
                return payload
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw ControlSocketClientError.timedOut
            }

            throw ControlSocketClientError.readFailed(String(cString: strerror(errno)))
        }

        throw ControlSocketClientError.readFailed("Control response exceeded \(maxBytes) bytes")
    }
}
