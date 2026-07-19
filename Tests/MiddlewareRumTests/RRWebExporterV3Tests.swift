import XCTest
import SWCompression
@testable import MiddlewareRum

/// Captures requests the exporter sends so tests can assert on them.
final class ReplayStubURLProtocol: URLProtocol {
    struct CapturedRequest {
        let url: URL?
        let headers: [String: String]
        let body: Data
    }

    static let lock = NSLock()
    static var captured: [CapturedRequest] = []
    static var statusCodes: [Int] = []

    static func reset() {
        lock.lock()
        captured = []
        statusCodes = []
        lock.unlock()
    }

    static func nextStatusCode() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return statusCodes.isEmpty ? 200 : statusCodes.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 64 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        Self.lock.lock()
        Self.captured.append(CapturedRequest(
            url: request.url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body ?? Data()))
        Self.lock.unlock()

        let status = Self.nextStatusCode()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RRWebExporterV3Tests: XCTestCase {

    private var exporter: RRWebExporterV3!

    override func setUp() {
        super.setUp()
        ReplayStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReplayStubURLProtocol.self]
        exporter = RRWebExporterV3(
            target: "https://example.middleware.io",
            token: "test-token",
            resourceAttributesProvider: { sessionId in
                [
                    "mw.rum": "true",
                    "recordingV3": "1",
                    "session.id": sessionId,
                ]
            },
            sessionConfiguration: configuration)
    }

    override func tearDown() {
        exporter.shutdown()
        exporter = nil
        super.tearDown()
    }

    private func waitForRequests(_ count: Int, timeout: TimeInterval = 10) -> [ReplayStubURLProtocol.CapturedRequest] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            ReplayStubURLProtocol.lock.lock()
            let captured = ReplayStubURLProtocol.captured
            ReplayStubURLProtocol.lock.unlock()
            if captured.count >= count {
                return captured
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        ReplayStubURLProtocol.lock.lock()
        defer { ReplayStubURLProtocol.lock.unlock() }
        return ReplayStubURLProtocol.captured
    }

    private func decodeBody(_ request: ReplayStubURLProtocol.CapturedRequest) throws -> [String: Any] {
        let unzipped = try GzipArchive.unarchive(archive: request.body)
        let json = try JSONSerialization.jsonObject(with: unzipped)
        return try XCTUnwrap(json as? [String: Any])
    }

    private func metrics(in body: [String: Any]) throws -> [[String: Any]] {
        let resourceMetrics = try XCTUnwrap(body["resourceMetrics"] as? [[String: Any]])
        let scopeMetrics = try XCTUnwrap(resourceMetrics.first?["scopeMetrics"] as? [[String: Any]])
        return try XCTUnwrap(scopeMetrics.first?["metrics"] as? [[String: Any]])
    }

    private func resourceAttributes(in body: [String: Any]) throws -> [String: String] {
        let resourceMetrics = try XCTUnwrap(body["resourceMetrics"] as? [[String: Any]])
        let resource = try XCTUnwrap(resourceMetrics.first?["resource"] as? [String: Any])
        let attributes = try XCTUnwrap(resource["attributes"] as? [[String: Any]])
        var result: [String: String] = [:]
        for attribute in attributes {
            let key = try XCTUnwrap(attribute["key"] as? String)
            let value = try XCTUnwrap((attribute["value"] as? [String: Any])?["stringValue"] as? String)
            result[key] = value
        }
        return result
    }

    func testExportsOtlpMetricsShape() throws {
        exporter.enqueue(RRWebEvents.meta(href: "ios-app://x/Main", width: 393, height: 852, timestampMs: 1000), sessionId: "session-1")
        exporter.enqueue(RRWebEvents.frameMutation(frameDataUri: "data:image/jpeg;base64,AA", timestampMs: 2000), sessionId: "session-1")
        exporter.flush()

        let requests = waitForRequests(1)
        XCTAssertEqual(requests.count, 1)
        let request = requests[0]
        XCTAssertEqual(request.url?.path, "/v1/metrics")
        XCTAssertEqual(request.headers["Authorization"], "test-token")
        XCTAssertEqual(request.headers["Origin"], "sdk.middleware.io")
        XCTAssertEqual(request.headers["Content-Encoding"], "gzip")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")

        let body = try decodeBody(request)
        let attrs = try resourceAttributes(in: body)
        XCTAssertEqual(attrs["recordingV3"], "1")
        XCTAssertEqual(attrs["session.id"], "session-1")

        let allMetrics = try metrics(in: body)
        XCTAssertEqual(allMetrics.count, 2)
        let first = allMetrics[0]
        XCTAssertEqual(first["name"] as? String, "rum_event")
        let gauge = try XCTUnwrap(first["gauge"] as? [String: Any])
        let dataPoint = try XCTUnwrap((gauge["dataPoints"] as? [[String: Any]])?.first)
        XCTAssertEqual(dataPoint["timeUnixNano"] as? String, "1000000000")
        XCTAssertEqual(dataPoint["asDouble"] as? Int, 0)
        let pointAttributes = try XCTUnwrap(dataPoint["attributes"] as? [[String: Any]])
        var attrsByKey: [String: String] = [:]
        for attribute in pointAttributes {
            let key = try XCTUnwrap(attribute["key"] as? String)
            attrsByKey[key] = (attribute["value"] as? [String: Any])?["stringValue"] as? String
        }
        XCTAssertEqual(attrsByKey["type"], "4")
        XCTAssertEqual(attrsByKey["timestamp"], "1000")
        let dataJson = try XCTUnwrap(attrsByKey["data"])
        let dataObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(dataJson.utf8)) as? [String: Any])
        XCTAssertEqual(dataObject["href"] as? String, "ios-app://x/Main")
        XCTAssertEqual(dataObject["width"] as? Int, 393)
    }

    func testGroupsBatchesBySession() throws {
        exporter.enqueue(RRWebEvents.meta(href: "a", width: 1, height: 1, timestampMs: 1), sessionId: "session-a")
        exporter.enqueue(RRWebEvents.meta(href: "b", width: 1, height: 1, timestampMs: 2), sessionId: "session-b")
        exporter.flush()

        let requests = waitForRequests(2)
        XCTAssertEqual(requests.count, 2)
        var sessions = Set<String>()
        for request in requests {
            let attrs = try resourceAttributes(in: try decodeBody(request))
            sessions.insert(try XCTUnwrap(attrs["session.id"]))
        }
        XCTAssertEqual(sessions, ["session-a", "session-b"])
    }

    func testRetriesFailedBatch() throws {
        ReplayStubURLProtocol.lock.lock()
        ReplayStubURLProtocol.statusCodes = [500, 200]
        ReplayStubURLProtocol.lock.unlock()

        exporter.enqueue(RRWebEvents.frameMutation(frameDataUri: "data:image/jpeg;base64,AA", timestampMs: 1), sessionId: "s")
        exporter.flush()
        _ = waitForRequests(1)

        // give the requeue a moment, then flush again
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        exporter.flush()
        let requests = waitForRequests(2)
        XCTAssertEqual(requests.count, 2)
        let retried = try metrics(in: try decodeBody(requests[1]))
        XCTAssertEqual(retried.count, 1)
    }

    func testDropsBatchAfterMaxRetries() throws {
        ReplayStubURLProtocol.lock.lock()
        ReplayStubURLProtocol.statusCodes = [500, 500, 500, 500]
        ReplayStubURLProtocol.lock.unlock()

        exporter.enqueue(RRWebEvents.frameMutation(frameDataUri: "data:image/jpeg;base64,AA", timestampMs: 1), sessionId: "s")
        // 1 initial attempt + 3 retries
        for expected in 1...4 {
            exporter.flush()
            let requests = waitForRequests(expected)
            XCTAssertEqual(requests.count, expected)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        exporter.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        ReplayStubURLProtocol.lock.lock()
        let total = ReplayStubURLProtocol.captured.count
        ReplayStubURLProtocol.lock.unlock()
        XCTAssertEqual(total, 4, "batch should be dropped after max retries")
    }

    func testEvictionKeepsKeyframes() throws {
        exporter.enqueue(RRWebEvents.meta(href: "a", width: 1, height: 1, timestampMs: 1), sessionId: "s")
        exporter.enqueue(RRWebEvents.fullSnapshot(frameDataUri: "data:image/jpeg;base64,AA", width: 1, height: 1, timestampMs: 2), sessionId: "s")
        for index in 0..<400 {
            exporter.enqueue(RRWebEvents.frameMutation(frameDataUri: "data:image/jpeg;base64,F\(index)", timestampMs: Int64(10 + index)), sessionId: "s")
        }
        exporter.flush()

        let requests = waitForRequests(1)
        let allMetrics = try metrics(in: try decodeBody(requests[0]))
        XCTAssertLessThanOrEqual(allMetrics.count, 300)

        var types = Set<String>()
        for metric in allMetrics {
            let gauge = try XCTUnwrap(metric["gauge"] as? [String: Any])
            let dataPoint = try XCTUnwrap((gauge["dataPoints"] as? [[String: Any]])?.first)
            let attributes = try XCTUnwrap(dataPoint["attributes"] as? [[String: Any]])
            for attribute in attributes where attribute["key"] as? String == "type" {
                if let value = (attribute["value"] as? [String: Any])?["stringValue"] as? String {
                    types.insert(value)
                }
            }
        }
        XCTAssertTrue(types.contains("4"), "meta event must survive eviction")
        XCTAssertTrue(types.contains("2"), "full snapshot must survive eviction")
    }

    func testGzipRoundTrip() throws {
        let original = Data("hello gzip".utf8)
        let archived = try GzipArchive.archive(data: original)
        // RFC 1952 magic bytes
        XCTAssertEqual(archived.prefix(2), Data([0x1f, 0x8b]))
        let restored = try GzipArchive.unarchive(archive: archived)
        XCTAssertEqual(restored, original)
    }
}
