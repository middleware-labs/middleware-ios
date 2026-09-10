import XCTest
@testable import MiddlewareRum

final class MiddlewareRumTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }

    func testRecordingEnabledByDefault() {
        let builder = MiddlewareRumBuilder()
        XCTAssertTrue(builder.isRecordingEnabled())
    }

    func testDisableRecording() {
        let builder = MiddlewareRumBuilder().disableRecording()
        XCTAssertFalse(builder.isRecordingEnabled())
    }

    func testOtlpExportHeadersIncludeAuthorizationForLogsAndTraces() {
        let headers = MiddlewareRum.otlpExportHeaders(token: "rum-token")
        XCTAssertEqual(headers.first(where: { $0.0 == "Authorization" })?.1, "rum-token")
        XCTAssertEqual(headers.first(where: { $0.0 == "Origin" })?.1, "sdk.middleware.io")
    }

    func testResourceCarriesBrowserTraceAndRecordingFlags() {
        let builder = MiddlewareRumBuilder()
            .target("https://example.middleware.io")
            .serviceName("test-service")
            .projectName("test-project")
            .rumAccessToken("token")
        let resource = MiddlewareRum.createMiddlewareResource(builder: builder)
        XCTAssertEqual(resource.attributes[MiddlewareConstants.Attributes.BROWSER_TRACE]?.description, "true")
        XCTAssertEqual(resource.attributes[MiddlewareConstants.Attributes.RECORDING]?.description, "1")
    }
}
