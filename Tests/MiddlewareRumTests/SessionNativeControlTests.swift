import XCTest
@testable import MiddlewareRum

final class SessionNativeControlTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Session APIs update the active resource; register a real provider
        // (the default no-op provider has no resource storage).
        if !(OpenTelemetry.instance.tracerProvider is TracerProviderSdk) {
            OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder().build())
        }
    }

    override func tearDown() {
        // release external session control so other suites (e.g. WebView
        // session-rotation tests) see normal rotation behavior again
        resetNativeSessionControlInternal()
        super.tearDown()
    }

    func testInjectedSessionWinsAndSuppressesRotation() {
        let injected = "cafebabecafebabecafebabecafebabe"
        MiddlewareRum.setNativeSession(injected, startTimeMs: 1750000000000)

        XCTAssertEqual(getRumSessionId(), injected)
        XCTAssertEqual(getSessionStartTime(), 1750000000000)
        XCTAssertTrue(isNativeSessionControlled())

        // forced rotation must be a no-op while externally controlled
        XCTAssertEqual(getRumSessionId(forceNewSessionId: true), injected)
    }

    func testCallbacksFireOnChangeOnly() {
        var fired = 0
        addSessionIdCallback { fired += 1 }

        MiddlewareRum.setNativeSession("11111111111111111111111111111111", startTimeMs: 1000)
        let afterFirst = fired
        XCTAssertGreaterThanOrEqual(afterFirst, 1)

        // re-pushing the identical id must not fire callbacks again
        MiddlewareRum.setNativeSession("11111111111111111111111111111111", startTimeMs: 1000)
        XCTAssertEqual(fired, afterFirst)

        // a new id fires again
        MiddlewareRum.setNativeSession("22222222222222222222222222222222", startTimeMs: 2000)
        XCTAssertEqual(fired, afterFirst + 1)
    }

    func testActiveResourceCarriesInjectedSession() {
        MiddlewareRum.setNativeSession("33333333333333333333333333333333", startTimeMs: 3000)
        let resource = OpenTelemetry.instance.tracerProvider.getActiveResource()
        XCTAssertEqual(
            resource.attributes[MiddlewareConstants.Attributes.SESSION_ID]?.description,
            "33333333333333333333333333333333")
        XCTAssertEqual(
            resource.attributes[MiddlewareConstants.Attributes.SESSION_START_TIME]?.description,
            "3000")
    }
}
