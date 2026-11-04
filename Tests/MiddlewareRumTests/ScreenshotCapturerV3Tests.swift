#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import XCTest
import UIKit
@testable import MiddlewareRum

// The test host has no render server, so `drawHierarchy` draws nothing here;
// these tests draw through the same context with UIKit calls instead.
final class ScreenshotCapturerV3Tests: XCTestCase {

    private let pointSize = CGSize(width: 400, height: 800)

    /// White background with a red 100x100 square at the top-left corner.
    private func drawScene() {
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: pointSize))
        UIColor.red.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    /// RGB of the pixel at `point` (points) in a top-left-origin image.
    private func pixel(_ image: CGImage, at point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8) {
        let scale = CGFloat(image.width) / pointSize.width
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // CGContext has a bottom-left origin: move the wanted pixel onto (0, 0).
        let x = point.x * scale
        let y = CGFloat(image.height) - point.y * scale - 1
        context.draw(image, in: CGRect(x: -x, y: -y, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (data[0], data[1], data[2])
    }

    func testRenderIsUprightAtRequestedScale() throws {
        let frame = try XCTUnwrap(ScreenshotCapturerV3.render(pointSize: pointSize, scale: 3) { drawScene() })

        XCTAssertEqual(frame.pointSize, pointSize)
        XCTAssertEqual(frame.scale, 3)
        XCTAssertEqual(frame.image.width, 1200)
        XCTAssertEqual(frame.image.height, 2400)

        let topLeft = pixel(frame.image, at: CGPoint(x: 50, y: 50))
        XCTAssertGreaterThan(topLeft.r, 200, "red square should be at the top, not flipped to the bottom")
        XCTAssertLessThan(topLeft.g, 60)
        let bottomLeft = pixel(frame.image, at: CGPoint(x: 50, y: 750))
        XCTAssertGreaterThan(bottomLeft.g, 200, "bottom-left should be the white background")
    }

    func testCaptureRendersWindowAtScreenScale() throws {
        let window = UIWindow(frame: CGRect(origin: .zero, size: pointSize))

        let frame = try XCTUnwrap(ScreenshotCapturerV3().captureMaskedImage(
            window: window, maskRects: [CGRect(x: 200, y: 0, width: 100, height: 100)]))

        XCTAssertEqual(frame.pointSize, pointSize)
        XCTAssertEqual(frame.scale, max(window.screen.scale, 1))
        XCTAssertEqual(frame.image.width, Int(pointSize.width * frame.scale))
    }

    func testOutputIsScaledToShortEdgeCap() throws {
        let frame = try XCTUnwrap(ScreenshotCapturerV3.render(pointSize: pointSize, scale: 3) { drawScene() })

        let output = try XCTUnwrap(ScreenshotCapturerV3.scaledForOutput(frame))

        // 640 / 400 = 1.6x
        XCTAssertEqual(output.width, 640)
        XCTAssertEqual(output.height, 1280)
        let topLeft = pixel(output, at: CGPoint(x: 50, y: 50))
        XCTAssertGreaterThan(topLeft.r, 200)
        XCTAssertLessThan(topLeft.g, 60)
        let bottomLeft = pixel(output, at: CGPoint(x: 50, y: 750))
        XCTAssertGreaterThan(bottomLeft.g, 200)
    }

    func testIPadFrameIsScaledDownToOnePointPerPixel() throws {
        // iPad 10th gen / iPad (A16): 820x1180 pt at 2x goes on the wire at 1x.
        let iPad = CGSize(width: 820, height: 1180)
        let frame = try XCTUnwrap(ScreenshotCapturerV3.render(pointSize: iPad, scale: 2) {})

        let output = try XCTUnwrap(ScreenshotCapturerV3.scaledForOutput(frame))

        XCTAssertEqual(output.width, 820)
        XCTAssertEqual(output.height, 1180)
    }

    func testFrameAlreadyAtOutputScaleIsNotRedrawn() throws {
        let frame = try XCTUnwrap(ScreenshotCapturerV3.render(pointSize: pointSize, scale: 1) { drawScene() })

        XCTAssertTrue(ScreenshotCapturerV3.scaledForOutput(frame) === frame.image)
    }

    func testEncodesJpegDataUriAtOutputSize() throws {
        let frame = try XCTUnwrap(ScreenshotCapturerV3.render(pointSize: pointSize, scale: 3) { drawScene() })

        let uri = try XCTUnwrap(ScreenshotCapturerV3().encodeDataUri(frame))

        let prefix = "data:image/jpeg;base64,"
        XCTAssertTrue(uri.hasPrefix(prefix))
        let jpeg = try XCTUnwrap(Data(base64Encoded: String(uri.dropFirst(prefix.count))))
        let decoded = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        XCTAssertEqual(decoded.width, 640)
        XCTAssertEqual(decoded.height, 1280)
        let topLeft = pixel(decoded, at: CGPoint(x: 50, y: 50))
        XCTAssertGreaterThan(topLeft.r, 200)
    }
}
#endif
