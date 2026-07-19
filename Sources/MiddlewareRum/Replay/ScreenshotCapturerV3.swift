// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// Captures window frames for v3 session recording and turns them into
/// masked, compressed data URIs.
class ScreenshotCapturerV3 {

    /// Target resolution of the shorter screen edge, matching the Android
    /// SDK's 640 px short edge.
    static let shortEdgePx: CGFloat = 640
    private static let maskCornerRadius: CGFloat = 10

    let jpegQuality: CGFloat

    init(jpegQuality: CGFloat = 0.5) {
        self.jpegQuality = jpegQuality
    }

    /// Render scale that caps the output's short edge at [shortEdgePx] while
    /// never exceeding the native screen scale (and never below 1).
    static func renderScale(for size: CGSize, screenScale: CGFloat) -> CGFloat {
        let shortEdge = min(size.width, size.height)
        guard shortEdge > 0 else { return 1 }
        return max(1, min(screenScale, shortEdgePx / shortEdge))
    }

    /// Main thread only. Renders the window and paints the mask rects
    /// (window points) as black rounded rects in the same context.
    /// Returns nil when the window has no size or rendering fails.
    func captureMaskedImage(window: UIWindow, maskRects: [CGRect]) -> UIImage? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.renderScale(for: bounds.size, screenScale: window.screen.scale)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        return autoreleasepool {
            renderer.image { _ in
                // afterScreenUpdates: true causes visible flicker when secure
                // text fields are on screen; false accepts a rare stale frame.
                window.drawHierarchy(in: bounds, afterScreenUpdates: false)
                UIColor.black.setFill()
                for rect in maskRects {
                    UIBezierPath(roundedRect: rect, cornerRadius: Self.maskCornerRadius).fill()
                }
            }
        }
    }

    /// CPU-bound; call off the main thread inside an autoreleasepool.
    /// iOS has no system WebP encoder — JPEG is part of the wire contract.
    func encodeDataUri(_ image: UIImage) -> String? {
        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
#endif
