// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// A window frame rendered at the screen's native scale, before it is
/// masked and scaled down for the wire.
///
/// `image` is unmasked: it never leaves the process, and `encodeDataUri`
/// always paints `maskRects` over it.
struct CapturedFrame {
    let image: CGImage
    /// Window size in points.
    let pointSize: CGSize
    /// Pixels per point of `image`.
    let scale: CGFloat
    /// Rects to black out, in window points.
    let maskRects: [CGRect]
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

    /// Main thread only. Renders the window; `maskRects` (window points) are
    /// painted later, off the main thread, by `encodeDataUri`.
    /// Returns nil when the window has no size or rendering fails.
    ///
    /// Draws into a plain bitmap context at the screen's native scale, which
    /// keeps the main thread as short as possible: `UIGraphicsImageRenderer`
    /// costs several times more per frame on device, and so does making
    /// `drawHierarchy` scale while it draws.
    func capture(window: UIWindow, maskRects: [CGRect]) -> CapturedFrame? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = max(window.screen.scale, 1)
        return Self.render(pointSize: bounds.size, scale: scale, maskRects: maskRects) {
            // afterScreenUpdates: true causes visible flicker when secure
            // text fields are on screen; false accepts a rare stale frame.
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }

    /// Runs `draw` with a UIKit (top-left origin, points) current context
    /// backed by a bitmap of `pointSize` × `scale` pixels.
    static func render(pointSize: CGSize, scale: CGFloat, maskRects: [CGRect] = [], _ draw: () -> Void) -> CapturedFrame? {
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
            return CapturedFrame(image: image, pointSize: pointSize, scale: scale, maskRects: maskRects)
        }
    }

    /// CPU-bound; call off the main thread inside an autoreleasepool.
    /// iOS has no system WebP encoder — JPEG is part of the wire contract.
    func encodeDataUri(_ frame: CapturedFrame) -> String? {
        guard let image = Self.outputImage(frame),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    /// Thread-safe. Scales a native-scale frame down to `renderScale` and
    /// paints its mask rects as black rounded rects. Returns the image as is
    /// when it is already that size and has nothing to mask.
    static func outputImage(_ frame: CapturedFrame) -> CGImage? {
        let outputScale = renderScale(for: frame.pointSize, screenScale: frame.scale)
        if outputScale >= frame.scale && frame.maskRects.isEmpty {
            return frame.image
        }

        let source = UIImage(cgImage: frame.image, scale: frame.scale, orientation: .up)
        return render(pointSize: frame.pointSize, scale: min(outputScale, frame.scale)) {
            UIGraphicsGetCurrentContext()?.interpolationQuality = .medium
            source.draw(in: CGRect(origin: .zero, size: frame.pointSize))
            UIColor.black.setFill()
            for rect in frame.maskRects {
                UIBezierPath(roundedRect: rect, cornerRadius: maskCornerRadius).fill()
            }
        }?.image
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
