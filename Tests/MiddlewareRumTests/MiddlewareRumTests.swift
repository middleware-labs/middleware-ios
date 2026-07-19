import XCTest
@testable import MiddlewareRum

final class MiddlewareRumTests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods
    }

    func testRecordingV3EnabledByDefault() {
        let builder = MiddlewareRumBuilder()
        XCTAssertTrue(builder.isRecordingEnabled())
        XCTAssertTrue(builder.isSessionRecordingV3Enabled())
    }

    func testDisableSessionRecordingV3FallsBackToV2() {
        let builder = MiddlewareRumBuilder().disableSessionRecordingV3()
        XCTAssertTrue(builder.isRecordingEnabled())
        XCTAssertFalse(builder.isSessionRecordingV3Enabled())
    }

    func testDisableRecordingAlsoDisablesV3() {
        let builder = MiddlewareRumBuilder().disableRecording()
        XCTAssertFalse(builder.isRecordingEnabled())
        XCTAssertFalse(builder.isSessionRecordingV3Enabled())
    }
}
