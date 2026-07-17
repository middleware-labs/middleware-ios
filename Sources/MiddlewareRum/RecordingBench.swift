// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit
import Foundation
import SWCompression

/// Capture / encode micro-benchmark that mirrors `ScreenshotManager` without uploading.
public struct RecordingBenchMetrics: Codable {
    public let scenario: String
    public let quality: String
    public let frames: Int
    public let durationMs: Double
    public let avgCaptureMs: Double
    public let p95CaptureMs: Double
    public let avgJpegBytes: Int
    public let totalJpegBytes: Int
    public let gzipBatchBytes: Int
    public let uploadMbPerMin: Double
    public let captureRateSec: Double
    public let imgCompression: Double
    public let sanitizeEnabled: Bool
    public let sanitizeRects: Int
}

public enum RecordingBench {
    /// Builds a dense synthetic screen, optionally with a “sensitive” region, and measures
    /// drawHierarchy + JPEG + tar.gz batching — the hot path for session recording.
    public static func run(
        scenario: String = "capture_encode",
        frames: Int = 30,
        quality: RecordingQuality = .Low,
        sanitize: Bool = true,
        screenSize: CGSize = CGSize(width: 390, height: 844)
    ) throws -> RecordingBenchMetrics {
        let settings = getCaptureSettings(for: quality)
        let window = UIWindow(frame: CGRect(origin: .zero, size: screenSize))
        let root = UIView(frame: window.bounds)
        root.backgroundColor = UIColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)

        // Dense hierarchy (scroll/list churn proxy)
        for i in 0..<24 {
            let y = CGFloat(48 + i * 36)
            let row = UILabel(frame: CGRect(x: 16, y: y, width: screenSize.width - 32, height: 28))
            row.text = "Bench row \(i) — product \(1000 + i) — $\(i).99"
            row.font = UIFont.systemFont(ofSize: 15)
            row.backgroundColor = i % 2 == 0 ? UIColor.white : UIColor(white: 0.96, alpha: 1)
            root.addSubview(row)
        }

        let card = UITextField(frame: CGRect(x: 16, y: screenSize.height - 160, width: screenSize.width - 32, height: 44))
        card.borderStyle = .roundedRect
        card.text = sanitize ? "4111111111111111" : "Ada Lovelace"
        card.isSecureTextEntry = sanitize
        root.addSubview(card)

        let sanitizeRect = CGRect(x: 16, y: screenSize.height - 160, width: screenSize.width - 32, height: 44)

        window.rootViewController = UIViewController()
        window.rootViewController?.view = root
        window.makeKeyAndVisible()
        root.layoutIfNeeded()

        var samples: [Double] = []
        var jpegSizes: [Int] = []
        var jpegBatch: [Data] = []
        let t0 = CFAbsoluteTimeGetCurrent()

        for _ in 0..<frames {
            let frameStart = CFAbsoluteTimeGetCurrent()
            let scale: CGFloat = 1.25
            UIGraphicsBeginImageContextWithOptions(screenSize, false, scale)
            defer { UIGraphicsEndImageContext() }
            guard let ctx = UIGraphicsGetCurrentContext() else {
                throw NSError(domain: "RecordingBench", code: 1, userInfo: [NSLocalizedDescriptionKey: "no graphics context"])
            }

            root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)

            if sanitize {
                let stripeWidth: CGFloat = 5
                let stripeSpacing: CGFloat = 15
                let converted = sanitizeRect
                let crop = CGRect(
                    x: converted.origin.x * scale,
                    y: converted.origin.y * scale,
                    width: converted.size.width * scale,
                    height: converted.size.height * scale
                )
                if let region = UIGraphicsGetImageFromCurrentImageContext()?.cgImage?.cropping(to: crop) {
                    let imageToBlur = UIImage(cgImage: region, scale: scale, orientation: .up)
                    let blurred = imageToBlur.applyBlurWithRadius(2.5)
                    blurred?.draw(in: converted)
                    ctx.saveGState()
                    UIRectClip(converted)
                    for x in stride(from: -converted.size.height, to: converted.size.width, by: stripeSpacing + stripeWidth) {
                        ctx.move(to: CGPoint(x: x + converted.minX, y: converted.minY))
                        ctx.addLine(to: CGPoint(x: x + converted.size.height + converted.minX, y: converted.size.height + converted.minY))
                    }
                    ctx.setLineWidth(stripeWidth)
                    UIColor.gray.withAlphaComponent(0.7).setStroke()
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            }

            guard let image = UIGraphicsGetImageFromCurrentImageContext(),
                  let jpeg = image.jpegData(compressionQuality: settings.imgCompression) else {
                throw NSError(domain: "RecordingBench", code: 2, userInfo: [NSLocalizedDescriptionKey: "jpeg encode failed"])
            }
            samples.append((CFAbsoluteTimeGetCurrent() - frameStart) * 1000)
            jpegSizes.append(jpeg.count)
            jpegBatch.append(jpeg)
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let gzipBytes = try gzipTar(batch: jpegBatch)
        let sorted = samples.sorted()
        let p95 = percentile(sorted, 95)
        let avgCapture = samples.reduce(0, +) / Double(max(samples.count, 1))
        let totalJpeg = jpegSizes.reduce(0, +)
        let avgJpeg = totalJpeg / max(jpegSizes.count, 1)
        let durationSec = max(durationMs / 1000.0, 0.001)
        // Extrapolate batch gzip size to continuous upload at this quality’s capture rate
        let framesPerMin = 60.0 / max(settings.captureRate, 0.01)
        let bytesPerFrameGzip = Double(gzipBytes.count) / Double(max(frames, 1))
        let uploadMbPerMin = (bytesPerFrameGzip * framesPerMin) / (1024.0 * 1024.0)

        window.isHidden = true

        return RecordingBenchMetrics(
            scenario: scenario,
            quality: qualityLabel(quality),
            frames: frames,
            durationMs: round1(durationMs),
            avgCaptureMs: round1(avgCapture),
            p95CaptureMs: round1(p95),
            avgJpegBytes: avgJpeg,
            totalJpegBytes: totalJpeg,
            gzipBatchBytes: gzipBytes.count,
            uploadMbPerMin: round3(uploadMbPerMin),
            captureRateSec: settings.captureRate,
            imgCompression: settings.imgCompression,
            sanitizeEnabled: sanitize,
            sanitizeRects: sanitize ? 1 : 0
        )
    }

    private static func gzipTar(batch: [Data]) throws -> Data {
        var entries: [TarContainer.Entry] = []
        let base = UInt64(Date().timeIntervalSince1970 * 1000)
        for (i, data) in batch.enumerated() {
            let name = "\(base)_1_\(base + UInt64(i)).jpeg"
            var entry = TarContainer.Entry(info: .init(name: name, type: .regular), data: data)
            entry.info.permissions = Permissions(rawValue: 420)
            entries.append(entry)
        }
        return try GzipArchive.archive(data: TarContainer.create(from: entries))
    }

    private static func qualityLabel(_ q: RecordingQuality) -> String {
        switch q {
        case .Low: return "low"
        case .Standard: return "standard"
        case .High: return "high"
        }
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, Int(ceil((p / 100.0) * Double(sorted.count))) - 1)
        return sorted[max(0, idx)]
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}
#endif
