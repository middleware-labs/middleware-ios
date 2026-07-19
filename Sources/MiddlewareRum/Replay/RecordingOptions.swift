// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import Foundation
import UIKit

/// Capture frequency for v3 session recording, mirroring the Android SDK's
/// RecordingFrequency (LOW 1000 ms / STANDARD 330 ms / HIGH 100 ms).
@objc public enum RecordingFrequency: Int {
    case low
    case standard
    case high

    var intervalSeconds: TimeInterval {
        switch self {
        case .low: return 1.0
        case .standard: return 0.33
        case .high: return 0.1
        }
    }
}

/// Options for v3 session recording, mirroring the Android SDK's
/// RecordingOptions: capture frequency, image quality and masking toggles.
/// Reuses the existing `RecordingQuality` enum.
@objc public class RecordingOptions: NSObject {
    @objc public private(set) var frequency: RecordingFrequency = .low
    @objc public private(set) var quality: RecordingQuality = .Standard
    @objc public private(set) var maskAllTextInputs: Bool = true
    @objc public private(set) var maskAllImages: Bool = true

    @objc public override init() {}

    /// Sets the recording frequency. Default is `.low` (~1 FPS).
    @discardableResult
    @objc(withFrequency:) public func setFrequency(_ frequency: RecordingFrequency) -> RecordingOptions {
        self.frequency = frequency
        return self
    }

    /// Sets the recording image quality (JPEG compression). Default is `.Standard`.
    @discardableResult
    @objc(withQuality:) public func setQuality(_ quality: RecordingQuality) -> RecordingOptions {
        self.quality = quality
        return self
    }

    /// Masks every text element in v3 session recording. When disabled, only
    /// secure/sensitive inputs are masked. Default is `true`.
    @discardableResult
    @objc(withMaskAllTextInputs:) public func setMaskAllTextInputs(_ maskAllTextInputs: Bool) -> RecordingOptions {
        self.maskAllTextInputs = maskAllTextInputs
        return self
    }

    /// Masks image content in v3 session recording. Default is `true`.
    @discardableResult
    @objc(withMaskAllImages:) public func setMaskAllImages(_ maskAllImages: Bool) -> RecordingOptions {
        self.maskAllImages = maskAllImages
        return self
    }

    /// JPEG compression quality, matching Android's 25/50/75.
    var jpegQuality: CGFloat {
        switch quality {
        case .Low: return 0.25
        case .Standard: return 0.5
        case .High: return 0.75
        }
    }
}
#endif
