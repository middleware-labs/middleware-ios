import XCTest
@testable import MiddlewareRum

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)

/// Regression tests for slow-frame detection.
///
/// The threshold used to be a fixed 16.7ms: about one normal frame at 60Hz, and
/// every frame when Low Power Mode drops the display link to 30Hz.
final class SlowRenderingDetectorTests: XCTestCase {

    private let hz60 = 1.0 / 60
    private let hz120 = 1.0 / 120
    private let hz30 = 1.0 / 30
    private let slow = 16.7 / 1e3
    private let frozen = 700.0 / 1e3

    private func classify(_ durationMs: Double, budget: CFTimeInterval) -> FrameClassification {
        SlowRenderingDetector.classify(
            duration: durationMs / 1e3, frameBudget: budget, slowThreshold: slow, frozenThreshold: frozen)
    }

    func testJitterAroundOneFrameIsNormalAt60Hz() {
        XCTAssertEqual(classify(16.67, budget: hz60), .normal)
        XCTAssertEqual(classify(16.7, budget: hz60), .normal)
        XCTAssertEqual(classify(17.5, budget: hz60), .normal)
    }

    func testMissedVsyncIsSlowAt60Hz() {
        XCTAssertEqual(classify(33.3, budget: hz60), .slow)
    }

    func testEveryFrameIsNotSlowInLowPowerMode() {
        XCTAssertEqual(classify(33.3, budget: hz30), .normal)
        XCTAssertEqual(classify(66.7, budget: hz30), .slow)
    }

    func testProMotionFollowsTheConfiguredThreshold() {
        // A normal 120Hz frame is fine and 16.7ms stays the floor for "slow".
        XCTAssertEqual(classify(8.33, budget: hz120), .normal)
        XCTAssertEqual(classify(25, budget: hz120), .slow)
    }

    func testAHigherConfiguredThresholdWins() {
        let classification = SlowRenderingDetector.classify(
            duration: 33.3 / 1e3, frameBudget: hz60, slowThreshold: 50.0 / 1e3, frozenThreshold: frozen)
        XCTAssertEqual(classification, .normal)
    }

    func testFrozenTakesPrecedenceAtAnyRefreshRate() {
        XCTAssertEqual(classify(700, budget: hz60), .frozen)
        XCTAssertEqual(classify(700, budget: hz30), .frozen)
    }

    func testSpansUseTheScreenCurrentWhenTheFrameWasSlow() throws {
        let exporter = InMemoryExporter()
        let provider = TracerProviderBuilder().add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter)).build()
        let previous = OpenTelemetry.instance.tracerProvider
        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
        defer { OpenTelemetry.registerTracerProvider(tracerProvider: previous) }

        let detector = SlowRenderingDetector(configuration: SlowRenderingConfiguration(), startImmediately: false)

        // The detector exists before navigation happens, as it does in a real app.
        setScreenNameInternal("Home", true)
        detector.recordFrame(duration: 40.0 / 1e3, frameBudget: hz60)
        detector.recordFrame(duration: 16.67 / 1e3, frameBudget: hz60)
        detector.recordFrame(duration: 50.0 / 1e3, frameBudget: hz60)
        setScreenNameInternal("Settings", true)
        detector.recordFrame(duration: 900.0 / 1e3, frameBudget: hz60)
        detector.flushFrames()
        provider.forceFlush()

        let spans = exporter.getFinishedSpanItems()
        XCTAssertEqual(spans.count, 2)

        let slowSpan = try XCTUnwrap(spans.first { $0.name == "slowRenders" })
        XCTAssertEqual(slowSpan.attributes["activity.name"]?.description, "Home")
        XCTAssertEqual(slowSpan.attributes["count"]?.description, "2")
        XCTAssertEqual(slowSpan.attributes["frame.max_duration_ms"]?.description, "50.0")

        let frozenSpan = try XCTUnwrap(spans.first { $0.name == "frozenRenders" })
        XCTAssertEqual(frozenSpan.attributes["activity.name"]?.description, "Settings")
        XCTAssertEqual(frozenSpan.attributes["count"]?.description, "1")

        // Nothing slow since the last flush, so no span.
        detector.flushFrames()
        provider.forceFlush()
        XCTAssertEqual(exporter.getFinishedSpanItems().count, 2)
    }
}

#endif
