// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// A window frame rendered at the screen's native scale, before it is
/// scaled down for the wire.
struct CapturedFrame {
    let image: CGImage
    /// Window size in points.
    let pointSize: CGSize
    /// Pixels per point of `image`.
    let scale: CGFloat
}

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
    ///
    /// Draws into a plain bitmap context at the screen's native scale, which
    /// keeps the main thread as short as possible: `UIGraphicsImageRenderer`
    /// costs several times more per frame on device, and so does making
    /// `drawHierarchy` scale while it draws. Scaling down for the wire
    /// happens off the main thread, in `encodeDataUri`.
    func captureMaskedImage(window: UIWindow, maskRects: [CGRect]) -> CapturedFrame? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = max(window.screen.scale, 1)
        return Self.render(pointSize: bounds.size, scale: scale) {
            // afterScreenUpdates: true causes visible flicker when secure
            // text fields are on screen; false accepts a rare stale frame.
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            UIColor.black.setFill()
            for rect in maskRects {
                UIBezierPath(roundedRect: rect, cornerRadius: Self.maskCornerRadius).fill()
            }
        }
    }

    /// Runs `draw` with a UIKit (top-left origin, points) current context
    /// backed by a bitmap of `pointSize` × `scale` pixels.
    static func render(pointSize: CGSize, scale: CGFloat, _ draw: () -> Void) -> CapturedFrame? {
        guard let context = makeContext(
            width: Int((pointSize.width * scale).rounded()),
            height: Int((pointSize.height * scale).rounded())) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)

        return autoreleasepool {
            UIGraphicsPushContext(context)
            draw()
            UIGraphicsPopContext()

            guard let image = context.makeImage() else { return nil }
            return CapturedFrame(image: image, pointSize: pointSize, scale: scale)
        }
    }

    /// CPU-bound; call off the main thread inside an autoreleasepool.
    /// iOS has no system WebP encoder — JPEG is part of the wire contract.
    func encodeDataUri(_ frame: CapturedFrame) -> String? {
        guard let image = Self.scaledForOutput(frame),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    /// Scales a native-scale frame down to `renderScale`; returns it as is
    /// when it is already that size.
    static func scaledForOutput(_ frame: CapturedFrame) -> CGImage? {
        let outputScale = renderScale(for: frame.pointSize, screenScale: frame.scale)
        guard outputScale < frame.scale else { return frame.image }

        guard let context = makeContext(
            width: Int((frame.pointSize.width * outputScale).rounded()),
            height: Int((frame.pointSize.height * outputScale).rounded())) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(frame.image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage()
    }

    /// Opaque 32-bit BGRX context, the layout iOS uses for opaque images
    /// (JPEG has no alpha anyway).
    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }
}
#endif
