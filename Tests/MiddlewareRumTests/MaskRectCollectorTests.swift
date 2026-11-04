#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import XCTest
import UIKit
#if os(iOS) || targetEnvironment(macCatalyst)
import WebKit
#endif
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

    func testDefaultsMaskOnlySensitiveInputs() {
        let label = UILabel()
        label.text = "hello"
        let plainField = UITextField()
        plainField.text = "search query"
        let cardField = UITextField()
        cardField.textContentType = .creditCardNumber
        cardField.text = "4111 1111 1111 1111"
        let window = makeWindow(with: [label, plainField, cardField])

        let rects = MaskRectCollector().collect(in: window, sanitized: [])
        XCTAssertEqual(rects.count, 1, "only the card number field should be masked")
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    func testWebViewRecordedByDefaultAndMaskedOnOptIn() {
        let webView = WKWebView()
        let window = makeWindow(with: [webView])

        XCTAssertEqual(MaskRectCollector().collect(in: window, sanitized: []).count, 0)
        XCTAssertEqual(MaskRectCollector(maskAllTextInputs: true, maskAllImages: false)
            .collect(in: window, sanitized: []).count, 1)
    }
    #endif

    // MARK: - SwiftUI drawing layers and React Native text

    /// Stand-ins for SwiftUI's private drawing layers and RN's text view.
    private final class FakeTextLayer: CALayer {}
    private final class FakeImageLayer: CALayer {}
    private final class FakeRNTextView: UIView {}
    private final class TextLayerBackedView: UIView {
        override class var layerClass: AnyClass { FakeTextLayer.self }
    }

    private func collector(maskAllText: Bool = true, maskAllImages: Bool = false) -> MaskRectCollector {
        MaskRectCollector(
            maskAllTextInputs: maskAllText,
            maskAllImages: maskAllImages,
            textLayerClasses: [FakeTextLayer.self],
            imageLayerClasses: [FakeImageLayer.self],
            textDrawingViewClasses: [FakeRNTextView.self])
    }

    /// A container with a subview and, like an iOS 26 SwiftUI card, a text
    /// layer two sublayers deep with no backing view.
    private func makeCardWindow() -> (UIWindow, FakeTextLayer) {
        let container = UIView()
        container.addSubview(UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let card = CALayer()
        card.frame = CGRect(x: 20, y: 0, width: 150, height: 40)
        let text = FakeTextLayer()
        text.frame = CGRect(x: 10, y: 5, width: 60, height: 20)
        card.addSublayer(text)
        container.layer.addSublayer(card)
        return (makeWindow(with: [container]), text)
    }

    func testNestedDrawingLayerMaskedOnViewWithSubviews() {
        let (window, _) = makeCardWindow()

        // container at (10, 10), card at +20, text at +10/+5
        XCTAssertEqual(collector().collect(in: window, sanitized: []),
                       [CGRect(x: 40, y: 15, width: 60, height: 20)])
        XCTAssertEqual(collector(maskAllText: false).collect(in: window, sanitized: []), [])
    }

    func testHiddenDrawingLayerSkipped() {
        let (window, text) = makeCardWindow()
        text.isHidden = true

        XCTAssertEqual(collector().collect(in: window, sanitized: []), [])
    }

    func testSubviewLayersAreNotCountedTwice() {
        let view = TextLayerBackedView()
        let window = makeWindow(with: [view])

        XCTAssertEqual(collector().collect(in: window, sanitized: []).count, 1)
    }

    func testDrawingImageLayerMaskedOnlyWhenMaskAllImages() {
        let container = UIView()
        let image = FakeImageLayer()
        image.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        container.layer.addSublayer(image)
        let window = makeWindow(with: [container])

        XCTAssertEqual(collector(maskAllText: true, maskAllImages: false).collect(in: window, sanitized: []), [])
        XCTAssertEqual(collector(maskAllText: false, maskAllImages: true).collect(in: window, sanitized: []).count, 1)
    }

    func testReactNativeTextViewMaskedWholeOnlyWhenMaskAllText() {
        let text = FakeRNTextView()
        let inline = UILabel(frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        inline.text = "inline"
        text.addSubview(inline)
        let window = makeWindow(with: [text])

        XCTAssertEqual(collector().collect(in: window, sanitized: []),
                       [CGRect(x: 10, y: 10, width: 200, height: 40)])
        XCTAssertEqual(collector(maskAllText: false).collect(in: window, sanitized: []), [])
    }

    func testReactNativeTextClassesResolveByName() {
        // The real classes only exist in RN apps; the table must just be nil-safe.
        XCTAssertTrue(MaskRectCollector.reactNativeTextViewClasses.isEmpty)
    }

    // MARK: - Private names and named images

    func testEncodedPrivateNamesDecodeAndResolve() {
        XCTAssertEqual(decodedPrivateName("X1VJUmVtb3RlVmlldw=="), "_UIRemoteView")
        XCTAssertEqual(decodedPrivateName("X1VJV2luZG93U3lzdGVtR2VzdHVyZVN0YXRlQ2hhbmdlZE5vdGlmaWNhdGlvbg=="),
                       "_UIWindowSystemGestureStateChangedNotification")
        XCTAssertEqual(decodedPrivateName("X1R0QzdTd2lmdFVJUDMzXzg2M0NDRjlENDlCNTM1REFFQjFDN0Q2MUJFRTUzQjU5MTRDR0RyYXdpbmdMYXllcg=="),
                       "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer")
        XCTAssertNil(decodedPrivateName("not base64!"))

        XCTAssertNotNil(decodedPrivateName("X1VJUmVtb3RlVmlldw==").flatMap(NSClassFromString))
        if #available(iOS 26.0, tvOS 26.0, *) {
            XCTAssertFalse(MaskRectCollector.swiftUITextLayerClasses.isEmpty, "SwiftUI text layer class should resolve on iOS 26")
        }
    }

    /// UIImage(named:) needs an asset catalog the test bundle lacks; stand in
    /// with the description format iOS 26 prints for catalog images.
    private final class CatalogImage: UIImage {
        override var description: String {
            "<UIImage:0x102e1c3c0 named(main: Logo) {20, 20} renderingMode=automatic(original)>"
        }
    }

    func testCatalogImageNotMaskedButDerivedImageIs() {
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        let catalog = CatalogImage(cgImage: drawn.cgImage!)
        XCTAssertTrue(MaskRectCollector.isNamedImage(catalog))
        XCTAssertFalse(MaskRectCollector.isNamedImage(drawn))

        let window = makeWindow(with: [UIImageView(image: catalog), UIImageView(image: drawn)])
        let rects = MaskRectCollector(maskAllTextInputs: false, maskAllImages: true).collect(in: window, sanitized: [])
        XCTAssertEqual(rects.count, 1, "only the drawn image should be masked")
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
