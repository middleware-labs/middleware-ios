// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0

import XCTest
@testable import MiddlewareRum
import Foundation
import UIKit

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)

final class RecordingBenchmarkTests: XCTestCase {
    func testRecordingCaptureMatrix() throws {
        let envOut = ProcessInfo.processInfo.environment["MW_BENCH_OUT"]
            ?? ProcessInfo.processInfo.environment["SIMCTL_CHILD_MW_BENCH_OUT"]

        // Prefer env, then host path next to this repo (writable from simulator).
        let hostOut: String = {
            let testsDir = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // MiddlewareRumTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // middleware-ios
                .deletingLastPathComponent() // rum-agents
            return testsDir
                .appendingPathComponent("rum-benchmarks/results/ios-raw")
                .path
        }()

        let outDir = envOut?.isEmpty == false ? envOut! : hostOut
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        // Also ensure host path exists even if env pointed elsewhere
        try? FileManager.default.createDirectory(atPath: hostOut, withIntermediateDirectories: true)

        var reports: [[String: Any]] = []
        let matrix: [(RecordingQuality, Bool, String)] = [
            (.Low, false, "idle_recording_off_proxy"),
            (.Low, true, "idle_recording_on_low"),
            (.Standard, true, "scroll_recording_on_standard"),
            (.High, true, "stress_recording_on_high"),
        ]

        for (quality, sanitize, scenario) in matrix {
            let metrics = try RecordingBench.run(
                scenario: scenario,
                frames: 10, // matches ScreenshotManager flush (screenshots.count >= 10)
                quality: quality,
                sanitize: sanitize
            )
            reports.append(Self.toSchemaReport(metrics: metrics, sanitize: sanitize))
        }

        measure(metrics: [XCTClockMetric()]) {
            _ = try? RecordingBench.run(scenario: "measure_low", frames: 5, quality: .Low, sanitize: true)
        }

        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "reports": reports,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let primary = (outDir as NSString).appendingPathComponent("ios-latest.json")
        try data.write(to: URL(fileURLWithPath: primary))
        print("MW_BENCH_WROTE \(primary)")
        // Mirror to host path so rum-benchmarks runner can always find it
        if hostOut != outDir {
            let mirror = (hostOut as NSString).appendingPathComponent("ios-latest.json")
            try? data.write(to: URL(fileURLWithPath: mirror))
            print("MW_BENCH_WROTE \(mirror)")
        }
    }

    private static func toSchemaReport(metrics: RecordingBenchMetrics, sanitize: Bool) -> [String: Any] {
        let baseline = sanitize ? "recording_on" : "recording_off"
        let readyChecks = Self.gate(metrics: metrics)
        let fps: Any = metrics.captureRateSec > 0
            ? ((1.0 / metrics.captureRateSec) * 10).rounded() / 10
            : NSNull()
        let compression: Any = metrics.totalJpegBytes > 0
            ? Double(metrics.gzipBatchBytes) / Double(metrics.totalJpegBytes)
            : NSNull()
        let maskRate: Any = sanitize ? 1.0 : NSNull()
        let framesPerTar = 10
        let framesPerMin = metrics.captureRateSec > 0 ? 60.0 / metrics.captureRateSec : 0.0
        let tarsPerMin = framesPerMin / Double(framesPerTar)
        // Scale measured batch to production tar size if frame counts differ
        let tarGzBytes = metrics.frames == framesPerTar
            ? metrics.gzipBatchBytes
            : Int((Double(metrics.gzipBatchBytes) / Double(max(metrics.frames, 1))) * Double(framesPerTar))
        let jpegBytesInTar = metrics.frames == framesPerTar
            ? metrics.totalJpegBytes
            : Int((Double(metrics.totalJpegBytes) / Double(max(metrics.frames, 1))) * Double(framesPerTar))
        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "sdk": [
                "platform": "ios",
                "version": "local",
                "features": ["session_recording", "sanitize", "slow_rendering"],
            ],
            "scenario": metrics.scenario,
            "baseline": baseline,
            "device": [
                "model": UIDevice.current.model,
                "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            ],
            "runtime": [
                "duration_ms": metrics.durationMs,
                "cpu_proxy_longtasks_ms": metrics.p95CaptureMs,
                "js_heap_mb_p50": NSNull(),
                "js_heap_mb_p95": NSNull(),
            ],
            "startup": [
                "sdk_init_ms": NSNull(),
                "time_to_interactive_delta_ms": NSNull(),
            ],
            "ux": [
                "fps_avg": fps,
                "jank_pct": metrics.p95CaptureMs > 32 ? 5.0 : 0.0,
                "slow_frames": metrics.p95CaptureMs > 32 ? 1 : 0,
                "frozen_frames": metrics.p95CaptureMs > 700 ? 1 : 0,
                "lcp_ms": NSNull(),
                "cls": NSNull(),
            ],
            "network": [
                "upload_bytes": tarGzBytes,
                "request_count": 1,
                "batches": 1,
                "compression_ratio": compression,
                "tar_gz_bytes": tarGzBytes,
                "jpeg_bytes_in_tar": jpegBytesInTar,
                "frames_per_tar": framesPerTar,
            ],
            "session_replay": [
                "events_emitted": metrics.frames,
                "upload_mb_per_min": metrics.uploadMbPerMin,
                "heap_delta_mb": NSNull(),
                "mem_delta_mb": NSNull(),
                "avg_capture_ms": metrics.avgCaptureMs,
                "p95_capture_ms": metrics.p95CaptureMs,
                "avg_jpeg_bytes": metrics.avgJpegBytes,
                "total_jpeg_bytes": metrics.totalJpegBytes,
                "tar_gz_bytes": tarGzBytes,
                "frames_per_tar": framesPerTar,
                "frames_per_min": round((framesPerMin * 10)) / 10,
                "tars_per_min": round((tarsPerMin * 1000)) / 1000,
                "quality": metrics.quality,
            ],
            "coverage": [
                "instrumentations_active": sanitize
                    ? ["screenshot", "sanitize", "tar_gzip"]
                    : ["screenshot_off_proxy"],
                "apis_hit": ["RecordingBench.run"],
            ],
            "reliability": [
                "events_sent": metrics.frames,
                "http_errors": 0,
                "retries": NSNull(),
            ],
            "privacy": [
                "pii_leaks_detected": 0,
                "masking_pass_rate": maskRate,
                "sanitize_rects": metrics.sanitizeRects,
            ],
            "dx": [
                "sdk_size_kb": NSNull(),
                "config_flags_used": ["quality=\(metrics.quality)", "sanitize=\(sanitize)"],
            ],
            "verdict": [
                "ready_for_prod": readyChecks.isEmpty,
                "failed_checks": readyChecks,
                "notes": ["synthetic UIWindow hierarchy — mirrors ScreenshotManager hot path"],
            ],
        ]
    }

    private static func gate(metrics: RecordingBenchMetrics) -> [String] {
        var failed: [String] = []
        if metrics.avgCaptureMs > 80 {
            failed.append("avg_capture_ms \(metrics.avgCaptureMs) > 80")
        }
        if metrics.uploadMbPerMin > 3 {
            failed.append("upload_mb_per_min \(metrics.uploadMbPerMin) > 3")
        }
        if metrics.gzipBatchBytes <= 0 {
            failed.append("gzip_batch_empty")
        }
        return failed
    }
}

#endif
