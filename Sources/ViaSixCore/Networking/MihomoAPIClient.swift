import Foundation

public struct MihomoAPIConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let secret: String

    public init(host: String = "127.0.0.1", port: Int, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
    }

    public var displayAddress: String { "\(host):\(port)" }

    public func webSocketURL(path: String) -> URL? {
        let trimmed = path.hasPrefix("/") ? path : "/\(path)"
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        components.path = trimmed
        return components.url
    }
}

public enum MihomoAPIClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL(String)
    case connectionFailed(String)
    case cancelled
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "无效的 Mihomo API 地址：\(path)"
        case .connectionFailed(let detail):
            "无法连接 Mihomo Controller：\(detail)"
        case .cancelled:
            "Mihomo API 连接已取消"
        case .decodingFailed(let detail):
            "无法解析 Mihomo API 数据：\(detail)"
        }
    }
}

/// Streams JSON text frames from a Mihomo external-controller WebSocket path.
public protocol MihomoWebSocketStreaming: Sendable {
    func stream(
        configuration: MihomoAPIConfiguration,
        path: String
    ) -> AsyncThrowingStream<Data, Error>
}

public struct MihomoWebSocketClient: MihomoWebSocketStreaming {
    public init() {}

    public func stream(
        configuration: MihomoAPIConfiguration,
        path: String
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            guard let url = configuration.webSocketURL(path: path) else {
                continuation.finish(throwing: MihomoAPIClientError.invalidURL(path))
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let secret = configuration.secret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }

            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: request)
            let box = WebSocketSessionBox(session: session, task: task)

            continuation.onTermination = { @Sendable _ in
                box.cancel()
            }

            task.resume()
            Task {
                await receiveLoop(box: box, continuation: continuation)
            }
        }
    }

    private func receiveLoop(
        box: WebSocketSessionBox,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await box.receive()
                switch message {
                case .string(let text):
                    guard let data = text.data(using: .utf8) else { continue }
                    continuation.yield(data)
                case .data(let data):
                    continuation.yield(data)
                @unknown default:
                    continue
                }
            } catch is CancellationError {
                continuation.finish(throwing: MihomoAPIClientError.cancelled)
                box.cancel()
                return
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                    continuation.finish(throwing: MihomoAPIClientError.cancelled)
                } else {
                    continuation.finish(
                        throwing: MihomoAPIClientError.connectionFailed(error.localizedDescription)
                    )
                }
                box.cancel()
                return
            }
        }
        continuation.finish(throwing: MihomoAPIClientError.cancelled)
        box.cancel()
    }
}

/// Owns one URLSession WebSocket used by the stream.
private final class WebSocketSessionBox: @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var isCancelled = false

    init(session: URLSession, task: URLSessionWebSocketTask) {
        self.session = session
        self.task = task
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isCancelled {
                lock.unlock()
                continuation.resume(throwing: MihomoAPIClientError.cancelled)
                return
            }
            lock.unlock()

            task.receive { result in
                switch result {
                case .success(let message):
                    continuation.resume(returning: message)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

/// Decodes Mihomo traffic and memory payloads.
public enum MihomoAPIDecoder {
    private static let decoder = JSONDecoder()

    public static func decodeTraffic(_ data: Data) throws -> TrafficSpeedSample {
        do {
            return try decoder.decode(TrafficSpeedSample.self, from: data)
        } catch {
            throw MihomoAPIClientError.decodingFailed(error.localizedDescription)
        }
    }

    public static func decodeMemory(_ data: Data) throws -> MihomoMemoryUsage {
        do {
            return try decoder.decode(MihomoMemoryUsage.self, from: data)
        } catch {
            throw MihomoAPIClientError.decodingFailed(error.localizedDescription)
        }
    }
}
