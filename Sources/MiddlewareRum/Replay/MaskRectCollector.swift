// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit
#if os(iOS) || targetEnvironment(macCatalyst)
import WebKit
#endif

/// Walks a window's view tree on the main thread and collects the rects (in
/// window points) that must be blacked out on the captured frame.
///
/// Masking rules (ported from PostHog iOS screenshot mode):
///  - `mw-no-mask` in accessibilityIdentifier/Label always wins (subtree skipped);
///  - `mw-no-capture` forces masking of the whole view;
///  - text inputs (UITextField/UITextView) masked when `maskAllTextInputs`,
///    OR the field is secure, OR its textContentType is sensitive — secure and
///    sensitive-content fields are masked even when `maskAllTextInputs` is off;
///  - UILabel/UIButton with text masked when `maskAllTextInputs`;
///  - UIImageView masked when `maskAllImages`, unless the image comes from the
///    asset catalog or is an SF Symbol (app chrome, not user content);
///  - WKWebView masked whole when `maskAllTextInputs` or `maskAllImages` is on
///    (content is opaque to us); both are off by default, so web content is
///    recorded unless the app opts in or tags the view `mw-no-capture`;
///  - `_UIRemoteView` (out-of-process camera/photo/contact pickers) always masked;
///  - UIPickerView masked under `maskAllTextInputs`;
///  - SwiftUI text/images detected via nil-safe class-name tables, including
///    the drawing layers iOS 26 nests at any depth without a backing view;
///  - React Native text views (which draw text themselves, not via UILabel)
///    masked under `maskAllTextInputs`;
///  - legacy compat: `Sanitizable` elements registered via addIgnoredView /
///    `.sensitive()` are always masked.
class MaskRectCollector {

    static let noCaptureToken = "mw-no-capture"
    static let noMaskToken = "mw-no-mask"

    private let maskAllTextInputs: Bool
    private let maskAllImages: Bool

    private static let sensitiveContentTypes: Set<UITextContentType> = {
        var types: Set<UITextContentType> = [
            .password, .newPassword, .oneTimeCode,
            .creditCardNumber, .telephoneNumber, .emailAddress,
            .username, .URL, .name, .nickname, .middleName, .familyName,
            .nameSuffix, .namePrefix, .organizationName, .location,
            .fullStreetAddress, .streetAddressLine1, .streetAddressLine2,
            .addressCity, .addressState, .addressCityAndState, .postalCode,
        ]
        if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, *) {
            types.formUnion([
                .creditCardSecurityCode, .creditCardExpiration,
                .creditCardExpirationMonth, .creditCardExpirationYear,
                .creditCardName, .creditCardGivenName, .creditCardMiddleName,
                .creditCardFamilyName, .creditCardType,
            ])
        }
        return types
    }()

    // SwiftUI renders text/images into private UIKit views/layers; these
    // class-name tables are nil-safe (missing classes on a given OS version
    // simply mean no extra masking from that rule).
    static let swiftUITextViewClasses: [AnyClass] = [
        "SwiftUI.CGDrawingView",
        "SwiftUI.TextEditorTextView",
        "SwiftUI.VerticalTextView",
    ].compactMap { NSClassFromString($0) }

    static let swiftUIImageLayerClasses: [AnyClass] = [
        "SwiftUI.ImageLayer",
    ].compactMap { NSClassFromString($0) }

    static let swiftUITextLayerClasses: [AnyClass] = [
        // iOS 26 draws SwiftUI Text/Button into this layer without a backing view
        "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer",
    ].compactMap { NSClassFromString($0) }

    /// React Native draws text in its own views rather than UILabel: Paper's
    /// RCTTextView and Fabric's RCTParagraphComponentView.
    static let reactNativeTextViewClasses: [AnyClass] = [
        "RCTTextView",
        "RCTParagraphComponentView",
    ].compactMap { NSClassFromString($0) }

    private static let remoteViewClass: AnyClass? = NSClassFromString("_UIRemoteView")

    private let textLayerClasses: [AnyClass]
    private let imageLayerClasses: [AnyClass]
    private let textDrawingViewClasses: [AnyClass]

    /// The class tables are parameters only so tests can stand in for the
    /// private SwiftUI and React Native classes.
    init(
        maskAllTextInputs: Bool = false,
        maskAllImages: Bool = false,
        textLayerClasses: [AnyClass] = MaskRectCollector.swiftUITextLayerClasses,
        imageLayerClasses: [AnyClass] = MaskRectCollector.swiftUIImageLayerClasses,
        textDrawingViewClasses: [AnyClass] = MaskRectCollector.reactNativeTextViewClasses
    ) {
        self.maskAllTextInputs = maskAllTextInputs
        self.maskAllImages = maskAllImages
        self.textLayerClasses = textLayerClasses
        self.imageLayerClasses = imageLayerClasses
        self.textDrawingViewClasses = textDrawingViewClasses
    }

    /// Main thread only.
    func collect(in window: UIWindow, sanitized: [Sanitizable]) -> [CGRect] {
        var rects: [CGRect] = []
        for element in sanitized {
            if let frame = element.frameInWindow, !frame.isEmpty {
                rects.append(frame)
            }
        }
        walk(window, window: window, into: &rects)
        return rects
    }

    private func walk(_ view: UIView, window: UIWindow, into rects: inout [CGRect]) {
        guard isVisible(view) else { return }

        if isUnmasked(view) {
            // mw-no-mask unmasks the whole subtree
            return
        }

        if isNoCapture(view) {
            appendRect(of: view, window: window, into: &rects)
            return
        }

        if let remoteClass = Self.remoteViewClass, view.isKind(of: remoteClass) {
            appendRect(of: view, window: window, into: &rects)
            return
        }

        if let textField = view as? UITextField {
            if maskAllTextInputs || isSensitiveInput(textField) {
                let hasContent = isUsefulString(textField.text) || isUsefulString(textField.placeholder)
                if hasContent {
                    appendRect(of: textField, window: window, into: &rects)
                }
            }
            return
        }

        if let textView = view as? UITextView {
            if (maskAllTextInputs || isSensitiveInput(textView)) && isUsefulString(textView.text) {
                appendRect(of: textView, window: window, into: &rects)
            }
            return
        }

        if let label = view as? UILabel {
            if maskAllTextInputs && isUsefulString(label.text) {
                appendRect(of: label, window: window, into: &rects)
            }
            return
        }

        if let button = view as? UIButton {
            if maskAllTextInputs && isUsefulString(button.titleLabel?.text) {
                appendRect(of: button, window: window, into: &rects)
            }
            return
        }

        if let imageView = view as? UIImageView {
            if shouldMask(imageView) {
                appendRect(of: imageView, window: window, into: &rects)
            }
            return
        }

        #if os(iOS) || targetEnvironment(macCatalyst)
        if view is WKWebView {
            if maskAllTextInputs || maskAllImages {
                appendRect(of: view, window: window, into: &rects)
            }
            return
        }

        if view is UIPickerView {
            if maskAllTextInputs {
                appendRect(of: view, window: window, into: &rects)
            }
            return
        }
        #endif

        // React Native text, including any inline views it hosts
        if maskAllTextInputs, textDrawingViewClasses.contains(where: { view.isKind(of: $0) }) {
            appendRect(of: view, window: window, into: &rects)
            return
        }

        // SwiftUI text views (leafs)
        if maskAllTextInputs, Self.swiftUITextViewClasses.contains(where: { view.isKind(of: $0) }) {
            if view.subviews.isEmpty {
                appendRect(of: view, window: window, into: &rects)
                return
            }
        }

        // SwiftUI image/text layers backing a leaf view
        if view.subviews.isEmpty, maskableDrawingLayer(view.layer) {
            appendRect(of: view.layer, window: window, into: &rects)
            return
        }

        // SwiftUI on iOS 26 draws text and images into sublayers with no
        // backing view, nested at any depth; subviews' layers are walked below.
        collectDrawingSublayers(of: view.layer, window: window, into: &rects)

        for subview in view.subviews {
            walk(subview, window: window, into: &rects)
        }
    }

    private func maskableDrawingLayer(_ layer: CALayer) -> Bool {
        if maskAllTextInputs, textLayerClasses.contains(where: { layer.isKind(of: $0) }) {
            return true
        }
        if maskAllImages, imageLayerClasses.contains(where: { layer.isKind(of: $0) }) {
            return true
        }
        return false
    }

    private func collectDrawingSublayers(of layer: CALayer, window: UIWindow, into rects: inout [CGRect]) {
        guard (maskAllTextInputs && !textLayerClasses.isEmpty) || (maskAllImages && !imageLayerClasses.isEmpty) else {
            return
        }
        for sublayer in layer.sublayers ?? [] {
            if sublayer.delegate is UIView || sublayer.isHidden || sublayer.opacity <= 0 {
                continue
            }
            if maskableDrawingLayer(sublayer) {
                appendRect(of: sublayer, window: window, into: &rects)
            } else {
                collectDrawingSublayers(of: sublayer, window: window, into: &rects)
            }
        }
    }

    private func appendRect(of layer: CALayer, window: UIWindow, into rects: inout [CGRect]) {
        let rect = layer.convert(layer.bounds, to: window.layer)
        if !rect.isEmpty {
            rects.append(rect)
        }
    }

    private func appendRect(of view: UIView, window: UIWindow, into rects: inout [CGRect]) {
        let rect = view.convert(view.bounds, to: window)
        if !rect.isEmpty {
            rects.append(rect)
        }
    }

    private func isVisible(_ view: UIView) -> Bool {
        return !view.isHidden && view.alpha > 0 && view.bounds.size != .zero
    }

    /// Secure entry and sensitive content types are masked unconditionally.
    private func isSensitiveInput(_ traits: UITextInputTraits) -> Bool {
        if traits.isSecureTextEntry == true {
            return true
        }
        // textContentType is UITextContentType! behind an optional protocol
        // requirement, hence the double unwrap.
        if let wrapped = traits.textContentType, let contentType = wrapped,
           Self.sensitiveContentTypes.contains(contentType) {
            return true
        }
        return false
    }

    private func isNoCapture(_ view: UIView) -> Bool {
        return containsToken(view, Self.noCaptureToken)
    }

    private func isUnmasked(_ view: UIView) -> Bool {
        return containsToken(view, Self.noMaskToken)
    }

    private func containsToken(_ view: UIView, _ token: String) -> Bool {
        if view.accessibilityIdentifier?.range(of: token, options: .caseInsensitive) != nil {
            return true
        }
        if view.accessibilityLabel?.range(of: token, options: .caseInsensitive) != nil {
            return true
        }
        return false
    }

    private func shouldMask(_ imageView: UIImageView) -> Bool {
        guard maskAllImages, let image = imageView.image else { return false }
        // Asset-catalog images and SF Symbols are app chrome, not user content.
        if let asset = image.imageAsset, asset.value(forKey: "_containingBundle") != nil {
            return false
        }
        if image.isSymbolImage {
            return false
        }
        return true
    }
}
#endif
