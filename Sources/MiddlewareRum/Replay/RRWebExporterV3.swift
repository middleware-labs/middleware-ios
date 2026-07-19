// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import SWCompression

/// Buffers v3 rrweb events and ships them through the metrics endpoint using
/// the same wire format as the browser and Android SDKs: an OTLP-JSON
/// `MetricsData` whose metrics are `rum_event` gauges with datapoint attributes
/// `type` / `timestamp` / `data`, POSTed gzip-compressed to `{target}/v1/metrics`.
///
/// Buffering policy (in-memory only):
///  - flush every 5 s, or immediately once the buffer holds 512 KB of
///    serialized event data;
///  - failed batches are retried up to 3 times on later flush ticks;
///  - when the buffer exceeds 3 MB / 300 events, the oldest incremental events
///    are dropped first — Meta and FullSnapshot events are kept because the
///    frames that follow them are unplayable without them.
class RRWebExporterV3 {

    private static let flushIntervalSeconds: Double = 5
    private static let flushThresholdBytes = 512 * 1024
    private static let maxBufferBytes = 3 * 1024 * 1024
    private static let maxBufferEvents = 300
    private static let maxRetries = 3

    private struct PendingEvent {
        let sessionId: String
        let type: Int
        let timestampMs: Int64
        let dataJson: String
        var retries: Int = 0

        var isKeyframe: Bool {
            type == RRWebEvents.typeFullSnapshot || type == RRWebEvents.typeMeta
        }
    }

    private let endpoint: URL?
    private let token: String
    private let resourceAttributesProvider: (_ sessionId: String) -> [String: String]

    private let session: URLSession
    private let exportQueue = DispatchQueue(label: "io.middleware.replay.v3.export", qos: .utility)
    private var flushTimer: DispatchSourceTimer?

    private let bufferLock = NSLock()
    private var buffer: [PendingEvent] = []
    private var bufferBytes = 0
    private var isShutdown = false

    init(target: String,
         token: String,
         resourceAttributesProvider: @escaping (_ sessionId: String) -> [String: String],
         sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.endpoint = URL(string: target + "/v1/metrics")
        self.token = token
        self.resourceAttributesProvider = resourceAttributesProvider
        sessionConfiguration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfiguration)

        let timer = DispatchSource.makeTimerSource(queue: exportQueue)
        timer.schedule(deadline: .now() + Self.flushIntervalSeconds,
                       repeating: Self.flushIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.flushInternal()
        }
        timer.resume()
        self.flushTimer = timer
    }

    func enqueue(_ event: RRWebEvent, sessionId: String) {
        guard !isShutdown, JSONSerialization.isValidJSONObject(event.data),
              let dataJson = try? JSONSerialization.data(withJSONObject: event.data),
              let dataJsonString = String(data: dataJson, encoding: .utf8) else {
            return
        }
        let pending = PendingEvent(
            sessionId: sessionId,
            type: event.type,
            timestampMs: event.timestampMs,
            dataJson: dataJsonString
        )
        var shouldFlushNow = false
        bufferLock.lock()
        buffer.append(pending)
        bufferBytes += dataJsonString.utf8.count
        evictIfNeededLocked()
        shouldFlushNow = bufferBytes >= Self.flushThresholdBytes
        bufferLock.unlock()

        if shouldFlushNow {
            flush()
        }
    }

    /// Asynchronously flushes everything currently buffered.
    func flush() {
        guard !isShutdown else { return }
        exportQueue.async { [weak self] in
            self?.flushInternal()
        }
    }

    /// Flushes remaining events and stops the timer.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        flushTimer?.cancel()
        flushTimer = nil
        exportQueue.async { [weak self] in
            self?.flushInternal()
        }
    }

    private func evictIfNeededLocked() {
        while buffer.count > Self.maxBufferEvents || bufferBytes > Self.maxBufferBytes {
            let victimIndex = buffer.firstIndex { !$0.isKeyframe } ?? (buffer.isEmpty ? nil : 0)
            guard let index = victimIndex else { return }
            let victim = buffer.remove(at: index)
            bufferBytes -= victim.dataJson.utf8.count
            Log.debug("Replay v3 buffer full - dropped a type=\(victim.type) event")
        }
    }

    /// Runs on `exportQueue` only.
    private func flushInternal() {
        bufferLock.lock()
        let batch = buffer
        buffer.removeAll()
        bufferBytes = 0
        bufferLock.unlock()

        guard !batch.isEmpty else { return }

        // Keep per-session streams intact: one payload per session id.
        let bySession = Dictionary(grouping: batch, by: { $0.sessionId })
        for (sessionId, events) in bySession {
            let sent = autoreleasepool { () -> Bool in
                guard let body = buildOtlpBody(sessionId: sessionId, events: events) else {
                    return true // unserializable — drop rather than retry forever
                }
                return send(body)
            }
            if !sent {
                requeue(events)
            }
        }
    }

    private func requeue(_ events: [PendingEvent]) {
        var retryable = events.filter { $0.retries < Self.maxRetries }
        let dropped = events.count - retryable.count
        if dropped > 0 {
            Log.debug("Replay v3 dropped \(dropped) events after \(Self.maxRetries) failed sends")
        }
        guard !retryable.isEmpty else { return }
        for index in retryable.indices {
            retryable[index].retries += 1
        }
        bufferLock.lock()
        buffer.insert(contentsOf: retryable, at: 0)
        bufferBytes += retryable.reduce(0) { $0 + $1.dataJson.utf8.count }
        evictIfNeededLocked()
        bufferLock.unlock()
    }

    /// Builds the OTLP-JSON payload — same shape as the browser SDK's
    /// RRWebExporter and Android's RRWebExporterV3.
    private func buildOtlpBody(sessionId: String, events: [PendingEvent]) -> Data? {
        let resourceAttributes = resourceAttributesProvider(sessionId).map { key, value -> [String: Any] in
            ["key": key, "value": ["stringValue": value]]
        }
        let metrics: [[String: Any]] = events.map { event in
            [
                "name": "rum_event",
                "gauge": [
                    "dataPoints": [
                        [
                            "attributes": [
                                ["key": "type", "value": ["stringValue": String(event.type)]],
                                ["key": "timestamp", "value": ["stringValue": String(event.timestampMs)]],
                                // data is the event payload's JSON, shipped as a string
                                ["key": "data", "value": ["stringValue": event.dataJson]],
                            ],
                            "timeUnixNano": String(event.timestampMs * 1_000_000),
                            "asDouble": 0,
                        ] as [String: Any],
                    ],
                ],
            ]
        }
        let payload: [String: Any] = [
            "resourceMetrics": [
                [
                    "resource": [
                        "attributes": resourceAttributes,
                        "droppedAttributesCount": 0,
                    ] as [String: Any],
                    "scopeMetrics": [
                        [
                            "scope": [String: Any](),
                            "metrics": metrics,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Synchronous send on the export queue (mirrors Android's blocking
    /// OkHttp execute on its export thread).
    private func send(_ body: Data) -> Bool {
        guard let endpoint = endpoint else {
            return true // misconfigured target — drop silently, nothing will ever succeed
        }
        guard let gzipped = try? GzipArchive.archive(data: body) else {
            Log.error("Replay v3 gzip failed")
            return true
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("sdk.middleware.io", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.httpBody = gzipped

        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                Log.debug("Replay v3 export failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                success = (200..<300).contains(http.statusCode)
                if !success {
                    Log.debug("Replay v3 export failed with status \(http.statusCode)")
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 35)
        return success
    }
}
