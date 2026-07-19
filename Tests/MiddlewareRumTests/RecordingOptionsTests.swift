#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import XCTest
@testable import MiddlewareRum

final class RecordingOptionsTests: XCTestCase {

    func testDefaults() {
        let options = RecordingOptions()
        XCTAssertEqual(options.frequency, .low)
        XCTAssertEqual(options.quality, .Standard)
        XCTAssertTrue(options.maskAllTextInputs)
        XCTAssertTrue(options.maskAllImages)
    }

    func testFluentSetters() {
        let options = RecordingOptions()
            .setFrequency(.high)
            .setQuality(.High)
            .setMaskAllTextInputs(false)
            .setMaskAllImages(false)
        XCTAssertEqual(options.frequency, .high)
        XCTAssertEqual(options.quality, .High)
        XCTAssertFalse(options.maskAllTextInputs)
        XCTAssertFalse(options.maskAllImages)
    }

    func testFrequencyIntervals() {
        XCTAssertEqual(RecordingFrequency.low.intervalSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(RecordingFrequency.standard.intervalSeconds, 0.33, accuracy: 0.001)
        XCTAssertEqual(RecordingFrequency.high.intervalSeconds, 0.1, accuracy: 0.001)
    }

    func testJpegQualityMatchesAndroid() {
        XCTAssertEqual(RecordingOptions().setQuality(.Low).jpegQuality, 0.25, accuracy: 0.001)
        XCTAssertEqual(RecordingOptions().setQuality(.Standard).jpegQuality, 0.5, accuracy: 0.001)
        XCTAssertEqual(RecordingOptions().setQuality(.High).jpegQuality, 0.75, accuracy: 0.001)
    }

    func testBuilderCarriesRecordingOptions() {
        let options = RecordingOptions().setFrequency(.standard)
        let builder = MiddlewareRumBuilder().recordingOptions(options)
        XCTAssertTrue(builder.recordingOptions === options)
    }
}
#endif
