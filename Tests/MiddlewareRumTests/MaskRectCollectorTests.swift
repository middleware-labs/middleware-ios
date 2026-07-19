#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import XCTest
import UIKit
@testable import MiddlewareRum

final class MaskRectCollectorTests: XCTestCase {

    private func makeWindow(with views: [UIView]) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.isHidden = false // new windows start hidden; the walk skips hidden trees
        var y: CGFloat = 10
        for view in views {
            view.frame = CGRect(x: 10, y: y, width: 200, height: 40)
            window.addSubview(view)
            y += 50
        }
        window.layoutIfNeeded()
        return window
    }

    func testSecureFieldMaskedEvenWhenMaskAllTextInputsOff() {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = "secret"
        let window = makeWindow(with: [field])

        let collector = MaskRectCollector(maskAllTextInputs: false, maskAllImages: false)
        let rects = collector.collect(in: window, sanitized: [])
        XCTAssertEqual(rects.count, 1)
    }

    func testSensitiveContentTypeMasked() {
        let field = UITextField()
        field.textContentType = .password
        field.text = "hunter2"
        let window = makeWindow(with: [field])

        let collector = MaskRectCollector(maskAllTextInputs: false, maskAllImages: false)
        let rects = collector.collect(in: window, sanitized: [])
        XCTAssertEqual(rects.count, 1)
    }

    func testPlainLabelMaskedOnlyWhenMaskAllTextInputs() {
        let label = UILabel()
        label.text = "hello"
        let window = makeWindow(with: [label])

        XCTAssertEqual(MaskRectCollector(maskAllTextInputs: true, maskAllImages: false)
            .collect(in: window, sanitized: []).count, 1)
        XCTAssertEqual(MaskRectCollector(maskAllTextInputs: false, maskAllImages: false)
            .collect(in: window, sanitized: []).count, 0)
    }

    func testNoMaskTokenWins() {
        let label = UILabel()
        label.text = "hello"
        label.accessibilityIdentifier = "some-mw-no-mask-view"
        let window = makeWindow(with: [label])

        let collector = MaskRectCollector(maskAllTextInputs: true, maskAllImages: true)
        XCTAssertEqual(collector.collect(in: window, sanitized: []).count, 0)
    }

    func testNoCaptureTokenForcesMasking() {
        let view = UIView()
        view.accessibilityLabel = "mw-no-capture"
        let window = makeWindow(with: [view])

        let collector = MaskRectCollector(maskAllTextInputs: false, maskAllImages: false)
        XCTAssertEqual(collector.collect(in: window, sanitized: []).count, 1)
    }

    func testDecodedImageMaskedButSymbolImageNot() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let decodedImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let decoded = UIImageView(image: decodedImage)
        let symbol = UIImageView(image: UIImage(systemName: "square.and.arrow.up"))
        let window = makeWindow(with: [decoded, symbol])

        let collector = MaskRectCollector(maskAllTextInputs: false, maskAllImages: true)
        let rects = collector.collect(in: window, sanitized: [])
        XCTAssertEqual(rects.count, 1, "only the decoded image should be masked")
    }

    func testHiddenViewsSkipped() {
        let label = UILabel()
        label.text = "hello"
        label.isHidden = true
        let window = makeWindow(with: [label])

        let collector = MaskRectCollector(maskAllTextInputs: true, maskAllImages: true)
        XCTAssertEqual(collector.collect(in: window, sanitized: []).count, 0)
    }

    func testSanitizedElementsAlwaysMasked() {
        let plain = UIView()
        let window = makeWindow(with: [plain])

        let collector = MaskRectCollector(maskAllTextInputs: false, maskAllImages: false)
        let rects = collector.collect(in: window, sanitized: [plain])
        XCTAssertEqual(rects.count, 1)
    }

    func testRenderScaleCapsShortEdge() {
        // iPhone-sized window at 3x native scale gets capped near 640/393
        let phoneScale = ScreenshotCapturerV3.renderScale(for: CGSize(width: 393, height: 852), screenScale: 3)
        XCTAssertEqual(phoneScale, 640.0 / 393.0, accuracy: 0.001)
        // iPad-sized window is already >= 640pt short edge -> scale 1
        XCTAssertEqual(ScreenshotCapturerV3.renderScale(for: CGSize(width: 768, height: 1024), screenScale: 2), 1)
        // tiny scale never exceeds native
        XCTAssertEqual(ScreenshotCapturerV3.renderScale(for: CGSize(width: 320, height: 480), screenScale: 1), 1)
        // zero size guards
        XCTAssertEqual(ScreenshotCapturerV3.renderScale(for: .zero, screenScale: 3), 1)
    }
}
#endif
