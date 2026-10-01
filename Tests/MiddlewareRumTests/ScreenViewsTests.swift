import XCTest
@testable import MiddlewareRum

final class ScreenViewsTests: XCTestCase {
    private var exporter: InMemoryExporter!
    private var processor: SimpleSpanProcessor!

    override func setUp() {
        super.setUp()
        exporter = InMemoryExporter()
        processor = SimpleSpanProcessor(spanExporter: exporter)
        OpenTelemetry.registerTracerProvider(
            tracerProvider: TracerProviderBuilder()
                .add(spanProcessor: processor)
                .build()
        )
        ScreenViews.shared.resetForTest()
    }

    override func tearDown() {
        ScreenViews.shared.resetForTest()
        super.tearDown()
    }

    private func screenViews() -> [SpanData] {
        // SimpleSpanProcessor exports on a background queue.
        processor.forceFlush()
        return exporter.getFinishedSpanItems().filter {
            $0.attributes[MiddlewareConstants.Attributes.EVENT_TYPE]?.description == "screen_view"
        }
    }

    func testEmitsNothingUntilArmed() {
        ScreenViews.shared.record("Home")
        XCTAssertTrue(screenViews().isEmpty)
    }

    func testEmitsOneScreenViewPerScreenChange() {
        ScreenViews.shared.armForTest()

        ScreenViews.shared.record("unknown")
        ScreenViews.shared.record("Home")
        ScreenViews.shared.record("Home")
        ScreenViews.shared.record("Cart")
        ScreenViews.shared.record("Home")

        let views = screenViews()
        XCTAssertEqual(views.map { $0.name }, ["Home", "Cart", "Home"])
        for view in views {
            XCTAssertEqual(view.attributes[MiddlewareConstants.Attributes.SCREEN_NAME]?.description, view.name)
        }
        XCTAssertNil(views[0].attributes[MiddlewareConstants.Attributes.LAST_SCREEN_NAME])
        XCTAssertEqual(views[1].attributes[MiddlewareConstants.Attributes.LAST_SCREEN_NAME]?.description, "Home")
    }
}
