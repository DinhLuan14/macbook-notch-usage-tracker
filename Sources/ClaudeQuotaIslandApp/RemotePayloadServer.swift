import ClaudeQuotaIslandCore
import Darwin
import Foundation

final class RemotePayloadServer: @unchecked Sendable {
    private static let maximumPayloadSize = 2 * 1_024 * 1_024

    private let socketPath: String
    private let source: ClaudeSnapshotSource
    private let snapshotStore: SnapshotStore
    private let allowedProjectPaths: [String]
    private let queue = DispatchQueue(
        label: "io.github.dinhluan14.macbook-notch-usage-tracker.remote-payload"
    )
    private let onIngest: @Sendable () -> Void
    private let onError: @Sendable (String) -> Void

    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?

    init(
        socketPath: String,
        source: ClaudeSnapshotSource,
        snapshotStore: SnapshotStore,
        allowedProjectPaths: [String] = [],
        onIngest: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.socketPath = socketPath
        self.source = source
        self.snapshotStore = snapshotStore
        self.allowedProjectPaths = allowedProjectPaths
        self.onIngest = onIngest
        self.onError = onError
    }

    func start() throws {
        guard listenerDescriptor == -1 else { return }

        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw RemotePayloadServerError.socketPathTooLong
        }

        let socketDirectory = URL(fileURLWithPath: socketPath)
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: socketDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: socketDirectory.path
        )
        try? FileManager.default.removeItem(atPath: socketPath)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw RemotePayloadServerError.systemCall("socket", errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = byte
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(descriptor)
            throw RemotePayloadServerError.systemCall("bind", code)
        }
        guard chmod(socketPath, 0o600) == 0 else {
            let code = errno
            close(descriptor)
            try? FileManager.default.removeItem(atPath: socketPath)
            throw RemotePayloadServerError.systemCall("chmod", code)
        }
        guard listen(descriptor, 8) == 0 else {
            let code = errno
            close(descriptor)
            throw RemotePayloadServerError.systemCall("listen", code)
        }

        let currentFlags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        listenerDescriptor = descriptor

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        listenerSource = source
        source.resume()
    }

    func stop() {
        queue.sync {
            listenerSource?.cancel()
            listenerSource = nil
            listenerDescriptor = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func acceptPendingConnections() {
        guard listenerDescriptor >= 0 else { return }
        while true {
            let client = accept(listenerDescriptor, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                onError("Remote socket accept failed (\(errno)).")
                return
            }
            let clientFlags = fcntl(client, F_GETFL)
            _ = fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK)
            readPayload(from: client)
        }
    }

    private func readPayload(from client: Int32) {
        defer { close(client) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while payload.count < Self.maximumPayloadSize {
            let count = recv(client, &buffer, buffer.count, 0)
            if count > 0 {
                payload.append(buffer, count: count)
                continue
            }
            if count == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            break
        }

        guard !payload.isEmpty, payload.count < Self.maximumPayloadSize else {
            onError("Remote status-line payload was empty or too large.")
            return
        }

        do {
            let decoded = try JSONDecoder().decode(ClaudeStatusLinePayload.self, from: payload)
            guard accepts(decoded.workingDirectory) else { return }
            _ = try snapshotStore.ingest(decoded, source: source)
            onIngest()
        } catch {
            onError("Remote status-line payload failed: \(error.localizedDescription)")
        }
    }

    private func accepts(_ workingDirectory: String?) -> Bool {
        guard !allowedProjectPaths.isEmpty else { return true }
        guard let workingDirectory else { return false }
        let normalized = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        return allowedProjectPaths.contains { projectPath in
            normalized == projectPath || normalized.hasPrefix(projectPath + "/")
        }
    }
}

enum RemotePayloadServerError: LocalizedError {
    case socketPathTooLong
    case systemCall(String, Int32)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            "The local remote-status socket path is too long."
        case let .systemCall(name, code):
            "\(name) failed with errno \(code)."
        }
    }
}
