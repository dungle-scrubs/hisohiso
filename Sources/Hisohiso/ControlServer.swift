import Darwin
import Foundation

/// Errors that can occur while starting or running the control socket server.
enum ControlServerError: Error, LocalizedError {
    case bindFailed(String)
    case failedToCreateSocket
    case listenFailed(String)
    case pathTooLong
    case requestTooLarge(Data)

    var errorDescription: String? {
        switch self {
        case let .bindFailed(message):
            "Failed to bind control socket: \(message)"
        case .failedToCreateSocket:
            "Failed to create control socket"
        case let .listenFailed(message):
            "Failed to listen on control socket: \(message)"
        case .pathTooLong:
            "Control socket path is too long"
        case .requestTooLarge:
            "Control request too large"
        }
    }
}

/// Local Unix-socket server that receives JSON control requests.
final class ControlServer: @unchecked Sendable {
    typealias RequestHandler = (ControlRequest, @escaping (ControlResponse) -> Void) -> Void

    private static let maxRequestBytes = 64 * 1024

    private let queue = DispatchQueue(label: "com.hisohiso.control.server", qos: .utility)
    private let requestHandler: RequestHandler
    private let socketPath: String

    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?

    init(
        socketPath: String = AppConstants.controlSocketPath,
        requestHandler: @escaping RequestHandler
    ) {
        self.socketPath = socketPath
        self.requestHandler = requestHandler
    }

    deinit {
        stop()
    }

    /// Start the control server.
    /// - Throws: `ControlServerError` when socket setup fails.
    func start() throws {
        try queue.sync {
            guard listenFD < 0 else { return }

            try removeStaleSocketIfNeeded()

            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw ControlServerError.failedToCreateSocket
            }

            do {
                try makeNonBlocking(fd)

                var addr = try makeSocketAddress()
                let bindResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }

                guard bindResult == 0 else {
                    let message = String(cString: strerror(errno))
                    throw ControlServerError.bindFailed(message)
                }

                guard Darwin.listen(fd, 8) == 0 else {
                    let message = String(cString: strerror(errno))
                    throw ControlServerError.listenFailed(message)
                }

                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                source.setEventHandler { [weak self] in
                    self?.acceptPendingConnections()
                }
                source.setCancelHandler {
                    Darwin.close(fd)
                }
                source.resume()

                listenFD = fd
                listenSource = source
                logInfo("Control server listening on \(socketPath)")
            } catch {
                Darwin.close(fd)
                throw error
            }
        }
    }

    /// Stop the control server and remove the socket file.
    func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            listenFD = -1
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    /// Accept all pending client sockets.
    private func acceptPendingConnections() {
        while true {
            let clientFD = Darwin.accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                logError("Control server accept failed: \(String(cString: strerror(errno)))")
                break
            }

            handleClient(clientFD)
        }
    }

    /// Read one request from a client and write one response.
    /// - Parameter clientFD: Accepted client file descriptor.
    private func handleClient(_ clientFD: Int32) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                Darwin.close(clientFD)
                return
            }

            defer { Darwin.close(clientFD) }

            var frameBuffer = Data()
            while true {
                let line: Data
                do {
                    guard let frame = try Self.readLine(from: clientFD, buffer: &frameBuffer, maxBytes: Self.maxRequestBytes) else {
                        return
                    }
                    line = frame
                } catch ControlServerError.requestTooLarge(let payload) {
                    let response = ControlResponse.failure(
                        id: Self.requestID(from: payload),
                        error: "Control request too large"
                    )
                    try? Self.writeResponse(response, to: clientFD)
                    return
                } catch {
                    let response = ControlResponse.failure(id: UUID().uuidString, error: "Invalid control request")
                    try? Self.writeResponse(response, to: clientFD)
                    return
                }

                let request: ControlRequest
                do {
                    request = try JSONDecoder().decode(ControlRequest.self, from: line)
                } catch {
                    let response = ControlResponse.failure(
                        id: Self.requestID(from: line),
                        error: "Invalid control request"
                    )
                    try? Self.writeResponse(response, to: clientFD)
                    return
                }

                let responseWritten = DispatchSemaphore(value: 0)
                self.requestHandler(request) { response in
                    try? Self.writeResponse(response, to: clientFD)
                    responseWritten.signal()
                }
                _ = responseWritten.wait(timeout: .now() + 30)
            }
        }
    }

    /// Build a Unix domain socket address from `socketPath`.
    /// - Returns: Filled `sockaddr_un` struct.
    /// - Throws: `ControlServerError.pathTooLong` when the path exceeds `sun_path`.
    private func makeSocketAddress() throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLength else {
            throw ControlServerError.pathTooLong
        }

        pathBytes.withUnsafeBufferPointer { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        }

        return addr
    }

    /// Remove the old socket file if it exists.
    private func removeStaleSocketIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        try FileManager.default.removeItem(atPath: socketPath)
    }

    /// Configure a file descriptor as non-blocking.
    /// - Parameter fd: File descriptor to configure.
    /// - Throws: `ControlServerError.listenFailed` when `fcntl` fails.
    private func makeNonBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else {
            throw ControlServerError.listenFailed(String(cString: strerror(errno)))
        }

        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw ControlServerError.listenFailed(String(cString: strerror(errno)))
        }
    }

    /// Read a newline-delimited payload from a socket.
    /// - Parameters:
    ///   - fd: Source file descriptor.
    ///   - maxBytes: Max accepted payload size.
    /// - Returns: Data up to (but not including) newline.
    private static func readLine(from fd: Int32, buffer: inout Data, maxBytes: Int) throws -> Data? {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(2.0)

        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return line
            }

            if buffer.count > maxBytes {
                throw ControlServerError.requestTooLarge(buffer)
            }

            let bytesRead = Darwin.read(fd, &chunk, chunk.count)
            if bytesRead > 0 {
                buffer.append(chunk, count: bytesRead)
                continue
            }

            if bytesRead == 0 {
                guard !buffer.isEmpty else { return nil }
                let line = buffer
                buffer.removeAll(keepingCapacity: true)
                return line
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                if Date() > deadline {
                    throw ControlServerError.listenFailed("Timed out waiting for request data")
                }
                usleep(1_000)
                continue
            }

            throw ControlServerError.listenFailed(String(cString: strerror(errno)))
        }
    }

    /// Extract a request id from raw JSON when full decoding fails.
    /// - Parameter payload: Raw request bytes.
    /// - Returns: Request id when present, otherwise a generated id.
    private static func requestID(from payload: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let id = object["id"] as? String,
           !id.isEmpty
        {
            return id
        }

        guard let string = String(data: payload, encoding: .utf8),
              let idKeyRange = string.range(of: "\"id\""),
              let colonRange = string[idKeyRange.upperBound...].range(of: ":"),
              let openingQuote = string[colonRange.upperBound...].firstIndex(of: "\"")
        else {
            return UUID().uuidString
        }

        let valueStart = string.index(after: openingQuote)
        guard let closingQuote = string[valueStart...].firstIndex(of: "\"") else {
            return UUID().uuidString
        }

        let id = String(string[valueStart..<closingQuote])
        return id.isEmpty ? UUID().uuidString : id
    }

    /// Encode and write one newline-delimited JSON response.
    /// - Parameters:
    ///   - response: Response payload.
    ///   - fd: Destination file descriptor.
    private static func writeResponse(_ response: ControlResponse, to fd: Int32) throws {
        let data = try JSONEncoder().encode(response)
        var line = data
        line.append(0x0A)

        var totalWritten = 0
        while totalWritten < line.count {
            let written = line.withUnsafeBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                let remaining = line.count - totalWritten
                let pointer = baseAddress.advanced(by: totalWritten)
                return Darwin.write(fd, pointer, remaining)
            }

            if written > 0 {
                totalWritten += written
                continue
            }

            if written < 0, errno == EINTR {
                continue
            }

            if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(1_000)
                continue
            }

            throw ControlServerError.listenFailed(String(cString: strerror(errno)))
        }
    }
}
