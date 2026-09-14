import Foundation
import UIKit

/// What changed, pushed from the API as it happens — the same `GET /stream`
/// the web reads.
///
/// Events say what changed, never the content. Listeners re-fetch through the
/// normal endpoints, which do their own access checks.
enum LiveEvent: Equatable {
    /// A new message in one of your threads.
    case message(conversationId: UUID, id: UUID)
    /// A notification arrived for you, or one was read on another device.
    case notification
    /// You joined or left a thread.
    case conversations
    /// A match changed — a ball, the toss, a handover, the result.
    case match(id: UUID, seq: Int64)
    /// Connected (or reconnected), or events may have been missed: re-fetch.
    case resync
}

/// The SSE wire format: `event:` and `data:` lines, a blank line ends an
/// event, and lines starting with ":" are keep-alive comments.
struct LiveEventParser {
    private var name = "message"
    private var data = ""

    /// One line, without its newline. An event comes back when a blank line
    /// finishes one.
    mutating func feed(_ line: String) -> LiveEvent? {
        if line.isEmpty {
            defer { name = "message"; data = "" }
            return Self.event(name: name, data: data)
        }
        if line.hasPrefix(":") { return nil }
        var field = Substring(line)
        var value = Substring("")
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        }
        switch field {
        case "event": name = String(value)
        case "data": data += (data.isEmpty ? "" : "\n") + value
        default: break
        }
        return nil
    }

    static func event(name: String, data: String) -> LiveEvent? {
        guard !data.isEmpty,
              let parsed = try? JSONSerialization.jsonObject(with: Data(data.utf8), options: .fragmentsAllowed)
        else { return nil }
        let payload = parsed as? [String: Any] ?? [:]
        let uuid = { (key: String) in (payload[key] as? String).flatMap(UUID.init(uuidString:)) }
        switch name {
        // Connected: whatever happened while we were not is only in a fetch.
        case "ready", "resync":
            return .resync
        case "message":
            guard let conversation = uuid("conversation_id"), let id = uuid("id") else { return nil }
            return .message(conversationId: conversation, id: id)
        case "notification":
            return .notification
        case "conversations":
            return .conversations
        case "match":
            guard let id = uuid("id") else { return nil }
            return .match(id: id, seq: (payload["seq"] as? NSNumber)?.int64Value ?? 0)
        default:
            return nil
        }
    }
}

/// One connection for the whole app, shared by every screen that listens: a
/// thread, the chat list, the bell, a scorecard.
///
/// ```swift
/// .task { for await event in LiveStream.shared.events() { … } }
/// ```
///
/// The connection opens with the first listener and closes with the last, so
/// a `.task` ending is all the unsubscribing there is. It drops while the app
/// is in the background — iOS would cut it anyway — and comes back, with a
/// `resync`, when the app does.
@MainActor
final class LiveStream {
    static let shared = LiveStream()

    private var listeners: [UUID: AsyncStream<LiveEvent>.Continuation] = [:]
    private var connection: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// The server sends a keep-alive every 20s. URLSession's request timeout
    /// is the gap allowed between packets, so 50s of silence ends a connection
    /// that died without saying so — a network change, a Wi-Fi hand-off.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 50
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LiveStream.shared.close() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LiveStream.shared.openIfNeeded() }
            },
        ]
    }

    func events() -> AsyncStream<LiveEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self, bufferingPolicy: .bufferingNewest(16))
        continuation.onTermination = { _ in
            Task { @MainActor in LiveStream.shared.remove(id) }
        }
        listeners[id] = continuation
        openIfNeeded()
        return stream
    }

    private func remove(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { close() }
    }

    private func deliver(_ event: LiveEvent) {
        for listener in listeners.values { listener.yield(event) }
    }

    private func close() {
        connection?.cancel()
        connection = nil
    }

    private func openIfNeeded() {
        guard connection == nil, !listeners.isEmpty,
              UIApplication.shared.applicationState != .background else { return }
        let session = session
        connection = Task.detached(priority: .utility) {
            var retry = 0
            while !Task.isCancelled {
                if await Self.read(session: session, deliver: { event in
                    await LiveStream.shared.deliver(event)
                }) {
                    retry = 0
                }
                if Task.isCancelled { return }
                // 1s, 2s, 4s … up to 30s, with jitter so a server restart does
                // not bring every phone back in the same instant.
                let wait = min(30, pow(2, Double(retry))) * Double.random(in: 0.75...1.25)
                retry += 1
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// One connection, read until it ends. True when it got as far as a
    /// stream, so the next attempt starts from the shortest wait.
    private nonisolated static func read(
        session: URLSession,
        deliver: @escaping (LiveEvent) async -> Void
    ) async -> Bool {
        guard var request = await NetworkService.shared.signedRequest(path: "/stream") else { return false }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                await NetworkService.shared.renewSession()
                return false
            }
            guard status == 200 else { return false }
            var parser = LiveEventParser()
            var line: [UInt8] = []
            // Byte by byte rather than `bytes.lines`, which skips the blank
            // lines that end each event.
            for try await byte in bytes {
                guard byte == UInt8(ascii: "\n") else {
                    line.append(byte)
                    continue
                }
                if line.last == UInt8(ascii: "\r") { line.removeLast() }
                if let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                    await deliver(event)
                }
                line.removeAll(keepingCapacity: true)
            }
            return true
        } catch {
            return false
        }
    }
}
