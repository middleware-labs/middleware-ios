import XCTest
@testable import MiddlewareRum

/// Captures span batches instead of sending them.
private final class CapturingSpanExporter: SpanExporter {
    var exported: [SpanData] = []

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        exported.append(contentsOf: spans)
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) {}
}

final class RawSpanExportTests: XCTestCase {

    private var capturing: CapturingSpanExporter!
    private var previousExporter: SpanExporter?

    override func setUp() {
        super.setUp()
        // The resource overlay reads the active resource; register a real
        // provider (the default no-op provider has no resource storage).
        if !(OpenTelemetry.instance.tracerProvider is TracerProviderSdk) {
            OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder().build())
        }
        capturing = CapturingSpanExporter()
        previousExporter = rawSpanExporter
        rawSpanExporter = capturing
    }

    override func tearDown() {
        rawSpanExporter = previousExporter
        resetNativeSessionControlInternal()
        super.tearDown()
    }

    /// The exact shape middleware-react-native's toNativeSpan() produces.
    private func jsSpan() -> [String: Any] {
        return [
            "name": "HTTP GET",
            "kind": 2, // OTel-JS client
            "traceId": "0af7651916cd43dd8448eb211c80319c",
            "spanId": "b7ad6b7169203331",
            "parentSpanId": "00f067aa0ba902b7",
            "startTime": 1_750_000_000_000_000_000.0, // ns
            "endTime": 1_750_000_001_000_000_000.0,
            "attributes": [
                "http.url": "https://api.example.com/products",
                "http.status_code": 200,
                "component": "http",
            ] as [String: Any],
            "events": [
                ["name": "fetchStart", "time": "1750000000100000000", "attributes": [:] as [String: Any]],
            ],
            "resource": [
                "telemetry.sdk.name": "middleware-react-native",
            ] as [String: Any],
        ]
    }

    func testConvertsJsSpanFaithfully() throws {
        XCTAssertTrue(MiddlewareRum.exportRawSpans([jsSpan()]))
        XCTAssertEqual(capturing.exported.count, 1)
        let span = capturing.exported[0]

        XCTAssertEqual(span.name, "HTTP GET")
        XCTAssertEqual(span.kind, .client) // OTel-JS 2 = client
        XCTAssertEqual(span.traceId.hexString, "0af7651916cd43dd8448eb211c80319c")
        XCTAssertEqual(span.spanId.hexString, "b7ad6b7169203331")
        XCTAssertEqual(span.parentSpanId?.hexString, "00f067aa0ba902b7")
        XCTAssertEqual(span.startTime.timeIntervalSince1970, 1_750_000_000, accuracy: 0.001)
        XCTAssertEqual(span.endTime.timeIntervalSince1970, 1_750_000_001, accuracy: 0.001)
        XCTAssertTrue(span.hasEnded)
        XCTAssertEqual(span.traceFlags.sampled, true)

        XCTAssertEqual(span.attributes["http.url"]?.description, "https://api.example.com/products")
        guard case .int(let statusCode)? = span.attributes["http.status_code"] else {
            return XCTFail("status code should stay numeric")
        }
        XCTAssertEqual(statusCode, 200)

        XCTAssertEqual(span.events.count, 1)
        XCTAssertEqual(span.events[0].name, "fetchStart")
    }

    func testKindMappingMatchesOtelJs() throws {
        for (jsKind, expected) in [(0, SpanKind.internal), (1, .server), (2, .client), (3, .producer), (4, .consumer)] {
            var span = jsSpan()
            span["kind"] = jsKind
            capturing.exported.removeAll()
            XCTAssertTrue(MiddlewareRum.exportRawSpans([span]))
            XCTAssertEqual(capturing.exported[0].kind, expected, "js kind \(jsKind)")
        }
    }

    func testResourceOverlaysJsAndForcesNativeSession() throws {
        MiddlewareRum.setNativeSession("44444444444444444444444444444444", startTimeMs: 4000)
        XCTAssertTrue(MiddlewareRum.exportRawSpans([jsSpan()]))
        let resource = capturing.exported[0].resource
        XCTAssertEqual(resource.attributes["telemetry.sdk.name"]?.description, "middleware-react-native")
        XCTAssertEqual(
            resource.attributes[MiddlewareConstants.Attributes.SESSION_ID]?.description,
            "44444444444444444444444444444444")
    }

    func testReturnsFalseBeforeInitialization() {
        rawSpanExporter = nil
        XCTAssertFalse(MiddlewareRum.exportRawSpans([jsSpan()]))
    }
}
