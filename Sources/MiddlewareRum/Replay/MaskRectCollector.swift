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
///  - WKWebView masked whole whenever any masking is on (content is opaque to us);
///  - `_UIRemoteView` (out-of-process camera/photo/contact pickers) always masked;
///  - UIPickerView masked under `maskAllTextInputs`;
///  - SwiftUI text/images detected via nil-safe class-name tables;
///  - legacy compat: `Sanitizable` elements registered via addIgnoredView /
///    `.sensitive()` are always masked.
class MaskRectCollector {

    static let noCaptureToken = "mw-no-capture"
    static let noMaskToken = "mw-no-mask"

    private let maskAllTextInputs: Bool
    private let maskAllImages: Bool

    private static let sensitiveContentTypes: Set<UITextContentType> = [
        .password, .newPassword, .oneTimeCode,
        .creditCardNumber, .telephoneNumber, .emailAddress,
        .username, .URL, .name, .nickname, .middleName, .familyName,
        .nameSuffix, .namePrefix, .organizationName, .location,
        .fullStreetAddress, .streetAddressLine1, .streetAddressLine2,
        .addressCity, .addressState, .addressCityAndState, .postalCode,
    ]

    // SwiftUI renders text/images into private UIKit views/layers; these
    // class-name tables are nil-safe (missing classes on a given OS version
    // simply mean no extra masking from that rule).
    private static let swiftUITextViewClasses: [AnyClass] = [
        "SwiftUI.CGDrawingView",
        "SwiftUI.TextEditorTextView",
        "SwiftUI.VerticalTextView",
    ].compactMap { NSClassFromString($0) }

    private static let swiftUIImageLayerClasses: [AnyClass] = [
        "SwiftUI.ImageLayer",
    ].compactMap { NSClassFromString($0) }

    private static let swiftUITextLayerClasses: [AnyClass] = [
        // iOS 26 draws SwiftUI Text/Button into this layer without a backing view
        "_TtC7SwiftUIP33_863CCF9D49B535DAEB1C7D61BEE53B5914CGDrawingLayer",
    ].compactMap { NSClassFromString($0) }

    private static let remoteViewClass: AnyClass? = NSClassFromString("_UIRemoteView")

    init(maskAllTextInputs: Bool = true, maskAllImages: Bool = true) {
        self.maskAllTextInputs = maskAllTextInputs
        self.maskAllImages = maskAllImages
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

        // SwiftUI text views (leafs)
        if maskAllTextInputs, Self.swiftUITextViewClasses.contains(where: { view.isKind(of: $0) }) {
            if view.subviews.isEmpty {
                appendRect(of: view, window: window, into: &rects)
                return
            }
        }

        // SwiftUI image/text layers hosted on generic views
        if view.subviews.isEmpty {
            if maskAllImages, layerMatches(view.layer, classes: Self.swiftUIImageLayerClasses, window: window, into: &rects) {
                return
            }
            if maskAllTextInputs, layerMatches(view.layer, classes: Self.swiftUITextLayerClasses, window: window, into: &rects) {
                return
            }
        }

        for subview in view.subviews {
            walk(subview, window: window, into: &rects)
        }
    }

    private func layerMatches(_ layer: CALayer, classes: [AnyClass], window: UIWindow, into rects: inout [CGRect]) -> Bool {
        guard !classes.isEmpty else { return false }
        var matched = false
        var layers: [CALayer] = [layer]
        layers.append(contentsOf: layer.sublayers ?? [])
        for candidate in layers where classes.contains(where: { candidate.isKind(of: $0) }) {
            let rect = candidate.convert(candidate.bounds, to: window.layer)
            if !rect.isEmpty {
                rects.append(rect)
                matched = true
            }
        }
        return matched
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
